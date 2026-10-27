import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive receiving terminal owner", .serialized)
@MainActor
struct SharedMediaNativeReceivingTerminalOwnerTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let reader = SharedMediaNativeReleasePairOwnerTests()

    @Test(arguments: [1, 2], [false, true])
    func closesActualCleanupAndReopensWithoutAnotherSave(_ count: Int, _ shared: Bool) async throws {
        let (h, owner, before) = try await fixture(count: count, shared: shared)
        let snapshot = try reader.snapshot(h)
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        let released = try await owner.finishAppRelease(before)
        #expect(released == (try .init(progress: before, inventoryRevision: snapshot.inventoryRevision + 1)))
        #expect(try terminal(h).value == released)
        #expect(try await owner.finishAppRelease(before) == released)
        #expect(saves == 1)
        let c = h.context(), id = before.plan.package.id
        #expect(try c.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id })) == 0)
        #expect(try c.fetchCount(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })) == 0)
        try SharedMediaNativeReceivingRows.requireAbsent(.init(before.plan), in: c)
        let inv = try inventory(h, c)
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inv,
            ownerID: h.ownerID, format: .appV2)
        #expect(budget.metadataByPackage[id] == nil)
        #expect(try SharedMediaNativeTerminalScan.read(container: h.container, inventoryID: h.inventoryID).bytes == Int64(released.encoded().count))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.finishAppRelease(before) == released)
        #expect(try await cold.discoverAppReceivedCandidates().isEmpty)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
        // Historical recovery tolerates an unrelated inventory advance only.
        let later = h.context(); try inventory(h, later).revision += 1; try later.save()
        #expect(try SharedMediaNativeReceivingTerminalRecovery.historical(before, context: h.context()) == released)
    }

    @Test(arguments: ["beforeSave", "afterSave", "beforeReadback"])
    func uncertainSaveNeverIssuesAnotherSave(_ fault: String) async throws {
        let (h, owner, before) = try await fixture()
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if (fault == "beforeSave" && $0 == .beforeSave) || (fault == "afterSave" && $0 == .afterSave) ||
                (fault == "beforeReadback" && $0 == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterSave" { _ = try await owner.finishAppRelease(before) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.finishAppRelease(before) } }
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        if fault == "beforeSave" {
            await #expect(throws: (any Error).self) { _ = try await owner.finishAppRelease(before) }
            #expect(try reader.snapshot(h).release.progress == before)
        } else { #expect(try await owner.finishAppRelease(before) == terminal(h).value) }
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.finishAppRelease(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func reappearingFinalOrPartialPreservesHeldRoots(_ partial: Bool) async throws {
        let (h, owner, before) = try await fixture()
        let prefix = try SharedMediaNativeReleasePrefix(terminal: reader.snapshot(h))
        guard case .absent(let file, _) = prefix.checks[0] else { Issue.record("Expected removed derivative"); return }
        let url = h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(file.token + (partial ? ".partial" : ""))
        try owner.setMetadataFault { if $0 == .beforeSave { try Data([1]).write(to: url) } }
        await #expect(throws: (any Error).self) { _ = try await owner.finishAppRelease(before) }
        #expect(try reader.snapshot(h).release.progress == before)
        try owner.setMetadataFault(nil)
        try FileManager.default.removeItem(at: url)
        // A failed frozen attempt remains read-only on this owner.
        await #expect(throws: (any Error).self) { _ = try await owner.finishAppRelease(before) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancellationBeforeSavePreservesRootsUntilJoinedRecovery() async throws {
        let (h, owner, before) = try await fixture()
        var saves = 0
        try owner.setMetadataFault { point in
            if point == .beforeSave {
                saves += 1
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let operation = Task { try await owner.finishAppRelease(before) }
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        #expect(saves == 1)
        #expect(try reader.snapshot(h).release.progress == before)
        try owner.setMetadataFault(nil)
        await #expect(throws: (any Error).self) { _ = try await owner.finishAppRelease(before) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        // The revoked owner cannot acquire fresh authority after its join.
        await #expect(throws: (any Error).self) { _ = try await owner.finishAppRelease(before) }
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.finishAppRelease(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["consumer", "queue", "job", "event"])
    func frozenQuartetRejectsPersistedFieldDrift(_ kind: String) async throws {
        let (h, owner, before) = try await fixture()
        let c = h.context(), snapshot = try reader.snapshot(h)
        let after = try Values.Released(progress: before, inventoryRevision: snapshot.inventoryRevision + 1)
        let seal = try SharedMediaNativeReceivingTerminalPoststate(before: snapshot, after: after, context: c)
        let other = h.context(), origin = try SharedMediaNativeReleaseOrigin.read(before.plan, in: other)
        switch kind {
        case "consumer": origin.rows.consumer.revision += 1
        case "queue": origin.rows.queue.coverImagePath = "synthetic-unrelated-change"
        case "job": origin.rows.job.priority += 1
        default: origin.rows.event.id = UUID().uuidString.lowercased()
        }
        try other.save()
        #expect(throws: (any Error).self) { try seal.requirePredecessor(h.context()) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func strictSealRejectsExtraWritesAndReplacementRows() async throws {
        let (h, owner, before) = try await fixture()
        let c = h.context(), snapshot = try reader.snapshot(h)
        let after = try Values.Released(progress: before, inventoryRevision: snapshot.inventoryRevision + 1)
        let seal = try SharedMediaNativeReceivingTerminalPoststate(before: snapshot, after: after, context: c)
        let ordinary = try h.package(h.ordinaryID, in: c)
        ordinary.supportingContextData = Data("changed-unrelated-draft".utf8)
        #expect(throws: (any Error).self) { try seal.validate(c) }
        c.rollback(); try seal.requirePredecessor(c)
        let other = h.context(), package = try h.package(in: other)
        let oldID = package.persistentModelID
        // Replacing even a byte-identical membership is not the frozen row.
        let id = before.plan.package.id
        let member = try SharedMediaNativePairPlanGraph.one(other,
            FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        let memberID = member.persistentModelID
        let replacement = SharedMediaPendingMembershipRecord(packageID: member.id, inventoryID: member.inventoryID,
            inventoryGeneration: member.inventoryGeneration, ownerID: member.ownerID,
            draftGeneration: member.draftGeneration, membersData: member.membersData)
        replacement.revision = member.revision
        other.delete(member); try other.save(); other.insert(replacement); try other.save()
        #expect(replacement.persistentModelID != memberID && package.persistentModelID == oldID)
        #expect(throws: (any Error).self) { try seal.requirePredecessor(h.context()) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func exactDirtySuccessorRejectsEveryDeletedRootMutationAndUnrelatedChanges() async throws {
        let (h, owner, before) = try await fixture()
        let snapshot = try reader.snapshot(h)
        let after = try Values.Released(progress: before, inventoryRevision: snapshot.inventoryRevision + 1)
        for fault in ["package", "member", "consumer", "queue", "job", "event", "inventory", "slot", "insert", "update", "delete"] {
            let c = h.context(), id = before.plan.package.id
            let seal = try SharedMediaNativeReceivingTerminalPoststate(before: snapshot, after: after, context: c)
            let package = try h.package(in: c), origin = try SharedMediaNativeReleaseOrigin.read(before.plan, in: c)
            let member = try SharedMediaNativePairPlanGraph.one(c,
                FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
            let inv = try inventory(h, c)
            let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(id, in: c))
            inv.revision = after.inventoryRevision
            row.phaseRaw = "released"; row.revision = try SharedMediaNativeReceivingTerminal.revision(after)
            row.preparedData = nil; row.releaseStartData = nil; row.releaseStartSHA256 = nil
            row.resultData = try after.encoded(); row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(row.resultData!)
            c.delete(package); c.delete(member); c.delete(origin.rows.consumer)
            c.delete(origin.rows.queue); c.delete(origin.rows.job); c.delete(origin.rows.event)
            // Establish the legal baseline before injecting one adversarial
            // difference, so rejection cannot be caused by an incomplete save.
            try seal.validate(c)
            switch fault {
            case "package": package.supportingContextData = Data("changed-submission".utf8)
            case "member": member.revision += 1
            case "consumer": origin.rows.consumer.revision += 1
            case "queue": origin.rows.queue.coverImagePath = "changed-cover"
            case "job": origin.rows.job.priority += 1
            case "event": origin.rows.event.id = UUID().uuidString.lowercased()
            case "inventory": inv.cursor = "unexpected"
            case "slot": row.preparedSHA256 = "unexpected"
            case "insert": c.insert(OfflineQueuedScan(id: UUID().uuidString.lowercased()))
            case "update": try h.package(h.ordinaryID, in: c).revision += 1
            default: c.delete(try h.package(h.ordinaryID, in: c))
            }
            #expect(throws: (any Error).self) { try seal.validate(c) }
            c.rollback()
            try seal.requirePredecessor(c)
            #expect(try reader.snapshot(h).release.progress == before)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    func fixture(count: Int = 1, shared: Bool = false) async throws -> (Store, SharedMediaNativeOriginalOwner, Values.Progress) {
        let h: Store, owner: SharedMediaNativeOriginalOwner
        var progress: Values.Progress
        if shared {
            let fixture = try await SharedMediaNativeOriginalDispositionSharingTests().fixture(foreign: true, count: count)
            h = fixture.0; owner = fixture.1
            progress = try await owner.disposeAppReleaseOriginal(fixture.2)
        } else {
            let fixture = try await SharedMediaNativeOriginalRemovalOwnerTests().fixture(count: count)
            h = fixture.0; owner = fixture.1
            progress = try await owner.removeAppReleaseOriginal(fixture.2)
        }
        if count == 2 {
            try await owner.continueAppRelease(progress)
            progress = try await owner.retireAppReleasePair(progress)
            progress = try await owner.removeAppReleasePair(progress)
            progress = try await owner.disposeAppReleaseOriginal(progress)
            if progress.targets[1].stage == .originalRetiring { progress = try await owner.removeAppReleaseOriginal(progress) }
        }
        return (h, owner, progress)
    }
    func inventory(_ h: Store, _ context: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = h.inventoryID
        return try SharedMediaNativePairPlanGraph.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
    func terminal(_ h: Store) throws -> SharedMediaNativeReceivingTerminal.Snapshot {
        let c = h.context(), id = h.packageID
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(id, in: c))
        return try SharedMediaNativeReceivingTerminal.read(row, context: c, inventory: inventory(h, c))
    }
}
