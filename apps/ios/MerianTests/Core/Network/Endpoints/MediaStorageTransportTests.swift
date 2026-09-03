import Foundation
import os
import Testing

@testable import Merian

@Suite("Media Storage Transport")
@MainActor
struct MediaStorageTransportTests {
    typealias RequestCase = MediaStorageRequestCase

    @Test(arguments: RequestCase.allCases, [400, 401, 403, 404, 409, 413, 422])
    func handlerDenialsDoNotRefreshOrDecodeSuccess(testCase: RequestCase, status: Int) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = {
            refreshes.withLock { $0 += 1 }
            return true
        }
        await confirmation("One handler denial") { sent in
            fixture.transport.register(path: "/\(testCase.function)") { request in
                sent()
                try testCase.expectRequest(request)
                return try NetworkEndpointTestSupport.response(to: request, status: status, json: testCase.responseJSON)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("A handler denial must propagate")
            } catch MerianError.httpError(let actual, _) {
                #expect(status != 401 && actual == status)
            } catch MerianError.invalidResponse {
                #expect(status == 401)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
        #expect(refreshes.withLock { $0 } == 0)
    }

    @Test(arguments: RequestCase.allCases, [200, 401, 503])
    func classifiedRefreshRetainsOneReplayAndExactRequest(testCase: RequestCase, replayStatus: Int) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let requests = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        await confirmation("One classified refresh") { refreshed in
            fixture.client.overridingAuthSessionRefresh = {
                refreshed()
                return true
            }
            fixture.transport.register(path: "/\(testCase.function)") { request in
                let snapshot = try testCase.expectRequest(request)
                requests.withLock { $0.append(snapshot) }
                let attempt = attempts.withLock { count in count += 1; return count }
                if attempt == 1 || replayStatus == 401 {
                    return try NetworkEndpointTestSupport.response(
                        to: request, status: 401,
                        json: #"{"code":"invalid_session_token","error":"Synthetic invalid session"}"#
                    )
                }
                return try NetworkEndpointTestSupport.response(to: request, status: replayStatus, json: testCase.responseJSON)
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

    @Test(arguments: RequestCase.allCases, [false, true])
    func signingAndBothRepairActionsRefuseAmbiguousReplay(testCase: RequestCase, serverFailure: Bool) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("One unkeyed request") { sent in
            fixture.transport.register(path: "/\(testCase.function)") { request in
                sent()
                try testCase.expectRequest(request)
                if serverFailure {
                    return try NetworkEndpointTestSupport.response(to: request, status: 503, json: testCase.responseJSON)
                }
                throw URLError(.networkConnectionLost)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("Ambiguous failure must propagate")
            } catch MerianError.httpError(let status, _) {
                #expect(serverFailure && status == 503)
            } catch let error as URLError {
                #expect(!serverFailure && error.code == .networkConnectionLost)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test(arguments: RequestCase.allCases)
    func preDispatchCancellationDoesNotSend(testCase: RequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No cancelled request", expectedCount: 0) { sent in
            fixture.transport.register(path: "/\(testCase.function)") { request in
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

    @Test(arguments: RequestCase.allCases)
    func independentTransportCancellationStaysUnwrapped(testCase: RequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("One cancelled transport") { sent in
            fixture.transport.register(path: "/\(testCase.function)") { _ in
                sent()
                throw URLError(.cancelled)
            }
            do {
                try await testCase.invoke(fixture.client)
                Issue.record("Cancellation must propagate")
            } catch let error as URLError {
                #expect(error.code == .cancelled)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }
}
