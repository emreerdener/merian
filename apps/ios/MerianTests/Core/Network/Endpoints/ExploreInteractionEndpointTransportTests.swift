import Foundation
import os
import Testing

@testable import Merian

@Suite("Explore Interaction Endpoint Transport")
@MainActor
struct ExploreInteractionEndpointTransportTests {
    @Test(arguments: ExploreInteractionEndpointRequestCase.typedOperations, ["", "not-json", "{}", #"{"success":true,"data":null}"#])
    func malformedTypedSuccessStillThrowsDecodingError(
        _ testCase: ExploreInteractionEndpointRequestCase,
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

    @Test(arguments: ExploreInteractionEndpointRequestCase.operations, [400, 401, 404])
    func handlerDenialsAreNotSuccessOrReplayed(
        _ testCase: ExploreInteractionEndpointRequestCase,
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

    @Test(arguments: ExploreInteractionEndpointRequestCase.operations, [200, 401, 503])
    func authRefreshKeepsOneReplayAndTheSamePayload(
        _ testCase: ExploreInteractionEndpointRequestCase,
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

    @Test(arguments: ExploreInteractionEndpointRequestCase.readOperations, [true, false])
    func ambiguousTransportReplayIsBounded(
        _ testCase: ExploreInteractionEndpointRequestCase,
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
    }

    @Test(arguments: ExploreInteractionEndpointRequestCase.readOperations, [true, false])
    func ambiguousServerReplayIsBounded(
        _ testCase: ExploreInteractionEndpointRequestCase,
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
    }

    @Test(arguments: ExploreInteractionEndpointRequestCase.operations)
    func cancellationBeforeDispatchDoesNotSend(_ testCase: ExploreInteractionEndpointRequestCase) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }

        await confirmation("No cancelled Explore interaction POST", expectedCount: 0) { sent in
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
    @Test(arguments: ExploreInteractionEndpointRequestCase.voidOperations)
    func voidMutationsIgnoreSuccessfulBodies(_ testCase: ExploreInteractionEndpointRequestCase) async throws {
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
                    try NetworkEndpointTestSupport.expectPOST(
                        request, function: testCase.function, json: testCase.expectedJSON
                    )
                    return try NetworkEndpointTestSupport.response(to: request, status: status, json: json)
                }
                try await testCase.invoke(fixture.client)
            }
        }
    }

    @Test(arguments: ExploreInteractionEndpointRequestCase.mutations, [false, true])
    func ambiguousMutationFailuresNeverReplay(
        _ testCase: ExploreInteractionEndpointRequestCase,
        serverFailure: Bool
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("Exactly one mutation attempt") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try NetworkEndpointTestSupport.expectPOST(
                    request, function: testCase.function, json: testCase.expectedJSON
                )
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

    @Test(arguments: ExploreInteractionEndpointRequestCase.operations)
    func independentlyCancelledTransportKeepsItsErrorAndDoesNotRetry(
        _ testCase: ExploreInteractionEndpointRequestCase
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
}
