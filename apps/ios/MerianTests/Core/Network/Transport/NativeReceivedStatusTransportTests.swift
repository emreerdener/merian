import Foundation
import os
import Testing
@testable import Merian

@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct NativeReceivedStatusTransportTests {
    @Test(arguments: [401, 409, 429, 503, 302, -1])
    func failuresNeverRefreshOrRepeat(status: Int) async throws {
        let owner = UUID(), fixture = InitialPhotoAllocationTransportTests.Fixture(ownerID: owner)
        defer { fixture.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.dispatcher.overridingAuthSessionRefresh = { Issue.record("Status refreshed Auth"); return true }
        fixture.mock.register(path: "/check-scan-status") { request in
            calls.withLock { $0 += 1 }
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
