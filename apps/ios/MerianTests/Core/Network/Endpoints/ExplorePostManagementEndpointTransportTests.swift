import Foundation
import os
import Testing

@testable import Merian

@Suite("Explore Post Management Endpoint Transport")
@MainActor
struct ExplorePostManagementEndpointTransportTests {
    @Test(arguments: ExplorePostManagementEndpointRequestCase.rawDecodingOperations, ["", "not-json", "{}", #"{"success":true,"data":null}"#])
    func malformedTypedSuccessStillThrowsDecodingError(
        _ testCase: ExplorePostManagementEndpointRequestCase,
        responseJSON: String
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.transport.register(path: testCase.path) { request in
            try NetworkEndpointTestSupport.response(to: request, json: responseJSON)
        }

        await #expect(throws: DecodingError.self) {
            try await testCase.invoke(fixture.client)
        }
    }

    @Test(arguments: ExplorePostManagementEndpointRequestCase.mappedDecodingOperations, ["", "not-json", "{}", #"{"success":true,"data":null}"#])
    func malformedMappedSuccessStillThrowsInvalidResponse(
        _ testCase: ExplorePostManagementEndpointRequestCase,
        responseJSON: String
    ) async throws {
        try await testCase.withResponse(responseJSON) { client in
            await #expect(throws: MerianError.invalidResponse) {
                try await testCase.invoke(client)
            }
        }
    }

    @Test(arguments: ExplorePostManagementEndpointRequestCase.operations, [400, 401, 403, 404, 409, 422])
    func handlerDenialsAreNotSuccessOrReplayed(
        _ testCase: ExplorePostManagementEndpointRequestCase,
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

    @Test(arguments: ExplorePostManagementEndpointRequestCase.operations, [200, 401, 503])
    func authRefreshKeepsOneReplayAndTheSamePayload(
        _ testCase: ExplorePostManagementEndpointRequestCase,
        replayStatus: Int
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let replayRequests = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())

        await confirmation("One session refresh") { refreshed in
            fixture.client.overridingAuthSessionRefresh = {
                refreshed()
                return true
            }
            fixture.transport.register(path: testCase.path) { request in
                let fingerprint = try testCase.expectRequest(request)
                replayRequests.withLock { $0.append(fingerprint) }
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
        #expect(replayRequests.withLock { $0.count == 2 && $0[0] == $0[1] })
    }

    @Test(arguments: ExplorePostManagementEndpointRequestCase.replayableOperations, [true, false])
    func ambiguousTransportReplayIsBounded(
        _ testCase: ExplorePostManagementEndpointRequestCase,
        replaySucceeds: Bool
    ) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let replayRequests = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        fixture.transport.register(path: testCase.path) { request in
            let fingerprint = try testCase.expectRequest(request)
            replayRequests.withLock { $0.append(fingerprint) }
            let attempt = attempts.withLock { count in
                count += 1
                return count
            }
            if attempt == 1 || (attempt == 2 && !replaySucceeds) {
                throw URLError(.networkConnectionLost)
            }
            return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
        }

        if replaySucceeds {
            try await testCase.invoke(fixture.client)
        } else {
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("An exhausted request must propagate its transport failure")
            } catch let error as URLError {
                #expect(error.code == .networkConnectionLost)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(attempts.withLock { $0 } == 2)
        #expect(replayRequests.withLock { $0.count == 2 && $0[0] == $0[1] })
    }

    @Test(arguments: ExplorePostManagementEndpointRequestCase.replayableOperations, [true, false])
    func ambiguousServerReplayIsBounded(
        _ testCase: ExplorePostManagementEndpointRequestCase,
        replaySucceeds: Bool
    ) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let replayRequests = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        fixture.transport.register(path: testCase.path) { request in
            let fingerprint = try testCase.expectRequest(request)
            replayRequests.withLock { $0.append(fingerprint) }
            let attempt = attempts.withLock { count in
                count += 1
                return count
            }
            let status = attempt == 1 || (attempt == 2 && !replaySucceeds) ? 503 : 200
            return try NetworkEndpointTestSupport.response(to: request, status: status, json: testCase.responseJSON)
        }

        if replaySucceeds {
            try await testCase.invoke(fixture.client)
        } else {
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("An exhausted request must propagate its HTTP failure")
            } catch MerianError.httpError(let status, _) {
                #expect(status == 503)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(attempts.withLock { $0 } == 2)
        #expect(replayRequests.withLock { $0.count == 2 && $0[0] == $0[1] })
    }

    @Test(arguments: ExplorePostManagementEndpointRequestCase.operations)
    func cancellationBeforeDispatchDoesNotSend(_ testCase: ExplorePostManagementEndpointRequestCase) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }

        await confirmation("No cancelled post-management POST", expectedCount: 0) { sent in
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
    @Test func unshareIgnoresSuccessfulBodies() async throws {
        let testCase = ExplorePostManagementEndpointRequestCase.unshare
        // Do not tighten existing HTTP-only success to require a JSON envelope,
        // nonempty body, success: true, or matching response identifiers.
        for (status, json) in [
            (200, ""), (204, ""), (200, "not-json"),
            (200, #"{"success":false,"error":"Test body is ignored","comment_id":"different"}"#),
            (299, "null")
        ] {
            let fixture = NetworkEndpointFixture()
            defer { fixture.close() }
            try await confirmation("One body-ignoring POST") { sent in
                fixture.transport.register(path: testCase.path) { request in
                    sent()
                    try testCase.expectRequest(request)
                    return try NetworkEndpointTestSupport.response(to: request, status: status, json: json)
                }
                try await testCase.invoke(fixture.client)
            }
        }
    }

    @Test(arguments: ExplorePostManagementEndpointRequestCase.nonReplayableMutations, [false, true])
    func ambiguousMutationFailuresNeverReplay(
        _ testCase: ExplorePostManagementEndpointRequestCase,
        serverFailure: Bool
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("Exactly one mutation attempt") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try testCase.expectRequest(request)
                if serverFailure {
                    return try NetworkEndpointTestSupport.response(to: request, status: 503, json: testCase.responseJSON)
                }
                throw URLError(.networkConnectionLost)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("An ambiguous mutation failure must propagate")
            } catch MerianError.httpError(let status, _) {
                #expect(serverFailure && status == 503)
            } catch let error as URLError {
                #expect(!serverFailure && error.code == .networkConnectionLost)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test(arguments: ExplorePostManagementEndpointRequestCase.operations)
    func independentlyCancelledTransportKeepsItsErrorAndDoesNotRetry(
        _ testCase: ExplorePostManagementEndpointRequestCase
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("One independently cancelled transport") { sent in
            fixture.transport.register(path: testCase.path) { _ in
                sent()
                throw URLError(.cancelled)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("Transport cancellation must propagate")
            } catch let error as URLError {
                #expect(error.code == .cancelled)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test func separateContentEditsReceiveDistinctKeysEvenWithoutMedia() async throws {
        let testCase = ExplorePostManagementEndpointRequestCase.contentEdit
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let keys = OSAllocatedUnfairLock(initialState: [String]())
        try await confirmation("Two independent edits", expectedCount: 2) { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try testCase.expectRequest(request)
                let key = try #require(request.value(forHTTPHeaderField: "Idempotency-Key"))
                keys.withLock { $0.append(key) }
                return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
            }
            try await testCase.invoke(fixture.client)
            try await testCase.invoke(fixture.client)
        }
        #expect(keys.withLock { $0.count == 2 && Set($0).count == 2 })
    }
}
