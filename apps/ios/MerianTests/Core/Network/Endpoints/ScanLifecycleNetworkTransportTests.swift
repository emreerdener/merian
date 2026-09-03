import Foundation
import os
import Testing

@testable import Merian

@Suite("Scan Lifecycle Network Transport")
@MainActor
struct ScanLifecycleNetworkTransportTests {
    @Test(arguments: ScanLifecycleNetworkRequestCase.operations, ["", "not-json", "{}", "null", "[]"])
    func malformedSuccessIsInvalidResponse(_ testCase: ScanLifecycleNetworkRequestCase, json: String) async throws {
        try await testCase.withResponse(json) { client in
            await #expect(throws: MerianError.invalidResponse) { try await testCase.invoke(client) }
        }
    }

    @Test(arguments: ScanLifecycleNetworkRequestCase.operations, [400, 401, 403, 404, 409, 422])
    func handlerDenialsDoNotDecodeSuccessOrRefreshAuth(_ testCase: ScanLifecycleNetworkRequestCase, status: Int) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = {
            refreshes.withLock { $0 += 1 }
            // An unexpected refresh must stay in the private mock transport.
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
                Issue.record("A handler denial must not become success")
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

    @Test(arguments: ScanLifecycleNetworkRequestCase.operations, [200, 401, 503])
    func classifiedAuthRefreshKeepsOneReplayAndTheSameBody(
        _ testCase: ScanLifecycleNetworkRequestCase, replayStatus: Int
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
                let snapshot = try testCase.expectRequest(request)
                requests.withLock { $0.append(snapshot) }
                let attempt = attempts.withLock { count in count += 1; return count }
                if attempt == 1 || (attempt == 2 && replayStatus == 401) {
                    return try NetworkEndpointTestSupport.response(
                        to: request, status: 401, json: #"{"code":"invalid_session_token","error":"Synthetic invalid session"}"#
                    )
                }
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

    @Test(arguments: ScanLifecycleNetworkRequestCase.statusOperations, ScanLifecycleReplayScenario.allCases)
    func statusKeepsBoundedAmbiguousReplay(_ testCase: ScanLifecycleNetworkRequestCase, scenario: ScanLifecycleReplayScenario) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let requests = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        fixture.transport.register(path: testCase.path) { request in
            let snapshot = try testCase.expectRequest(request)
            requests.withLock { $0.append(snapshot) }
            let attempt = attempts.withLock { count in count += 1; return count }
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

    @Test(arguments: [false, true])
    func ambiguousDeletionIsNotReplayed(isServerFailure: Bool) async {
        let testCase = ScanLifecycleNetworkRequestCase.deletion
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("Only one deletion attempt") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try testCase.expectRequest(request)
                if !isServerFailure { throw URLError(.networkConnectionLost) }
                return try NetworkEndpointTestSupport.response(to: request, status: 503, json: testCase.responseJSON)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("An ambiguous deletion must remain unconfirmed")
            } catch MerianError.httpError(let status, _) {
                #expect(isServerFailure && status == 503)
            } catch let error as URLError {
                #expect(!isServerFailure && error.code == .networkConnectionLost)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test(arguments: ScanLifecycleNetworkRequestCase.operations)
    func cancellationBeforeDispatchDoesNotSend(_ testCase: ScanLifecycleNetworkRequestCase) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No cancelled request", expectedCount: 0) { sent in
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

    @Test(arguments: ScanLifecycleNetworkRequestCase.operations)
    func independentlyCancelledTransportKeepsItsError(_ testCase: ScanLifecycleNetworkRequestCase) async {
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

    @Test(arguments: ScanLifecycleNetworkRequestCase.operations)
    func cancellationDuringDispatchRemainsTaskCancellation(_ testCase: ScanLifecycleNetworkRequestCase) async {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let taskStorage = OSAllocatedUnfairLock<Task<Void, Error>?>(initialState: nil)
        defer { taskStorage.withLock { $0 = nil } }
        await confirmation("One task-cancelled transport") { sent in
            fixture.transport.register(path: testCase.path) { request in
                sent()
                try testCase.expectRequest(request)
                taskStorage.withLock { $0 }?.cancel()
                throw URLError(.cancelled)
            }
            let task = Task { @MainActor in try await testCase.invoke(fixture.client) }
            taskStorage.withLock { $0 = task }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }
}

enum ScanLifecycleReplayScenario: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case transportRecovers, transportExhausts, serverRecovers, serverExhausts
    var testDescription: String { rawValue }
    var isServerFailure: Bool { self == .serverRecovers || self == .serverExhausts }
    var replaySucceeds: Bool { self == .transportRecovers || self == .serverRecovers }
}
