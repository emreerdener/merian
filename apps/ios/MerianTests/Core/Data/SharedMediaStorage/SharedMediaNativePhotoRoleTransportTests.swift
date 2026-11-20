import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct SharedMediaNativePhotoRoleTransportTests {
    typealias Allocation = SharedMediaNativePhotoAllocation
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Wire = InitialPhotoAllocationTransportTests
    private func saved(_ h: Store) throws -> Allocation {
        let id = h.packageID
        let row = try SharedMediaNativePairPlanGraph.one(h.context(), FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        return try .decode(#require(row.allocationData), sha256: #require(row.allocationSHA256))
    }
    private func authorize(_ p: SharedMediaNativeReceivingIntent.Prepared) throws -> IdentificationDispatchAuthorization {
        .init(recipient: try #require(p.photoAdmission).expectedProcessorPermission, validate: {})
    }
    @Test(arguments: ["fresh", "ambiguousSave", "lostReply"])
    func durableReservationPrecedesWireAndColdRecoveryNeverCreates(mode: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let f = Wire.Fixture(ownerID: p.profile.ownerID); defer { f.close() }
        if mode == "ambiguousSave" {
            var fail = true
            try owner.setMetadataFault { if $0 == .afterSave && fail { fail = false; throw SharedMediaStorageFailure.unavailable } }
        }
        var sent = 0
        do {
            let value = try await owner.allocateAppPhotoRoles(p, authorizeCreate: { value, check in try check(); return try authorize(value) }) { request, validate, settle in
                sent += 1
                #expect(request.projection == .roles && request.allocation.version == 2)
                #expect(request.action == (mode == "ambiguousSave" ? .status : .create))
                #expect(try saved(h) == request.allocation)
                #expect(request.allocation.remainingAdvances == 2)
                let data = try Wire.reply(request), body = request.body
                let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(fields["version"] as? Int == 2)
                f.mock.register(path: Wire.path) { wire in
                    #expect(MockURLProtocol.bodyData(for: wire) == body)
                    if mode == "lostReply" { throw URLError(.networkConnectionLost) }
                    return (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
                }
                return try await f.transport.performRoles(request, validateAttempt: validate, validateResponse: settle)
            }
            #expect(mode != "lostReply" && value.roleMapping?.entries.count == 3)
        } catch { #expect(mode == "lostReply") }
        #expect(sent == 1)
        let held = try saved(h)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let recovered = try await cold.allocateAppPhotoRoles(p, authorizeCreate: { _, _ in
            Issue.record("Recovery requested create authorization"); throw SharedMediaStorageFailure.closed
        }) { request, validate, settle in
            #expect(request.action == .status && request.allocation == held)
            let data = try Wire.reply(request)
            f.mock.register(path: Wire.path) { wire in
                (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
            }
            return try await f.transport.performRoles(request, validateAttempt: validate, validateResponse: settle)
        }
        #expect(recovered.roleMapping?.entries.count == 3 && recovered.remainingAdvances == 0)
        #expect(recovered.claim == held.claim)
        #expect(try saved(h) == recovered)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: [false, true])
    func legacyClaimAndReceiptUpgradeOnlyToStatus(settled: Bool) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let receipt = Allocation.Receipt(assignmentDigest: String(repeating: "a", count: 64), createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001)
        let legacy = try await owner.allocateAppPhoto(p, authorizeCreate: { value, _ in try authorize(value) }) { _, _, _ in
            settled ? .allocated(receipt) : .held(.notFound)
        }
        let before = try legacy.encoded(), f = Wire.Fixture(ownerID: legacy.claim.profile.ownerID)
        defer { f.close() }
        let upgraded = try await owner.allocateAppPhotoRoles(p, authorizeCreate: { _, _ in
            Issue.record("Legacy recovery requested create authorization"); throw SharedMediaStorageFailure.closed
        }) { request, validate, settle in
            #expect(request.action == .status && request.projection == .roles)
            #expect(try request.allocation.legacyEncoded() == before)
            #expect(try saved(h) == request.allocation)
            let fields = try #require(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            if settled { #expect(fields["saved_assignment_digest"] as? String == receipt.assignmentDigest) }
            else { #expect(fields["saved_assignment_digest"] is NSNull) }
            let data = try Wire.reply(request)
            f.mock.register(path: Wire.path) { wire in
                (HTTPURLResponse(url: wire.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, data)
            }
            return try await f.transport.performRoles(request, validateAttempt: validate, validateResponse: settle)
        }
        #expect(upgraded.roleMapping?.entries.count == 3 && upgraded.receipt == receipt)
        #expect(upgraded.claim == legacy.claim)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}
