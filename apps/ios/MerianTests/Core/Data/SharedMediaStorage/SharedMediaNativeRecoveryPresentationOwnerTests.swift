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

    private func budget(_ h: Store) throws -> SharedMediaNativeAcquisitionBudget.Snapshot {
        let c = h.context()
        return try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory(h, c),
            ownerID: h.ownerID, format: .appV2)
    }
    private func audit(_ h: Store, _ p: Prepared) async throws {
        let inv = try inventory(h, h.context())
        _ = try await SharedMediaNativeScopedAudit(app: h.container, profile: p.profile,
            expected: .init(generation: inv.generation, revision: inv.revision, phase: inv.phaseRaw, cursor: inv.cursor),
            check: {}, betweenPages: { await Task.yield() }).run()
    }
    private func transaction(_ h: Store, _ p: Prepared) throws -> SharedMediaNativeReceivingIntent.Transaction {
        let c = h.context(), row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(p.package.id, in: c))
        if row.allocationData != nil {
            return try SharedMediaNativePhotoAllocationSnapshot.read(.init(row), inventory: inventory(h, c), context: c).transaction
        }
        guard case .received(_, _, let value) = try SharedMediaNativeReceivingSlot.decode(.init(row), profile: p.profile) else {
            throw SharedMediaStorageFailure.closed
        }
        return value
    }

    @Test(arguments: [false, true])
    func positiveStateSurvivesColdAuditWithoutExecutionAuthority(allocated: Bool) async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        if allocated {
            _ = try await owner.allocateAppPhoto(p, authorizeCreate: { _, _ in .init(recipient: .gemini, validate: {}) }) { _, _, _ in .held(.notFound) }
        }
        let before = try budget(h)
        let attempt = try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: UUID())
        let bytes = try attempt.presentation.encoded(), after = try budget(h)
        #expect(attempt.acknowledged && attempt.presentation.needsAttention)
        #expect(after.receivedLiabilityByPackage == before.receivedLiabilityByPackage)
        #expect(after.metadataByPackage[p.package.id] == (try #require(before.metadataByPackage[p.package.id])) + 512)
        var expected = before.totals
        try expected.include(.init(packageID: p.package.id, pool: .durable, materialized: Int64(bytes.count), reserved: 512 - Int64(bytes.count)))
        #expect(after.totals == expected)
        try await audit(h, p)
        let tx = try transaction(h, p), rows = try SharedMediaNativeReceivingRows.readObserved(tx, in: h.context())
        #expect(throws: (any Error).self) { _ = try SharedMediaNativeReceivingRows.read(tx, in: h.context(), absent: false) }
        #expect(throws: (any Error).self) { try SharedMediaNativeReceivingRows.validate(rows, request: tx) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let revision = try inventory(h, h.context()).revision
        try cold.setMetadataFault { if $0 != .beforeReadback { Issue.record("Cold observation attempted a save") } }
        if !allocated { #expect(try await cold.receiveAppPrepared(p) == tx.cohort) }
        await #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try await cold.allocateAppPhoto(p, authorizeCreate: { _, _ in
                Issue.record("Positive observation authorized execution"); return .init(recipient: .gemini, validate: {})
            }) { _, _, _ in Issue.record("Positive observation dispatched"); return .held(.notFound) }
        }
        await #expect(throws: SharedMediaStorageFailure.closed) { _ = try await cold.appReleaseStageRequest(p, releaseID: UUID()) }
        #expect(try inventory(h, h.context()).revision == revision)
        #expect(try queue(p, h.context()).recoveryPresentationData == bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func observedReaderRejectsForeignMalformedAndAlteredQuartet() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let attempt = try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: UUID())
        let bytes = try attempt.presentation.encoded(), tx = try transaction(h, p)
        let foreign = try AnalysisRecoveryPresentation.initial(for: .init(ownerID: UUID(),
            observationID: p.observationID, operationID: p.operationID)).reserve(id: UUID()).reserved.encoded()
        for invalid in [foreign, Data([1]), bytes + Data([32])] {
            let c = h.context(); try queue(p, c).recoveryPresentationData = invalid; try c.save()
            #expect(throws: (any Error).self) { _ = try SharedMediaNativeReceivingRows.readObserved(tx, in: h.context()) }
            await #expect(throws: (any Error).self) { try await audit(h, p) }
        }
        let c = h.context(), q = try queue(p, c)
        q.recoveryPresentationData = bytes; q.fieldNotes = "unexpected"; try c.save()
        #expect(throws: (any Error).self) { _ = try SharedMediaNativeReceivingRows.readObserved(tx, in: h.context()) }
        q.fieldNotes = nil; try c.save(); try await audit(h, p)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func independentAcquisitionPreservesPositivePeerAndLiability() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let attempt = try await owner.reserveAppRecoveryPresentationForTesting(p, reservationID: UUID())
        let bytes = try attempt.presentation.encoded(), before = try budget(h)
        let prior = try SharedMediaNativeReceivingTerminalRaw.fields(queue(p, h.context()))
        let acquisition = try await owner.prepareAppOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
        let image = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(acquisition) { image }
        let after = try budget(h)
        #expect(after.metadataByPackage[p.package.id] == before.metadataByPackage[p.package.id])
        #expect(after.receivedLiabilityByPackage[p.package.id] == before.receivedLiabilityByPackage[p.package.id])
        #expect(try queue(p, h.context()).recoveryPresentationData == bytes)
        #expect(try SharedMediaNativeReceivingTerminalRaw.fields(queue(p, h.context())) == prior)
        try await audit(h, p)
        // Other progress cannot silently rebase the original attempted save.
        await #expect(throws: (any Error).self) { _ = try await owner.reconcileAppRecoveryPresentationForTesting(attempt) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func presentationAppearingBeforeReleaseSaveRejectsStage() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        let admission = try await owner.appReleaseStageRequest(p, releaseID: UUID())
        let before = try inventory(h, h.context()).revision
        let bytes = try AnalysisRecoveryPresentation.initial(for: .init(ownerID: h.ownerID,
            observationID: p.observationID, operationID: p.operationID)).reserve(id: UUID()).reserved.encoded()
        var saves = 0
        try owner.setMetadataFault { point in
            if point == .afterSave { saves += 1 }
            guard point == .beforeSave else { return }
            let c = h.context(); try queue(p, c).recoveryPresentationData = bytes; try c.save()
        }
        await #expect(throws: SharedMediaStorageFailure.closed) { _ = try await owner.stageAppRelease(admission) }
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(p.package.id, in: h.context()))
        #expect(row.releaseStartData == nil && row.releaseStartSHA256 == nil && saves == 0)
        #expect(try inventory(h, h.context()).revision == before)
        #expect(try queue(p, h.context()).recoveryPresentationData == bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true], ["afterSave", "beforeReadback"])
    func positiveReadbackCannotMintCreateOrTicket(ticket: Bool, point: String) async throws {
        let h: Store, owner: SharedMediaNativeOriginalOwner, p: Prepared
        if ticket {
            let fixture = try await SharedMediaNativePhotoTransferReadbackTests().fixture()
            h = fixture.store; owner = fixture.owner; p = fixture.prepared
            _ = try await owner.reserveAppPhotoRemoteAttempt(p)
        } else { (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture() }
        let before = try inventory(h, h.context()).revision
        let bytes = try AnalysisRecoveryPresentation.initial(for: .init(ownerID: h.ownerID,
            observationID: p.observationID, operationID: p.operationID)).reserve(id: UUID()).reserved.encoded()
        var saves = 0, injections = 0
        try owner.setMetadataFault { boundary in
            if boundary == .afterSave { saves += 1 }
            guard saves == 1, injections == 0, (point == "afterSave" && boundary == .afterSave) ||
                (point == "beforeReadback" && boundary == .beforeReadback) else { return }
            let c = h.context(); try queue(p, c).recoveryPresentationData = bytes; try c.save(); injections += 1
        }
        if ticket {
            await #expect(throws: SharedMediaStorageFailure.closed) {
                _ = try await owner.requestAppPhotoTicketForTesting(p) { _, _ in Issue.record("Positive readback minted ticket authority") }
            }
        } else {
            await #expect(throws: SharedMediaStorageFailure.closed) {
                _ = try await owner.allocateAppPhoto(p, authorizeCreate: { _, _ in .init(recipient: .gemini, validate: {}) }) { _, _, _ in
                    Issue.record("Positive readback minted create authority"); return .held(.notFound)
                }
            }
        }
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(p.package.id, in: h.context()))
        #expect(row.allocationData != nil && saves == 1 && injections == 1)
        #expect(try inventory(h, h.context()).revision == before + 1)
        #expect(try queue(p, h.context()).recoveryPresentationData == bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}
