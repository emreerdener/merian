import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Inference Lifecycle Persistence")
struct InferenceLifecyclePersistenceTests {
    private func createIsolatedContainer() throws -> ModelContainer {
        try DatabaseActorTestSupport.makeIsolatedContainer()
    }

    // MARK: - tryClaimForInference: distributed lock (V33)

    @Test func testTryClaimForInferenceSucceedsOnStagedScan() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        // A persisted deadline may remain on a staged row after a relaunch, but
        // only an elapsed deadline is runnable. Future deadlines are covered by
        // pausedScansCannotBeClaimedOrReconciled().
        let retryAt = Date().addingTimeInterval(-600)
        let generation = UUID()
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("claim.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged,
            queueNextRetryAt: retryAt
        )
        context.insert(scan)
        context.insert(OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
            kind: .scanIngestion,
            subjectId: scan.id,
            status: .waiting,
            nextRunAt: retryAt
        ))
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(
            scanId: scanId,
            generation: generation
        )

        #expect(
            claimed == true,
            "tryClaimForInference must claim an eligible .staged scan after its retry deadline"
        )
        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let fetched = try verificationContext.fetch(descriptor).first
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        var jobDescriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        jobDescriptor.fetchLimit = 1
        let fetchedJob = try verificationContext.fetch(jobDescriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.inferencing.rawValue,
                "scan must be .inferencing after a successful claim")
        #expect(fetched?.queueNextRetryAt == nil,
                "an active inference claim must clear its scheduled-retry label")
        #expect(fetchedJob?.status == .running)
        #expect(fetchedJob?.nextRunAt == nil)
        #expect(
            fetchedJob?.metadataJSON ==
                InferenceGenerationMetadataContract.json(for: generation)
        )
    }

    @Test func testTryClaimForInferenceFailsWhenAlreadyInferencing() async throws {
        // Guards the double-pipeline race: if replayInferenceForUploadedScans and
        // processUploadCompletion both see the scan in .staged and race to claim it,
        // only one can win. The second call must return false.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("already.webp")]), encoding: .utf8), scanState: .inferencing)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(claimed == false, "tryClaimForInference must return false when scan is already .inferencing")
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.inferencing.rawValue,
                "state must remain .inferencing — not regressed by a failed claim")
    }

    @Test func testTryClaimForInferenceFailsWhenPending() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("pending.webp")]), encoding: .utf8), scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(claimed == false, "tryClaimForInference must return false for non-.staged scans")
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.pending.rawValue,
                "state must remain .pending after a failed claim")
    }

    @Test func testTryClaimForInferenceRejectsUnsupportedQueuedAudio() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: MediaJSONParser.jsonString(from: [
                .audio(.documents("unsupported-recording.m4a"))
            ]),
            scanState: .staged,
            stagedR2Keys: [
                "staging/owner/unsupported-recording.m4a"
            ]
        )
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(!claimed)
        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.queueState == .staged)
        #expect(persisted.stagedR2Keys == [
            "staging/owner/unsupported-recording.m4a"
        ])
    }

    @Test func testTryClaimForInferenceDoesNotResurrectTombstone() async throws {
        // A .failed tombstone must never enter the inference pipeline.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("dead.webp")]), encoding: .utf8), scanState: .failed)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let claimed = await actor.tryClaimForInference(scanId: scanId)

        #expect(claimed == false, "tryClaimForInference must not resurrect a tombstoned scan")
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.failed.rawValue,
                "tombstoned scan must remain .failed after a claim attempt")
    }

    @Test func testTryClaimForInferenceSecondCallReturnsFalse() async throws {
        // Simulate processUploadCompletion winning the claim, then replayInference trying again.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("race.webp")]), encoding: .utf8), scanState: .staged)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstClaim  = await actor.tryClaimForInference(scanId: scanId)
        let secondClaim = await actor.tryClaimForInference(scanId: scanId)

        #expect(firstClaim == true, "First claim on a .staged scan must succeed")
        #expect(secondClaim == false, "Second claim on the same scan must fail — pipeline already in progress")
    }

    @Test func testTryClaimForInferenceCreatesMissingLegacyJob() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let generation = UUID()
        let scan = OfflineQueuedScan(
            capturedMediaJSON: MediaJSONParser.jsonString(from: [
                .image(.documents("legacy-claim.webp"))
            ]),
            scanState: .staged
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: generation
            )
        )

        let verificationContext = ModelContext(container)
        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scan.id)
        let persistedJob = try verificationContext.fetchOfflineJob(id: jobId)
        let job = try #require(persistedJob)
        #expect(job.subjectId == scan.id)
        #expect(job.status == .running)
        #expect(
            InferenceGenerationMetadataContract.matches(
                generation,
                in: job.metadataJSON
            )
        )
    }

    @Test func cancelledClaimReleasesPersistenceFence() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: MediaJSONParser.jsonString(from: [
                .image(.documents("cancelled-claim.webp"))
            ]),
            scanState: .staged
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let cancelledClaim = await Task { () -> Bool in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return await actor.tryClaimForInference(scanId: scan.id)
        }.value

        #expect(!cancelledClaim)
        #expect(
            await actor.tryClaimForInference(scanId: scan.id),
            "A cancelled waiter must release the per-scan persistence fence"
        )
    }

    // MARK: - transitionScanToStaged: tombstone resurrection guard (V33)

    @Test func testTransitionScanToStagedSucceedsFromInferencing() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("retry.webp")]), encoding: .utf8), scanState: .inferencing)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.transitionScanToStaged(id: scanId)

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.staged.rawValue,
                "transitionScanToStaged must retreat .inferencing → .staged on transient failure")
    }

    @Test func testTransitionScanToStagedRejectsOlderPersistedGeneration() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("generation-race.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .staged
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let firstGeneration = UUID()
        let secondGeneration = UUID()
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: firstGeneration
            )
        )
        #expect(
            await actor.transitionScanToStaged(
                id: scan.id,
                expectedGeneration: firstGeneration
            )
        )
        #expect(
            await actor.tryClaimForInference(
                scanId: scan.id,
                generation: secondGeneration
            )
        )

        let staleTransition = await actor.transitionScanToStaged(
            id: scan.id,
            expectedGeneration: firstGeneration
        )
        #expect(staleTransition == false)

        let verificationContext = ModelContext(container)
        let expectedScanId = scan.id
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == expectedScanId }
        )
        descriptor.fetchLimit = 1
        #expect(
            try verificationContext.fetch(descriptor).first?.scanStateRaw ==
                ScanQueueState.inferencing.rawValue
        )
    }

    @Test func absentQueueRequiresExactCompletedGenerationForInferenceDeletion() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "guarded-completion-replay-\(UUID().uuidString)"
        let generation = UUID()
        let otherGeneration = UUID()
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scanId),
            kind: .scanIngestion,
            subjectId: scanId,
            status: .running,
            metadataJSON:
                InferenceGenerationMetadataContract.json(for: generation)
        )
        context.insert(job)
        try context.save()

        func durableGenerationIsCurrent() async -> Bool {
            await ScanInferencePersistenceCoordinator.shared.acquire(
                scanId: scanId
            )
            let actor = BackgroundDatabaseActor(modelContainer: container)
            let isCurrent =
                await actor
                    .inferenceGenerationIsCurrentAssumingPersistenceLock(
                        scanId: scanId,
                        expectedGeneration: generation
                    )
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: scanId
            )
            return isCurrent
        }

        #expect(!(await durableGenerationIsCurrent()))

        job.status = .complete
        job.metadataJSON =
            InferenceGenerationMetadataContract.json(for: otherGeneration)
        try context.save()
        #expect(!(await durableGenerationIsCurrent()))

        job.metadataJSON =
            InferenceGenerationMetadataContract.json(for: generation)
        try context.save()
        #expect(await durableGenerationIsCurrent())
    }

    @Test func testTransitionScanToStagedDoesNotResurrectTombstone() async throws {
        // The critical guard: a MainActor softDeleteQueuedScan wins the race and sets .failed.
        // The background actor must not overwrite it when its transitionScanToStaged runs later.
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("tombstoned.webp")]), encoding: .utf8), scanState: .failed)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.transitionScanToStaged(id: scanId)

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.failed.rawValue,
                "transitionScanToStaged must not overwrite a .failed tombstone — last-writer-wins guard")
    }

    @Test func testTransitionScanToStagedIsNoOpFromPending() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let scan = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("pending.webp")]), encoding: .utf8), scanState: .pending)
        context.insert(scan)
        try context.save()
        let scanId = scan.id

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.transitionScanToStaged(id: scanId)

        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.scanStateRaw == ScanQueueState.pending.rawValue,
                "transitionScanToStaged must be a no-op for non-.inferencing scans")
    }

    // MARK: - reconcileOrphanedInferencingScans

    @Test func testReconcileOrphanedInferencingScansResetsAllToStaged() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)

        let inf1   = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("i1.webp")]), encoding: .utf8), scanState: .inferencing)
        let inf2   = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("i2.webp")]), encoding: .utf8), scanState: .inferencing)
        let staged = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("s.webp")]), encoding: .utf8), scanState: .staged)
        let failed = OfflineQueuedScan(capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("f.webp")]), encoding: .utf8), scanState: .failed)
        let inferenceJob1 = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: inf1.id),
            kind: .scanIngestion,
            subjectId: inf1.id,
            status: .running
        )
        let inferenceJob2 = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: inf2.id),
            kind: .scanIngestion,
            subjectId: inf2.id,
            status: .running
        )

        for scan in [inf1, inf2, staged, failed] { context.insert(scan) }
        context.insert(inferenceJob1)
        context.insert(inferenceJob2)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.reconcileOrphanedInferencingScans(activeInferenceScanIds: [])

        let allDescriptor = FetchDescriptor<OfflineQueuedScan>()
        let all = try context.fetch(allDescriptor)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })

        #expect(byId[inf1.id]   == ScanQueueState.staged.rawValue, ".inferencing must reset to .staged")
        #expect(byId[inf2.id]   == ScanQueueState.staged.rawValue, "all .inferencing scans must reset")
        #expect(byId[staged.id] == ScanQueueState.staged.rawValue, ".staged must be unaffected")
        #expect(byId[failed.id] == ScanQueueState.failed.rawValue, ".failed tombstone must be unaffected")

        let jobReadContext = ModelContext(container)
        let jobs = try jobReadContext.fetch(
            FetchDescriptor<OfflineJobRecord>()
        )
        let jobStatusById = Dictionary(uniqueKeysWithValues: jobs.map {
            ($0.id, $0.status)
        })
        #expect(jobStatusById[inferenceJob1.id] == .pending)
        #expect(jobStatusById[inferenceJob2.id] == .pending)
    }

    @Test func testInferenceReconciliationDoesNotResetWorkNewerThanSnapshot() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let observedThrough = Date()
        let oldScan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([SerializedMediaItem.image("old-inference.webp")]),
                encoding: .utf8
            ),
            scanState: .inferencing,
            queueUpdatedAt: observedThrough.addingTimeInterval(-10)
        )
        let replacementScan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([SerializedMediaItem.image("replacement-inference.webp")]),
                encoding: .utf8
            ),
            scanState: .inferencing,
            queueUpdatedAt: observedThrough.addingTimeInterval(10)
        )
        context.insert(oldScan)
        context.insert(replacementScan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.reconcileOrphanedInferencingScans(
            activeInferenceScanIds: [],
            observedThrough: observedThrough
        )

        let all = try context.fetch(FetchDescriptor<OfflineQueuedScan>())
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.scanStateRaw) })
        #expect(byId[oldScan.id] == ScanQueueState.staged.rawValue)
        #expect(byId[replacementScan.id] == ScanQueueState.inferencing.rawValue)
    }

    @Test func reconciliationRevalidatesAfterPersistenceFenceWait() async throws {
        let container = try createIsolatedContainer()
        let context = ModelContext(container)
        let scan = OfflineQueuedScan(
            capturedMediaJSON: try! String(
                data: JSONEncoder().encode([
                    SerializedMediaItem.image("fenced-orphan.webp")
                ]),
                encoding: .utf8
            ),
            scanState: .inferencing,
            queueUpdatedAt: Date().addingTimeInterval(-60)
        )
        let job = OfflineJobRecord(
            id: OfflineQueueManager.scanIngestionJobId(scanId: scan.id),
            kind: .scanIngestion,
            subjectId: scan.id,
            status: .running
        )
        context.insert(scan)
        context.insert(job)
        try context.save()

        let scanId = scan.id
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        let actor = BackgroundDatabaseActor(modelContainer: container)
        let reconciliation = Task {
            await actor.reconcileOrphanedInferencingScans(
                activeInferenceScanIds: []
            )
        }
        do {
            // Give reconciliation time to select the row and wait on the fence.
            try await Task.sleep(for: .milliseconds(50))
            scan.scanStateRaw = ScanQueueState.failed.rawValue
            scan.queueNeedsAttention = true
            scan.queueLastErrorCode = "newer_terminal_owner"
            scan.queueUpdatedAt = Date()
            job.status = .needsAttention
            try context.save()
        } catch {
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: scanId
            )
            reconciliation.cancel()
            throw error
        }
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        await reconciliation.value

        let verificationContext = ModelContext(container)
        let persistedScan = try verificationContext.fetch(
            FetchDescriptor<OfflineQueuedScan>()
        ).first { $0.id == scanId }
        let persistedJob = try verificationContext.fetch(
            FetchDescriptor<OfflineJobRecord>()
        ).first { $0.id == job.id }
        let retryEvents = try verificationContext.fetch(
            FetchDescriptor<OfflineQueueEvent>()
        ).filter {
            $0.scanId == scanId && $0.kind == .retryScheduled
        }
        #expect(persistedScan?.scanStateRaw == ScanQueueState.failed.rawValue)
        #expect(persistedScan?.queueLastErrorCode == "newer_terminal_owner")
        #expect(persistedJob?.status == .needsAttention)
        #expect(retryEvents.isEmpty)
    }

}
