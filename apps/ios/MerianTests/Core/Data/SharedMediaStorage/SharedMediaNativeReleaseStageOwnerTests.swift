import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive native release-stage owner", .serialized)
@MainActor
struct SharedMediaNativeReleaseStageOwnerTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    typealias Request = SharedMediaNativeReleaseStartRequest
    typealias Values = SharedMediaNativeReceivingReleaseValues

    @Test func exactSaveReplayAndColdOwnerPreserveSubmittedRows() async throws {
        let (h, owner, p, admission) = try await fixture()
        let request = admission.request
        let before = try row(h), revision = try inventory(h.context(), h).revision
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        #expect(try await owner.stageAppRelease(admission) == .staged(request))
        #expect(try await owner.recoverAppRelease(request) == .staged(request))
        #expect(saves == 1)
        let after = try row(h)
        #expect(after.preparedData == before.preparedData && after.resultData == before.resultData)
        #expect(after.preparedSHA256 == before.preparedSHA256 && after.resultSHA256 == before.resultSHA256)
        #expect(after.phase == before.phase && after.revision == before.revision && after.version == before.version)
        #expect(after.releaseStartData == (try request.encoded()))
        #expect(try inventory(h.context(), h).revision == revision + 1)
        try heldQuartet(h, prepared: p, row: after)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        try cold.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.conflict } }
        #expect(try await cold.recoverAppRelease(request) == .staged(request))
        #expect(try row(h) == after)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "afterSave", "beforeReadback"])
    func deterministicBoundariesKeepOneAttemptAndOriginalRecovery(_ point: String) async throws {
        let (h, owner, p, admission) = try await fixture()
        let request = admission.request
        let before = try row(h), revision = try inventory(h.context(), h).revision
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if (point == "beforeSave" && $0 == .beforeSave) || (point == "afterSave" && $0 == .afterSave) ||
                (point == "beforeReadback" && $0 == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if point == "afterSave" {
            #expect(try await owner.stageAppRelease(admission) == .staged(request))
        } else {
            await #expect(throws: (any Error).self) { _ = try await owner.stageAppRelease(admission) }
        }
        #expect(saves == 1)
        if point == "beforeSave" {
            #expect(try row(h) == before)
            #expect(try inventory(h.context(), h).revision == revision)
        } else {
            #expect(try row(h).releaseStartData == request.encoded())
            #expect(try inventory(h.context(), h).revision == revision + 1)
            let wrong = try SharedMediaNativeReceivingTestFixture.copy(request, changes: ["releaseID": UUID().uuidString])
            await #expect(throws: (any Error).self) { _ = try await owner.recoverAppRelease(wrong) }
        }
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        if point == "beforeSave" { #expect(try await owner.stageAppRelease(admission) == .staged(request)) }
        else { #expect(try await owner.recoverAppRelease(request) == .staged(request)) }
        #expect(saves == (point == "beforeSave" ? 2 : 1))
        try heldQuartet(h, prepared: p, row: row(h))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func missingOrMismatchedUncertainReadbackNeverRestages() async throws {
        let (h, owner, _, admission) = try await fixture()
        let request = admission.request
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if $0 == .beforeReadback { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.stageAppRelease(admission) }
        let saved = try row(h)
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        // Simulate incomplete/unavailable persisted evidence after uncertainty.
        // This test-only mutation is not a supported production recovery route.
        for mode in ["absent", "partial", "mismatch"] {
            let c = h.context(), record = try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: c))
            record.releaseStartData = mode == "absent" ? nil : saved.releaseStartData
            record.releaseStartSHA256 = mode == "absent" || mode == "partial" ? nil : String(repeating: "a", count: 64)
            try c.save()
            await #expect(throws: (any Error).self) { _ = try await owner.recoverAppRelease(request) }
            #expect(saves == 1)
        }
        let c = h.context(), record = try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: c))
        record.releaseStartData = saved.releaseStartData; record.releaseStartSHA256 = saved.releaseStartSHA256; try c.save()
        #expect(try await owner.recoverAppRelease(request) == .staged(request))
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func sealRejectsExtraWritesAndAllImmutableInventoryFields() async throws {
        let (h, owner, _, admission) = try await fixture()
        let request = admission.request
        for fault in ["valid", "slot", "root", "store", "mode", "phase", "cursor", "generation", "package", "delete"] {
            let c = h.context(), i = try inventory(c, h)
            let r = try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: c))
            let snapshot = try SharedMediaNativeReceivedReleaseSnapshot.prospectiveStage(request, context: c)
            let seal = try SharedMediaNativeReleaseStagePoststate(request: request, snapshot: snapshot, context: c, row: r, inventory: i)
            r.releaseStartData = try request.encoded(); r.releaseStartSHA256 = SharedMediaAcquisitionEncoding.digest(r.releaseStartData!)
            i.revision += 1
            switch fault {
            case "slot": r.resultSHA256 = String(repeating: "b", count: 64)
            case "root": i.rootIdentity += "changed"
            case "store": i.storeIdentity = UUID().uuidString
            case "mode": i.modeRaw += "changed"
            case "phase": i.phaseRaw += "changed"
            case "cursor": i.cursor = "changed"
            case "generation": i.generation = UUID()
            case "package": try h.package(in: c).allocatedByteCount += 1
            case "delete": c.delete(r)
            default: break
            }
            if fault == "valid" { try seal.validate(c, row: r, inventory: i) }
            else { #expect(throws: (any Error).self) { try seal.validate(c, row: r, inventory: i) } }
            c.rollback()
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func availabilityIncludesRetiredTargetsAndCanonicalAliases() async throws {
        let (h, owner, _, admission) = try await fixture()
        let request = admission.request
        let snapshot = try SharedMediaNativeReceivedReleaseSnapshot.prospectiveStage(request, context: h.context())
        let p = snapshot.predecessor.components.progress, target = try #require(p.targets.first), retirement = UUID()
        let progress = try p.advancing(.init(pairID: target.pairID, stage: .retiringPair,
            pair: .init(retirementID: retirement, closureSHA256: String(repeating: "b", count: 64)), original: nil))
        #expect(throws: (any Error).self) { try SharedMediaNativeReleaseStageIdentity.requireAbsent(retirement, progress: progress) }
        for id in p.plan.targets.flatMap(\.identities) {
            #expect(throws: (any Error).self) { try SharedMediaNativeReleaseStageIdentity.requireAbsent(id, progress: progress) }
        }
        try SharedMediaNativeReleaseStageIdentity.requireAbsent(UUID(), progress: progress)
        let c = h.context(), id = UUID()
        let event = OfflineQueueEvent(id: id.uuidString.uppercased(), jobId: nil, scanId: nil,
            kind: .needsAttention, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        c.insert(event); try c.save()
        #expect(throws: (any Error).self) { try SharedMediaNativeReleaseStageIdentity.direct(id, context: c) }
        c.delete(event); try c.save()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func consumedSidecarRecoversOnlyItsRetainedProgressAssociation() async throws {
        let (h, owner, p, admission) = try await fixture()
        let request = admission.request
        #expect(try await owner.stageAppRelease(admission) == .staged(request))
        let c = h.context(), i = try inventory(c, h), r = try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: c))
        let origin = try SharedMediaNativeStagedReleaseOrigin.read(.init(r), inventory: i, context: c)
        let snapshot = try SharedMediaNativeReceivedReleaseSnapshot.readStaged(origin, context: c)
        let received = try Intent.Received.decode(#require(r.resultData), prepared: p)
        let synthetic = try SharedMediaNativeReleaseLiveFixture(store: h, prepared: p, received: received,
            plan: snapshot.components.progress.plan)
        // Only stage is a production write here; the later start is a synthetic
        // saved-state fixture, not qualification of a release-start writer.
        r.releaseStartData = nil; r.releaseStartSHA256 = nil
        try synthetic.save(c); try synthetic.inventoryAdvance()
        let saved = try row(h)
        try owner.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.conflict } }
        #expect(try await owner.recoverAppRelease(request) == .releasing(synthetic.progress))
        #expect(try row(h) == saved)
        let wrong = try SharedMediaNativeReceivingTestFixture.copy(request, changes: ["releaseID": UUID().uuidString])
        await #expect(throws: (any Error).self) { _ = try await owner.recoverAppRelease(wrong) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.discoverAppRelease(p) == .releasing(synthetic.progress))
        #expect(try await cold.recoverAppRelease(request) == .releasing(synthetic.progress))
        #expect(try row(h) == saved)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancelledCoordinatorWaitAndSealedAccountCannotStage() async throws {
        let (h, owner, _, admission) = try await fixture()
        let request = admission.request
        let before = try row(h)
        let coordinator = ScanInferencePersistenceCoordinator.shared
        let held = await coordinator.acquireAll(scanIds: [request.queueID.uuidString, request.observationID.uuidString])
        let task = Task { try await owner.stageAppRelease(admission) }
        await Task.yield(); task.cancel()
        await coordinator.releaseAll(scanIds: held)
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(try row(h) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { _ = try await owner.stageAppRelease(admission) }
        #expect(try row(h) == before)
    }

    @Test func coldAbsenceAndReceiptReplayCannotMintFreshCapability() async throws {
        let (h, owner, p, admission) = try await fixture()
        let request = admission.request, before = try row(h)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.receiveAppPrepared(p) // Exact saved receive replay.
        await #expect(throws: (any Error).self) { _ = try await cold.appReleaseStageRequest(p, releaseID: request.releaseID) }
        await #expect(throws: (any Error).self) { _ = try await cold.stageAppRelease(admission) }
        await #expect(throws: (any Error).self) { _ = try await cold.recoverAppRelease(request) }
        #expect(try await cold.discoverAppRelease(p) == nil)
        #expect(try row(h) == before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func uncertainSaveDrainsThroughReadOnlyRecoveryAndCannotReissue() async throws {
        let (h, owner, p, admission) = try await fixture()
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if $0 == .beforeReadback { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.stageAppRelease(admission) }
        let saved = try row(h)
        await #expect(throws: (any Error).self) { _ = try await owner.appReleaseStageRequest(p, releaseID: admission.request.releaseID) }
        await #expect(throws: (any Error).self) { _ = try await owner.appReleaseStageRequest(p, releaseID: UUID()) }
        await #expect(throws: (any Error).self) { _ = try await owner.stageAppRelease(admission) }
        // The ordinary readback hook still fails. Drain uses only its retained,
        // physically fenced read capability after active dispatch is sealed.
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        #expect(saves == 1)
        #expect(try row(h) == saved)
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.discoverAppRelease(p) == .staged(admission.request))
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func absentUncertainEvidenceKeepsDrainClosedUntilExactRestoration() async throws {
        let (h, owner, _, admission) = try await fixture()
        try owner.setMetadataFault { if $0 == .beforeReadback { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { _ = try await owner.stageAppRelease(admission) }
        let saved = try row(h), c = h.context()
        let record = try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: c))
        record.releaseStartData = nil; record.releaseStartSHA256 = nil; try c.save()
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        #expect(try row(h).releaseStartData == nil)
        record.releaseStartData = saved.releaseStartData; record.releaseStartSHA256 = saved.releaseStartSHA256; try c.save()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        #expect(try row(h) == saved)
    }

    private func fixture() async throws -> (Store, SharedMediaNativeOriginalOwner, Intent.Prepared, SharedMediaNativeReleaseStageAdmission) {
        let (h, owner, receiving) = try await SharedMediaNativeAppReceivingTests().fixture(temporaryStore: true, fenceBootstrap: true)
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
            pairIDs: SharedMediaNativeReceivingStagingTests().pairIDs(receiving))
        _ = try await owner.receiveAppPrepared(p)
        let request = try await owner.appReleaseStageRequest(p, releaseID: UUID())
        return (h, owner, p, request)
    }
    private func row(_ h: Store) throws -> Row {
        .init(try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: h.context())))
    }
    private func inventory(_ c: ModelContext, _ h: Store) throws -> SharedMediaInventoryRecord {
        let id = h.inventoryID
        return try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func heldQuartet(_ h: Store, prepared: Intent.Prepared, row: Row) throws {
        let received = try Intent.Received.decode(#require(row.resultData), prepared: prepared)
        _ = try #require(try SharedMediaNativeReceivingRows.read(received.reconstruct(prepared), in: h.context(), absent: false))
    }
}
