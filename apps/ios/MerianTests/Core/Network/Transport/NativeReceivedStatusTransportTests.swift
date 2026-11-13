import Foundation
import os
import Testing
@testable import Merian

@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct NativeReceivedStatusTransportTests {
    @Test func recoveryUsesExactSavedBindingsAndDedicatedResponseBudgets() async throws {
        let saved = try InitialCompletionStatusTestFixture.load(), owner = try #require(UUID(uuidString: saved.original.ownerID))
        let fixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: owner)
        defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let found = try #require(saved.replies.first { $0.name == "unicode" })
        fixture.dispatcher.overridingAuthSessionRefresh = { Issue.record("Recovery refreshed Auth"); return true }
        fixture.mock.register(path: "/check-scan-status") { request in
            calls.withLock { $0 += 1 }
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let envelope = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(Set(envelope.keys) == ["initial_recovery"])
            #expect(envelope["scan_id"] == nil && envelope["scans"] == nil && envelope["recovery_scan"] == nil)
            let recovery = try #require(envelope["initial_recovery"] as? [String: Any])
            let original = try #require(recovery["original"] as? [String: Any])
            #expect(original["owner_id"] as? String == saved.original.ownerID)
            #expect(original["scan_id"] as? String == saved.original.scanID)
            let admission = recovery["phase"] as? String == "admission"
            #expect(request.value(forHTTPHeaderField: "X-Merian-Initial-Recovery") == (admission ? "admission-v1" : "completion-v1"))
            if admission {
                #expect(original["candidate_canonical"] as? String == saved.original.candidateCanonical)
                #expect(original["assignment_canonical"] == nil && original.count == 8)
            } else { #expect(original.count == 12 && original["result_evidence_id"] == nil) }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, Data((admission ? saved.acknowledgement : found.bytes).utf8))
        }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        let acknowledgement = try await transport.recoverAdmission(saved.original, validate: {})
        let admission = try InitialCompletionDocuments.CpmAdmission(acknowledgement: acknowledgement, original: saved.original)
        let result = try #require(await transport.recoverCompletion(admission, validate: {}))
        let expectedResult = try #require(found.result_canonical)
        #expect(result.result.result == Data(expectedResult.utf8))
        #expect(calls.withLock { $0 } == 2)
        #expect(NativeReceivedStatusTransport.maximumBytes == 4096)
    }

    @Test(arguments: ["owner", "attempt", "oversized", "mime", "401", "cancelled"])
    func recoveryFailuresNeverRefreshOrRepeat(fault: String) async throws {
        let saved = try InitialCompletionStatusTestFixture.load(), owner = try #require(UUID(uuidString: saved.original.ownerID))
        let fixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: owner)
        defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.dispatcher.overridingAuthSessionRefresh = { Issue.record("Recovery refreshed Auth"); return true }
        fixture.mock.register(path: "/check-scan-status") { request in
            calls.withLock { $0 += 1 }
            return (HTTPURLResponse(url: request.url!, statusCode: fault == "401" ? 401 : 200, httpVersion: nil,
                headerFields: ["Content-Type": fault == "mime" ? "text/plain" : "application/json"])!,
                fault == "oversized" ? Data(repeating: 32, count: 8193) : Data(saved.acknowledgement.utf8))
        }
        if fault == "owner" { fixture.dispatcher.overridingAuthUserID = UUID() }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        let task = Task {
            if fault == "cancelled" { withUnsafeCurrentTask { $0?.cancel() } }
            return try await transport.recoverAdmission(saved.original, validate: {
                if fault == "attempt" { throw SharedMediaStorageFailure.stale }
            })
        }
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(calls.withLock { $0 } == (["owner", "attempt", "cancelled"].contains(fault) ? 0 : 1))
    }
    @Test(arguments: [401, 409, 429, 503, 302, -1])
    func failuresNeverRefreshOrRepeat(status: Int) async throws {
        let owner = UUID(), fixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: owner)
        defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.dispatcher.overridingAuthSessionRefresh = { Issue.record("Status refreshed Auth"); return true }
        fixture.mock.register(path: "/check-scan-status") { request in
            calls.withLock { $0 += 1 }
            #expect(request.value(forHTTPHeaderField: "X-Merian-Initial-Recovery") == "observe-v1")
            if status == -1 { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!, Data())
        }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        await #expect(throws: (any Error).self) {
            _ = try await transport.perform(scanID: UUID(), ownerID: owner, validate: {})
        }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test(arguments: ["owner", "attempt", "oversized", "mime"])
    func ownerAndResponseBoundsAreEnforced(fault: String) async throws {
        let owner = UUID(), fixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: owner)
        defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.mock.register(path: "/check-scan-status") { request in
            calls.withLock { $0 += 1 }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": fault == "mime" ? "text/plain" : "application/json"])!,
                fault == "oversized" ? Data(repeating: 32, count: 4097) : Data("{\"status\":\"found\"}".utf8))
        }
        if fault == "owner" { fixture.dispatcher.overridingAuthUserID = UUID() }
        let transport = NativeReceivedStatusTransport(baseURL: "https://example.supabase.co", dispatcher: fixture.dispatcher)
        await #expect(throws: (any Error).self) {
            _ = try await transport.perform(scanID: UUID(), ownerID: owner, validate: {
                if fault == "attempt" { throw SharedMediaStorageFailure.stale }
            })
        }
        #expect(calls.withLock { $0 } == (["owner", "attempt"].contains(fault) ? 0 : 1))
    }
}
