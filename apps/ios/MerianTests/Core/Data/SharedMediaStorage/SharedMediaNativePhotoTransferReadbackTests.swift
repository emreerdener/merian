import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Reserved photo role byte verification", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct SharedMediaNativePhotoTransferReadbackTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Allocation = SharedMediaNativePhotoAllocation
    typealias Mapping = SharedMediaNativePhotoRoleMapping
    typealias Prepared = SharedMediaNativeReceivingIntent.Prepared

    private func fixture(_ role: Mapping.Role = .source) async throws -> (Store, SharedMediaNativeOriginalOwner, Prepared, Allocation) {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let allocation = try await owner.allocateAppPhotoRoles(p, authorizeCreate: { p, _ in
            .init(recipient: try #require(p.photoAdmission).expectedProcessorPermission, validate: {})
        }) { request, validate, settle in
            try validate(); try settle()
            let entries = try Mapping.references(request.allocation.claim).enumerated().map { index, reference in
                Mapping.Entry(photoOrdinal: index / 3, role: Mapping.Role.allCases[index % 3], referenceID: reference, objectID: UUID())
            }
            return .allocated(.init(receipt: .init(assignmentDigest: String(repeating: "a", count: 64),
                createdAtMilliseconds: 1, expiresAtMilliseconds: 1_800_001), entries: entries))
        }
        let entry = try #require(allocation.roleMapping?.entries.first { $0.role == role })
        return (h, owner, p, try await owner.reserveAppPhotoTransfer(p, selection: entry))
    }
    private func row(_ h: Store) throws -> SharedMediaNativeReceivingIntentGraph.Row {
        let id = h.packageID
        return .init(try SharedMediaNativePairPlanGraph.one(h.context(),
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id })))
    }

    @Test(arguments: Mapping.Role.allCases)
    func exactRoleAndColdRepeatKeepReservation(_ role: Mapping.Role) async throws {
        let (h, owner, p, held) = try await fixture(role), before = try row(h)
        let reservation = try #require(held.transferReservation)
        try owner.setMetadataFault { if $0 == .beforeSave { Issue.record("Read attempted persistence") } }
        let read = try await owner.verifyAppPhotoTransfer(p, allocation: held)
        #expect(read.selection == reservation.selection && read.byteCount == reservation.byteCount && read.sha256 == reservation.sha256)
        #expect(try await owner.verifyAppPhotoTransfer(p, allocation: held) == read)
        #expect(try row(h) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.verifyAppPhotoTransfer(p, allocation: held) == read)
        #expect(try row(h) == before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["generation", "descriptor", "role", "claim"])
    func callerCannotSubstituteSavedIdentity(_ fault: String) async throws {
        let (h, owner, p, held) = try await fixture(), before = try row(h)
        var json = try #require(try JSONSerialization.jsonObject(with: held.encoded()) as? [String: Any])
        var transfer = try #require(json["transferReservation"] as? [String: Any])
        if fault == "generation" { transfer["assetGeneration"] = UUID().uuidString }
        if fault == "descriptor" {
            var descriptor = try #require(transfer["descriptor"] as? [String: Any]); descriptor["file"] = "different"; transfer["descriptor"] = descriptor
        }
        if fault == "role" {
            var selection = try #require(transfer["selection"] as? [String: Any]); selection["role"] = "ai"; transfer["selection"] = selection
        }
        if fault == "claim" {
            var claim = try #require(json["claim"] as? [String: Any]); claim["attemptID"] = UUID().uuidString; json["claim"] = claim
        }
        json["transferReservation"] = transfer
        let candidate = try JSONDecoder().decode(Allocation.self, from: JSONSerialization.data(withJSONObject: json))
        await #expect(throws: (any Error).self) { _ = try await owner.verifyAppPhotoTransfer(p, allocation: candidate) }
        #expect(try row(h) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["missing", "symlink", "replaced", "truncated", "appended", "modified", "cancel", "account", "saved"])
    func heldReadRejectsRacesWithoutRetiring(_ fault: String) async throws {
        let (h, owner, p, held) = try await fixture(), before = try row(h)
        let reservation = try #require(held.transferReservation)
        let file = h.parent.appendingPathComponent("photo/PhotoPreparation")
            .appendingPathComponent(h.ownerID.uuidString.lowercased()).appendingPathComponent(h.packageID.uuidString.lowercased())
            .appendingPathComponent(reservation.assetID.uuidString.lowercased())
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        try await owner.setAcquisitionEntryPause { if $0 == .readTransfer { await entered.open(); await release.wait() } }
        let operation = Task { try await owner.verifyAppPhotoTransfer(p, allocation: held) }
        await entered.wait()
        var transition: Task<Bool, Never>?, transitionFinished = false
        switch fault {
        case "missing": try FileManager.default.removeItem(at: file)
        case "symlink", "replaced":
            let retained = file.appendingPathExtension("retained-test-original")
            try FileManager.default.moveItem(at: file, to: retained)
            if fault == "symlink" { try FileManager.default.createSymbolicLink(at: file, withDestinationURL: retained) }
            else { try Data(contentsOf: retained).write(to: file) }
        case "truncated": try Data([0]).write(to: file)
        case "appended", "modified":
            var bytes = try Data(contentsOf: file)
            if fault == "appended" { bytes.append(0) } else { bytes[0] ^= 1 }
            try bytes.write(to: file)
        case "cancel": operation.cancel()
        case "saved":
            let c = h.context(), id = h.packageID
            let row = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
            row.revision += 1; try c.save()
        default:
            transition = Task { let result = await owner.invalidateAndAwaitForAccountTransition(); transitionFinished = true; return result }
            while !owner.heldOriginalAdmissionClosedForTesting { await Task.yield() }
            #expect(!transitionFinished)
        }
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        let after = try row(h)
        #expect(after.allocationData == before.allocationData && after.allocationSHA256 == before.allocationSHA256)
        if let transition { #expect(await transition.value) }
        else { #expect(await owner.invalidateAndAwaitForAccountTransition()) }
    }
}
