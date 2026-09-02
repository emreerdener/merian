import Foundation
import os
import Testing

@testable import Merian

@Suite("Field Trip Endpoints")
@MainActor
struct FieldTripEndpointTests {
    @Test(arguments: FieldTripEndpointRequestCase.all)
    func requestMappingRemainsStable(_ testCase: FieldTripEndpointRequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("Exactly one Field Trips POST") { sent in
            fixture.transport.register(path: "/field-trips") { request in
                sent()
                try NetworkEndpointTestSupport.expectPOST(
                    request, function: "field-trips", json: testCase.expectedJSON, timeout: testCase.timeout
                )
                return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
            }
            try await testCase.invoke(fixture.client)
        }
    }

    @Test(arguments: [
        (#"{"liked":true}"#, #"{"liked":1}"#),
        (#"{"liked":false}"#, #"{"liked":0}"#),
        (#"{"limit":1}"#, #"{"limit":"1"}"#),
        (#"{"title":null}"#, #"{}"#)
    ])
    func requestComparisonPreservesJSONTypes(_ expected: String, _ actual: String) throws {
        #expect(
            try NetworkEndpointTestSupport.canonicalRequestJSON(Data(expected.utf8))
                != NetworkEndpointTestSupport.canonicalRequestJSON(Data(actual.utf8))
        )
    }

    @Test func requestComparisonIgnoresObjectKeyOrder() throws {
        let first = Data(#"{"publication_id":"publication","liked":true}"#.utf8)
        let reordered = Data(#"{"liked":true,"publication_id":"publication"}"#.utf8)
        #expect(try NetworkEndpointTestSupport.canonicalRequestJSON(first) == NetworkEndpointTestSupport.canonicalRequestJSON(reordered))
    }

    @Test func decodesSnakeCaseAndKeepsTypedPublicationResponses() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/field-trips") { request in
            try NetworkEndpointTestSupport.response(to: request, json: FieldTripEndpointResponses.like)
        }

        let outing = try await fixture.client.setFieldTripLike(publicationId: "publication", liked: true)
        let event = try await fixture.client.setFieldTripChallengeEntryLike(entryId: "entry", liked: true)
        #expect(outing.publicationId == "publication")
        #expect(event.entryId == "entry")
        #expect(outing.likeCount == 7 && event.likeCount == 7)
        #expect(outing.commentCount == 3 && event.commentCount == 3)
        #expect(outing.viewerHasLiked && event.viewerHasLiked)
    }

    @Test func progressPreservesAchievementProjection() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/field-trips") { request in
            try NetworkEndpointTestSupport.response(to: request, json: FieldTripEndpointResponses.progress)
        }

        let result = try await fixture.client.applyFieldTripProgress(scanId: "scan")
        #expect(result.fieldTripUpdates.isEmpty && result.challengeUpdates.isEmpty)
        #expect(result.firstFieldTripAchievement?.kind == .standardOuting)
        #expect(result.firstFieldTripAchievement?.templateSlug == "outing")
        #expect(result.firstFieldTripAchievementNewlyUnlocked)
    }

    @Test func malformedSuccessStillThrowsDecodingError() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: "/field-trips") { request in
            try NetworkEndpointTestSupport.response(to: request, json: #"{"data":"not-an-array"}"#)
        }

        await #expect(throws: DecodingError.self) {
            try await fixture.client.getFieldTrips()
        }
    }

    @Test func handlerFailureIsNotDecodedAsSuccess() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }

        await confirmation("A handler denial is not replayed") { sent in
            fixture.transport.register(path: "/field-trips") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, status: 400, json: #"{"code":"invalid_action"}"#)
            }
            do {
                _ = try await fixture.client.getFieldTrips()
                Issue.record("A handler failure must not return a catalog")
            } catch MerianError.httpError(let status, _) {
                #expect(status == 400)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test func authRefreshKeepsTheExistingSingleReplayBoundary() async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)

        try await confirmation("One session refresh") { refreshed in
            fixture.client.overridingAuthSessionRefresh = {
                refreshed()
                return true
            }
            fixture.transport.register(path: "/field-trips") { request in
                let attempt = attempts.withLock { count in
                    count += 1
                    return count
                }
                if attempt == 1 {
                    return try NetworkEndpointTestSupport.response(
                        to: request,
                        status: 401,
                        json: #"{"code":"invalid_session_token","error":"Invalid session"}"#
                    )
                }
                return try NetworkEndpointTestSupport.response(to: request, json: FieldTripEndpointResponses.empty)
            }
            let result = try await fixture.client.getFieldTrips()
            #expect(result.isEmpty)
        }
        #expect(attempts.withLock { $0 } == 2)
    }

    @Test func ambiguousFieldTripPostsAreNotReplayed() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }

        await confirmation("Exactly one ambiguous POST") { sent in
            fixture.transport.register(path: "/field-trips") { _ in
                sent()
                throw URLError(.networkConnectionLost)
            }
            do {
                _ = try await fixture.client.startFieldTrip(templateId: "template")
                Issue.record("An ambiguous POST must propagate its transport failure")
            } catch let error as URLError {
                #expect(error.code == .networkConnectionLost)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test func cancellationBeforeDispatchDoesNotSend() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }

        await confirmation("No cancelled POST", expectedCount: 0) { sent in
            fixture.transport.register(path: "/field-trips") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: FieldTripEndpointResponses.empty)
            }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await fixture.client.getFieldTrips()
            }
            await #expect(throws: CancellationError.self) {
                try await task.value
            }
        }
    }
}
