import Foundation
import SwiftData
import Testing
@testable import Merian

private actor PhotoPreparationCallbackGate {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func hold() async {
        entered = true
        entryWaiter?.resume(); entryWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

@Suite("P1 disk and lifecycle", .serialized)
@MainActor
struct PhotoPreparationPersistenceTests {
    @Test func committedFileBeforeLedgerSaveRetainsSameIntentUntilCleanup() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let intent = PhotoPreparationIntent(leaseID: UUID(), ownerID: h.ownerID, packageID: UUID(),
            assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), draftGeneration: UUID(), processEpoch: UUID(),
            role: .original, ordinal: 0, acquisitionKind: "picker", maximumBytes: PhotoPreparationPolicy.original)
        try await owner.files.locked { files in
            try await owner.repository.reserve(intent)
            _ = try files.write(bytes, intent: intent)
            // Simulate process loss after durable rename, before the ledger ACK.
        }
        let resumed = try h.owner()
        let draft = try #require(try await resumed.recover().first)
        #expect(draft.packageID == intent.packageID && draft.needsAttention)
        let lease = try #require(ModelContext(h.container).fetch(FetchDescriptor<PhotoPreparationLease>()).first)
        #expect(lease.id == intent.leaseID && lease.reservedByteCount == PhotoPreparationPolicy.original)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 0)
        #expect(FileManager.default.fileExists(atPath: h.root.appendingPathComponent("PhotoPreparation").appendingPathComponent(intent.fileToken).path))
        try await resumed.discard(packageID: draft.packageID, revision: draft.revision)
        #expect(try !PhotoPreparationRepository.hasLiabilities(in: ModelContext(h.container)))
    }

    @Test func renamedRootCannotAcknowledgePreparationAgainstReplacement() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let handle = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
            sourceKind: "picker", load: { bytes })
        let root = h.root, moved = h.root.appendingPathExtension("retained")
        // Retain the renamed synthetic store while SQLite descriptors may remain open.
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.prepare(handle) { _ in
                try FileManager.default.moveItem(at: root, to: moved)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                return true
            }
        }
        #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("PhotoPreparation").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("PhotoPreparation").path))
    }

    @Test func secondOwnerCannotAllocateAndAuthDrainWaitsForCallbackTermination() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let first = try h.owner(), second = try h.owner(), gate = PhotoPreparationCallbackGate()
        let bytes = PhotoPreparationTestHarness.image()
        let acquisition = Task {
            try await first.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
                sourceKind: "picker", load: { await gate.hold(); return bytes })
        }
        await gate.waitForEntry()
        await #expect(throws: PhotoPreparationFailure.self) {
            try await second.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
                sourceKind: "picker", load: { Issue.record("Competing callback was reached"); return bytes })
        }
        var drained = false
        let transition = Task { drained = await first.invalidateAndAwaitForAccountTransition() }
        await Task.yield()
        #expect(!drained)
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 1)
        await gate.release()
        _ = await acquisition.result
        await transition.value
        #expect(drained)
        await h.runtime.awaitAccountWorkDrain()
        #expect(try await second.recover().first?.needsAttention == true)
    }

    @Test func committedInboxCopyStaysChargedUntilSourceReleaseIsConfirmed() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let sourceID = UUID().uuidString
        let handle = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
            sourceKind: "inbox", sourceByteLiability: PhotoPreparationPolicy.original, sourceIdentity: sourceID, load: { bytes })
        let sourceLease = try #require(ModelContext(h.container).fetch(FetchDescriptor<PhotoPreparationLease>()).first)
        #expect(sourceLease.writerStateRaw == "closedSourceRetained")
        #expect(sourceLease.allocatedByteCount == PhotoPreparationPolicy.original)
        #expect(sourceLease.reservedByteCount == 0)
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.releaseSource(handle, identity: "wrong-source") { Issue.record("Invalid identity reached destructive callback") }
        }
        let retained = try #require(try await owner.recover().first)
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.discard(packageID: handle.packageID, revision: retained.revision)
        }
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.remove(handle)
        }
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.releaseSource(handle, identity: sourceID) { throw PhotoPreparationFailure.cleanupPending }
        }
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 1)
        #expect(try await h.owner().recover().first?.needsAttention == true)
        try await owner.releaseSource(handle, identity: sourceID) {}
        #expect(try ModelContext(h.container).fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
        #expect(try await owner.originalData(handle) == bytes)
    }

    @Test func purgeWaitsForOwnershipAndRemovesNamespaceBeforeRows() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0,
            sourceKind: "picker", load: { bytes })
        #expect(try PhotoPreparationRepository.hasLiabilities(in: ModelContext(h.container)))
        try await owner.purge()
        #expect(try !PhotoPreparationRepository.hasLiabilities(in: ModelContext(h.container)))
        #expect(!FileManager.default.fileExists(atPath: h.root.appendingPathComponent("PhotoPreparation").path))
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, sourceKind: "picker", load: { bytes })
        }
    }

    @Test func symlinkedNamespaceNeverAdmitsOrDeletesTarget() async throws {
        let h = try PhotoPreparationTestHarness(); defer { h.cleanup() }
        let outside = h.root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: h.root.appendingPathComponent("PhotoPreparation"), withDestinationURL: outside)
        let owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        await #expect(throws: PhotoPreparationFailure.self) {
            try await owner.acquire(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, sourceKind: "picker", load: { bytes })
        }
        #expect(try !PhotoPreparationRepository.hasLiabilities(in: ModelContext(h.container)))
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func diskV58MigrationRetainsQueueHistoryAndStartsEmptyOwnership() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nco1-migration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Retain the synthetic migration store; do not unlink live SQLite files.
        let url = root.appendingPathComponent("ledger.store")
        let owner = UUID(uuidString: "00000000-0000-4000-8000-00000000c002")!
        let observation = UUID(), analysis = UUID(), child = UUID()
        let bytes = Data("{ \"synthetic\": true }".utf8)
        do {
            let schema = Schema(versionedSchema: MerianSchemaV58.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let scan = MerianSchemaV58.LocalScanRecord(id: observation.uuidString, speciesId: "synthetic", scientificName: "Fixture", commonName: "Fixture")
            let result = try MerianSchemaV58.LocalAnalysisRecord(analysisID: analysis, observationID: observation.uuidString,
                ownerAccountID: owner, completedAt: nil, snapshotVersion: 3, resultSnapshotData: bytes)
            scan.analysisRecords = [result]
            context.insert(scan)
            let queue = MerianSchemaV58.OfflineQueuedScan(id: child.uuidString, scanState: .staged, stagedR2Keys: ["synthetic/key"])
            queue.workKindRaw = "reanalysis"; queue.parentObservationID = observation.uuidString
            queue.sourceAnalysisID = analysis.uuidString; queue.reanalysisOwnerAccountID = owner.uuidString
            context.insert(queue)
            try context.save()
        }
        #expect(ModelStoreRecoveryCoordinator.migrationDecision(at: url, currentSchemaMajor: 59).hint == .recentSource(.v58))
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let migrated = try ModelContainer(for: schema, migrationPlan: MerianRecentV58MigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let context = ModelContext(migrated)
        #expect(try !PhotoPreparationRepository.hasLiabilities(in: context))
        let result = try #require(context.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        #expect(result.resultSnapshotData == bytes)
        let queue = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        #expect(queue.workKindRaw == "reanalysis" && queue.id == child.uuidString)
        #expect(queue.sourceAnalysisID == analysis.uuidString && queue.parentObservationID == observation.uuidString)
        #expect(queue.reanalysisOwnerAccountID == owner.uuidString && queue.stagedR2Keys == ["synthetic/key"])
        #expect(!queue.permitsOrdinaryInference)
    }
}
