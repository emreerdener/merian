import Foundation
import os
import Testing

@testable import Merian

@Suite("Field Chat Network Transport")
@MainActor
struct FieldChatNetworkTransportTests {
    @Test(arguments: FieldChatNetworkRequestCase.operations, ["", "not-json", "{}", #"{"data":null}"#])
    func malformedSuccessIsInvalidResponse(
        _ testCase: FieldChatNetworkRequestCase, json: String
    ) async throws {
        try await testCase.withResponse(json) { client in
            await #expect(throws: MerianError.invalidResponse) {
                try await testCase.invoke(client)
            }
        }
    }

    @Test(arguments: FieldChatNetworkRequestCase.operations)
    func oversizedSuccessIsRejectedWithoutReplay(_ testCase: FieldChatNetworkRequestCase) async throws {
        let padding = String(repeating: " ", count: 1_048_577 - testCase.responseJSON.utf8.count)
        try await testCase.withResponse(testCase.responseJSON + padding) { client in
            await #expect(throws: MerianError.invalidResponse) {
                try await testCase.invoke(client)
            }
        }
    }

    @Test(arguments: FieldChatNetworkRequestCase.operations, [400, 401, 403, 404, 409, 422])
    func handlerDenialsAreNotSuccessOrReplayed(_ testCase: FieldChatNetworkRequestCase, status: Int) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = {
            refreshes.withLock { $0 += 1 }
            // A regression must remain inside the mock transport, not recover
            // a live identity when an unclassified denial is misclassified.
            return true
        }
        await confirmation("One handler denial") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try testCase.expectRequest(request)
                return try NetworkEndpointTestSupport.response(to: request, status: status, json: testCase.responseJSON)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("A handler denial must not be decoded as success")
            } catch MerianError.httpError(let actualStatus, _) {
                #expect(status != 401 && actualStatus == status)
            } catch MerianError.invalidResponse {
                #expect(status == 401)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(refreshes.withLock { $0 } == 0)
    }

    @Test(arguments: FieldChatNetworkRequestCase.operations, [200, 401, 503])
    func authRefreshKeepsOneReplayAndTheSameEncodedRequest(
        _ testCase: FieldChatNetworkRequestCase, replayStatus: Int
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let requests = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        await confirmation("One session refresh") { refreshed in
            fixture.client.overridingAuthSessionRefresh = {
                refreshed()
                return true
            }
            fixture.transport.register(path: testCase.path) { request in
                let fingerprint = try testCase.expectRequest(request)
                requests.withLock { $0.append(fingerprint) }
                let attempt = attempts.withLock { count in
                    count += 1
                    return count
                }
                if attempt == 1 || (attempt == 2 && replayStatus == 401) {
                    return try NetworkEndpointTestSupport.response(
                        to: request, status: 401, json: #"{"code":"invalid_session_token","error":"Invalid session"}"#
                    )
                }
                // A third attempt succeeds so accidental extra replay fails
                // bounded assertions instead of hanging the test.
                return try NetworkEndpointTestSupport.response(
                    to: request, status: attempt == 2 ? replayStatus : 200, json: testCase.responseJSON
                )
            }
            do {
                try await testCase.invoke(fixture.client)
                #expect(replayStatus == 200)
            } catch MerianError.httpError(let status, _) {
                #expect(replayStatus != 200 && status == replayStatus)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(attempts.withLock { $0 } == 2)
        #expect(requests.withLock { $0.count == 2 && $0[0] == $0[1] })
    }

    @Test(arguments: FieldChatNetworkRequestCase.replayableOperations, FieldChatReplayScenario.allCases)
    func ambiguousReplayIsBoundedAndKeepsTheEncodedRequest(
        _ testCase: FieldChatNetworkRequestCase, scenario: FieldChatReplayScenario
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let requests = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        fixture.transport.register(path: testCase.path) { request in
            let fingerprint = try testCase.expectRequest(request)
            requests.withLock { $0.append(fingerprint) }
            let attempt = attempts.withLock { count in
                count += 1
                return count
            }
            if attempt == 1 || (attempt == 2 && !scenario.replaySucceeds) {
                if !scenario.isServerFailure { throw URLError(.networkConnectionLost) }
                return try NetworkEndpointTestSupport.response(to: request, status: 503, json: testCase.responseJSON)
            }
            return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
        }
        do {
            try await testCase.invoke(fixture.client)
            #expect(scenario.replaySucceeds)
        } catch MerianError.httpError(let status, _) {
            #expect(!scenario.replaySucceeds && scenario.isServerFailure && status == 503)
        } catch let error as URLError {
            #expect(!scenario.replaySucceeds && !scenario.isServerFailure && error.code == .networkConnectionLost)
        } catch {
            Issue.record("Unexpected error type: \(type(of: error))")
        }
        #expect(attempts.withLock { $0 } == 2)
        #expect(requests.withLock { $0.count == 2 && $0[0] == $0[1] })
    }

    @Test(arguments: FieldChatNetworkRequestCase.nonReplayableOperations, [false, true])
    func unkeyedActionsNeverReplayAmbiguousFailures(
        _ testCase: FieldChatNetworkRequestCase, serverFailure: Bool
    ) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("One unkeyed action attempt") { sent in
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
                Issue.record("An unkeyed action must propagate an ambiguous failure")
            } catch MerianError.httpError(let status, _) {
                #expect(serverFailure && status == 503)
            } catch let error as URLError {
                #expect(!serverFailure && error.code == .networkConnectionLost)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test(arguments: FieldChatNetworkRequestCase.operations)
    func cancellationBeforeDispatchDoesNotSend(_ testCase: FieldChatNetworkRequestCase) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No cancelled Field Chat POST", expectedCount: 0) { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: testCase.responseJSON)
            }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                try await testCase.invoke(fixture.client)
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test(arguments: FieldChatNetworkRequestCase.operations)
    func independentlyCancelledTransportKeepsItsError(_ testCase: FieldChatNetworkRequestCase) async {
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

    @Test(arguments: [FieldChatNetworkRequestCase.prompts(.insight), FieldChatNetworkRequestCase.summary])
    func independentGeneratedActionsReceiveDifferentKeys(_ testCase: FieldChatNetworkRequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let keys = OSAllocatedUnfairLock(initialState: [String]())
        try await confirmation("Two independent generated actions", expectedCount: 2) { sent in
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

    @Test func encodingFailureIsNotMappedOrDispatched() async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No unencodable request", expectedCount: 0) { sent in
            fixture.transport.register(path: "/insight-chat") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "{}")
            }
            await #expect(throws: FieldChatEncodingFailure.rejected) {
                _ = try await fixture.client.performAuthenticatedEncodedJSONPost(
                    function: "insight-chat", body: UnencodableFieldChatBody(), timeoutInterval: 20
                )
            }
        }
    }
}

enum FieldChatReplayScenario: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case transportRecovers, transportExhausts, serverRecovers, serverExhausts
    var testDescription: String { rawValue }
    var isServerFailure: Bool { self == .serverRecovers || self == .serverExhausts }
    var replaySucceeds: Bool { self == .transportRecovers || self == .serverRecovers }
}

private enum FieldChatEncodingFailure: Error { case rejected }
private struct UnencodableFieldChatBody: Encodable {
    func encode(to encoder: Encoder) throws { throw FieldChatEncodingFailure.rejected }
}
