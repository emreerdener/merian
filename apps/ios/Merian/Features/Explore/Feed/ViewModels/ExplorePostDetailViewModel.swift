import Foundation
import Observation

@MainActor
@Observable
final class ExplorePostDetailViewModel {
    struct Dependencies {
        let loadDetail: @MainActor (_ postId: String) async throws -> ExplorePostDetail
        let loadComposerMedia: @MainActor (_ postId: String) async throws -> ExploreComposerMediaPayload
        let updateFieldNotes: @MainActor (
            _ postId: String,
            _ fieldNotes: String?
        ) async throws -> ExploreUpdateFieldNotesResponse
        let updateContent: @MainActor (
            _ postId: String,
            _ speciesCommonName: String,
            _ fieldNotes: String?,
            _ hashtags: [String],
            _ locationSharing: ExplorePostLocationSharing,
            _ mediaItems: [ExplorePostMediaSelection]?
        ) async throws -> ExploreUpdateFieldNotesResponse
        let errorMessage: @MainActor (Error) -> String
    }

    let postId: String
    private let dependencies: Dependencies
    private var detailRequestGeneration: UInt64 = 0

    private(set) var detail: ExplorePostDetail?
    private(set) var isLoadingDetail = false
    private(set) var detailErrorMessage: String?
    private(set) var isUpdatingFieldNotesVisibility = false
    private(set) var isSavingPostContent = false
    private(set) var postComposerMediaItems: [ExplorePostComposerMediaDraft] = []

    init(postId: String, dependencies: Dependencies = .live) {
        self.postId = postId
        self.dependencies = dependencies
    }

    func loadDetail(force: Bool = false) async {
        guard force || !isLoadingDetail else { return }

        detailRequestGeneration &+= 1
        let requestGeneration = detailRequestGeneration
        isLoadingDetail = true
        detailErrorMessage = nil
        detail = nil

        defer {
            if requestGeneration == detailRequestGeneration {
                isLoadingDetail = false
            }
        }

        do {
            let response = try await dependencies.loadDetail(postId)
            guard requestGeneration == detailRequestGeneration else { return }
            detail = response
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard requestGeneration == detailRequestGeneration else { return }
            detailErrorMessage = dependencies.errorMessage(error)
        }
    }

    func setInitialComposerMedia(from mediaItems: [ExploreMediaItem]) {
        postComposerMediaItems = ExplorePostComposerMediaDraft.existingPostItems(from: mediaItems)
    }

    func loadComposerMedia() async throws -> [ExplorePostComposerMediaDraft] {
        let payload = try await dependencies.loadComposerMedia(postId)
        return ExplorePostComposerMediaDraft.sourceItems(from: payload.mediaItems)
    }

    func commitComposerMedia(_ mediaItems: [ExplorePostComposerMediaDraft]) {
        postComposerMediaItems = mediaItems
    }

    func prepareEditor(existingMediaItems: [ExploreMediaItem]) async throws {
        setInitialComposerMedia(from: existingMediaItems)

        do {
            let loadedDetail = try await dependencies.loadDetail(postId)
            let loadedMedia = try await loadComposerMedia()
            detailRequestGeneration &+= 1
            detail = loadedDetail
            detailErrorMessage = nil
            commitComposerMedia(loadedMedia)
        } catch {
            detailRequestGeneration &+= 1
            detail = nil
            throw error
        }
    }

    func updateFieldNotes(_ fieldNotes: String?) async throws -> ExploreUpdateFieldNotesResponse {
        guard !isUpdatingFieldNotesVisibility else {
            throw ExplorePostDetailMutationError.fieldNotesUpdateInProgress
        }

        isUpdatingFieldNotesVisibility = true
        defer { isUpdatingFieldNotesVisibility = false }

        let response = try await dependencies.updateFieldNotes(postId, fieldNotes)
        detail?.fieldNotes = response.postId == postId ? response.fieldNotes : fieldNotes
        return response
    }

    func updateContent(_ draft: ExplorePostComposerDraft) async throws -> ExploreUpdateFieldNotesResponse {
        guard !isSavingPostContent else {
            throw ExplorePostDetailMutationError.contentUpdateInProgress
        }

        isSavingPostContent = true
        defer { isSavingPostContent = false }

        let response = try await dependencies.updateContent(
            postId,
            draft.selectedCommonName,
            draft.publicFieldNotes,
            draft.hashtags,
            draft.locationSharing,
            draft.mediaItems
        )
        detailRequestGeneration &+= 1
        detail?.fieldNotes = response.fieldNotes
        detail?.locationSharing = response.locationSharing ?? draft.locationSharing
        return response
    }
}

enum ExplorePostDetailMutationError: LocalizedError {
    case fieldNotesUpdateInProgress
    case contentUpdateInProgress

    var errorDescription: String? {
        switch self {
        case .fieldNotesUpdateInProgress:
            "Field notes visibility is already updating"
        case .contentUpdateInProgress:
            "This post is already being updated"
        }
    }
}
