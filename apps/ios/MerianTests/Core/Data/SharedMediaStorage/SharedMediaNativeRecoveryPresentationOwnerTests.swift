import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native first presentation reservation owner", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct SharedMediaNativeRecoveryPresentationOwnerTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Prepared = SharedMediaNativeReceivingIntent.Prepared
    private func inventory(_ h: Store, _ c: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = h.inventoryID
        return try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func queue(_ p: Prepared, _ c: ModelContext) throws -> OfflineQueuedScan {
        let id = p.queueID.uuidString.lowercased()
        return try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id }))
    }

    @Test(arguments: [false, true])
    func firstReserveIsDurableAndCannotBeRepeated(allocated: Bool) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        if allocated {
            _ = try await owner.allocateAppPhoto(p, authorizeCreate: { _, _ in .init(recipient: .gemini, validate: {}) }) { _, _, _ in .held(.notFound) }
        }
        let before = try inventory(h, h.context()).revision, id = UUID()
        let slot = try #require(try SharedMediaNativeReceivingPhaseGraph.row(p.package.id, in: h.context()))
        let slotFields = try SharedMediaNativeReleasePairRaw.fields(slot)
        try owner.setMetadataFault { [weak owner] boundary in
            guard boundary == .beforeSave else { return }
            let owner = try #require(owner)
            #expect(throws: SharedMediaStorageFailure.closed) { try owner.setMetadataFault(nil) }
            #expect(throws: SharedMediaStorageFailure.closed) { try owner.setLifecycleFault(nil) }
            #expect(throws: SharedMediaStorageFailure.closed) { try owner.setPreparationFault(nil) }
        }
        let result = try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: id)
        #expect(result.acknowledged && result.presentation.revision == 1)
        #expect(result.presentation.activeReservationID == id)
        #expect(try queue(p, h.context()).recoveryPresentationData == result.presentation.encoded())
        #expect(try inventory(h, h.context()).revision == before + 1)
        let after = try #require(try SharedMediaNativeReceivingPhaseGraph.row(p.package.id, in: h.context()))
        #expect(try SharedMediaNativeReleasePairRaw.fields(after) == slotFields)
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: UUID()) }
        #expect(try await owner.reconcileAppRecoveryPresentationForTesting(result))
        #expect(try inventory(h, h.context()).revision == before + 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { _ = try await owner.reconcileAppRecoveryPresentationForTesting(result) }
    }

    @Test(arguments: ["before", "after", "readback"])
    func saveFaultsKeepOneExactAttempt(point: String) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let before = try inventory(h, h.context()).revision, id = UUID()
        var saves = 0
        try owner.setMetadataFault { boundary in
            if boundary == .afterSave { saves += 1 }
            if (point == "before" && boundary == .beforeSave) || (point == "after" && boundary == .afterSave) ||
                (point == "readback" && boundary == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if point == "before" {
            await #expect(throws: (any Error).self) { _ = try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: id) }
            #expect(try queue(p, h.context()).recoveryPresentationData == nil)
            #expect(try inventory(h, h.context()).revision == before && saves == 0)
        } else {
            let attempt = try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: id)
            #expect(attempt.acknowledged == (point == "after"))
            #expect(attempt.presentation.activeReservationID == id && saves == 1)
            #expect(try queue(p, h.context()).recoveryPresentationData == attempt.presentation.encoded())
            try owner.setMetadataFault { if $0 != .beforeReadback { Issue.record("Reconciliation attempted another save") } }
            #expect(try await owner.reconcileAppRecoveryPresentationForTesting(attempt))
            #expect(try await owner.reconcileAppRecoveryPresentationForTesting(attempt))
            #expect(try inventory(h, h.context()).revision == before + 1 && saves == 1)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func exactAdditionalCapacityIsRequiredBeforeAnySave() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let c = h.context(), inv = try inventory(h, c)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inv, ownerID: h.ownerID, format: .appV2)
        var low: Int64 = 0, high = Int64.max
        while low < high {
            let mid = low + (high - low) / 2
            if (try? budget.totals.checkAvailable(mid)) != nil { high = mid } else { low = mid + 1 }
        }
        let exact = try SharedMediaStoragePolicy.add(low, 512), before = inv.revision
        try owner.setMetadataFault(nil, availableBytes: exact - 1)
        await #expect(throws: SharedMediaStorageFailure.capacity) { _ = try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: UUID()) }
        #expect(try queue(p, h.context()).recoveryPresentationData == nil)
        #expect(try inventory(h, h.context()).revision == before)
        try owner.setMetadataFault(nil, availableBytes: exact)
        #expect(try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: UUID()).acknowledged)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func finalAuditRejectsSameHeaderPeerMutation() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture(), peer = UUID(), draft = UUID()
        let acquisition = try await owner.prepareAppOriginal(packageID: peer, draftGeneration: draft, ordinal: 0, kind: .picker)
        let image = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(acquisition) { image }
        let before = try inventory(h, h.context()).revision
        try owner.setMetadataFault { boundary in
            guard boundary == .beforeSave else { return }
            let c = h.context()
            let member = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == peer }))
            member.membersData = Data([1]); try c.save()
        }
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: UUID()) }
        #expect(try queue(p, h.context()).recoveryPresentationData == nil)
        #expect(try inventory(h, h.context()).revision == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func deletedQueueCannotBeRecreatedByAcknowledgement() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        try owner.setMetadataFault { boundary in
            guard boundary == .afterSave else { return }
            let c = h.context(); c.delete(try queue(p, c)); try c.save()
        }
        let attempt = try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: UUID())
        #expect(!attempt.acknowledged)
        try owner.setMetadataFault(nil)
        await #expect(throws: (any Error).self) { _ = try await owner.reconcileAppRecoveryPresentationForTesting(attempt) }
        #expect(throws: (any Error).self) { _ = try queue(p, h.context()) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func ordinaryApplicationSupportStoreIsNotEligible() throws {
        let ordinary = try Store()
        #expect(throws: SharedMediaStorageFailure.closed) {
            try SharedMediaNativeAppRecoveryPresentationOperations.requireFixture(ordinary.container)
        }
    }
}
