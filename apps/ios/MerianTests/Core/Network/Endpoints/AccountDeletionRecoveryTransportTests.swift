import Foundation
import os
import Testing

@testable import Merian

@Suite("Account Deletion Recovery Transport")
@MainActor
struct AccountDeletionRecoveryTransportTests {
    typealias RequestCase = AccountDeletionRecoveryRequestCase

    @Test(arguments: RequestCase.allCases)
    func everyOperationUsesExactPublicHeadersAndProofKeysWithoutAnAccount(testCase: RequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        fixture.client.overridingAuthSessionRefresh = {
            Issue.record("Public recovery must not refresh Auth")
            return false
        }
        try await confirmation("One capability-only request") { sent in
            fixture.transport.register(path: "/recover-account-deletion") { request in
                sent()
                try testCase.expectRequest(request)
                return try testCase.response(to: request)
            }
            let receipt = try await testCase.invoke(fixture.client)
            #expect(receipt.status == .completed)
        }
    }

    @Test(arguments: RequestCase.allCases)
    func invalidProofIsRejectedBeforeIO(testCase: RequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No malformed-proof request", expectedCount: 0) { sent in
            fixture.transport.register(path: "/recover-account-deletion") { request in
                sent()
                return try testCase.response(to: request)
            }
            await #expect(throws: MerianError.invalidResponse) { try await testCase.invoke(fixture.client, capability: "invalid") }
        }
    }

    @Test(arguments: RequestCase.allCases, [202, 400, 401, 404, 410, 413])
    func non200ClientResponsesPropagateWithoutAuthOrReplay(testCase: RequestCase, status: Int) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let json = #"{"code":"synthetic_recovery_denial"}"#
        fixture.client.overridingAuthSessionRefresh = {
            Issue.record("Even a recovery 401 must not refresh Auth")
            return true
        }
        await confirmation("One rejected recovery request") { sent in
            fixture.transport.register(path: "/recover-account-deletion") { request in
                sent()
                try testCase.expectRequest(request)
                return try NetworkEndpointTestSupport.response(to: request, status: status, json: json)
            }
            await #expect(throws: MerianError.httpError(statusCode: status, message: json)) {
                try await testCase.invoke(fixture.client)
            }
        }
    }

    @Test(arguments: RequestCase.allCases, [false, true])
    func serverFailureAllowsExactlyOneIdenticalReplay(testCase: RequestCase, replaySucceeds: Bool) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let snapshots = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        fixture.transport.register(path: "/recover-account-deletion") { request in
            let snapshot = try testCase.expectRequest(request)
            let attempt = snapshots.withLock { values in values.append(snapshot); return values.count }
            return try testCase.response(to: request, status: attempt == 2 && replaySucceeds ? 200 : 503)
        }
        if replaySucceeds {
            #expect(try await testCase.invoke(fixture.client).status == .completed)
        } else {
            do {
                _ = try await testCase.invoke(fixture.client)
                Issue.record("The second server failure must propagate")
            } catch MerianError.httpError(let status, _) {
                #expect(status == 503)
            }
        }
        #expect(snapshots.withLock { $0.count == 2 && $0[0] == $0[1] })
    }

    @Test(arguments: [URLError.Code.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet])
    func eachTransientTransportFailureHasOnlyOneRetry(code: URLError.Code) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let snapshots = OSAllocatedUnfairLock(initialState: [NetworkEndpointRequestSnapshot]())
        fixture.transport.register(path: "/recover-account-deletion") { request in
            let snapshot = try RequestCase.recoverV2.expectRequest(request)
            snapshots.withLock { $0.append(snapshot) }
            throw URLError(code)
        }
        do {
            _ = try await RequestCase.recoverV2.invoke(fixture.client)
            Issue.record("The second transport failure must propagate")
        } catch let error as URLError {
            #expect(error.code == code)
        }
        #expect(snapshots.withLock { $0.count == 2 && $0[0] == $0[1] })
    }

    @Test(arguments: [64 * 1024, 64 * 1024 + 1], [200, 503])
    func responseLimitIsCheckedBeforeDecodingOrServerRetry(size: Int, status: Int) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: "/recover-account-deletion") { request in
            attempts.withLock { $0 += 1 }
            let (response, receipt) = try RequestCase.recoverV2.response(to: request, status: status)
            return (response, receipt + Data(repeating: 0x20, count: size - receipt.count))
        }
        if size > 64 * 1024 {
            await #expect(throws: MerianError.invalidResponse) { try await RequestCase.recoverV2.invoke(fixture.client) }
        } else if status == 200 {
            #expect(try await RequestCase.recoverV2.invoke(fixture.client).status == .completed)
        } else {
            do {
                _ = try await RequestCase.recoverV2.invoke(fixture.client)
                Issue.record("The bounded server error must propagate")
            } catch MerianError.httpError(let actual, let message) {
                #expect(actual == status && message.utf8.count == size)
            }
        }
        #expect(attempts.withLock { $0 } == (size <= 64 * 1024 && status == 503 ? 2 : 1))
    }

    @Test(arguments: RequestCase.allCases)
    func malformedReceiptsMapToInvalidResponseWithoutRetry(testCase: RequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("One malformed receipt") { sent in
            fixture.transport.register(path: "/recover-account-deletion") { request in
                sent()
                return try NetworkEndpointTestSupport.response(to: request, json: "{}")
            }
            await #expect(throws: MerianError.invalidResponse) { try await testCase.invoke(fixture.client) }
        }
    }

    @Test(arguments: RequestCase.allCases)
    func preDispatchCancellationDoesNotSend(testCase: RequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("No cancelled request", expectedCount: 0) { sent in
            fixture.transport.register(path: "/recover-account-deletion") { request in
                sent()
                return try testCase.response(to: request)
            }
            let task = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                return try await testCase.invoke(fixture.client)
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test(arguments: RequestCase.allCases)
    func independentTransportCancellationIsNotWrappedOrRetried(testCase: RequestCase) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        await confirmation("One independently cancelled transport") { sent in
            fixture.transport.register(path: "/recover-account-deletion") { _ in
                sent()
                throw URLError(.cancelled)
            }
            do {
                _ = try await testCase.invoke(fixture.client)
                Issue.record("Independent cancellation must propagate")
            } catch let error as URLError {
                #expect(error.code == .cancelled)
            } catch {
                Issue.record("Unexpected error type: \(type(of: error))")
            }
        }
    }

    @Test(arguments: [false, true])
    func owningTaskCancellationWinsOverResponseOrTransportFailure(transportFails: Bool) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        let owner = OSAllocatedUnfairLock(initialState: Optional<Task<AccountDeletionReceipt, Error>>.none)
        fixture.transport.register(path: "/recover-account-deletion") { request in
            owner.withLock { $0?.cancel() }
            if transportFails { throw URLError(.cancelled) }
            return try RequestCase.recoverV2.response(to: request)
        }
        // MainActor serialization installs the handle before the child can dispatch.
        let task = Task { @MainActor in try await RequestCase.recoverV2.invoke(fixture.client) }
        owner.withLock { $0 = task }
        defer { owner.withLock { $0 = nil }; task.cancel() }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
