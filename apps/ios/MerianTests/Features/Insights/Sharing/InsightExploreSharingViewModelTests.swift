import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightExploreSharingViewModelTests {
    @Test func successfulPublicationUsesDependenciesAndCommitsCurrentScan() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "sharing_dependency_species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            coverImagePath: "monarch.webp"
        )
        context.insert(record)
        try context.save()

        let postID = UUID().uuidString.lowercased()
        let response = try makeShareResponse(
            scanID: record.id,
            postID: postID,
            locationSharing: .obscured
        )
        var cachedPostID: String?
        var publishedEvent: (scanID: String, postID: String?)?
        var successFeedbackCount = 0
        var capturedHashtags: [String] = []

        let dependencies = InsightSharingDependencies(
            shareScanToExplore: {
                scan,
                _,
                commonName,
                _,
                hashtags,
                locationSharing,
                _ in
                #expect(scan.id == record.id)
                #expect(commonName == "Monarch")
                #expect(locationSharing == .obscured)
                capturedHashtags = hashtags
                return response
            },
            loadCachedPostID: { _ in cachedPostID },
            storeCachedPostID: { value, _ in cachedPostID = value },
            publishShareStateChanged: { scanID, value in
                publishedEvent = (scanID, value)
            },
            persistPreferredCommonName: { name, _, _ in name },
            successFeedback: { successFeedbackCount += 1 }
        )
        let viewModel = makePresentedViewModel(
            record: record,
            dependencies: dependencies
        )
        let draft = ExplorePostComposerDraft(
            selectedCommonName: "Monarch",
            fieldNotes: "Seen on milkweed",
            fieldNotesArePublic: true,
            hashtags: ["#Monarch"],
            locationSharing: .obscured,
            mediaItems: nil
        )

        let didShare = await viewModel.shareToExplore(
            draft,
            expectedScanId: record.id,
            expectedGeneration: viewModel.scanBoundActionGeneration,
            modelContext: context
        )

        #expect(didShare)
        #expect(capturedHashtags == ["#Monarch"])
        #expect(cachedPostID == postID)
        #expect(publishedEvent?.scanID == record.id)
        #expect(publishedEvent?.postID == postID)
        #expect(viewModel.state.sharedExplorePostId == postID)
        #expect(viewModel.state.sharedExploreHashtags == ["#Monarch"])
        #expect(viewModel.state.exploreFieldNotesArePublic)
        #expect(successFeedbackCount == 1)
        #expect(!viewModel.state.isSharingToExplore)
    }

    @Test func localMutationWinsAgainstInFlightShareStateRefresh() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "sharing_refresh_species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            coverImagePath: "monarch.webp"
        )
        context.insert(record)
        try context.save()

        let stalePostID = UUID().uuidString.lowercased()
        let currentPostID = UUID().uuidString.lowercased()
        let staleState = try makeShareState(
            scanID: record.id,
            postID: stalePostID
        )
        let publicationResponse = try makeShareResponse(
            scanID: record.id,
            postID: currentPostID,
            locationSharing: .obscured
        )
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (responses, responseContinuation) =
            AsyncStream<ExploreScanShareState>.makeStream()
        var startedIterator = started.makeAsyncIterator()
        var cachedPostID: String?

        let dependencies = InsightSharingDependencies(
            shareScanToExplore: { _, _, _, _, _, _, _ in
                publicationResponse
            },
            loadExploreShareState: { _ in
                startedContinuation.yield()
                for await response in responses {
                    return response
                }
                throw CancellationError()
            },
            loadCachedPostID: { _ in cachedPostID },
            storeCachedPostID: { value, _ in cachedPostID = value }
        )
        let viewModel = makePresentedViewModel(
            record: record,
            dependencies: dependencies
        )
        let generation = viewModel.scanBoundActionGeneration

        let refresh = Task { @MainActor in
            await viewModel.refreshSharedExploreStateFromServer(
                expectedScanId: record.id,
                expectedGeneration: generation,
                modelContext: context
            )
        }
        _ = await startedIterator.next()

        await viewModel.shareToExplore(
            expectedScanId: record.id,
            expectedGeneration: generation,
            modelContext: context
        )
        responseContinuation.yield(staleState)
        responseContinuation.finish()
        startedContinuation.finish()
        await refresh.value

        #expect(cachedPostID == currentPostID)
        #expect(viewModel.state.sharedExplorePostId == currentPostID)
        #expect(viewModel.state.isExploreFeedVisible)
    }

    @Test func mismatchedPostDetailCannotOverwriteShareState() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "sharing_detail_identity_species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            coverImagePath: "monarch.webp"
        )
        context.insert(record)
        try context.save()

        let postID = UUID().uuidString.lowercased()
        let shareState = try makeShareState(
            scanID: record.id,
            postID: postID
        )
        let mismatchedDetail = try makePostDetail(
            postID: UUID().uuidString.lowercased(),
            fieldNotes: nil,
            hashtags: ["#WrongPost"],
            locationSharing: .privateLocation
        )
        var cachedPostID: String?
        let dependencies = InsightSharingDependencies(
            loadExploreShareState: { _ in shareState },
            loadExplorePostDetail: { _ in mismatchedDetail },
            loadCachedPostID: { _ in cachedPostID },
            storeCachedPostID: { value, _ in cachedPostID = value }
        )
        let viewModel = makePresentedViewModel(
            record: record,
            dependencies: dependencies
        )
        viewModel.state.sharedExploreHashtags = ["#Current"]
        viewModel.state.exploreFieldNotesArePublic = true

        await viewModel.refreshSharedExploreStateFromServer(
            expectedScanId: record.id,
            expectedGeneration: viewModel.scanBoundActionGeneration,
            modelContext: context
        )

        #expect(cachedPostID == postID)
        #expect(viewModel.state.sharedExplorePostId == postID)
        #expect(viewModel.state.sharedExploreHashtags == ["#Current"])
        #expect(viewModel.state.exploreFieldNotesArePublic)
        #expect(viewModel.state.sharedExploreLocationSharing == .obscured)
    }

    @Test(arguments: ["owner", "selection", "revision", "hold"])
    func enrollmentBlocksCommunityCreateAndEditFromAlreadyOpenPresentation(protection: String) async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(speciesId: "community-species", scientificName: "Danaus plexippus",
            commonName: "Monarch", coverImagePath: "monarch.webp")
        context.insert(record)
        try context.save()
        var calls = 0
        let dependencies = InsightSharingDependencies(
            requestCommunityIdentification: { _, _, _, _, _ in calls += 1; throw URLError(.badServerResponse) },
            updateCommunityIdentificationRequest: { _, _, _ in calls += 1; throw URLError(.badServerResponse) }
        )
        let viewModel = makePresentedViewModel(record: record, dependencies: dependencies)
        #expect(viewModel.canRequestCommunityIdentification)
        let fresh = ModelContext(context.container)
        let freshRecord = try #require(try fresh.fetch(FetchDescriptor<LocalScanRecord>()).first)
        switch protection {
        case "owner": freshRecord.analysisOwnerAccountID = UUID().uuidString
        case "selection": freshRecord.selectedAnalysisID = "malformed"
        case "revision": freshRecord.observationStateRevision = 0
        default:
            fresh.insert(OfflineJobRecord(id: ObservationHistoryEnrollmentIntent.jobID(record.id), kind: .future,
                subjectId: record.id, status: .needsAttention))
        }
        try fresh.save()
        await viewModel.requestCommunityIdentification(note: nil, locationSharing: .obscured,
            expectedScanId: record.id, expectedGeneration: viewModel.scanBoundActionGeneration, modelContext: context)
        viewModel.state.sharedCommunityIdentificationRequestId = UUID().uuidString
        await viewModel.updateCommunityIdentificationRequest(note: nil, locationSharing: .obscured,
            expectedScanId: record.id, expectedGeneration: viewModel.scanBoundActionGeneration, modelContext: context)
        #expect(calls == 0)
        #expect(!viewModel.state.isRequestingCommunityIdentification)
    }

    @Test(arguments: [false, true])
    func communityCreateRechecksEnrollmentBeforeCacheAndPresentation(enrollDuringRequest: Bool) async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(speciesId: "community-species", scientificName: "Danaus plexippus",
            commonName: "Monarch", coverImagePath: "monarch.webp")
        context.insert(record); try context.save()
        var calls = 0, cacheWrites = 0, events = 0, successes = 0
        let requestID = UUID().uuidString
        let dependencies = InsightSharingDependencies(requestCommunityIdentification: { _, _, _, _, _ in
            calls += 1
            if enrollDuringRequest {
                let fresh = ModelContext(context.container)
                fresh.insert(OfflineJobRecord(id: ObservationHistoryEnrollmentIntent.jobID(record.id), kind: .future,
                    subjectId: record.id, status: .needsAttention))
                try fresh.save()
            }
            return CommunityIdentificationRequest(id: requestID, postId: UUID().uuidString, scanId: record.id,
                requestedBy: UUID().uuidString, requestedAt: "2026-10-05T00:00:00Z", status: .needsId, note: nil,
                initialTaxonNodeId: nil, taxonomyVersionId: nil, currentCommunityTaxonNodeId: nil, resolvedTaxonNodeId: nil,
                consensusScore: nil, consensusIdentificationCount: 0, consensusRank: nil, consensusProcessingState: nil)
        }, storeCachedPostID: { _, _ in cacheWrites += 1 }, publishShareStateChanged: { _, _ in events += 1 },
           successFeedback: { successes += 1 })
        let viewModel = makePresentedViewModel(record: record, dependencies: dependencies)
        viewModel.state.isCommunityRequestSheetPresented = true
        await viewModel.requestCommunityIdentification(note: nil, locationSharing: .obscured,
            expectedScanId: record.id, expectedGeneration: viewModel.scanBoundActionGeneration, modelContext: context)
        #expect(calls == 1)
        #expect(cacheWrites == (enrollDuringRequest ? 0 : 1))
        #expect(events == cacheWrites && successes == cacheWrites)
        #expect(viewModel.state.sharedCommunityIdentificationRequestId == (enrollDuringRequest ? nil : requestID))
        #expect(viewModel.state.isCommunityRequestSheetPresented == enrollDuringRequest)
        #expect(!viewModel.state.isRequestingCommunityIdentification)
    }

    @Test(arguments: [false, true])
    func communityEditRechecksEnrollmentAfterAwait(enrollDuringRequest: Bool) async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(speciesId: "community-species", scientificName: "Danaus plexippus",
            commonName: "Monarch", coverImagePath: "monarch.webp")
        context.insert(record)
        try context.save()
        var calls = 0
        var successes = 0
        let dependencies = InsightSharingDependencies(updateCommunityIdentificationRequest: { request, _, sharing in
            calls += 1
            if enrollDuringRequest {
                let fresh = ModelContext(context.container)
                fresh.insert(OfflineJobRecord(id: ObservationHistoryEnrollmentIntent.jobID(record.id), kind: .future,
                    subjectId: record.id, status: .needsAttention))
                try fresh.save()
            }
            return CommunityRequestUpdate(id: request, postId: UUID().uuidString, note: nil,
                locationSharing: sharing, updatedAt: "2026-10-05T00:00:00Z")
        }, successFeedback: { successes += 1 })
        let viewModel = makePresentedViewModel(record: record, dependencies: dependencies)
        viewModel.state.sharedCommunityIdentificationRequestId = UUID().uuidString
        await viewModel.updateCommunityIdentificationRequest(note: nil, locationSharing: .obscured,
            expectedScanId: record.id, expectedGeneration: viewModel.scanBoundActionGeneration, modelContext: context)
        #expect(calls == 1)
        #expect(successes == (enrollDuringRequest ? 0 : 1))
        #expect(!viewModel.state.isRequestingCommunityIdentification)
    }

    private func makePresentedViewModel(
        record: LocalScanRecord,
        dependencies: InsightSharingDependencies
    ) -> InsightSheetViewModel {
        let viewModel = InsightSheetViewModel(
            sharingDependencies: dependencies
        )
        let engine = InsightSheetTestSupport.biologicalEngine(
            scanId: record.id
        )
        engine.activeMedia = ActiveScanMedia(
            items: [.image(record.coverImagePath ?? "monarch.webp")]
        )
        viewModel.inferenceEngine = engine
        viewModel.activeLocalRecord = record
        viewModel.activeLocalRecordId = record.id
        viewModel.toolbarRecordSnapshot =
            InsightToolbarRecordSnapshot(record: record)
        return viewModel
    }

    private func makeShareResponse(
        scanID: String,
        postID: String,
        locationSharing: ExplorePostLocationSharing
    ) throws -> ExploreShareResponse {
        let json = """
        {
          "success": true,
          "post_id": "\(postID)",
          "scan_id": "\(scanID)",
          "shared_at": "2026-08-31T12:00:00Z",
          "location_sharing": "\(locationSharing.rawValue)",
          "publication_status": "published"
        }
        """
        return try decoder().decode(
            ExploreShareResponse.self,
            from: Data(json.utf8)
        )
    }

    private func makeShareState(
        scanID: String,
        postID: String
    ) throws -> ExploreScanShareState {
        let json = """
        {
          "scan_id": "\(scanID)",
          "post_id": "\(postID)",
          "shared_at": "2026-08-31T12:00:00Z",
          "community_request_id": null,
          "community_request_status": null,
          "is_explore_feed_visible": true,
          "location_sharing": "obscured"
        }
        """
        return try decoder().decode(
            ExploreScanShareState.self,
            from: Data(json.utf8)
        )
    }

    private func makePostDetail(
        postID: String,
        fieldNotes: String?,
        hashtags: [String],
        locationSharing: ExplorePostLocationSharing
    ) throws -> ExplorePostDetail {
        let fieldNotesJSON = fieldNotes.map { "\"\($0)\"" } ?? "null"
        let hashtagsJSON = hashtags
            .map { "\"\($0)\"" }
            .joined(separator: ",")
        let json = """
        {
          "post_id": "\(postID)",
          "field_notes": \(fieldNotesJSON),
          "hashtags": [\(hashtagsJSON)],
          "location_sharing": "\(locationSharing.rawValue)"
        }
        """
        return try decoder().decode(
            ExplorePostDetail.self,
            from: Data(json.utf8)
        )
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
