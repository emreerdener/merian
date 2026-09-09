import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Upload Lifecycle Persistence")
struct UploadLifecyclePersistenceTests {
    private func createIsolatedContainer() throws -> ModelContainer {
        try DatabaseActorTestSupport.makeIsolatedContainer()
    }

    // MARK: - markScanAsStaged: source-state guard and R2 key persistence (V33)

    @Test func testMarkScanAsStagedPersistsR2Keys() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("img.webp")]), encoding: .utf8), scanState: .uploading)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let r2Keys = ["staging/user123/\(scanId)_img.webp"]
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let outcome = await actor.markScanAsStaged(
            scanId: scanId,
            r2Keys: r2Keys
        )

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(outcome == .staged)
        #expect(fetched?.scanStateRaw == ScanQueueState.staged.rawValue,
                "markScanAsStaged must transition .uploading → .staged")
        #expect(fetched?.stagedR2Keys == r2Keys,
                "markScanAsStaged must persist R2 keys so inference can use them without auth reconstruction")
    }

    @Test func testMarkScanAsStagedPreservesScheduledServerFailureRetry() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("server-retry.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged,
            stagedR2Keys: ["staging/user/server-retry-consumed.webp"]
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstGeneration = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: firstGeneration
            )
        )
        #expect(
            await actor.scheduleInferenceRetry(
                id: scan.id,
                expectedGeneration: firstGeneration,
                code: OfflineQueueManager.serverRetryableFailureCode,
                message: "Exact server retry is ready.",
                delay: 1,
                resetMediaUploads: true
            ) == 1
        )
        // Simulate a migrated store whose queue-row snapshot lost the marker
        // and counter while the job-row mirror remained durable.
        let driftContext = ModelContext(container)
        let driftedScanId = scan.id
        var driftDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == driftedScanId }
        )
        driftDescriptor.fetchLimit = 1
        let driftedScan = try #require(
            driftContext.fetch(driftDescriptor).first
        )
        let driftedJobId =
            OfflineQueueManager.scanIngestionJobId(scanId: driftedScanId)
        var driftedJobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == driftedJobId }
        )
        driftedJobDescriptor.fetchLimit = 1
        let driftedJob = try #require(
            driftContext.fetch(driftedJobDescriptor).first
        )
        driftedScan.queueLastErrorCode = nil
        driftedScan.queueAttemptCount = 0
        // Advance the fixture to the scheduled wake. The transition under test
        // is preservation of the surviving retry marker during re-upload, not
        // an attempt to bypass durable backoff.
        let scheduledWake = Date().addingTimeInterval(-1)
        driftedScan.queueNextRetryAt = scheduledWake
        driftedJob.nextRunAt = scheduledWake
        try driftContext.save()

        let stagingActor =
            BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await stagingActor.markScansAsUploading(scanIds: [scan.id]) ==
                Set([scan.id])
        )
        let outcome = await stagingActor.markScanAsStaged(
            scanId: scan.id,
            r2Keys: ["staging/user/\(scan.id)_server-retry.webp"]
        )

        let verificationContext = ModelContext(container)
        let scanId = scan.id
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let persistedScan = try #require(
            verificationContext.fetch(scanDescriptor).first
        )
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let persistedJob = try #require(
            verificationContext.fetch(jobDescriptor).first
        )

        #expect(outcome == .staged)
        #expect(persistedScan.queueState == .staged)
        #expect(persistedScan.queueAttemptCount == 1)
        #expect(
            persistedScan.queueLastErrorCode
                == OfflineQueueManager.serverRetryableFailureCode
        )
        #expect(persistedScan.queueNextRetryAt == nil)
        #expect(persistedJob.attemptCount == 1)
        #expect(
            persistedJob.lastErrorCode
                == OfflineQueueManager.serverRetryableFailureCode
        )
    }

    @Test func testMarkScanAsStagedDoesNotResurrectTombstone() async throws {
        // Prevents a late-arriving HTTP 200 for a partially-uploaded scan from
        // resurrecting it into the inference pipeline after it was tombstoned.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("dead.webp")]), encoding: .utf8), scanState: .failed)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let outcome = await actor.markScanAsStaged(
            scanId: scanId,
            r2Keys: ["staging/user/\(scanId)_dead.webp"]
        )

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(outcome == .discarded)
        #expect(fetched?.scanStateRaw == ScanQueueState.failed.rawValue,
                "markScanAsStaged must not resurrect .failed tombstones")
        #expect(fetched?.stagedR2Keys == nil,
                "R2 keys must not be written to a tombstoned scan")
    }

    @Test func testMarkScanAsStagedIsNoOpFromPending() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("pending.webp")]), encoding: .utf8), scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let outcome = await actor.markScanAsStaged(
            scanId: scanId,
            r2Keys: ["staging/user/\(scanId)_pending.webp"]
        )

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(outcome == .retryRequired)
        #expect(fetched?.scanStateRaw == ScanQueueState.pending.rawValue,
                "markScanAsStaged must be a no-op for non-.uploading scans — prevents skipping the upload state")
        #expect(fetched?.stagedR2Keys == nil)
    }

    @Test func testMarkScanAsStagedReportsSerializedAdvance() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("advanced.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        let r2Keys = ["staging/user/\(scan.id)_advanced.webp"]
        scan.stagedR2Keys = r2Keys
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let outcome = await actor.markScanAsStaged(
            scanId: scan.id,
            r2Keys: r2Keys
        )

        #expect(outcome == .alreadyAdvanced)
    }

    @Test func testMarkScanAsStagedRejectsMismatchedAdvancedManifest() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("persisted.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        let scanId = scan.id
        let persistedKeys = ["staging/user/\(scanId)_persisted.webp"]
        scan.stagedR2Keys = persistedKeys
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let outcome = await actor.markScanAsStaged(
            scanId: scanId,
            r2Keys: ["staging/user/\(scanId)_stale-callback.webp"]
        )

        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        #expect(outcome == .retryRequired)
        #expect(try context.fetch(descriptor).first?.stagedR2Keys == persistedKeys)
    }

    // MARK: - markScansAsUploading: source-state guard (V33)

    @Test func testMarkScansAsUploadingOnlyTransitionsPendingScans() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let pending    = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("p.webp")]), encoding: .utf8), scanState: .pending)
        let uploading  = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("u.webp")]), encoding: .utf8), scanState: .uploading)
        let staged     = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("s.webp")]), encoding: .utf8), scanState: .staged)
        let failed     = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("f.webp")]), encoding: .utf8), scanState: .failed)

        for scan in [pending, uploading, staged, failed] { context.insert(scan) }
        try context.save()

        // Pass all four IDs — only the .pending one must advance.
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimedIds = await actor.markScansAsUploading(scanIds: [pending.id, uploading.id, staged.id, failed.id])
        #expect(claimedIds == Set([pending.id]), "only pending scans should be claimed for upload dispatch")

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })

        #expect(byId[pending.id]   == ScanQueueState.uploading.rawValue, ".pending must advance to .uploading")
        #expect(byId[uploading.id] == ScanQueueState.uploading.rawValue, "already-.uploading must stay .uploading")
        #expect(byId[staged.id]    == ScanQueueState.staged.rawValue, ".staged must not be regressed")
        #expect(byId[failed.id]    == ScanQueueState.failed.rawValue, ".failed tombstone must not be touched")
    }

    @Test func testReconcileOrphanedUploadingScansResetsOrphansKeepsActive() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let orphan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("orphan.webp")]), encoding: .utf8), scanState: .uploading)
        let active = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("active.webp")]), encoding: .utf8), scanState: .uploading)
        let pending = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("pending.webp")]), encoding: .utf8), scanState: .pending)
        let orphanJob = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: orphan.id),
            kind: .scanIngestion,
            subjectId: orphan.id,
            status: .running
        )
        let activeJob = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: active.id),
            kind: .scanIngestion,
            subjectId: active.id,
            status: .running
        )

        for scan in [orphan, active, pending] { context.insert(scan) }
        context.insert(orphanJob)
        context.insert(activeJob)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        // Only `active` has a live URLSession task.
        let hadOrphans = await actor.reconcileOrphanedUploadingScans(
            activeScanIds: Set([active.id])
        )

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })

        #expect(byId[orphan.id]  == ScanQueueState.pending.rawValue, "orphaned .uploading scan must reset to .pending")
        #expect(byId[active.id]  == ScanQueueState.uploading.rawValue, ".uploading scan with active task must stay .uploading")
        #expect(byId[pending.id] == ScanQueueState.pending.rawValue, ".pending scan must be unaffected")
        #expect(hadOrphans, "callers must be told to restart signing after a reset")

        let jobReadContext = ModelContext(container)
        let jobs = try jobReadContext.fetch(
            FetchDescriptor<OfflineJobRecord>()
        )
        let jobStatusById = Dictionary(uniqueKeysWithValues: jobs.map {
            ($0.id, $0.status)
        })
        #expect(
            jobStatusById[orphanJob.id] == .pending,
            "orphan recovery must atomically release the durable running job"
        )
        #expect(
            jobStatusById[activeJob.id] == .running,
            "a live task must retain its durable running job"
        )
    }

    @Test func testReconcileOrphanedUploadingScansWithEmptyActiveSet() async throws {
        // Process died mid-dispatch — no URLSession tasks survived. All .uploading → .pending.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan1 = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("a.webp")]), encoding: .utf8), scanState: .uploading)
        let scan2 = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("b.webp")]), encoding: .utf8), scanState: .uploading)

        context.insert(scan1)
        context.insert(scan2)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let hadOrphans = await actor.reconcileOrphanedUploadingScans(
            activeScanIds: Set()
        )

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        for scan in all {
            #expect(scan.scanStateRaw == ScanQueueState.pending.rawValue,
                    "all .uploading scans must be reset when no active tasks exist")
        }
        #expect(hadOrphans)
    }

    @Test func testUploadReconciliationDoesNotResetWorkNewerThanSnapshot() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let observedThrough = Date()
        let oldScan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([SerializedMediaItem.image("old.webp")]),
                encoding: .utf8
            ),
            scanState: .uploading,
            queueUpdatedAt: observedThrough.addingTimeInterval(-10)
        )
        let replacementScan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([SerializedMediaItem.image("replacement.webp")]),
                encoding: .utf8
            ),
            scanState: .uploading,
            queueUpdatedAt: observedThrough.addingTimeInterval(10)
        )
        let unrelatedScan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([SerializedMediaItem.image("unrelated.webp")]),
                encoding: .utf8
            ),
            scanState: .uploading,
            queueUpdatedAt: observedThrough.addingTimeInterval(-10)
        )
        context.insert(oldScan)
        context.insert(replacementScan)
        context.insert(unrelatedScan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.reconcileOrphanedUploadingScans(
            activeScanIds: [],
            candidateScanIds: Set([oldScan.id, replacementScan.id]),
            observedThrough: observedThrough
        )

        let all = try context.fetch(FetchDescriptor<OfflineQueuedScan>())
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })
        #expect(byId[oldScan.id] == ScanQueueState.pending.rawValue)
        #expect(byId[replacementScan.id] == ScanQueueState.uploading.rawValue)
        #expect(
            byId[unrelatedScan.id] == ScanQueueState.uploading.rawValue,
            "an exact post-claim release must not reset unrelated work"
        )
    }
}
