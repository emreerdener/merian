import Foundation
import os
import Testing

@testable import Merian

@Suite("Community Identification Endpoints")
@MainActor
struct CommunityIdentificationEndpointTests {
    @Test(arguments: CommunityIdentificationEndpointRequestCase.all)
    func requestMappingRemainsStable(_ testCase: CommunityIdentificationEndpointRequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }

        try await confirmation("Exactly one Community POST") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try NetworkEndpointTestSupport.expectPOST(
                    request, function: testCase.function, json: testCase.expectedJSON
                )
                return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
            }
            try await testCase.invoke(fixture.client)
        }
    }

    // Rehomed feed, activity, and request-update regressions use isolated clients.
    @Test func testGetCommunityIdentificationFeedConstructsScopedPayload() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/get-community-identification-feed") { request in
            try NetworkEndpointTestSupport.expectPOST(
                request, function: "get-community-identification-feed",
                json: """
                {"limit":12,"scope":"mine","group":"plants","latitude":0,"longitude":0,
                 "before_requested_at":"2026-01-01T12:00:00.000Z","before_request_id":"request-cursor"}
                """
            )
            return try NetworkEndpointTestSupport.response(to: request, json: CommunityIdentificationEndpointResponses.feed)
        }

        let requests = try await fixture.client.getCommunityIdentificationFeed(
            limit: 12, scope: .mine, group: .plants, latitude: .zero, longitude: .zero,
            cursor: .init(beforeRequestedAt: "2026-01-01T12:00:00.000Z", beforeRequestId: "request-cursor")
        )
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.id == "request" && request.postId == "post" && request.scanId == "scan")
        #expect(request.requestGroup == .plants)
        #expect(request.taxonomyVersionId == "taxonomy-version")
        #expect(request.projectionState == "community_needs_id" && request.consensusProcessingState == "idle")
        #expect(request.requestedAt == "2026-01-01T12:00:00.000Z")
        #expect(request.authorName == "Test observer" && request.authorUsername == "test_observer")
        #expect(request.authorIsPro == true && request.authorAvatarUrl == nil)
        #expect(request.currentTaxonId == "taxon" && request.initialTaxonId == "initial-taxon")
        #expect(request.consensusScore == 0.5 && request.identificationCount == 2)
        #expect(!request.viewerHasIdentified && request.locationSharing == .open)
        #expect(request.mediaItems?.first?.kind == .image)
    }

    @Test func testGetCommunityIdentificationActivityConstructsCursorPayload() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/get-community-identification-activity") { request in
            try NetworkEndpointTestSupport.expectPOST(
                request, function: "get-community-identification-activity",
                json: """
                {"limit":10,"scope":"mine","group":"plants",
                 "before_activity_at":"2026-01-01T12:00:00.000Z","before_activity_id":"activity-cursor"}
                """
            )
            return try NetworkEndpointTestSupport.response(to: request, json: CommunityIdentificationEndpointResponses.activity)
        }

        let activity = try await fixture.client.getCommunityIdentificationActivity(
            limit: 10, scope: .mine, group: .plants,
            cursor: .init(beforeActivityAt: "2026-01-01T12:00:00.000Z", beforeActivityId: "activity-cursor")
        )
        #expect(activity.map(\.activityType) == [.suggestionBurst, .consensusChanged, .resolved])
        let burst = try #require(activity.first)
        #expect(burst.activityId == "activity" && burst.requestId == "request")
        #expect(burst.postId == "post" && burst.scanId == "scan")
        #expect(burst.activityAt == "2026-01-01T12:00:00.000Z")
        #expect(burst.suggestionCount == 3)
        #expect(burst.recentActorNames == ["test_observer", "test_contributor"])
        #expect(burst.taxonId == "taxon" && burst.taxonRank == "species")
        #expect(burst.taxonCommonName == "Test rose" && burst.taxonScientificName == "Rosa test")
        #expect(burst.consensusScore == 0.82 && burst.requestGroup == .plants)
        #expect(burst.thumbnailUrl == "https://media.example.test/community-thumb.webp")
        #expect(activity.dropFirst().allSatisfy { $0.heroImageUrl == nil && $0.mediaItems.isEmpty })
    }

    @Test func testUpdateCommunityIdentificationRequestConstructsPayload() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/update-community-identification-request") { request in
            try NetworkEndpointTestSupport.expectPOST(
                request, function: "update-community-identification-request",
                json: #"{"request_id":"request","note":"Test request","location_sharing":"obscured"}"#
            )
            return try NetworkEndpointTestSupport.response(to: request, json: CommunityIdentificationEndpointResponses.update)
        }

        let update = try await fixture.client.updateCommunityIdentificationRequest(
            requestId: "request", note: "Test request", locationSharing: .obscured
        )
        #expect(update.id == "request" && update.postId == "post")
        #expect(update.note == "Test request" && update.locationSharing == .obscured)
        #expect(update.updatedAt == "2026-01-01T12:01:00.000Z")
    }

    @Test func detailKeepsTimelineAndPinnedTaxonomyProjection() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/get-community-identification-detail") { request in
            try NetworkEndpointTestSupport.response(to: request, json: CommunityIdentificationEndpointResponses.detail)
        }

        let detail = try await fixture.client.getCommunityIdentificationDetail(requestId: "request")
        #expect(detail.requestId == "request" && detail.postId == "post" && detail.scanId == "scan")
        #expect(detail.status == .needsId && detail.note == "Test request")
        #expect(detail.taxonomyVersionId == "taxonomy-version")
        #expect(detail.consensusProcessingState == "queued" && detail.inferenceTier == "pro")
        #expect(detail.locationSharing == .obscured && detail.identificationCount == 1)
        #expect(detail.viewerIdentificationId == "identification")
        let identification = try #require(detail.identifications.first)
        #expect(identification.id == "identification" && identification.userId == "contributor")
        #expect(identification.disagreementMode == .implicitSupport && !identification.isGenusBestPossible)
        #expect(identification.isViewer && identification.withdrawnAt == nil && identification.reasoning == nil)
        let suggestion = try #require(detail.suggestedTaxa?.first)
        #expect(suggestion.taxonomyVersionId == "taxonomy-version" && suggestion.speciesId == nil)
        #expect(suggestion.suggestionSource == .aiInitial && suggestion.confidenceScore == 0.8)
        #expect(suggestion.distinguishingFeature == "Test reasoning")
    }

    @Test func taxonomySearchKeepsExternalTaxaWithoutDictionaryRows() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/search-community-taxa") { request in
            try NetworkEndpointTestSupport.response(to: request, json: CommunityIdentificationEndpointResponses.taxa)
        }

        let results = try await fixture.client.searchCommunityTaxa(query: "Rosa", taxonomyVersionId: "taxonomy-version")
        let taxon = try #require(results.first)
        #expect(results.count == 1 && taxon.taxonId == "taxon" && taxon.taxonomyVersionId == "taxonomy-version")
        #expect(taxon.scientificName == "Rosa test" && taxon.commonName == nil)
        #expect(taxon.path == "plantae.rosa.rosa_test" && taxon.rank == "species")
        #expect(taxon.speciesId == nil && taxon.isInDictionary == false)
        #expect(taxon.gbifTaxonKey == 3000001 && taxon.acceptedGbifTaxonKey == 3000001)
        #expect(taxon.source == "gbif" && taxon.taxonomicStatus == "accepted")
    }

    @Test func contributionOperationsKeepTheAuthoritativeMutationProjection() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        for (path, response) in [
            ("/submit-community-identification", CommunityIdentificationEndpointResponses.submittedMutation),
            ("/withdraw-community-identification", CommunityIdentificationEndpointResponses.withdrawnMutation),
            ("/restore-community-identification", CommunityIdentificationEndpointResponses.restoredMutation)
        ] {
            fixture.transport.register(path: path) { request in
                try NetworkEndpointTestSupport.response(to: request, json: response)
            }
        }

        let submitted = try await fixture.client.submitCommunityIdentification(
            requestId: "request", taxonId: "taxon", disagreementMode: .explicitDisagreement,
            reasoning: "Test reasoning", isGenusBestPossible: true
        )
        let withdrawn = try await fixture.client.withdrawCommunityIdentification(identificationId: "identification")
        let restored = try await fixture.client.restoreCommunityIdentification(identificationId: "identification")
        for mutation in [submitted, withdrawn, restored] {
            #expect(mutation.id == "identification" && mutation.requestId == "request" && mutation.postId == "post")
            #expect(mutation.userId == "contributor" && mutation.taxonNodeId == "taxon")
            #expect(mutation.disagreementMode == .explicitDisagreement && mutation.isGenusBestPossible)
            #expect(mutation.reasoning == "Test reasoning" && mutation.createdAt == "2026-01-01T12:01:00.000Z")
        }
        #expect(submitted.withdrawnAt == nil && submitted.restoredAt == nil)
        #expect(withdrawn.withdrawnAt == "2026-01-01T12:02:00.000Z" && withdrawn.restoredAt == nil)
        #expect(restored.withdrawnAt == nil && restored.restoredAt == "2026-01-01T12:03:00.000Z")
    }

    @Test(arguments: CommunityIdentificationEndpointRequestCase.operations)
    func malformedSuccessStillThrowsDecodingError(_ testCase: CommunityIdentificationEndpointRequestCase) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: testCase.path) { request in
            try NetworkEndpointTestSupport.response(to: request, json: #"{"success":true,"data":null}"#)
        }

        await #expect(throws: DecodingError.self) {
            try await testCase.invoke(fixture.client)
        }
    }

    @Test(arguments: CommunityIdentificationEndpointRequestCase.operations, [400, 401, 404])
    func handlerDenialsAreNotSuccessOrReplayed(
        _ testCase: CommunityIdentificationEndpointRequestCase,
        status: Int
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = {
            refreshes.withLock { $0 += 1 }
            // Keep an incorrectly classified denial inside the mock boundary;
            // returning false could fall through to live identity recovery.
            return true
        }

        await confirmation("One handler denial") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, status: status, json: testCase.responseJSON)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("A handler denial must not be decoded as success")
            } catch MerianError.httpError(let actualStatus, _) {
                #expect(status != 401 && actualStatus == status)
            } catch MerianError.invalidResponse {
                // Unclassified 401s preserve the account and use the existing
                // invalid-response mapping rather than trigger identity recovery.
                #expect(status == 401)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(refreshes.withLock { $0 } == 0)
    }

    @Test(arguments: CommunityIdentificationEndpointRequestCase.operations, [200, 401, 503])
    func authRefreshKeepsOneReplayAndTheSamePayload(
        _ testCase: CommunityIdentificationEndpointRequestCase,
        replayStatus: Int
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)

        await confirmation("One session refresh") { refreshed in
            fixture.client.overridingAuthSessionRefresh = {
                refreshed()
                return true
            }
            fixture.transport.register(path: testCase.path) { request in
                try NetworkEndpointTestSupport.expectPOST(
                    request, function: testCase.function, json: testCase.expectedJSON
                )
                let attempt = attempts.withLock { count in
                    count += 1
                    return count
                }
                if attempt == 1 || (attempt == 2 && replayStatus == 401) {
                    return try NetworkEndpointTestSupport.response(
                        to: request, status: 401, json: #"{"code":"invalid_session_token","error":"Invalid session"}"#
                    )
                }
                // A third attempt succeeds so an accidental extra replay fails
                // the assertions instead of leaving an unbounded retry loop.
                return try NetworkEndpointTestSupport.response(
                    to: request, status: attempt == 2 ? replayStatus : 200, json: testCase.responseJSON
                )
            }
            do {
                try await testCase.invoke(fixture.client)
                #expect(replayStatus == 200, "A failed auth replay must propagate its HTTP failure")
            } catch MerianError.httpError(let status, _) {
                #expect(replayStatus != 200 && status == replayStatus)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(attempts.withLock { $0 } == 2)
    }

    @Test(arguments: CommunityIdentificationEndpointRequestCase.operations, [true, false])
    func ambiguousTransportReplayFollowsExistingAllowlist(
        _ testCase: CommunityIdentificationEndpointRequestCase,
        replaySucceeds: Bool
    ) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: testCase.path) { request in
            try NetworkEndpointTestSupport.expectPOST(
                request, function: testCase.function, json: testCase.expectedJSON
            )
            let attempt = attempts.withLock { count in
                count += 1
                return count
            }
            if attempt == 1 || (attempt == 2 && !replaySucceeds) {
                throw URLError(.networkConnectionLost)
            }
            return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
        }

        if testCase.isAmbiguousReplayAllowlisted && replaySucceeds {
            try await testCase.invoke(fixture.client)
        } else {
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("A non-replayed or exhausted request must propagate its transport failure")
            } catch let error as URLError {
                #expect(error.code == .networkConnectionLost)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(attempts.withLock { $0 } == (testCase.isAmbiguousReplayAllowlisted ? 2 : 1))
    }

    @Test(arguments: CommunityIdentificationEndpointRequestCase.operations, [true, false])
    func ambiguousServerReplayFollowsExistingAllowlist(
        _ testCase: CommunityIdentificationEndpointRequestCase,
        replaySucceeds: Bool
    ) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: testCase.path) { request in
            try NetworkEndpointTestSupport.expectPOST(
                request, function: testCase.function, json: testCase.expectedJSON
            )
            let attempt = attempts.withLock { count in
                count += 1
                return count
            }
            let status = attempt == 1 || (attempt == 2 && !replaySucceeds) ? 503 : 200
            return try NetworkEndpointTestSupport.response(to: request, status: status, json: testCase.responseJSON)
        }

        if testCase.isAmbiguousReplayAllowlisted && replaySucceeds {
            try await testCase.invoke(fixture.client)
        } else {
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("A non-replayed or exhausted request must propagate its HTTP failure")
            } catch MerianError.httpError(let status, _) {
                #expect(status == 503)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(attempts.withLock { $0 } == (testCase.isAmbiguousReplayAllowlisted ? 2 : 1))
    }

    @Test(arguments: CommunityIdentificationEndpointRequestCase.operations)
    func cancellationBeforeDispatchDoesNotSend(_ testCase: CommunityIdentificationEndpointRequestCase) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }

        await confirmation("No cancelled Community POST", expectedCount: 0) { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
            }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                try await testCase.invoke(fixture.client)
            }
            await #expect(throws: CancellationError.self) {
                try await task.value
            }
        }
    }
}
