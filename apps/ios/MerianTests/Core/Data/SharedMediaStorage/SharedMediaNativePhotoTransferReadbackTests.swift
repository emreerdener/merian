import Foundation
import os
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

    func fixture(_ role: Mapping.Role = .source, boundBackend: Bool = false, createdAtMilliseconds: Int64 = 1) async throws -> (Store, SharedMediaNativeOriginalOwner, Prepared, Allocation) {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        do {
            let allocation = try await owner.allocateAppPhotoRoles(p, backendBinding: boundBackend, authorizeCreate: { p, _ in
                .init(recipient: try #require(p.photoAdmission).expectedProcessorPermission, validate: {})
            }) { request, validate, settle in
                try validate(); try settle()
                let entries = try Mapping.references(request.allocation.claim).enumerated().map { index, reference in
                    Mapping.Entry(photoOrdinal: index / 3, role: Mapping.Role.allCases[index % 3], referenceID: reference, objectID: UUID())
                }
                return .allocated(.init(receipt: .init(assignmentDigest: String(repeating: "a", count: 64),
                    createdAtMilliseconds: createdAtMilliseconds, expiresAtMilliseconds: createdAtMilliseconds + 1_800_000), entries: entries,
                    backendBinding: boundBackend ? InitialPhotoUploadTicketTests().binding() : nil))
            }
            let entry = try #require(allocation.roleMapping?.entries.first { $0.role == role })
            return (h, owner, p, try await owner.reserveAppPhotoTransfer(p, selection: entry))
        } catch {
            _ = await owner.invalidateAndAwaitForAccountTransition(); throw error
        }
    }
    private func row(_ h: Store) throws -> SharedMediaNativeReceivingIntentGraph.Row {
        let id = h.packageID
        return .init(try SharedMediaNativePairPlanGraph.one(h.context(),
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id })))
    }

    @Test(arguments: Mapping.Role.allCases, [false, true])
    func exactRoleAndColdRepeatKeepReservation(_ role: Mapping.Role, boundBackend: Bool) async throws {
        let (h, owner, p, held) = try await fixture(role, boundBackend: boundBackend), before = try row(h)
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
    @Test(arguments: Mapping.Role.allCases)
    func accountShutdownJoinsSynchronousRoleRead(_ role: Mapping.Role) async throws {
        try await joinedRoleRead(role, throughAuth: false)
    }

    @Test(arguments: Mapping.Role.allCases)
    func authDrainJoinsRegisteredRoleRead(_ role: Mapping.Role) async throws {
        try await joinedRoleRead(role, throughAuth: true)
    }

    private func joinedRoleRead(_ role: Mapping.Role, throughAuth: Bool) async throws {
        let (h, initialOwner, p, held) = try await fixture(role), before = try row(h)
        let registeredDrain = SharedMediaNativeOriginalDrain()
        let owner: SharedMediaNativeOriginalOwner
        if throughAuth {
            try #require(await initialOwner.invalidateAndAwaitForAccountTransition())
            owner = try SharedMediaNativeOriginalOwner.appDispatch(
                account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime),
                drain: registeredDrain)
            _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID)
        } else { owner = initialOwner }
        let entered = ImageFocusEngineTests.Signal(), release = DispatchSemaphore(value: 0)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let timedOut = OSAllocatedUnfairLock(initialState: false)
        try await owner.setAcquisitionEntryPause(nil, transferReadFault: { total in
            let first = calls.withLock { $0 += 1; return $0 == 1 }
            guard first else { return }
            #expect(total > 0)
            Task.detached(priority: .userInitiated) { await entered.open() }
            guard release.wait(timeout: .now() + 5) == .success else {
                timedOut.withLock { $0 = true }; throw SharedMediaStorageFailure.unavailable
            }
        })
        var resultEscaped = false, drainFinished = false
        let operation = Task {
            do {
                let value = try await owner.verifyAppPhotoTransfer(p, allocation: held)
                resultEscaped = true; await entered.open(); return value
            } catch { await entered.open(); throw error }
        }
        // Async signal keeps MainActor free; the synchronous wait is on the I/O actor.
        await entered.wait()
        let didEnter = calls.withLock { $0 } == 1
        #expect(didEnter)
        guard didEnter else {
            release.signal(); _ = try? await operation.value
            #expect(await owner.invalidateAndAwaitForAccountTransition()); return
        }
        var order: [String] = []
        let drain = Task {
            let value: Bool
            if throughAuth {
                value = await SupabaseManager.drainPhotoPreparationBeforeAccountWork(preparation: {
                    order.append("photo"); return true
                }, native: {
                    order.append("native")
                    let stopped = await registeredDrain.shutdown()
                    order.append("native-finished"); return stopped
                }, drain: {
                    order.append("auth")
                    await h.runtime.awaitAccountWorkDrain()
                    order.append("auth-finished")
                })
            } else { value = await owner.invalidateAndAwaitForAccountTransition() }
            drainFinished = true; return value
        }
        while !owner.heldOriginalAdmissionClosedForTesting && !drainFinished { await Task.yield() }
        #expect(!drainFinished && !resultEscaped)
        if throughAuth { #expect(order == ["native"]) }
        #expect(try row(h) == before)
        await #expect(throws: (any Error).self) { try await owner.setAcquisitionEntryPause(nil) }
        release.signal()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        #expect(await drain.value)
        if throughAuth {
            #expect(order == ["native", "native-finished", "photo", "auth", "auth-finished"])
            #expect(await registeredDrain.shutdown())
        }
        #expect(!resultEscaped && !timedOut.withLock { $0 })
        #expect(try row(h) == before)
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let verified = try await cold.verifyAppPhotoTransfer(p, allocation: held)
        #expect(verified.selection == held.transferReservation?.selection)
        #expect(try row(h) == before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

}
