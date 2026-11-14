import Darwin
import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationReanalysisCleanupTests {
    let fixture = ObservationReanalysisPersistenceTests()

    func receipt(_ container: ModelContainer) throws -> ObservationReanalysisErasureReceipt {
        _ = try fixture.stage(container)
        let context = ModelContext(container)
        _ = try ObservationReanalysisErasure.removeChildren(of: fixture.fixture.observation.uuidString, context: context)
        try context.save()
        return .init(parentID: fixture.fixture.observation, childID: fixture.child)
    }

    func write(_ root: URL, child: UUID) throws -> URL {
        let directory = root.appendingPathComponent("ReanalysisQueue/" + child.uuidString.lowercased())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("photo.jpg"))
        try Data([4]).write(to: directory.appendingPathComponent(".interrupted.preparing"))
        return directory
    }

    func status(_ container: ModelContainer) throws -> OfflineJobStatus {
        let job = try #require(try ModelContext(container).fetchOfflineJob(id: ObservationReanalysisErasureReceipt.jobID(fixture.child)))
        return job.status
    }

    @Test func restartedOwnerErasesWholeNamespaceAndRetainsMinimalTombstone() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID), sibling = try write(root, child: UUID())
        let owner = ObservationReanalysisErasureOwner(files: .init(documents: root))
        await owner.drain(container: container, isCurrent: { true })
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sibling.path).count == 2)
        #expect(try status(container) == .complete)
        #expect(throws: (any Error).self) { try fixture.stage(container) }
        // Completed receipts never cause a later object to be erased.
        try Data([9]).write(to: child.appendingPathComponent("replacement.jpg"))
        await ObservationReanalysisErasureOwner(files: .init(documents: root)).drain(container: container, isCurrent: { true })
        #expect(try Data(contentsOf: child.appendingPathComponent("replacement.jpg")) == Data([9]))
    }

    @Test func retiredOwnerLeavesLegacyReceiptForFreshOwner() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID)
        let owner = ObservationReanalysisErasureOwner(files: .init(documents: root))
        #expect(await owner.retire())
        await owner.erase(expected, container: container, isCurrent: { true })
        await owner.drain(container: container, isCurrent: { true })
        #expect(try status(container) == .pending)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).count == 2)
        let successor = try owner.successor()
        await successor.drain(container: container, isCurrent: { true })
        #expect(try status(container) == .complete)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
    }

    @Test func failedLocalCleanupRetainsReceiptAndLaterOpportunityRetries() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID)
        let unexpected = child.appendingPathComponent("unexpected-directory")
        try FileManager.default.createDirectory(at: unexpected, withIntermediateDirectories: false)
        let owner = ObservationReanalysisErasureOwner(files: .init(documents: root))
        await owner.drain(container: container, isCurrent: { true })
        #expect(try status(container) == .pending)
        try FileManager.default.removeItem(at: unexpected)
        await owner.drain(container: container, isCurrent: { true })
        #expect(try status(container) == .complete)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
    }

    @Test func failedAcknowledgmentAfterErasureRecoversFromEmptyDirectory() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID), files = ObservationReanalysisFileStore(documents: root)
        await #expect(throws: (any Error).self) {
            try await files.erase(child: expected.childID, authorize: {
                try ObservationReanalysisErasurePersistence.validate(expected, container: container, isCurrent: { true })
            }, acknowledge: {
                _ = try ObservationReanalysisErasurePersistence.validate(expected, container: container, isCurrent: { true }, complete: true,
                    save: { _ in throw CocoaError(.fileWriteUnknown) })
            })
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        #expect(try status(container) == .pending)
        await ObservationReanalysisErasureOwner(files: files).drain(container: container, isCurrent: { true })
        #expect(try status(container) == .complete)
    }

    @Test func survivingChildAndChangedContainerNeverAuthorizeErasure() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container)
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID)
        let owner = ObservationReanalysisErasureOwner(files: .init(documents: root))
        await owner.drain(container: container, isCurrent: { false })
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).count == 2)
        let context = ModelContext(container)
        context.insert(OfflineQueuedScan(id: expected.childID.uuidString.lowercased())); try context.save()
        await owner.drain(container: container, isCurrent: { true })
        #expect(try status(container) == .pending)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).count == 2)
    }

    @Test func sharedChildLockAndExclusiveRootLockFenceCleanup() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let childID = UUID(), child = try write(root, child: childID)
        for url in [child, root] {
            let descriptor = open(url.path, O_RDONLY | O_DIRECTORY)
            defer { close(descriptor) }
            #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
            await #expect(throws: ObservationReanalysisFileStore.Failure.busy) {
                try await ObservationReanalysisFileStore(documents: root).erase(child: childID,
                    authorize: { Issue.record("Lock was bypassed"); return true }, acknowledge: {})
            }
            #expect(flock(descriptor, LOCK_UN) == 0)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).count == 2)
    }

    @Test func childSymlinkIsRejectedAndFileSymlinkNeverFollowsDestination() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory(), outside = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("private.jpg"); try Data([8]).write(to: target)
        let childID = UUID(), child = try write(root, child: childID)
        try FileManager.default.createSymbolicLink(at: child.appendingPathComponent("link.jpg"), withDestinationURL: target)
        try await ObservationReanalysisFileStore(documents: root).erase(child: childID, authorize: { true }, acknowledge: {})
        #expect(try Data(contentsOf: target) == Data([8]))
        try FileManager.default.removeItem(at: child)
        try FileManager.default.createSymbolicLink(at: child, withDestinationURL: outside)
        await #expect(throws: (any Error).self) {
            try await ObservationReanalysisFileStore(documents: root).erase(child: childID, authorize: { true }, acknowledge: {})
        }
        #expect(try Data(contentsOf: target) == Data([8]))
    }

    @Test func namespaceReplacementCannotBeAcknowledgedAsClean() async throws {
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let childID = UUID(), child = try write(root, child: childID)
        await #expect(throws: ObservationReanalysisFileStore.Failure.cleanupFailed) {
            try await ObservationReanalysisFileStore(documents: root).erase(child: childID, authorize: {
                try FileManager.default.moveItem(at: child, to: root.appendingPathComponent("detached"))
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
                try Data([9]).write(to: child.appendingPathComponent("replacement.jpg"))
                return true
            }, acknowledge: { Issue.record("Replacement namespace was incorrectly acknowledged") })
        }
        #expect(try Data(contentsOf: child.appendingPathComponent("replacement.jpg")) == Data([9]))
    }

    @Test func malformedFirstPageCannotStarveLaterValidReceipt() async throws {
        let container = try fixture.fixture.container(), expected = try receipt(container), context = ModelContext(container)
        for index in 0..<65 {
            context.insert(OfflineJobRecord(id: String(format: "000-invalid-%03d", index), kind: .observationReanalysisErasure,
                status: .pending, metadataJSON: "invalid"))
        }
        try context.save()
        let root = try ObservationReanalysisFileStoreTests().directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = try write(root, child: expected.childID)
        await ObservationReanalysisErasureOwner(files: .init(documents: root)).drain(container: container, isCurrent: { true })
        #expect(try status(container) == .complete)
        #expect(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OfflineJobRecord>()) == 66)
    }
    /// Persist a real input under original startup authority, then drop only its
    /// runtime lease. This models restart without claiming that storage was erased.
    private func coldInput(_ seed: ObservationReanalysisLocalVideoInputTests.Seed) async throws -> ObservationReanalysisInputReceipt {
        let fence = try seed.startup.acquireFence(container: seed.container)
        let store = ObservationReanalysisFileStore(documents: seed.documents)
        let validate: @MainActor @Sendable () throws -> Void = { try seed.startup.require(container: seed.container, fence: fence) }
        try await store.initializeInputs(readState: {
            try validate(); return try ObservationReanalysisInputPersistence.inspectForFreshPreparation(container: seed.container)
        }, commit: {
            try ObservationReanalysisInputPersistence.initialize($0, container: seed.container, validate: { _ in try validate() })
        }, validate: validate)
        let token = try await store.createInput(.init(ownerID: seed.source.ownerID, parentID: seed.source.observationID,
            childID: UUID(), planDigest: String(repeating: "a", count: 64)), inspect: {
                try validate(); return try ObservationReanalysisInputPersistence.inspect(container: seed.container)
            }, reserve: {
                try ObservationReanalysisInputPersistence.reserve($0, container: seed.container, validate: { _ in try validate() })
            }, advance: {
                try ObservationReanalysisInputPersistence.advance(from: $0, to: $1, container: seed.container, validate: validate)
            }, validate: validate, copy: { descriptor in
                await seed.files.copyVideoInput(filename: "chosen.mp4", ownedOutput: descriptor)
            })
        #expect(await store.releaseInputLease(token))
        return token.receipt
    }

    private func coldOwner(_ seed: ObservationReanalysisLocalVideoInputTests.Seed,
                           isCurrent: @escaping @MainActor () -> Bool = { true }) throws -> (AppDIContainer, ObservationReanalysisErasureOwner) {
        let di = AppDIContainer.preview, owner = ObservationReanalysisErasureOwner(files: .init(documents: seed.documents))
        try di.configureNativeMediaForTesting(container: seed.container, admission: seed.startup)
        try di.configureInputRecoveryForTesting(owner: owner, isCurrent: isCurrent, install: { _ in })
        return (di, owner)
    }

    @Test(arguments: [false, true])
    func productionRecoveryBarrierWorksBeforeStableAuth(deletionPending: Bool) async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let receipt = try await coldInput(seed), context = ModelContext(seed.container)
        try context.delete(model: LocalAnalysisRecord.self); try context.delete(model: LocalScanRecord.self); try context.save()
        let di = AppDIContainer.preview, manager = di.supabaseManager
        let owner = ObservationReanalysisErasureOwner(files: .init(documents: seed.documents))
        let defaults = UserDefaults.standard, key = UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        let prior = defaults.object(forKey: key)
        defer { if let prior { defaults.set(prior, forKey: key) } else { defaults.removeObject(forKey: key) } }
        #expect(manager.currentUser == nil && !manager.isAuthTransitionInProgress)
        defaults.removeObject(forKey: key)
        if deletionPending { defaults.set(AccountDeletionLocalRecoveryState.intakePending.rawValue, forKey: key) }
        di.offlineQueueManager.modelContext = context
        try di.configureNativeMediaForTesting(container: seed.container, admission: seed.startup)
        // No injected predicate/install closure: this is the same local barrier
        // and exact manager hook used by initial setup and lifetime renewal.
        try di.configureInputRecoveryForTesting(owner: owner)
        #expect(di.nativeMediaLifetime == nil)
        await owner.drain(container: seed.container, isCurrent: { true })
        do {
            let state = try ObservationReanalysisInputPersistence.read(child: receipt.childID, container: seed.container)
            #expect(state?.phase == (deletionPending ? receipt.phase : .complete))
            #expect(di.nativeMediaOwner == nil && manager.currentUser == nil)
            #expect((di.nativeMediaLifetime == nil) == deletionPending)
            if deletionPending {
                defaults.removeObject(forKey: key)
                await owner.drain(container: seed.container, isCurrent: { true })
                #expect(try ObservationReanalysisInputPersistence.read(child: receipt.childID, container: seed.container)?.phase == .complete)
            }
        } catch {
            if let lifetime = di.nativeMediaLifetime {
                _ = await lifetime.shutdown(); try? manager.retireNativeMediaAccountTransitionDrain(lifetime)
            }
            throw error
        }
        if let lifetime = di.nativeMediaLifetime {
            #expect(await lifetime.shutdown()); try manager.retireNativeMediaAccountTransitionDrain(lifetime)
        }
        _ = try seed.startup.acquireFence(container: seed.container)
        #expect(throws: SharedMediaStorageFailure.closed) {
            try owner.configureInputRecovery(admission: { _ in throw SharedMediaStorageFailure.closed }, isCurrent: { true })
        }
    }

    @Test func coldInputRecoveryDoesNotNeedFormerAccountOrSourceAndIsRepeatable() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let receipt = try await coldInput(seed), context = ModelContext(seed.container)
        try context.delete(model: LocalAnalysisRecord.self)
        try context.delete(model: LocalScanRecord.self)
        try context.save()
        let (di, owner) = try coldOwner(seed)
        #expect(di.nativeMediaLifetime == nil) // Configuration never opens a fence.
        await owner.drain(container: seed.container, isCurrent: { true })
        #expect(di.nativeMediaOwner == nil) // No native discovery or account/profile adoption.
        #expect(try ObservationReanalysisInputPersistence.read(child: receipt.childID, container: seed.container)?.phase == .complete)
        let path = seed.documents.appendingPathComponent("ReanalysisInputs/\(receipt.slot)/input.mp4")
        #expect(!FileManager.default.fileExists(atPath: path.path))
        await owner.drain(container: seed.container, isCurrent: { true })
        #expect(try ObservationReanalysisInputPersistence.inspect(container: seed.container).ledger.slots.allSatisfy { $0.state != .active })
        #expect(await di.nativeMediaLifetime?.shutdown() == true)
        _ = try seed.startup.acquireFence(container: seed.container)
    }

    @Test(arguments: ["control", "receipt", "admission", "container"])
    func coldInputRecoveryHoldsDamagedOrForeignAuthority(reason: String) async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let receipt = try await coldInput(seed), context = ModelContext(seed.container)
        let path = seed.documents.appendingPathComponent("ReanalysisInputs/\(receipt.slot)/input.mp4"), bytes = try Data(contentsOf: path)
        if reason == "control" || reason == "receipt" {
            let id = reason == "control" ? ObservationReanalysisInputLedger.jobID : receipt.jobID
            let row = try #require(try context.fetchOfflineJob(id: id)); row.metadataJSON = "damaged"; try context.save()
        }
        let (di, owner) = try coldOwner(seed, isCurrent: { reason != "admission" })
        let foreign = try reason == "container" ? ObservationReanalysisLocalVideoInputTests().seed() : nil
        defer { foreign?.remove() }
        let foreignReceipt: ObservationReanalysisInputReceipt?
        if let foreign { foreignReceipt = try await coldInput(foreign) } else { foreignReceipt = nil }
        await owner.drain(container: foreign?.container ?? seed.container, isCurrent: { true })
        #expect(try Data(contentsOf: path) == bytes)
        if let foreign, let foreignReceipt {
            // A populated foreign ledger reaches the original-container admission check.
            #expect(try ObservationReanalysisInputPersistence.read(child: foreignReceipt.childID, container: foreign.container) == foreignReceipt)
            #expect(try Data(contentsOf: foreign.documents.appendingPathComponent("ReanalysisInputs/\(foreignReceipt.slot)/input.mp4")).count == 150_001)
            #expect(di.nativeMediaLifetime == nil)
        }
        if let lifetime = di.nativeMediaLifetime { #expect(await lifetime.shutdown()) }
        _ = try seed.startup.acquireFence(container: seed.container)
    }

    @Test func coldInputRecoveryCannotEraseLiveSlotButLaterOpportunityCan() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let receipt = try await coldInput(seed)
        let live = ObservationReanalysisFileStore(documents: seed.documents)
        let token = try await live.recoverInput(receipt, read: {
            try #require(try ObservationReanalysisInputPersistence.read(child: receipt.childID, container: seed.container))
        })
        let (di, owner) = try coldOwner(seed)
        await owner.drain(container: seed.container, isCurrent: { true })
        #expect(try ObservationReanalysisInputPersistence.read(child: receipt.childID, container: seed.container) == receipt)
        #expect(try Data(contentsOf: token.url).count == 150_001)
        #expect(await live.releaseInputLease(token))
        await owner.drain(container: seed.container, isCurrent: { true })
        #expect(try ObservationReanalysisInputPersistence.read(child: receipt.childID, container: seed.container)?.phase == .complete)
        #expect(await di.nativeMediaLifetime?.shutdown() == true)
    }

    @Test func retirementJoinsActualInputExitAndNeverReopensOldOwner() async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let receipt = try await coldInput(seed), (di, owner) = try coldOwner(seed)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        owner.inputErasureCheckpoint = { await entered.open(); await release.wait() }
        let cleaning = Task { await owner.drain(container: seed.container, isCurrent: { true }) }
        await entered.wait()
        var retired = false
        let closing = Task { retired = await owner.retire() }
        for _ in 0..<10 { await Task.yield() }
        #expect(!retired)
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try owner.successor() }
        await release.open(); await cleaning.value; await closing.value
        #expect(retired)
        let successor = try owner.successor()
        #expect(successor !== owner)
        await owner.drain(container: seed.container, isCurrent: { true })
        #expect(try ObservationReanalysisInputPersistence.read(child: receipt.childID, container: seed.container) == receipt)
        #expect(throws: SharedMediaStorageFailure.closed) {
            try owner.configureInputRecovery(admission: { _ in throw SharedMediaStorageFailure.closed }, isCurrent: { true })
        }
        #expect(await di.nativeMediaLifetime?.shutdown() == true)
    }

    @Test func purgeSuspensionCannotBeRetiredIntoFreshCleanup() async throws {
        let owner = ObservationReanalysisErasureOwner()
        await owner.suspendForLibraryPurge()
        #expect(await owner.retire() == false)
        #expect(throws: SharedMediaStorageFailure.closed) { _ = try owner.successor() }
        owner.resumeAfterLibraryPurge()
        #expect(await owner.retire())
        #expect(try owner.successor() !== owner)
    }

    @Test(arguments: [false, true])
    func inputCleanupJoinsActualExitBeforeLifetimeShutdownOrWholePurge(fullPurge: Bool) async throws {
        let seed = try ObservationReanalysisLocalVideoInputTests().seed(); defer { seed.remove() }
        let receipt = try await coldInput(seed), (di, owner) = try coldOwner(seed)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        owner.inputErasureCheckpoint = { await entered.open(); await release.wait() }
        let cleaning = Task { await owner.drain(container: seed.container, isCurrent: { true }) }
        await entered.wait()
        let lifetime = try #require(di.nativeMediaLifetime)
        var joined = false
        let closing = Task {
            if fullPurge { await owner.suspendForLibraryPurge() } else { #expect(await lifetime.shutdown()) }
            joined = true
        }
        for _ in 0..<10 { await Task.yield() }
        #expect(!joined)
        #expect(throws: (any Error).self) { _ = try seed.startup.acquireFence(container: seed.container) }
        #expect(try ObservationReanalysisInputPersistence.read(child: receipt.childID, container: seed.container) == receipt)
        await release.open()
        await cleaning.value; await closing.value
        #expect(joined)
        #expect(try ObservationReanalysisInputPersistence.read(child: receipt.childID, container: seed.container) == receipt)
        if fullPurge {
            owner.resumeAfterLibraryPurge()
            #expect(await lifetime.shutdown())
        }
        _ = try seed.startup.acquireFence(container: seed.container)
    }

}
