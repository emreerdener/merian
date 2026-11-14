import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive held original disposition", .serialized)
@MainActor
struct SharedMediaNativeOriginalDispositionOwnerTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Rows = SharedMediaNativeAppOriginalRows
    let prior = SharedMediaNativeReleasePairOwnerTests()

    @Test(arguments: [1, 2])
    func finalReferenceRetiresMetadataAndPreservesBytes(_ count: Int) async throws {
        let (h, owner, before) = try await fixture(count: count)
        let target = before.plan.targets[0], original = try accounting(h, target.original.assetID)
        let bytes = try originalBytes(h, before), old = try prior.snapshot(h)
        let beforeLiability = try SharedMediaNativeOriginalLiability.read(context: h.context(), inventoryID: h.inventoryID)
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        let after = try await owner.disposeAppReleaseOriginal(before)
        let saved = try prior.snapshot(h), current = try accounting(h, target.original.assetID)
        #expect(after.targets[0].stage == .originalRetiring)
        #expect(after.targets.dropFirst() == before.targets.dropFirst())
        #expect(after.plan == before.plan && after.targets[0].pair == before.targets[0].pair)
        #expect(current.liveCount == 0 && current.countRevision == original.countRevision + 1)
        let identity = try #require(current.retirement)
        #expect(after.targets[0].original?.retirementID == identity.retirementID)
        #expect(after.targets[0].original?.closureSHA256 == SharedMediaAcquisitionEncoding.digest(Data(try identity.encoded().utf8)))
        let rows = try Rows(h.context(), profile: before.plan.profile, source: target.original)
        #expect(identity.proof == (try rows.completed().1.descriptor))
        #expect(saved.release.state.package.allocated == old.release.state.package.allocated)
        #expect(saved.release.state.member.bytes == old.release.state.member.bytes)
        #expect(try originalBytes(h, before) == bytes)
        let liability = try SharedMediaNativeOriginalLiability.read(context: h.context(), inventoryID: h.inventoryID)
        #expect(liability.entries.count == beforeLiability.entries.count)
        #expect(try liability.currentBytes + liability.reservedBytes == beforeLiability.currentBytes + beforeLiability.reservedBytes)
        #expect(try await owner.disposeAppReleaseOriginal(before) == after && saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.disposeAppReleaseOriginal(before) == after)
        #expect(try originalBytes(h, before) == bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "afterSave", "beforeReadback"])
    func uncertaintyDoesNotReissueMetadataAndReopensExactBoundary(_ fault: String) async throws {
        let (h, owner, before) = try await fixture()
        let bytes = try originalBytes(h, before)
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if (fault == "beforeSave" && $0 == .beforeSave) || (fault == "afterSave" && $0 == .afterSave) ||
                (fault == "beforeReadback" && $0 == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterSave" { _ = try await owner.disposeAppReleaseOriginal(before) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.disposeAppReleaseOriginal(before) } }
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        if fault == "beforeSave" {
            await #expect(throws: (any Error).self) { _ = try await owner.disposeAppReleaseOriginal(before) }
            #expect(try prior.snapshot(h).release.progress == before)
        } else { #expect(try await owner.disposeAppReleaseOriginal(before) == prior.snapshot(h).release.progress) }
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let after = try await cold.disposeAppReleaseOriginal(before)
        #expect(after.targets[0].stage == .originalRetiring)
        #expect(try originalBytes(h, before) == bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func coldPredecessorRequiresOldOwnerClosure() async throws {
        let (h, owner, before) = try await fixture()
        await #expect(throws: (any Error).self) { _ = try await SharedMediaNativeReceivingStagingTests().reopen(h) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let after = try await cold.disposeAppReleaseOriginal(before)
        #expect(after.targets[0].stage == .originalRetiring)
        await #expect(throws: (any Error).self) { _ = try await owner.disposeAppReleaseOriginal(before) }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["count", "identity", "reference", "inventory", "pair", "digest"])
    func corruptPredecessorCannotBecomeAnAdmission(_ fault: String) async throws {
        let (h, owner, before) = try await fixture()
        let c = h.context(), target = before.plan.targets[0]
        let rows = try Rows(c, profile: before.plan.profile, source: target.original)
        let (ref, _) = try Rows.reference(c, source: target.original, live: true)
        let originalCount = rows.count.liveCount, originalIdentity = rows.allocation.physicalIdentity
        let originalGeneration = rows.inventory.generation
        let slot = try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: c))
        let originalDigest = slot.resultSHA256
        switch fault {
        case "count": rows.count.liveCount += 1
        case "identity": rows.allocation.physicalIdentity = "invalid"
        case "reference": ref.roleRaw = "display"
        case "inventory": rows.inventory.generation = UUID()
        case "pair":
            // Existing derivative role row must remain absent at this boundary.
            c.insert(SharedMediaReferenceRecord(id: target.ai.referenceID, allocationID: target.ai.assetID,
                accountID: h.ownerID, ownerID: target.ai.referenceID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        default: slot.resultSHA256 = String(repeating: "0", count: 64)
        }
        try c.save()
        await #expect(throws: (any Error).self) { _ = try await owner.disposeAppReleaseOriginal(before) }
        rows.count.liveCount = originalCount; rows.allocation.physicalIdentity = originalIdentity
        ref.roleRaw = "original"; rows.inventory.generation = originalGeneration; slot.resultSHA256 = originalDigest
        if fault == "pair" {
            let id = target.ai.referenceID
            c.delete(try Rows.one(c, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id })))
        }
        try c.save()
        #expect(try prior.snapshot(h).release.progress == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func rawSealRejectsUnrelatedWritesAndPreservedFieldDrift() async throws {
        let (h, owner, before) = try await fixture()
        let c = h.context(), header = try currentHeader(h, before)
        let attempt = try SharedMediaNativeOriginalDispositionAttempt.audited(before, retirementID: UUID(), header: header, context: c)
        let rows = try Rows(c, profile: before.plan.profile, source: before.plan.targets[0].original)
        rows.receipt.revision += 1
        #expect(throws: (any Error).self) { try attempt.seal.validate(c) }
        c.rollback(); try attempt.seal.requirePredecessor(c)
        let oldKind = rows.asset.acquisitionKindRaw
        let other = h.context(), current = try Rows(other, profile: before.plan.profile, source: before.plan.targets[0].original)
        current.asset.acquisitionKindRaw = "changed"; try other.save()
        #expect(throws: (any Error).self) { try attempt.seal.requirePredecessor(h.context()) }
        current.asset.acquisitionKindRaw = oldKind; try other.save()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func rawSealRejectsSameLogicalCountWithReplacementPersistenceIdentity() async throws {
        let (h, owner, before) = try await fixture()
        let attempt = try SharedMediaNativeOriginalDispositionAttempt.audited(before, retirementID: UUID(),
            header: currentHeader(h, before), context: h.context())
        let c = h.context(), id = before.plan.targets[0].original.assetID
        let old = try Rows.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == id }))
        let oldID = old.persistentModelID
        let replacement = SharedMediaAssetReferenceCountRecord(assetID: old.id, assetGeneration: old.assetGeneration,
            inventoryID: old.inventoryID, inventoryGeneration: old.inventoryGeneration, ownerID: old.ownerID,
            liveCount: old.liveCount)
        replacement.revision = old.revision; replacement.retirementID = old.retirementID
        c.delete(old); try c.save(); c.insert(replacement); try c.save()
        #expect(replacement.persistentModelID != oldID)
        #expect(throws: (any Error).self) { try attempt.requirePredecessor(h.context(), header: currentHeader(h, before)) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    func fixture(count: Int = 1) async throws -> (Store, SharedMediaNativeOriginalOwner, Values.Progress) {
        let (h, owner, retiring) = try await SharedMediaNativeReleasePairRemovalOwnerTests().fixture(count: count)
        return (h, owner, try await owner.removeAppReleasePair(retiring))
    }
    func currentHeader(_ h: Store, _ before: Values.Progress) throws -> SharedMediaNativeAppEligibility.Header {
        let p = before.plan.profile
        return try SharedMediaNativeAppEligibility.snapshot(context: h.context(), scope: .init(inventoryID: p.inventoryID,
            generation: p.generation, ownerID: p.ownerID, storeIdentity: p.storeIdentity, rootBinding: p.rootIdentity))
    }
    func accounting(_ h: Store, _ id: UUID) throws -> SharedMediaNativeOriginalAccounting.Snapshot {
        try SharedMediaNativeOriginalAccounting.audit(assetID: id, inventoryID: h.inventoryID, context: h.context())
    }
    func originalBytes(_ h: Store, _ progress: Values.Progress) throws -> [Data] {
        try progress.plan.targets.map { target in
            let rows = try Rows(h.context(), profile: progress.plan.profile, source: target.original)
            return try Data(contentsOf: h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(rows.asset.fileToken))
        }
    }
}
