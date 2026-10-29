import Foundation
import os
import Testing
@testable import Merian

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct InitialPhotoAllocationTransportTests {
    typealias Request = InitialPhotoAllocationRequest
    static let path = "/initial-photo-allocation"
    struct Fixture {
        let mock = ScopedMockTransport(), pinned = PinnedNetworkTransport()
        let session: URLSession
        let dispatcher: AuthenticatedTransportDispatcher
        var transport: InitialPhotoAllocationTransport { .init(baseURL: "https://example.supabase.co", dispatcher: dispatcher) }
        init(ownerID: UUID) {
            session = mock.makeSession(); pinned.overridingSession = session
            dispatcher = AuthenticatedTransportDispatcher(sessionTransport: pinned)
            dispatcher.overridingAuthUserID = ownerID
            dispatcher.overridingAuthSessionRefresh = { Issue.record("Unexpected refresh"); return false }
        }
        func close() { session.invalidateAndCancel() }
    }
    static func reply(_ request: Request, changedObject: Bool = false) throws -> Data {
        let claim = request.allocation.claim
        let receipt = request.allocation.receipt ?? .init(assignmentDigest: String(repeating: "a", count: 64),
            createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001)
        let refs = try SharedMediaNativePhotoRoleMapping.references(claim)
        let entries: [[String: Any]] = refs.enumerated().map { index, ref in
            ["photo_ordinal": index / 3, "role": SharedMediaNativePhotoRoleMapping.Role.allCases[index % 3].rawValue,
             "reference_id": ref.uuidString.lowercased(),
             "object_id": String(format: "00000000-0000-4000-8000-%012d", index + (changedObject ? 200 : 100))]
        }
        return try JSONSerialization.data(withJSONObject: ["version": 2, "variant": "client_prepared_photo", "authority": "none",
            "scan_id": claim.observationID.uuidString.lowercased(), "package_id": claim.packageID.uuidString.lowercased(),
            "candidate_digest": claim.candidateDigest, "content_digest": claim.contentDigest, "outcome": "allocated",
            "assignment_digest": receipt.assignmentDigest, "created_at_ms": receipt.createdAtMilliseconds,
            "expires_at_ms": receipt.expiresAtMilliseconds, "role_mapping": entries], options: [.sortedKeys])
    }
    private func candidate() throws -> Request {
        try .init(allocation: InitialPhotoAllocationRoleReplyTests().request().allocation.reservingRoleMapping(), action: .status, projection: .roles)
    }
    @Test func projectionRequiresExplicitReservationAndRejectsCrossVersionAdapters() async throws {
        let legacy = try InitialPhotoAllocationRoleReplyTests().request(), request = try candidate()
        #expect(throws: (any Error).self) { _ = try Request(allocation: legacy.allocation, action: .status, projection: .roles) }
        let ordinary = try Request(allocation: request.allocation, action: .status)
        #expect(ordinary.projection == .legacy)
        let f = Fixture(ownerID: request.allocation.claim.profile.ownerID); defer { f.close() }
        f.mock.register(path: Self.path) { _ in Issue.record("Cross-version adapter sent"); throw MerianError.invalidResponse }
        await #expect(throws: (any Error).self) { _ = try await f.transport.perform(request, validateAttempt: {}, validateResponse: {}) }
        await #expect(throws: (any Error).self) { _ = try await f.transport.performRoles(ordinary, validateAttempt: {}, validateResponse: {}) }
    }
    @Test func exactBodyAndSavedMappingAreBoundToOneAttempt() async throws {
        let request = try candidate(), f = Fixture(ownerID: request.allocation.claim.profile.ownerID)
        defer { f.close() }
        let data = try Self.reply(request), body = request.body, calls = OSAllocatedUnfairLock(initialState: 0)
        f.mock.register(path: Self.path) { wire in
            calls.withLock { $0 += 1 }
            #expect(wire.httpMethod == "POST" && wire.timeoutInterval == 5)
            #expect(MockURLProtocol.bodyData(for: wire) == body)
            #expect(wire.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == nil)
            #expect(wire.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            return (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
        }
        var attempts = 0, responses = 0
        let reply = try await f.transport.performRoles(request, validateAttempt: { attempts += 1 }, validateResponse: { responses += 1 })
        guard case .allocated(let projection) = reply else { throw MerianError.invalidResponse }
        #expect(calls.withLock { $0 } == 1 && attempts == 1 && responses == 1)
        let enriched = try request.allocation.enriching(projection.receipt, mapping: .init(entries: projection.entries))
        let saved = try Request(allocation: enriched, action: .status, projection: .roles), changed = try Self.reply(saved, changedObject: true)
        f.mock.register(path: Self.path) { wire in
            (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, changed)
        }
        await #expect(throws: (any Error).self) { _ = try await f.transport.performRoles(saved, validateAttempt: {}, validateResponse: { Issue.record("Changed mapping accepted") }) }
    }
    @Test(arguments: [401, 409, 429, 503, -1, 302])
    func transportFailuresDoNotRetry(status: Int) async throws {
        let request = try candidate(), f = Fixture(ownerID: request.allocation.claim.profile.ownerID)
        defer { f.close() }
        let calls = OSAllocatedUnfairLock(initialState: 0)
        f.mock.register(path: Self.path) { wire in
            calls.withLock { $0 += 1 }
            if status == -1 { throw URLError(.networkConnectionLost) }
            return (HTTPURLResponse(url: wire.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, Data())
        }
        await #expect(throws: (any Error).self) { _ = try await f.transport.performRoles(request, validateAttempt: {}, validateResponse: {}) }
        #expect(calls.withLock { $0 } == 1)
    }
    @Test(arguments: ["owner", "attempt", "response", "mime", "oversized"])
    func accountAndResponseFencesRejectWithoutSettlement(fault: String) async throws {
        let request = try candidate(), f = Fixture(ownerID: request.allocation.claim.profile.ownerID)
        defer { f.close() }
        let data = try fault == "oversized" ? Data(repeating: 32, count: 2049) : Self.reply(request)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        f.mock.register(path: Self.path) { wire in
            calls.withLock { $0 += 1 }
            return (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": fault == "mime" ? "text/plain" : "application/json"])!, data)
        }
        if fault == "owner" { f.dispatcher.overridingAuthUserID = UUID() }
        await #expect(throws: (any Error).self) {
            _ = try await f.transport.performRoles(request, validateAttempt: {
                if fault == "attempt" { throw SharedMediaStorageFailure.stale }
            }, validateResponse: { throw SharedMediaStorageFailure.stale })
        }
        #expect(calls.withLock { $0 } == (["owner", "attempt"].contains(fault) ? 0 : 1))
    }
}
