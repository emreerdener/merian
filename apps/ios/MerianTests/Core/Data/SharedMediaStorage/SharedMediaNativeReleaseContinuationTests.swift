import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive ordered held release continuation", .serialized)
@MainActor
struct SharedMediaNativeReleaseContinuationTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let reader = SharedMediaNativeReleasePairOwnerTests()
    let originals = SharedMediaNativeOriginalDispositionOwnerTests()

    @Test(arguments: [false, true])
    func explicitContinuationCompletesOwnedAndSharedPackages(_ shared: Bool) async throws {
        let (h, owner, before) = try await fixture(shared: shared)
        let old = try reader.snapshot(h), selected = before.plan.targets[1]
        let accounting = try originals.accounting(h, selected.original.assetID)
        let first = before.targets[0], frozen = old.release.origin.prepared
        let prefix = try SharedMediaNativeReleasePrefix(old)
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(before) }
        try await owner.continueAppRelease(before)
        try await owner.continueAppRelease(before) // Same unused right, no new save.
        #expect(try reader.snapshot(h).release.progress == before)
        await #expect(throws: (any Error).self) {
            _ = try await owner.prepareAppOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
        }
        let retiring = try await owner.retireAppReleasePair(before)
        #expect(retiring.targets[0] == first && retiring.targets[1].stage == .retiringPair)
        #expect(try reader.snapshot(h).release.state.package.allocated == old.release.state.package.allocated)
        await #expect(throws: (any Error).self) { try await owner.continueAppRelease(before) }
        let gone = try await owner.removeAppReleasePair(retiring)
        #expect(gone.targets[0] == first && gone.targets[1].stage == .pairGoneOriginalLive)
        let afterPair = try reader.snapshot(h)
        let disposing = try await owner.disposeAppReleaseOriginal(gone)
        #expect(disposing.targets[0] == first && disposing.targets[1].stage == .originalRetiring)
        #expect(try reader.snapshot(h).release.state.package.allocated == afterPair.release.state.package.allocated)
        let removed = try await owner.removeAppReleaseOriginal(disposing)
        let saved = try reader.snapshot(h)
        #expect(removed.targets.allSatisfy { $0.stage == .removed } && removed.targets[0] == first)
        #expect(saved.release.state.package.allocated == afterPair.release.state.package.allocated - accounting.byteCount)
        #expect(saved.inventoryRevision == old.inventoryRevision + 4)
        #expect(saved.release.slot.revision == old.release.slot.revision + 4)
        #expect(saved.release.slot.phase == "releasing") // Package closure is a separate step.
        #expect(try saved.release.origin.prepared.encoded() == frozen.encoded())
        #expect(removed.plan == before.plan)
        for check in prefix.checks {
            switch check {
            case .absent(let file, _): #expect(!FileManager.default.fileExists(atPath: path(h, file.token).path))
            case .shared(let file, _):
                #expect(FileManager.default.fileExists(atPath: path(h, file.token).path))
                #expect(try originals.accounting(h, file.assetID).liveCount == 1)
            }
        }
        await #expect(throws: (any Error).self) { try await owner.continueAppRelease(removed) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func coldRecoveryDoesNotGrantContinuation() async throws {
        let (h, owner, before) = try await fixture()
        let prepared = try reader.snapshot(h).release.origin.prepared
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.discoverAppRelease(prepared) == .releasing(before))
        await #expect(throws: (any Error).self) { _ = try await cold.retireAppReleasePair(before) }
        try await cold.continueAppRelease(before)
        _ = try await cold.retireAppReleasePair(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "joinedBeforeSave", "afterSave", "beforeReadback"])
    func uncertainContinuationCannotReplenishItsRight(_ fault: String) async throws {
        let (h, owner, before) = try await fixture()
        try await owner.continueAppRelease(before)
        let beforeSave = fault == "beforeSave" || fault == "joinedBeforeSave"
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if (beforeSave && $0 == .beforeSave) || (fault == "afterSave" && $0 == .afterSave) ||
                (fault == "beforeReadback" && $0 == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterSave" { _ = try await owner.retireAppReleasePair(before) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(before) } }
        let saved = try reader.snapshot(h).release.progress
        #expect(saved.targets[0] == before.targets[0])
        #expect(saved.targets[1].stage == (beforeSave ? .readyPair : .retiringPair))
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        await #expect(throws: (any Error).self) { try await owner.continueAppRelease(before) }
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(before) }
        #expect(saves == 1)
        if fault != "afterSave" && fault != "joinedBeforeSave" {
            #expect(try await owner.recoverAppReleasePair(saved) == saved)
            await #expect(throws: (any Error).self) { try await owner.continueAppRelease(before) }
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        if beforeSave {
            await #expect(throws: (any Error).self) { _ = try await cold.retireAppReleasePair(before) }
            try await cold.continueAppRelease(before)
            _ = try await cold.retireAppReleasePair(before)
        } else {
            #expect(try await cold.recoverAppReleasePair(saved) == saved)
        }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["original", "ai", "display", "originalPartial", "aiPartial", "displayPartial"])
    func reappearingPrefixBlocksAdmission(_ leaf: String) async throws {
        let (h, owner, before) = try await fixture()
        let prefix = try SharedMediaNativeReleasePrefix(reader.snapshot(h))
        let index = leaf.hasPrefix("original") ? 2 : (leaf.hasPrefix("ai") ? 0 : 1)
        guard case .absent(let file, _) = prefix.checks[index] else { Issue.record("Expected removed prefix"); return }
        var url = path(h, file.token)
        if leaf.hasSuffix("Partial") { url = url.appendingPathExtension("partial") }
        try Data([1]).write(to: url)
        await #expect(throws: (any Error).self) { try await owner.continueAppRelease(before) }
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(before) }
        #expect(try reader.snapshot(h).release.progress == before)
        try FileManager.default.removeItem(at: url)
        // The failed audit never issued a right. Repair allows an explicit new audit.
        try await owner.continueAppRelease(before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func failedUseBurnsAnUnusedRightUntilOwnerCloses() async throws {
        let (h, owner, before) = try await fixture()
        try await owner.continueAppRelease(before)
        let prefix = try SharedMediaNativeReleasePrefix(reader.snapshot(h))
        guard case .absent(let file, _) = prefix.checks[0] else { Issue.record("Expected pair prefix"); return }
        let url = path(h, file.token)
        try Data([1]).write(to: url)
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(before) }
        try FileManager.default.removeItem(at: url)
        await #expect(throws: (any Error).self) { try await owner.continueAppRelease(before) }
        #expect(try reader.snapshot(h).release.progress == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        try await cold.continueAppRelease(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func continuationCannotReplaceTheInitialAcknowledgement() async throws {
        let (firstStore, firstOwner, ready) = try await reader.fixture()
        await #expect(throws: (any Error).self) { try await firstOwner.continueAppRelease(ready) }
        #expect(await firstOwner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(firstStore)
        await #expect(throws: (any Error).self) { try await cold.continueAppRelease(ready) }
        await #expect(throws: (any Error).self) { _ = try await cold.retireAppReleasePair(ready) }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
        let (h, owner, retiring) = try await SharedMediaNativeReleasePairRemovalOwnerTests().fixture(count: 2)
        await #expect(throws: (any Error).self) { try await owner.continueAppRelease(retiring) }
        let initial = try Values.Progress(plan: retiring.plan)
        await #expect(throws: (any Error).self) { try await owner.continueAppRelease(initial) }
        #expect(try reader.snapshot(h).release.progress == retiring)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func missingSharedPrefixPreservesSurvivorAndDeniesAdmission() async throws {
        let (h, owner, before) = try await fixture(shared: true)
        let prefix = try SharedMediaNativeReleasePrefix(reader.snapshot(h))
        guard case .shared(let file, _) = try #require(prefix.checks.last) else { Issue.record("Expected shared original"); return }
        let url = path(h, file.token), held = h.parent.appendingPathComponent("held-original")
        try FileManager.default.moveItem(at: url, to: held)
        await #expect(throws: (any Error).self) { try await owner.continueAppRelease(before) }
        #expect(try originals.accounting(h, file.assetID).liveCount == 1)
        #expect(try reader.snapshot(h).release.progress == before)
        try FileManager.default.moveItem(at: held, to: url)
        // Restoring the pathname does not restore the frozen ctime identity.
        await #expect(throws: (any Error).self) { try await owner.continueAppRelease(before) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func fixture(shared: Bool = false) async throws -> (Store, SharedMediaNativeOriginalOwner, Values.Progress) {
        if shared {
            let (h, owner, gone) = try await SharedMediaNativeOriginalDispositionSharingTests().fixture(foreign: true, count: 2)
            return (h, owner, try await owner.disposeAppReleaseOriginal(gone))
        }
        let (h, owner, retiring) = try await SharedMediaNativeOriginalRemovalOwnerTests().fixture(count: 2)
        return (h, owner, try await owner.removeAppReleaseOriginal(retiring))
    }
    private func path(_ h: Store, _ token: String) -> URL {
        h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token)
    }
}
