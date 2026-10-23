import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive native release-start owner", .serialized)
@MainActor
struct SharedMediaNativeReleaseStartOwnerTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Intent = SharedMediaNativeReceivingIntent
    typealias Row = SharedMediaNativeReceivingIntentGraph.Row
    typealias Request = SharedMediaNativeReleaseStartRequest
    typealias Values = SharedMediaNativeReceivingReleaseValues

    @Test(arguments: [false, true])
    func actualStartPreservesHeldRowsAndSharedOriginals(_ foreign: Bool) async throws {
        let (h, owner, p, admission) = try await fixture(foreign: foreign)
        let request = admission.request
        #expect(try await owner.stageAppRelease(admission) == .staged(request))
        let snapshot = try staged(h), before = try row(h), member = try h.memberBytes()
        let envelope = try h.package().supportingContextData
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        let result = try await owner.startAppRelease(request)
        #expect(result == snapshot.components.progress)
        let after = try row(h)
        #expect(after.phase == "releasing" && after.preparedData == nil)
        #expect(after.releaseStartData == nil && after.releaseStartSHA256 == nil)
        #expect(after.preparedSHA256 == before.preparedSHA256)
        #expect(after.resultData == (try result.encoded()))
        #expect(try h.memberBytes() == member && h.package().supportingContextData == envelope)
        _ = try SharedMediaNativeReceivingPhaseGraph.receivedRows(snapshot.origin.transaction, context: h.context())
        #expect(try await owner.recoverAppReleaseStart(result) == result)
        await #expect(throws: (any Error).self) { _ = try await owner.startAppRelease(request) }
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.discoverAppRelease(p) == .releasing(result))
        #expect(try await cold.recoverAppReleaseStart(result) == result)
        await #expect(throws: (any Error).self) { _ = try await cold.startAppRelease(request) }
        #expect(try row(h) == after)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["afterSave", "beforeReadback", "cold"])
    func stageRecoveryNeverCreatesAStartRight(_ fault: String) async throws {
        let (h, owner, _, admission) = try await fixture()
        if fault != "cold" {
            try owner.setMetadataFault {
                if (fault == "afterSave" && $0 == .afterSave) || (fault == "beforeReadback" && $0 == .beforeReadback) {
                    throw SharedMediaStorageFailure.unavailable
                }
            }
        }
        if fault == "beforeReadback" {
            await #expect(throws: (any Error).self) { _ = try await owner.stageAppRelease(admission) }
        } else { #expect(try await owner.stageAppRelease(admission) == .staged(admission.request)) }
        try owner.setMetadataFault { _ in }
        let saved = try row(h)
        if fault == "cold" {
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
            #expect(try await cold.recoverAppRelease(admission.request) == .staged(admission.request))
            await #expect(throws: (any Error).self) { _ = try await cold.startAppRelease(admission.request) }
            #expect(await cold.invalidateAndAwaitForAccountTransition())
        } else {
            #expect(try await owner.recoverAppRelease(admission.request) == .staged(admission.request))
            await #expect(throws: (any Error).self) { _ = try await owner.startAppRelease(admission.request) }
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        }
        #expect(try row(h) == saved)
    }

    @Test(arguments: ["beforeSave", "afterSave", "beforeReadback"])
    func startBoundaryFaultsRecoverOnlyExactProgress(_ fault: String) async throws {
        let (h, owner, _, admission) = try await fixture()
        _ = try await owner.stageAppRelease(admission)
        let before = try row(h), expected = try staged(h).components.progress
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if (fault == "beforeSave" && $0 == .beforeSave) || (fault == "afterSave" && $0 == .afterSave) ||
                (fault == "beforeReadback" && $0 == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterSave" { #expect(try await owner.startAppRelease(admission.request) == expected) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.startAppRelease(admission.request) } }
        #expect(saves == 1)
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        if fault == "beforeSave" {
            #expect(try row(h) == before)
            await #expect(throws: (any Error).self) { _ = try await owner.recoverAppReleaseStart(expected) }
            #expect(try await owner.startAppRelease(admission.request) == expected)
        } else {
            // Generic stage reconciliation must not settle pending start.
            if fault == "beforeReadback" {
                await #expect(throws: (any Error).self) { _ = try await owner.recoverAppRelease(admission.request) }
            }
            #expect(try await owner.recoverAppReleaseStart(expected) == expected)
            await #expect(throws: (any Error).self) { _ = try await owner.startAppRelease(admission.request) }
        }
        #expect(saves == (fault == "beforeSave" ? 2 : 1))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func unknownStartBlocksDispatchAndDrainUntilExactEvidenceReturns() async throws {
        let (h, owner, _, admission) = try await fixture()
        _ = try await owner.stageAppRelease(admission)
        let before = try row(h), expected = try staged(h).components.progress
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if $0 == .beforeReadback { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.startAppRelease(admission.request) }
        let saved = try row(h)
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        for mode in ["staged", "partial", "mismatch", "absent"] {
            let c = h.context(), r = try record(h, c)
            r.phaseRaw = mode == "staged" ? before.phase : saved.phase
            r.revision = mode == "staged" ? before.revision : saved.revision
            r.preparedData = mode == "staged" ? before.preparedData : nil
            r.resultData = mode == "staged" ? before.resultData : saved.resultData
            r.resultSHA256 = mode == "staged" ? before.resultSHA256 : mode == "partial" ? nil : String(repeating: "a", count: 64)
            r.releaseStartData = mode == "staged" ? before.releaseStartData : nil
            r.releaseStartSHA256 = mode == "staged" ? before.releaseStartSHA256 : nil
            if mode == "absent" { c.delete(r) }
            try c.save()
            await #expect(throws: (any Error).self) { _ = try await owner.recoverAppReleaseStart(expected) }
            await #expect(throws: (any Error).self) { _ = try await owner.startAppRelease(admission.request) }
            if mode == "absent" {
                let replacement = SharedMediaReceivingIntentRecord(packageID: saved.id, inventoryID: saved.inventoryID,
                    inventoryGeneration: saved.inventoryGeneration, ownerID: saved.ownerID,
                    draftGeneration: saved.draftGeneration, operationID: saved.operationID,
                    preparedData: Data(), preparedSHA256: saved.preparedSHA256)
                replacement.schemaVersion = saved.version; replacement.phaseRaw = saved.phase
                replacement.revision = saved.revision; replacement.preparedData = nil
                replacement.resultData = saved.resultData; replacement.resultSHA256 = nil
                c.insert(replacement); try c.save()
            }
        }
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        let c = h.context(), r = try record(h, c)
        r.phaseRaw = saved.phase; r.revision = saved.revision; r.preparedData = saved.preparedData
        r.resultData = saved.resultData; r.resultSHA256 = saved.resultSHA256
        r.releaseStartData = saved.releaseStartData; r.releaseStartSHA256 = saved.releaseStartSHA256; try c.save()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        #expect(saves == 1)
        #expect(try row(h) == saved)
    }

    @Test func identityAliasesAndFrozenDriftRejectBeforeConsumption() async throws {
        let (h, owner, _, admission) = try await fixture()
        _ = try await owner.stageAppRelease(admission)
        let before = try row(h), snapshot = try staged(h)
        // A clean ready pair includes counters for both derivative outputs.
        // Prove acceptance before testing collisions, so negatives cannot be vacuous.
        try SharedMediaNativeReleaseStartDirectIdentity.check(snapshot, context: h.context())
        let counterContext = h.context(), plan = snapshot.components.progress.plan
        let foreignCounter = SharedMediaAssetReferenceCountRecord(assetID: plan.releaseID, assetGeneration: UUID(),
            inventoryID: plan.profile.inventoryID, inventoryGeneration: plan.profile.generation,
            ownerID: plan.profile.ownerID, liveCount: 1)
        counterContext.insert(foreignCounter); try counterContext.save()
        #expect(throws: SharedMediaStorageFailure.conflict) {
            try SharedMediaNativeReleaseStartDirectIdentity.check(snapshot, context: h.context())
        }
        counterContext.delete(foreignCounter); try counterContext.save()
        try SharedMediaNativeReleaseStartDirectIdentity.check(snapshot, context: h.context())
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        // Check every logical/physical target, not only the release operation ID.
        for id in SharedMediaNativeReleaseStartIdentity.ids(snapshot.components.progress.plan) {
            let c = h.context(), event = OfflineQueueEvent(id: id.uuidString.uppercased(), jobId: nil, scanId: nil,
                kind: .needsAttention, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
            c.insert(event); try c.save()
            #expect(throws: (any Error).self) { try SharedMediaNativeReleaseStartDirectIdentity.check(snapshot, context: h.context()) }
            c.delete(event); try c.save()
        }
        let c = h.context(), package = try h.package(in: c), original = package.supportingContextData
        package.supportingContextData = Data("changed".utf8); try c.save()
        await #expect(throws: (any Error).self) { _ = try await owner.startAppRelease(admission.request) }
        #expect(saves == 0)
        #expect(try row(h) == before)
        package.supportingContextData = original; try c.save()
        #expect(try await owner.startAppRelease(admission.request) == snapshot.components.progress)
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func selectedForeignReceiptCannotHideAHistoricalReferenceAlias() async throws {
        let (h, owner, _, admission) = try await fixture(foreign: true)
        _ = try await owner.stageAppRelease(admission)
        let snapshot = try staged(h), plan = snapshot.components.progress.plan
        let c = h.context(), id = plan.targets[0].acquisitionID
        let original = try SharedMediaNativePairPlanGraph.one(c,
            FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        guard case .completed(let request, let result) = try SharedMediaAcquisitionReceipt.read(original) else {
            Issue.record("Expected completed original acquisition"); return
        }
        let aliased = try SharedMediaNativeReceivingTestFixture.copy(request, changes: ["referenceID": plan.eventID.uuidString])
        let fingerprint = SharedMediaAcquisitionEncoding.digest(try aliased.encoded())
        let aliasedResult = try SharedMediaNativeReceivingTestFixture.copy(result,
            changes: ["referenceID": plan.eventID.uuidString, "requestFingerprint": fingerprint])
        c.delete(original); try c.save()
        let replacement = try receipt(aliased, aliasedResult)
        c.insert(replacement); try c.save()
        // Prove this is canonical and passes the physical/staged readers; the
        // rejection must come from the newly added cross-role identity proof.
        _ = try SharedMediaAcquisitionReceipt.read(replacement)
        let stillStaged = try staged(h)
        #expect(stillStaged.components.progress == snapshot.components.progress)
        await #expect(throws: SharedMediaStorageFailure.conflict) {
            try await SharedMediaNativeReleaseStartIdentity.audit(stillStaged, container: h.container, check: {})
        }
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        await #expect(throws: (any Error).self) { _ = try await owner.startAppRelease(admission.request) }
        #expect(saves == 0)
        c.delete(replacement); try c.save()
        c.insert(try receipt(request, result)); try c.save()
        #expect(try await owner.startAppRelease(admission.request) == snapshot.components.progress)
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func receipt(_ request: SharedMediaAcquisitionIntent, _ result: SharedMediaAcquisitionResult) throws -> SharedMediaAcquisitionReceiptRecord {
        let bytes = try request.encoded()
        let row = SharedMediaAcquisitionReceiptRecord(operationID: request.operationID, inventoryID: request.inventoryID,
            inventoryGeneration: request.inventoryGeneration, ownerID: request.ownerID,
            requestFingerprint: SharedMediaAcquisitionEncoding.digest(bytes), packageID: request.packageID,
            assetID: request.assetID, requestData: bytes)
        row.phaseRaw = "completed"; row.revision = 1; row.resultData = try result.encoded(request: request)
        return row
    }

    @Test func exactDirtySealRejectsExtraWritesAndImmutableDrift() async throws {
        let (h, owner, _, admission) = try await fixture()
        _ = try await owner.stageAppRelease(admission)
        for fault in ["valid", "slot", "inventory", "package", "delete"] {
            let c = h.context(), i = try inventory(h, c), r = try record(h, c)
            let snapshot = try staged(h, c), progress = snapshot.components.progress
            let seal = try SharedMediaNativeReleaseStartPoststate(snapshot: snapshot, context: c, row: r, inventory: i)
            r.phaseRaw = "releasing"; r.revision = try progress.plan.releasingRevision
            r.preparedData = nil; r.resultData = try progress.encoded(); r.resultSHA256 = SharedMediaAcquisitionEncoding.digest(r.resultData!)
            r.releaseStartData = nil; r.releaseStartSHA256 = nil; i.revision += 1
            switch fault {
            case "slot": r.preparedSHA256 = String(repeating: "b", count: 64)
            case "inventory": i.rootIdentity += "changed"
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

    @Test func currentHeaderIsReauditedAndInsufficientRunwayNeverSaves() async throws {
        let (h, owner, _, admission) = try await fixture()
        _ = try await owner.stageAppRelease(admission)
        let before = try row(h), c = h.context(), i = try inventory(h, c), revision = i.revision
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        // Test-only exhaustion; no production path changes an inventory directly.
        i.revision = Int64.max - 1; try c.save()
        await #expect(throws: SharedMediaStorageFailure.invalid) { _ = try await owner.startAppRelease(admission.request) }
        #expect(saves == 0)
        #expect(try row(h) == before)
        i.revision = revision; try c.save()
        try owner.setMetadataFault { _ in }
        // Generic acquisition deliberately rejects a staged release sidecar.
        // Preserve that fence; this test does not qualify acquisition coexistence.
        await #expect(throws: SharedMediaStorageFailure.closed) {
            _ = try await owner.prepareAppOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
        }
        #expect(try row(h) == before)
        #expect(try inventory(h, h.context()).revision == revision)
        // Test-only monotonic metadata advance exercises the typed release
        // reader's current-header contract, not an ordinary acquisition path.
        i.revision = try SharedMediaStoragePolicy.add(revision, 1); try c.save()
        let expected = try staged(h).components.progress
        #expect(expected.plan.preHeader.inventory.revision > revision)
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        #expect(try await owner.startAppRelease(admission.request) == expected)
        let wrongPlan = try SharedMediaNativeReceivingTestFixture.copy(expected.plan, changes: ["releaseID": UUID().uuidString])
        let wrong = try Values.Progress(plan: wrongPlan)
        await #expect(throws: (any Error).self) { _ = try await owner.recoverAppReleaseStart(wrong) }
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancelledWaitAndClosedOwnerNeverStart() async throws {
        let (h, owner, _, admission) = try await fixture()
        _ = try await owner.stageAppRelease(admission)
        let before = try row(h), request = admission.request
        let coordinator = ScanInferencePersistenceCoordinator.shared
        let held = await coordinator.acquireAll(scanIds: [request.queueID.uuidString, request.observationID.uuidString])
        let work = Task { try await owner.startAppRelease(request) }
        await Task.yield(); work.cancel()
        await coordinator.releaseAll(scanIds: held)
        await #expect(throws: (any Error).self) { _ = try await work.value }
        #expect(try row(h) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        await #expect(throws: (any Error).self) { _ = try await owner.startAppRelease(request) }
        #expect(try row(h) == before)
    }

    func fixture(foreign: Bool = false) async throws -> (Store, SharedMediaNativeOriginalOwner, Intent.Prepared, SharedMediaNativeReleaseStageAdmission) {
        let (h, owner, receiving) = try await SharedMediaNativeAppReceivingTests().fixture(foreignOriginal: foreign, temporaryStore: true, fenceBootstrap: true)
        let p = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
            pairIDs: SharedMediaNativeReceivingStagingTests().pairIDs(receiving))
        _ = try await owner.receiveAppPrepared(p)
        return (h, owner, p, try await owner.appReleaseStageRequest(p, releaseID: UUID()))
    }
    func staged(_ h: Store, _ context: ModelContext? = nil) throws -> SharedMediaNativeReceivedReleaseSnapshot.StagedSnapshot {
        let c = context ?? h.context()
        return try SharedMediaNativeReceivedReleaseSnapshot.readStaged(.read(.init(record(h, c)), inventory: inventory(h, c), context: c), context: c)
    }
    func record(_ h: Store, _ c: ModelContext) throws -> SharedMediaReceivingIntentRecord {
        try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: c))
    }
    func row(_ h: Store) throws -> Row { .init(try record(h, h.context())) }
    func inventory(_ h: Store, _ c: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = h.inventoryID
        return try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
}
