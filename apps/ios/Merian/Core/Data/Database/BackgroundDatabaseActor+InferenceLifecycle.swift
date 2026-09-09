import Foundation
import SwiftData

extension BackgroundDatabaseActor {
    // MARK: - Inference Lifecycle

    /// Returns inferencing rows that still permit automatic server ownership
    /// reconciliation. Reading through the queue actor keeps a main-context
    /// cached fault from bypassing a background-committed attention fence.
    func fetchServerOwnedInferencingScanIds(
        excludingScanIds: Set<String>,
        observedThrough: Date
    ) -> [String] {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.scanStateRaw == inferencingRaw
                    && !$0.queueNeedsAttention
            },
            sortBy: [
                SortDescriptor(\OfflineQueuedScan.timestamp),
                SortDescriptor(\OfflineQueuedScan.id)
            ]
        )
        do {
            return try modelContext.fetch(descriptor)
                .filter {
                    $0.queueUpdatedAt <= observedThrough
                        && !excludingScanIds.contains($0.id)
                }
                .map(\.id)
        } catch {
            MerianLog.data.error(
                "fetchServerOwnedInferencingScanIds: durable eligibility read failed error=\(error, privacy: .private)"
            )
            return []
        }
    }

    /// Atomically transitions a scan from `.staged` to `.inferencing`.
    ///
    /// Returns `true` if the claim succeeded (the scan was runnable in `.staged`
    /// state and is now `.inferencing`). Returns `false` if it was paused,
    /// delayed, already `.inferencing`, or not found — caller must skip.
    ///
    /// The shared persistence coordinator prevents two actor instances from
    /// winning the same `.staged → .inferencing` fetch-and-save window.
    func tryClaimForInference(
        scanId: String,
        generation: UUID? = nil
    ) async -> Bool {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        guard !Task.isCancelled else {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return false
        }
        let didClaim = tryClaimForInferenceLocked(
            scanId: scanId,
            generation: generation
        )
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        return didClaim
    }

    private func tryClaimForInferenceLocked(
        scanId: String,
        generation: UUID?
    ) -> Bool {
        let stagedRaw = ScanQueueState.staged.rawValue
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let scan: OfflineQueuedScan
        do {
            guard let persistedScan = try modelContext.fetch(descriptor).first else {
                MerianLog.data.debug(
                    "tryClaimForInference: scan missing scanId=\(scanId, privacy: .public)"
                )
                return false
            }
            scan = persistedScan
        } catch {
            MerianLog.data.error(
                "tryClaimForInference: scan lookup failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return false
        }
        guard scan.scanStateRaw == stagedRaw else {
            MerianLog.data.debug(
                "tryClaimForInference: state mismatch scanId=\(scanId, privacy: .public) state=\(scan.scanStateRaw, privacy: .public)"
            )
            return false
        }
        let now = Date()
        guard !scan.queueNeedsAttention,
              scan.queueNextRetryAt.map({ $0 <= now }) ?? true else {
            MerianLog.data.debug(
                "tryClaimForInference: scan is paused scanId=\(scanId, privacy: .public)"
            )
            return false
        }
        guard !QueuedInferenceMediaPolicy.containsUnsupportedAudio(
            in: scan.capturedMediaSnapshot
        ) else {
            // Normal replay quarantines this impossible-by-current-admission
            // state. Keep the serialized claim as the final authority so a
            // future or resumed path cannot dispatch non-WAV queue audio.
            MerianLog.data.error(
                "tryClaimForInference: refused unsupported queued audio scanId=\(scanId, privacy: .private)"
            )
            return false
        }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let existingJob: OfflineJobRecord?
        do {
            existingJob = try modelContext.fetchOfflineJob(id: jobId)
        } catch {
            MerianLog.data.error(
                "tryClaimForInference: job lookup failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return false
        }
        let job = existingJob ?? {
            let created = OfflineJobRecord(
                id: jobId,
                kind: .scanIngestion,
                subjectId: scanId,
                status: .running
            )
            modelContext.insert(created)
            return created
        }()

        scan.scanStateRaw = inferencingRaw
        scan.queueLastAttemptAt = now
        scan.queueNextRetryAt = nil
        scan.queueUpdatedAt = now
        reconcileMirroredInferenceState(scan: scan, job: job)
        if let generation {
            job.metadataJSON = InferenceGenerationMetadataContract.setting(
                generation,
                in: job.metadataJSON
            )
        }
        job.status = .running
        job.updatedAt = now
        job.lastAttemptAt = now
        job.nextRunAt = nil
        modelContext.insert(OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .inferenceStarted,
            message: "Queued scan claimed for inference."
        ))
        do {
            try modelContext.save()
            MerianLog.data.debug(
                "tryClaimForInference: claimed scanId=\(scanId, privacy: .public)"
            )
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "tryClaimForInference: save failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        return true
    }

    /// Transitions a scan back to `.staged` from `.inferencing` and persists.
    ///
    /// **Only valid for the transient-error retry path** (`handleInferenceRetry` transient catch).
    /// Guarded to `.inferencing` as source state so a concurrent `softDeleteQueuedScan` on
    /// the MainActor that already tombstoned the scan to `.failed` cannot be overwritten —
    /// the last-writer-wins nature of two separate `ModelContext`s would otherwise resurrect
    /// a tombstoned scan back into the inference replay queue.
    @discardableResult
    func transitionScanToStaged(
        id scanId: String,
        expectedGeneration: UUID? = nil
    ) async -> Bool {
        await ScanInferencePersistenceCoordinator.shared.acquire(scanId: scanId)
        guard !Task.isCancelled else {
            await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
            return false
        }
        let didTransition = transitionScanToStagedLocked(
            id: scanId,
            expectedGeneration: expectedGeneration
        )
        await ScanInferencePersistenceCoordinator.shared.release(scanId: scanId)
        return didTransition
    }

    private func transitionScanToStagedLocked(
        id scanId: String,
        expectedGeneration: UUID?
    ) -> Bool {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        let stagedRaw = ScanQueueState.staged.rawValue
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let scan: OfflineQueuedScan
        do {
            guard let persistedScan = try modelContext.fetch(descriptor).first else {
                return false
            }
            scan = persistedScan
        } catch {
            MerianLog.data.error(
                "transitionScanToStaged: scan lookup failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return false
        }
        // Only retreat from .inferencing — do not overwrite a concurrent tombstone (.failed).
        guard scan.scanStateRaw == inferencingRaw else { return false }
        if let expectedGeneration {
            let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
            let job: OfflineJobRecord?
            do {
                job = try modelContext.fetchOfflineJob(id: jobId)
            } catch {
                MerianLog.data.error(
                    "transitionScanToStaged: job lookup failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
                )
                return false
            }
            guard let job,
                  InferenceGenerationMetadataContract.matches(
                      expectedGeneration,
                      in: job.metadataJSON
                  ) else {
                MerianLog.data.debug(
                    "transitionScanToStaged: generation mismatch scanId=\(scanId, privacy: .public)"
                )
                return false
            }
        }
        scan.scanStateRaw = stagedRaw
        scan.queueUpdatedAt = Date()
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "transitionScanToStaged: save failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
    }

    /// Must be called only while `ScanInferencePersistenceCoordinator` is held
    /// for `scanId`. This intentionally does not acquire the coordinator itself
    /// so the main-actor queue deletion path can validate durable ownership
    /// while keeping the lock across URLSession cancellation and SwiftData save.
    ///
    /// An absent queue row is accepted only when the exact generation's durable
    /// job is already complete. That narrow terminal proof makes committed
    /// queue deletion idempotent without allowing an active or stale generation
    /// to delete replacement work.
    func inferenceGenerationIsCurrentAssumingPersistenceLock(
        scanId: String,
        expectedGeneration: UUID
    ) -> Bool {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let queuedScan: OfflineQueuedScan?
        do {
            queuedScan = try modelContext.fetch(scanDescriptor).first
        } catch {
            MerianLog.data.error(
                "inferenceGenerationIsCurrent: queue lookup failed scanId=\(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let job: OfflineJobRecord?
        do {
            job = try modelContext.fetchOfflineJob(id: jobId)
        } catch {
            MerianLog.data.error(
                "inferenceGenerationIsCurrent: job lookup failed scanId=\(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        guard let job,
              InferenceGenerationMetadataContract.matches(
                  expectedGeneration,
                  in: job.metadataJSON
              ) else {
            return false
        }
        if let queuedScan {
            return queuedScan.scanStateRaw == inferencingRaw
        }
        return job.status == .complete
    }

    /// Validates a foreground owner while
    /// `ScanInferencePersistenceCoordinator` is already held for `scanId`.
    ///
    /// Unlike background inference, a live request may own a queued scan while
    /// recovery media is pending, uploading, or staged. The durable job
    /// generation is therefore the cross-actor source of truth.
    func liveInferenceGenerationIsCurrentAssumingPersistenceLock(
        scanId: String,
        expectedGeneration: UUID
    ) -> Bool {
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        scanDescriptor.fetchLimit = 1
        let scan: OfflineQueuedScan
        do {
            guard let persistedScan = try modelContext.fetch(scanDescriptor).first else {
                return false
            }
            scan = persistedScan
        } catch {
            MerianLog.data.error(
                "liveInferenceGenerationIsCurrent: queue lookup failed scanId=\(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        guard scan.queueState != .failed,
              scan.queueState != .externalImport else {
            return false
        }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let job: OfflineJobRecord?
        do {
            job = try modelContext.fetchOfflineJob(id: jobId)
        } catch {
            MerianLog.data.error(
                "liveInferenceGenerationIsCurrent: job lookup failed scanId=\(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return false
        }
        guard let job else { return false }
        return InferenceGenerationMetadataContract.matches(
            expectedGeneration,
            in: job.metadataJSON
        )
    }

    /// Resets `.inferencing` scans that have no active background URLSession
    /// inference task back to `.staged` so replay can re-claim them.
    ///
    /// The live task snapshot prevents duplicate dispatch after relaunch. The
    /// cutoff also excludes generations claimed while reconciliation awaits
    /// this actor. Candidate locks are acquired in stable order, then durable
    /// eligibility is reread so deletion, completion, or retry work that won
    /// while this pass waited cannot be overwritten by stale recovery state.
    func reconcileOrphanedInferencingScans(
        activeInferenceScanIds: Set<String>,
        observedThrough: Date = Date()
    ) async {
        guard let candidateScanIds = orphanedInferenceCandidateIds(
            activeInferenceScanIds: activeInferenceScanIds,
            observedThrough: observedThrough
        )?.sorted(), !candidateScanIds.isEmpty else { return }

        var acquiredScanIds: [String] = []
        for scanId in candidateScanIds {
            await ScanInferencePersistenceCoordinator.shared.acquire(
                scanId: scanId
            )
            acquiredScanIds.append(scanId)
            guard !Task.isCancelled else {
                for acquiredScanId in acquiredScanIds.reversed() {
                    await ScanInferencePersistenceCoordinator.shared.release(
                        scanId: acquiredScanId
                    )
                }
                return
            }
        }

        reconcileOrphanedInferencingScansLocked(
            candidateScanIds: Set(candidateScanIds),
            activeInferenceScanIds: activeInferenceScanIds,
            observedThrough: observedThrough
        )
        for scanId in acquiredScanIds.reversed() {
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: scanId
            )
        }
    }

    private func reconcileOrphanedInferencingScansLocked(
        candidateScanIds: Set<String>,
        activeInferenceScanIds: Set<String>,
        observedThrough: Date
    ) {
        guard let eligibleScanIds = orphanedInferenceCandidateIds(
            activeInferenceScanIds: activeInferenceScanIds,
            observedThrough: observedThrough
        ).map(Set.init) else {
            return
        }
        let revalidatedScanIds = candidateScanIds.intersection(eligibleScanIds)
        guard !revalidatedScanIds.isEmpty else { return }

        let inferencingRaw = ScanQueueState.inferencing.rawValue
        let stagedRaw = ScanQueueState.staged.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.scanStateRaw == inferencingRaw && !$0.queueNeedsAttention
            }
        )
        let scans: [OfflineQueuedScan]
        do {
            scans = try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.error(
                "reconcileOrphanedInferencingScans: scan fetch failed error=\(error, privacy: .private)"
            )
            return
        }
        let candidates = scans.filter { revalidatedScanIds.contains($0.id) }
        guard !candidates.isEmpty,
              let jobsByScanId = inferenceJobsForOrphanReconciliation(
                  candidates
              ) else {
            return
        }

        let now = Date()
        for scan in candidates {
            scan.scanStateRaw = stagedRaw
            scan.queueUpdatedAt = now
            let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scan.id)
            if let job = jobsByScanId[scan.id] {
                job.status = scan.queueNextRetryAt.map {
                    $0 > now ? .waiting : .pending
                } ?? .pending
                job.updatedAt = now
                job.nextRunAt = scan.queueNextRetryAt
            }
            modelContext.insert(OfflineQueueEvent(
                jobId: jobId,
                scanId: scan.id,
                kind: .retryScheduled,
                message: "Recovered an inference claim without an active task."
            ))
        }

        do {
            try modelContext.save()
            MerianLog.data.debug(
                "reconcileOrphanedInferencingScans: reset orphaned .inferencing scans to .staged"
            )
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "reconcileOrphanedInferencingScans: save failed: \(error, privacy: .private)"
            )
        }
    }

    private func orphanedInferenceCandidateIds(
        activeInferenceScanIds: Set<String>,
        observedThrough: Date
    ) -> [String]? {
        let readContext = ModelContext(modelContext.container)
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.scanStateRaw == inferencingRaw && !$0.queueNeedsAttention
            }
        )
        do {
            return try readContext.fetch(descriptor)
                .filter {
                    $0.queueUpdatedAt <= observedThrough
                        && !activeInferenceScanIds.contains($0.id)
                }
                .map(\.id)
        } catch {
            MerianLog.data.error(
                "reconcileOrphanedInferencingScans: eligibility fetch failed error=\(error, privacy: .private)"
            )
            return nil
        }
    }

    private func inferenceJobsForOrphanReconciliation(
        _ scans: [OfflineQueuedScan]
    ) -> [String: OfflineJobRecord]? {
        var jobsByScanId: [String: OfflineJobRecord] = [:]
        for scan in scans {
            let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scan.id)
            do {
                if let job = try modelContext.fetchOfflineJob(id: jobId) {
                    jobsByScanId[scan.id] = job
                }
            } catch {
                MerianLog.data.error(
                    "reconcileOrphanedInferencingScans: job fetch failed scanId=\(scan.id, privacy: .private) error=\(error, privacy: .private)"
                )
                return nil
            }
        }
        return jobsByScanId
    }

    /// Persists weather backfill data onto the queued scan record before the inference
    /// request is dispatched as a background download task.
    ///
    /// Called after WeatherKit resolves so the delegate can read hydrated telemetry from
    /// SwiftData on result delivery — even if the app was suspended between dispatch and receipt.
    func updateScanTelemetry(
        scanId: String,
        weatherCondition: String?,
        weatherTemperatureF: Double?,
        locationName: String?
    ) {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let scan: OfflineQueuedScan
        do {
            guard let persistedScan = try modelContext.fetch(descriptor).first else {
                return
            }
            scan = persistedScan
        } catch {
            MerianLog.data.error(
                "updateScanTelemetry: scan lookup failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return
        }
        if let weatherCondition {
            scan.weatherCondition = weatherCondition
        }
        if let weatherTemperatureF {
            scan.weatherTemperatureF = weatherTemperatureF
        }
        if scan.locationName == nil, let locationName {
            scan.locationName = locationName
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "updateScanTelemetry: save failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
        }
    }
}
