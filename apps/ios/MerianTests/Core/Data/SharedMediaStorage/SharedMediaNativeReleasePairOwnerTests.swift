import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive held pair-retirement owner", .serialized)
@MainActor
struct SharedMediaNativeReleasePairOwnerTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let start = SharedMediaNativeReleaseStartOwnerTests()

    @Test(arguments: [false, true])
    func actualRetirementPreservesHeldMediaAndRecoversCold(_ shared: Bool) async throws {
        let (h, owner, progress) = try await fixture(shared: shared)
        let before = try snapshot(h), state = try #require(before.pairs.first)
        let files = try state.work.map { try path(h, state.file($0.id).token) }
        let bytes = try files.map { try Data(contentsOf: $0) }, envelope = try h.package().supportingContextData
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        let result = try await owner.retireAppReleasePair(progress)
        #expect(result.targets.first?.stage == .retiringPair && result.targets.dropFirst().allSatisfy { $0.stage == .readyPair })
        let after = try snapshot(h)
        #expect(after.release.progress == result)
        #expect(after.release.state.package.phase == before.release.state.package.phase)
        #expect(after.release.state.package.allocated == before.release.state.package.allocated)
        #expect(try h.package().supportingContextData == envelope)
        #expect(after.ownedOriginals == before.ownedOriginals && after.targetOrigins == before.targetOrigins)
        #expect(try files.map { try Data(contentsOf: $0) } == bytes)
        #expect(after.pairs.first?.work.allSatisfy { $0.phase == "retiring" && $0.closure != nil } == true)
        #expect(try await owner.recoverAppReleasePair(result) == result)
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(progress) }
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(result) }
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.recoverAppReleasePair(result) == result)
        await #expect(throws: (any Error).self) { _ = try await cold.retireAppReleasePair(progress) }
        #expect(try files.map { try Data(contentsOf: $0) } == bytes)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func confirmedMissingOutputKeepsAllAccounting() async throws {
        let (h, owner, progress) = try await fixture()
        let before = try snapshot(h), state = try #require(before.pairs.first), work = try #require(state.work.first)
        let file = try path(h, state.file(work.id).token)
        try FileManager.default.removeItem(at: file)
        let result = try await owner.retireAppReleasePair(progress), after = try snapshot(h)
        #expect(after.release.progress == result && after.release.state.package.allocated == before.release.state.package.allocated)
        #expect(after.pairs.first?.work.first?.retirementFinal == "absent")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "afterSave", "beforeReadback"])
    func faultsKeepOneFrozenOutcome(_ fault: String) async throws {
        let (h, owner, progress) = try await fixture()
        let row = try start.row(h)
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if (fault == "beforeSave" && $0 == .beforeSave) || (fault == "afterSave" && $0 == .afterSave) ||
                (fault == "beforeReadback" && $0 == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterSave" { _ = try await owner.retireAppReleasePair(progress) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(progress) } }
        #expect(saves == 1)
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        if fault == "beforeSave" {
            #expect(try start.row(h) == row)
            let result = try await owner.retireAppReleasePair(progress)
            #expect(try await owner.recoverAppReleasePair(result) == result && saves == 2)
        } else {
            let result = try snapshot(h).release.progress
            await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(progress) }
            await #expect(throws: (any Error).self) { _ = try await owner.recoverAppReleaseStart(progress) }
            #expect(try await owner.recoverAppReleasePair(result) == result && saves == 1)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["afterSave", "beforeReadback", "cold"])
    func recoveredStartNeverGrantsRetirement(_ fault: String) async throws {
        let (h, owner, _, admission) = try await start.fixture()
        _ = try await owner.stageAppRelease(admission)
        let progress = try start.staged(h).components.progress
        if fault != "cold" {
            try owner.setMetadataFault {
                if (fault == "afterSave" && $0 == .afterSave) || (fault == "beforeReadback" && $0 == .beforeReadback) {
                    throw SharedMediaStorageFailure.unavailable
                }
            }
        }
        if fault == "beforeReadback" { await #expect(throws: (any Error).self) { _ = try await owner.startAppRelease(admission.request) } }
        else { _ = try await owner.startAppRelease(admission.request) }
        try owner.setMetadataFault { _ in }
        #expect(try await owner.recoverAppReleaseStart(progress) == progress)
        if fault == "cold" {
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
            #expect(try await cold.recoverAppReleaseStart(progress) == progress)
            await #expect(throws: (any Error).self) { _ = try await cold.retireAppReleasePair(progress) }
            #expect(await cold.invalidateAndAwaitForAccountTransition())
        } else {
            await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(progress) }
            #expect(await owner.invalidateAndAwaitForAccountTransition())
        }
        #expect(try snapshot(h).release.progress == progress)
    }

    @Test(arguments: ["partial", "replacement", "lateReplacement"])
    func foreignPathsNeverAuthorizeRetirement(_ fault: String) async throws {
        let (h, owner, progress) = try await fixture()
        let state = try #require(try snapshot(h).pairs.first), work = try #require(state.work.first)
        let file = try path(h, state.file(work.id).token), old = try Data(contentsOf: file), row = try start.row(h)
        func replace() throws { try FileManager.default.removeItem(at: file); try old.write(to: file) }
        if fault == "partial" { try Data([1]).write(to: URL(fileURLWithPath: file.path + ".partial")) }
        else if fault == "replacement" { try replace() }
        else { try owner.setMetadataFault { if $0 == .beforeSave { try replace() } } }
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(progress) }
        #expect(try start.row(h) == row)
        try owner.setMetadataFault { _ in }
        // A changed file cannot be accepted by replacing the frozen proofs.
        if fault == "lateReplacement" {
            await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(progress) }
            #expect(try start.row(h) == row)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func unknownClosureBlocksDispatchAndDrainUntilRestored() async throws {
        let (h, owner, progress) = try await fixture()
        try owner.setMetadataFault { if $0 == .beforeReadback { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(progress) }
        let saved = try snapshot(h).release.progress, context = h.context()
        let row = try #require(try context.fetch(FetchDescriptor<PhotoPreparationLease>()).first)
        let closure = row.terminalProof
        row.terminalProof = "invalid"; try context.save()
        try owner.setMetadataFault { _ in }
        await #expect(throws: (any Error).self) { _ = try await owner.recoverAppReleasePair(saved) }
        await #expect(throws: (any Error).self) { _ = try await owner.recoverAppReleaseStart(progress) }
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        row.terminalProof = closure; try context.save()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        #expect(try snapshot(h).release.progress == saved)
    }

    @Test func cancelledWaitAndWrongPlanNeverMutate() async throws {
        let (h, owner, progress) = try await fixture(), before = try start.row(h)
        let wrongPlan = try SharedMediaNativeReceivingTestFixture.copy(progress.plan, changes: ["releaseID": UUID().uuidString])
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(Values.Progress(plan: wrongPlan)) }
        let coordinator = ScanInferencePersistenceCoordinator.shared
        let held = await coordinator.acquireAll(scanIds: [progress.plan.queueID.uuidString, progress.plan.observationID.uuidString])
        let work = Task { try await owner.retireAppReleasePair(progress) }
        await Task.yield(); work.cancel(); await coordinator.releaseAll(scanIds: held)
        await #expect(throws: (any Error).self) { _ = try await work.value }
        #expect(try start.row(h) == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    func fixture(shared: Bool = false) async throws -> (Store, SharedMediaNativeOriginalOwner, Values.Progress) {
        let (h, owner, _, admission) = try await start.fixture(foreign: shared)
        _ = try await owner.stageAppRelease(admission)
        return (h, owner, try await owner.startAppRelease(admission.request))
    }
    func snapshot(_ h: Store) throws -> SharedMediaNativeReleaseMetadataSnapshot.Snapshot {
        try SharedMediaNativeReleaseMetadataSnapshot.read(packageID: h.packageID, inventoryID: h.inventoryID, context: h.context())
    }
    private func path(_ h: Store, _ token: String) -> URL { h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token) }
}
