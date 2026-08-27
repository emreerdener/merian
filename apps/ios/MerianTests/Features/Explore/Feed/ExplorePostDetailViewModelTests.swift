import XCTest

@testable import Merian

@MainActor
final class ExplorePostDetailViewModelTests: XCTestCase {
    private struct RequestedContent {
        let name: String
        let fieldNotes: String?
        let hashtags: [String]
        let locationSharing: ExplorePostLocationSharing
        let mediaItems: [ExplorePostMediaSelection]?
    }

    func testForcedReloadSupersedesOlderDetailRequest() async {
        let staleDetail = ExploreFeedTestFixtures.detail(
            postId: "post-1",
            fieldNotes: "Stale"
        )
        let currentDetail = ExploreFeedTestFixtures.detail(
            postId: "post-1",
            fieldNotes: "Current"
        )
        let firstLoadStarted = expectation(description: "First detail load started")
        var pendingFirstLoad: CheckedContinuation<ExplorePostDetail, any Error>?
        var loadCount = 0
        let viewModel = ExplorePostDetailViewModel(
            postId: "post-1",
            dependencies: makeDependencies(loadDetail: { _ in
                loadCount += 1
                if loadCount == 1 {
                    return try await withCheckedThrowingContinuation { continuation in
                        pendingFirstLoad = continuation
                        firstLoadStarted.fulfill()
                    }
                }
                return currentDetail
            })
        )

        let staleTask = Task {
            await viewModel.loadDetail()
        }
        await fulfillment(of: [firstLoadStarted], timeout: 1)

        await viewModel.loadDetail(force: true)
        pendingFirstLoad?.resume(returning: staleDetail)
        _ = await staleTask.value

        XCTAssertEqual(viewModel.detail?.fieldNotes, "Current")
        XCTAssertNil(viewModel.detailErrorMessage)
        XCTAssertFalse(viewModel.isLoadingDetail)
    }

    func testPrepareEditorReplacesFallbackMediaWithEndpointOrdering() async throws {
        let existingMedia = [
            ExploreMediaItem(
                kind: .image,
                url: "https://example.com/fallback.jpg",
                thumbnailUrl: nil,
                orderIndex: 0,
                durationSeconds: nil,
                hasAudio: false
            )
        ]
        let payload = ExploreComposerMediaPayload(
            scanId: "scan-1",
            postId: "post-1",
            mediaItems: [
                ExploreComposerMediaItem(
                    sourceMediaId: "video-1",
                    kind: .video,
                    url: "https://example.com/video.mp4",
                    thumbnailUrl: "https://example.com/video.jpg",
                    orderIndex: 1,
                    isSelected: true,
                    selectionOrderIndex: 0
                ),
                ExploreComposerMediaItem(
                    sourceMediaId: "image-1",
                    kind: .image,
                    url: "https://example.com/image.jpg",
                    thumbnailUrl: "https://example.com/image.jpg",
                    orderIndex: 0,
                    isSelected: false,
                    selectionOrderIndex: 1
                )
            ]
        )
        let detail = ExploreFeedTestFixtures.detail(postId: "post-1")
        let viewModel = ExplorePostDetailViewModel(
            postId: "post-1",
            dependencies: makeDependencies(
                loadDetail: { _ in detail },
                loadComposerMedia: { _ in payload }
            )
        )

        try await viewModel.prepareEditor(existingMediaItems: existingMedia)

        XCTAssertEqual(viewModel.detail?.postId, "post-1")
        XCTAssertEqual(viewModel.postComposerMediaItems.map(\.id), ["video-1", "image-1"])
        XCTAssertEqual(viewModel.postComposerMediaItems.map(\.isIncluded), [true, false])
        XCTAssertEqual(
            viewModel.postComposerMediaItems.first?.previewPath,
            "https://example.com/video.jpg"
        )
    }

    func testMutationsForwardTypedDraftAndApplyAuthoritativeResponse() async throws {
        var requestedFieldNotes: String?
        var requestedContent: RequestedContent?
        let initialDetail = ExploreFeedTestFixtures.detail(postId: "post-1")
        let fieldNotesResponse = ExploreUpdateFieldNotesResponse(
            success: true,
            postId: "post-1",
            fieldNotes: "Public notes",
            hashtags: ["birding"],
            speciesCommonName: nil,
            locationSharing: .open
        )
        let contentResponse = ExploreUpdateFieldNotesResponse(
            success: true,
            postId: "post-1",
            fieldNotes: "Edited notes",
            hashtags: ["wetlands"],
            speciesCommonName: "Great Blue Heron",
            locationSharing: .privateLocation
        )
        let viewModel = ExplorePostDetailViewModel(
            postId: "post-1",
            dependencies: makeDependencies(
                loadDetail: { _ in initialDetail },
                updateFieldNotes: { _, fieldNotes in
                    requestedFieldNotes = fieldNotes
                    return fieldNotesResponse
                },
                updateContent: { _, name, fieldNotes, hashtags, locationSharing, mediaItems in
                    requestedContent = RequestedContent(
                        name: name,
                        fieldNotes: fieldNotes,
                        hashtags: hashtags,
                        locationSharing: locationSharing,
                        mediaItems: mediaItems
                    )
                    return contentResponse
                }
            )
        )
        await viewModel.loadDetail()

        _ = try await viewModel.updateFieldNotes("Public notes")
        let mediaSelection = ExplorePostMediaSelection(
            kind: .image,
            sourceMediaId: "image-1",
            sourceIndex: 0,
            thumbnailSourceIndex: nil,
            url: nil,
            thumbnailUrl: nil,
            orderIndex: 0
        )
        let draft = ExplorePostComposerDraft(
            selectedCommonName: "Great Blue Heron",
            fieldNotes: "Edited notes",
            fieldNotesArePublic: true,
            hashtags: ["wetlands"],
            locationSharing: .privateLocation,
            mediaItems: [mediaSelection]
        )
        _ = try await viewModel.updateContent(draft)

        XCTAssertEqual(requestedFieldNotes, "Public notes")
        XCTAssertEqual(requestedContent?.name, "Great Blue Heron")
        XCTAssertEqual(requestedContent?.fieldNotes, "Edited notes")
        XCTAssertEqual(requestedContent?.hashtags, ["wetlands"])
        XCTAssertEqual(requestedContent?.locationSharing, .privateLocation)
        XCTAssertEqual(requestedContent?.mediaItems, [mediaSelection])
        XCTAssertEqual(viewModel.detail?.fieldNotes, "Edited notes")
        XCTAssertEqual(viewModel.detail?.locationSharing, .privateLocation)
        XCTAssertFalse(viewModel.isUpdatingFieldNotesVisibility)
        XCTAssertFalse(viewModel.isSavingPostContent)
    }

    private func makeDependencies(
        loadDetail: @escaping @MainActor (String) async throws -> ExplorePostDetail,
        loadComposerMedia: @escaping @MainActor (String) async throws -> ExploreComposerMediaPayload = { _ in
            throw ExploreFeedTestFixtures.StubError.unexpected
        },
        updateFieldNotes: @escaping @MainActor (
            String,
            String?
        ) async throws -> ExploreUpdateFieldNotesResponse = { _, _ in
            throw ExploreFeedTestFixtures.StubError.unexpected
        },
        updateContent: @escaping @MainActor (
            String,
            String,
            String?,
            [String],
            ExplorePostLocationSharing,
            [ExplorePostMediaSelection]?
        ) async throws -> ExploreUpdateFieldNotesResponse = { _, _, _, _, _, _ in
            throw ExploreFeedTestFixtures.StubError.unexpected
        }
    ) -> ExplorePostDetailViewModel.Dependencies {
        ExplorePostDetailViewModel.Dependencies(
            loadDetail: loadDetail,
            loadComposerMedia: loadComposerMedia,
            updateFieldNotes: updateFieldNotes,
            updateContent: updateContent,
            errorMessage: { _ in "Stub error" }
        )
    }
}
