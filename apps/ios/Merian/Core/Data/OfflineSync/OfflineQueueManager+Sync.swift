import Foundation
import SwiftData

private struct UploadDispatchEntry {
    let item: ScanUploadItem
    let presignedURL: PreSignedURL
    let remoteURL: URL
}

// MARK: - Sync Operations

extension OfflineQueueManager {

    // MARK: - Cloud Deletions

    /// Drains the `PendingCloudDeletionTask` queue, calling the delete Edge function for each record.
    ///
    /// A task is removed only after an explicitly validated success response.
    /// Authentication, malformed-response, transport, and server errors all
    /// retain the task for the next connectivity cycle.
    func syncPendingDeletions() async {
        guard isOnline, let context = modelContext else { return }
        guard !isCloudDeletionSyncing else { return }
        isCloudDeletionSyncing = true
        defer { isCloudDeletionSyncing = false }

        let pendingTasks: [PendingCloudDeletionTask]
        do {
            var descriptor = FetchDescriptor<PendingCloudDeletionTask>(sortBy: [SortDescriptor(\.timestamp)])
            descriptor.fetchLimit = 200
            pendingTasks = try context.fetch(descriptor)
        } catch {
            MerianLog.data.debug("syncPendingDeletions: fetch failed: \(error, privacy: .private)")
            return
        }

        guard !pendingTasks.isEmpty else { return }

        let now = Date()
        var didPrepareJob = false
        let runnableTasks = pendingTasks.filter { task in
            let job = ensureCloudDeletionJob(scanId: task.scanId, context: context)
            if job?.created == true {
                didPrepareJob = true
            }
            guard let record = job?.record else { return true }
            if Self.cloudDeletionStatusRequiresRecovery(record.status) {
                // PendingCloudDeletionTask is the durable source of truth.
                // Older builds could pause an erasure permanently after the
                // generic retry budget, while complete/cancelled here would
                // contradict the still-present task. Heal every such state
                // before applying its retry eligibility date.
                record.status = .pending
                record.updatedAt = now
                record.nextRunAt = nil
                didPrepareJob = true
            }
            guard isRunnableCloudDeletionStatus(record.statusRaw) else { return false }
            if let nextRunAt = record.nextRunAt, nextRunAt > now {
                return false
            }
            return true
        }

        if didPrepareJob {
            do {
                try context.save()
            } catch {
                context.rollback()
                MerianLog.data.error("syncPendingDeletions: failed to prepare deletion jobs: \(error, privacy: .private)")
                return
            }
        }

        guard !runnableTasks.isEmpty else { return }

        for task in runnableTasks {
            if let job = ensureCloudDeletionJob(scanId: task.scanId, context: context)?.record {
                job.status = .running
                job.updatedAt = now
                job.lastAttemptAt = now
                job.nextRunAt = nil
                context.insert(OfflineQueueEvent(
                    jobId: job.id,
                    scanId: task.scanId,
                    kind: .claimed,
                    message: "Cloud deletion started."
                ))
            }
        }

        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.error("syncPendingDeletions: failed to claim deletion jobs: \(error, privacy: .private)")
            return
        }

        // Fetch O(n) results using the batch dispatcher
        let scanIds = runnableTasks.map(\.scanId)
        let allResults = await dispatchDeleteBatches(scanIds: scanIds)

        // Build an O(1) lookup so the per-result loop below doesn't scan the full
        // pendingTasks array for each result (was O(n²) when the batch was large).
        let taskById = Dictionary(uniqueKeysWithValues: runnableTasks.map { ($0.scanId, $0) })
        var didMutate = false
        for (scanId, error) in allResults {
            guard let task = taskById[scanId] else { continue }
            if Self.cloudDeletionWasConfirmed(error: error) {
                MerianLog.data.debug("✅ Deleted \(scanId, privacy: .private) from Edge")
                context.delete(task)
                markCloudDeletionJob(scanId: scanId, success: true, error: nil, context: context)
                didMutate = true
            } else if let error {
                MerianLog.data.error("syncPendingDeletions: failed for \(scanId, privacy: .private): \(error, privacy: .private)")
                markCloudDeletionJob(scanId: scanId, success: false, error: error, context: context)
                didMutate = true
            }
        }

        if didMutate {
            do {
                try context.save()
                OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
            } catch {
                context.rollback()
                MerianLog.data.error("syncPendingDeletions: save failed: \(error, privacy: .private)")
            }
        }
    }

    /// No local error category proves remote erasure. In particular,
    /// `invalidResponse` can represent an auth/session failure or a malformed
    /// HTTP success body. Only a nil dispatch error means `deleteScan` decoded
    /// the Edge route's explicit `success: true` confirmation.
    static func cloudDeletionWasConfirmed(error: Error?) -> Bool {
        error == nil
    }

    /// A pending erasure cannot be cancelled or declared complete locally.
    /// These statuses came from an older exhausted retry budget or contradict
    /// the still-present durable task, so the next drain repairs them.
    static func cloudDeletionStatusRequiresRecovery(
        _ status: OfflineJobStatus
    ) -> Bool {
        switch status {
        case .needsAttention, .complete, .cancelled:
            true
        case .pending, .running, .waiting:
            false
        }
    }

    /// Cloud erasure retries never exhaust. The diagnostic attempt number is
    /// capped only so exponential delay remains bounded and corrupt persisted
    /// values cannot overflow.
    static func nextCloudDeletionRetryAttempt(after currentAttempt: Int) -> Int {
        let maximumAttempt = OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        let boundedAttempt = min(max(0, currentAttempt), maximumAttempt)
        return min(boundedAttempt + 1, maximumAttempt)
    }

    /// Fans out deletions in batches to prevent unbounded concurrent network requests.
    /// Without a cap, a user returning from a week offline could saturate the pool and trigger rate limits.
    ///
    /// Batch size is hardware-aware: 10 concurrent sockets is the normal-operation ceiling,
    /// but in Low Power Mode the baseband chip is already constrained by the OS. Dropping to 3
    /// limits peak antenna transmit power, avoiding the thermal spike that cascades to CPU
    /// throttling and visible UI lag during large backlog drains.
    private func dispatchDeleteBatches(scanIds: [String]) async -> [(String, Error?)] {
        let batchSize = ProcessInfo.processInfo.isLowPowerModeEnabled ? 3 : 10
        var allResults: [(String, Error?)] = []
        allResults.reserveCapacity(scanIds.count)

        for batchStart in stride(from: 0, to: scanIds.count, by: batchSize) {
            let batch = Array(scanIds[batchStart..<min(batchStart + batchSize, scanIds.count)])
            let batchResults: [(String, Error?)] = await withTaskGroup(of: (String, Error?).self) { group in
                for scanId in batch {
                    group.addTask {
                        do {
                            try await MerianNetworkClient.shared.deleteScan(scanId: scanId)
                            return (scanId, nil)
                        } catch {
                            return (scanId, error)
                        }
                    }
                }
                var collected: [(String, Error?)] = []
                for await result in group { collected.append(result) }
                return collected
            }
            allResults.append(contentsOf: batchResults)
        }
        return allResults
    }

    private func markCloudDeletionJob(scanId: String, success: Bool, error: Error?, context: ModelContext) {
        let jobId = "cloud-deletion:\(scanId)"
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        guard let job = (try? context.fetch(descriptor))?.first else { return }
        job.updatedAt = Date()
        if success {
            job.status = .complete
            job.nextRunAt = nil
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            job.lastHTTPStatus = nil
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                scanId: scanId,
                kind: .completed,
                message: "Cloud deletion completed."
            ))
        } else {
            job.lastAttemptAt = Date()
            job.lastErrorMessage = error?.localizedDescription
            job.status = .waiting
            job.attemptCount = Self.nextCloudDeletionRetryAttempt(
                after: job.attemptCount
            )
            job.nextRunAt = Date().addingTimeInterval(
                OfflineQueueRetryPolicy.jitteredDelay(forAttempt: job.attemptCount)
            )
            job.lastErrorCode = "cloud_deletion_failed"
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                scanId: scanId,
                kind: .retryScheduled,
                message: error?.localizedDescription,
                errorCode: "cloud_deletion_failed"
            ))
        }
    }

    private func isRunnableCloudDeletionStatus(_ statusRaw: String) -> Bool {
        statusRaw == OfflineJobStatus.pending.rawValue ||
            statusRaw == OfflineJobStatus.waiting.rawValue ||
            statusRaw == OfflineJobStatus.running.rawValue
    }

    private func ensureCloudDeletionJob(
        scanId: String,
        context: ModelContext
    ) -> (record: OfflineJobRecord, created: Bool)? {
        let jobId = "cloud-deletion:\(scanId)"
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            return (existing, false)
        }

        let record = OfflineJobRecord(
            id: jobId,
            kind: .cloudDeletion,
            subjectId: scanId,
            priority: 60
        )
        context.insert(record)
        context.insert(OfflineQueueEvent(
            jobId: jobId,
            scanId: scanId,
            kind: .queued,
            message: "Queued cloud deletion."
        ))
        return (record, true)
    }

    // MARK: - Uploads

    /// Fetches `.pending` scans and schedules background `PUT` uploads to Cloudflare R2 staging.
    ///
    /// Upload tasks are tracked by
    /// `MediaStagingContract.uploadTaskDescription(scanId:uploadIndex:syncGeneration:objectKey:)`.
    /// Scans are atomically transitioned to `.uploading` state before tasks are dispatched,
    /// so `syncPendingScans` never re-dispatches in-flight uploads after an app restart.
    /// Confirmed R2 keys are persisted on the record at upload completion (in URLSession delegate).
    ///
    /// Guards: expedition mode, connectivity, and an in-flight sync must all clear.
    func syncPendingScans() {
        MerianLog.data.debug(
            "syncPendingScans: requested isOnline=\(self.isOnline, privacy: .public) isSyncing=\(self.isSyncing, privacy: .public) unsynced=\(self.unsyncedItemsCount, privacy: .public)"
        )
        guard !hardwareOrchestrator.isExpeditionModeActive else {
            MerianLog.data.debug("syncPendingScans: skipped because expedition mode is active")
            return
        }
        guard isOnline else {
            MerianLog.data.debug("syncPendingScans: skipped because network is offline")
            return
        }
        guard !isCurrentNetworkConstrained else {
            MerianLog.data.debug("syncPendingScans: skipped because network is constrained")
            return
        }
        guard !isSyncing else {
            MerianLog.data.debug("syncPendingScans: skipped because a sync is already active")
            return
        }
        guard let container = modelContext?.container else {
            MerianLog.data.error("syncPendingScans: skipped because modelContext is nil")
            return
        }

        let generation = UUID()
        isSyncing = true
        syncGeneration = generation

        syncTask = BackgroundTaskWrapper.execute(
            name: "OfflineQueueSync",
            expirationHandler: { [weak self] in
                MerianLog.data.debug("OfflineQueueSync background task expired")
                Task { @MainActor [weak self] in
                    self?.expireUploadSync(generation: generation)
                }
            }
        ) { [weak self] _ in
            guard let self else { return }
            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }

            let dbActor = await MainActor.run {
                self.resolvedQueueDbActor(container: container)
            }
            let initialAllowsLargeUploads = await MainActor.run {
                self.allowsLargeQueuedUploadsOnCurrentNetwork
            }
            let initialForcedLargeUploadIds = await MainActor.run {
                self.userRequestedLargeUploadScanIds
            }
            let initialDeferredLiveUploadIds = await MainActor.run {
                self.deferredLiveUploadScanIds
            }
            var scanData = await dbActor.fetchPendingScans(
                limit: MerianConfig.pendingScanFetchLimit,
                excludingScanIds: initialDeferredLiveUploadIds,
                allowsVideoUploads: initialAllowsLargeUploads,
                forcedVideoUploadScanIds: initialForcedLargeUploadIds
            )
            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }
            let session  = await MainActor.run { self.backgroundSession }
            let allowsLargeUploads = await MainActor.run { self.allowsLargeQueuedUploadsOnCurrentNetwork }
            let forcedLargeUploadIds = await MainActor.run { self.userRequestedLargeUploadScanIds }
            let deferredLiveUploadIds = await MainActor.run { self.deferredLiveUploadScanIds }
            if allowsLargeUploads != initialAllowsLargeUploads
                || forcedLargeUploadIds != initialForcedLargeUploadIds
                || deferredLiveUploadIds != initialDeferredLiveUploadIds {
                scanData = await dbActor.fetchPendingScans(
                    limit: MerianConfig.pendingScanFetchLimit,
                    excludingScanIds: deferredLiveUploadIds,
                    allowsVideoUploads: allowsLargeUploads,
                    forcedVideoUploadScanIds: forcedLargeUploadIds
                )
                guard await MainActor.run(body: {
                    self.isCurrentUploadSync(generation)
                }) else { return }
            }
            // Recheck process-local eligibility after the actor read. The
            // paged actor inputs prevent starvation; this latest snapshot
            // prevents a changed live/network state from dispatching stale
            // candidates.
            let eligibleScanData = scanData.filter { scan in
                !deferredLiveUploadIds.contains(scan.id) &&
                    (allowsLargeUploads || scan.localVideoPaths.isEmpty || forcedLargeUploadIds.contains(scan.id))
            }

            let emptyPendingScanIds = eligibleScanData
                .filter { $0.localUploadPaths.isEmpty }
                .map(\.id)
            if !emptyPendingScanIds.isEmpty {
                let quarantinedScanIds =
                    await dbActor.quarantineEmptyPendingScans(
                        scanIds: emptyPendingScanIds
                    )
                await MainActor.run {
                    guard self.isCurrentUploadSync(generation),
                          !quarantinedScanIds.isEmpty else {
                        return
                    }
                    self.updateUnsyncedItemCount()
                    ScanLibraryEvents.postLibraryDidUpdate()
                }
            }
            let uploadCandidates = eligibleScanData.filter {
                !$0.localUploadPaths.isEmpty
            }
            let filteredScans = self.selectUploadBatch(from: uploadCandidates)
            MerianLog.data.debug(
                "syncPendingScans: fetched pending=\(scanData.count, privacy: .public) eligible=\(eligibleScanData.count, privacy: .public) empty=\(emptyPendingScanIds.count, privacy: .public) selected=\(filteredScans.count, privacy: .public) largeUploads=\(allowsLargeUploads, privacy: .public)"
            )

            guard !filteredScans.isEmpty else {
                _ = await MainActor.run {
                    self.finishUploadSync(generation: generation)
                }
                return
            }

            await MainActor.run {
                guard self.isCurrentUploadSync(generation) else { return }
                SyncStateManager.shared.beginSync(
                    itemCount: filteredScans.count,
                    generation: generation
                )
            }

            let stagingUserId = await self.currentMediaStagingUserId()
            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }
            let preparation = self.prepareUploadItems(from: filteredScans, userId: stagingUserId)

            if !preparation.rejectedScanIds.isEmpty {
                await MainActor.run {
                    guard self.isCurrentUploadSync(generation) else { return }
                    for scanId in preparation.rejectedScanIds {
                        self.softDeleteQueuedScan(
                            scanId: scanId,
                            reason: "Queued media is missing, invalid, or exceeds the upload limit.",
                            errorCode: "queued_media_invalid"
                        )
                    }
                }
            }

            // Auth/session lookup and filesystem validation above may suspend.
            // Recheck live/network policy immediately before the database
            // claim so a path that became constrained or expensive cannot
            // dispatch a stale video candidate.
            let finalPolicy = await MainActor.run {
                (
                    isOnline: self.isOnline,
                    isConstrained: self.isCurrentNetworkConstrained,
                    allowsLargeUploads:
                        self.allowsLargeQueuedUploadsOnCurrentNetwork,
                    forcedLargeUploadIds:
                        self.userRequestedLargeUploadScanIds,
                    deferredLiveUploadIds:
                        self.deferredLiveUploadScanIds
                )
            }
            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }
            let finallyEligibleScanIds = Set(filteredScans.lazy.filter {
                finalPolicy.isOnline
                    && !finalPolicy.isConstrained
                    && !finalPolicy.deferredLiveUploadIds.contains($0.id)
                    && (
                        finalPolicy.allowsLargeUploads
                            || $0.localVideoPaths.isEmpty
                            || finalPolicy.forcedLargeUploadIds.contains($0.id)
                    )
            }.map(\.id))
            let finallyEligiblePreparation = zip(
                preparation.uploadItems,
                preparation.uploadFiles
            ).filter {
                finallyEligibleScanIds.contains($0.0.scanId)
            }
            let uploadItems = finallyEligiblePreparation.map { $0.0 }
            let uploadFiles = finallyEligiblePreparation.map { $0.1 }
            MerianLog.data.debug(
                "syncPendingScans: prepared uploadItems=\(uploadItems.count, privacy: .public) rejected=\(preparation.rejectedScanIds.count, privacy: .public) finalEligibleScans=\(finallyEligibleScanIds.count, privacy: .public)"
            )

            guard !uploadItems.isEmpty else {
                _ = await MainActor.run {
                    self.finishUploadSync(generation: generation)
                }
                return
            }

            let candidateUploadScanIds = Set(uploadItems.map(\.scanId))
            await MainActor.run {
                guard self.isCurrentUploadSync(generation) else { return }
                self.trackUploadPreparation(
                    scanIds: candidateUploadScanIds,
                    generation: generation
                )
                MerianLog.data.debug(
                    "syncPendingScans: tracking upload preparation ids=\(candidateUploadScanIds.sorted().joined(separator: ","), privacy: .private)"
                )
            }

            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }
            let claimedScanIds = await dbActor.markScansAsUploading(scanIds: Array(candidateUploadScanIds))
            let claimObservedThrough = Date()
            let playbackVideoCandidateIds = Set(uploadItems.lazy.filter {
                $0.mediaKind == .video
            }.map(\.scanId))
            let postClaimPolicy = await MainActor.run {
                (
                    isCurrent: self.isCurrentUploadSync(generation),
                    isOnline: self.isOnline,
                    isConstrained: self.isCurrentNetworkConstrained,
                    allowsLargeUploads:
                        self.allowsLargeQueuedUploadsOnCurrentNetwork,
                    forcedLargeUploadIds:
                        self.userRequestedLargeUploadScanIds,
                    deferredLiveUploadIds:
                        self.deferredLiveUploadScanIds
                )
            }
            let dispatchableClaimedScanIds = Set(claimedScanIds.lazy.filter {
                postClaimPolicy.isCurrent
                    && postClaimPolicy.isOnline
                    && !postClaimPolicy.isConstrained
                    && !postClaimPolicy.deferredLiveUploadIds.contains($0)
                    && (
                        postClaimPolicy.allowsLargeUploads
                            || !playbackVideoCandidateIds.contains($0)
                            || postClaimPolicy.forcedLargeUploadIds.contains($0)
                    )
            })
            let undispatchedClaimedScanIds =
                claimedScanIds.subtracting(dispatchableClaimedScanIds)
            if !undispatchedClaimedScanIds.isEmpty {
                // Connectivity and path policy can change while the serialized
                // actor claim is awaiting execution. No task from this
                // generation exists yet, so release only exact claims that are
                // still absent from the live URLSession snapshot. This is a
                // policy handoff, not a failed attempt: retry budget and error
                // metadata remain untouched.
                let liveTasks = await session.allTasks
                let activeUploadIds = Set(liveTasks.compactMap { task in
                    guard task.state != .canceling,
                          task.state != .completed else {
                        return nil
                    }
                    return MediaStagingContract.parseUploadTaskDescription(
                        task.taskDescription
                    )?.scanId
                })
                _ = await dbActor.reconcileOrphanedUploadingScans(
                    activeScanIds: activeUploadIds,
                    candidateScanIds: undispatchedClaimedScanIds,
                    observedThrough: claimObservedThrough
                )
                await MainActor.run {
                    self.clearUploadPreparation(
                        scanIds: undispatchedClaimedScanIds,
                        generation: generation
                    )
                }
            }
            guard postClaimPolicy.isCurrent else { return }
            await MainActor.run {
                for scanId in dispatchableClaimedScanIds {
                    self.uploadCompletionStates[scanId] = nil
                    self.latestUploadGenerations[scanId] = generation
                }
                self.userRequestedLargeUploadScanIds.subtract(
                    dispatchableClaimedScanIds
                )
            }
            let forcedExpensiveVideoUploadScanIds =
                postClaimPolicy.forcedLargeUploadIds
                    .intersection(dispatchableClaimedScanIds)
            MerianLog.data.debug(
                "syncPendingScans: claimed scans=\(claimedScanIds.count, privacy: .public) dispatchable=\(dispatchableClaimedScanIds.count, privacy: .public) ids=\(dispatchableClaimedScanIds.sorted().joined(separator: ","), privacy: .private)"
            )
            let unclaimedScanIds = candidateUploadScanIds.subtracting(claimedScanIds)
            if !unclaimedScanIds.isEmpty {
                await MainActor.run {
                    self.clearUploadPreparation(
                        scanIds: unclaimedScanIds,
                        generation: generation
                    )
                }
            }
            let claimedUploadPairs = zip(uploadItems, uploadFiles).filter {
                dispatchableClaimedScanIds.contains($0.0.scanId)
            }
            let claimedUploadItems = claimedUploadPairs.map { $0.0 }
            let claimedUploadFiles = claimedUploadPairs.map { $0.1 }

            guard !claimedUploadItems.isEmpty else {
                MerianLog.data.error("syncPendingScans: no scans could be claimed for upload; leaving queue for retry")
                await MainActor.run {
                    self.clearUploadPreparation(
                        scanIds: candidateUploadScanIds,
                        generation: generation
                    )
                    self.finishUploadSync(generation: generation)
                }
                return
            }

            do {
                let presignedUrls = try await MerianNetworkClient.shared.generateUploadURLs(
                    uploadFiles: claimedUploadFiles
                )
                guard await MainActor.run(body: {
                    self.isCurrentUploadSync(generation)
                }) else { return }
                MerianLog.data.debug(
                    "syncPendingScans: received presigned URLs=\(presignedUrls.count, privacy: .public)"
                )
                guard MediaStagingContract.presignedUploadManifestIsValid(
                    uploadItems: claimedUploadItems,
                    presignedURLs: presignedUrls
                ) else {
                    MerianLog.data.error(
                        "syncPendingScans: rejected an invalid staging response manifest"
                    )
                    throw MerianError.invalidResponse
                }
                let dispatchedScanIDs = await self.dispatchUploadTasks(
                    session: session,
                    uploadItems: claimedUploadItems,
                    presignedUrls: presignedUrls,
                    syncGeneration: generation,
                    forcedExpensiveVideoUploadScanIds:
                        forcedExpensiveVideoUploadScanIds
                )
                let undispatchedScanIDs =
                    dispatchableClaimedScanIds.subtracting(dispatchedScanIDs)
                if !undispatchedScanIDs.isEmpty {
                    let observedThrough = Date()
                    let liveTasks = await session.allTasks
                    let activeUploadIds = Set(liveTasks.compactMap { task in
                        guard task.state != .canceling,
                              task.state != .completed else {
                            return nil
                        }
                        return MediaStagingContract.parseUploadTaskDescription(
                            task.taskDescription
                        )?.scanId
                    })
                    _ = await dbActor.reconcileOrphanedUploadingScans(
                        activeScanIds: activeUploadIds,
                        candidateScanIds: undispatchedScanIDs,
                        observedThrough: observedThrough
                    )
                }
                await MainActor.run {
                    guard self.isCurrentUploadSync(generation) else { return }
                    self.clearUploadPreparation(
                        scanIds: dispatchableClaimedScanIds,
                        generation: generation
                    )
                    MerianLog.data.debug(
                        "syncPendingScans: cleared upload preparation ids=\(dispatchableClaimedScanIds.sorted().joined(separator: ","), privacy: .private) dispatched=\(dispatchedScanIDs.sorted().joined(separator: ","), privacy: .private)"
                    )
                }

                if dispatchedScanIDs.isEmpty {
                    let taskCount = await self.activeUploadTaskCount(
                        session: session,
                        generation: generation
                    )
                    MerianLog.data.debug(
                        "syncPendingScans: dispatched no upload tasks activeTaskCount=\(taskCount, privacy: .public)"
                    )
                    if taskCount == 0 {
                        _ = await MainActor.run {
                            self.finishUploadSync(generation: generation)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.clearUploadPreparation(
                        scanIds: dispatchableClaimedScanIds,
                        generation: generation
                    )
                }
                await self.handleSyncNetworkFailure(
                    error: error,
                    affectedScanIds: dispatchableClaimedScanIds,
                    session: session,
                    dbActor: dbActor,
                    syncGeneration: generation,
                    playbackVideoScanIds:
                        playbackVideoCandidateIds.intersection(
                            dispatchableClaimedScanIds
                        ),
                    forcedExpensiveVideoUploadScanIds:
                        forcedExpensiveVideoUploadScanIds
                )
                return
            }

            // Failsafe: if no tasks were spawned, unlock manually.
            let activeTaskCount = await self.activeUploadTaskCount(
                session: session,
                generation: generation
            )
            MerianLog.data.debug(
                "syncPendingScans: active task count after dispatch=\(activeTaskCount, privacy: .public)"
            )
            if activeTaskCount == 0 {
                _ = await MainActor.run {
                    self.finishUploadSync(generation: generation)
                }
            }
        }
    }

    private func activeUploadTaskCount(
        session: URLSession,
        generation: UUID
    ) async -> Int {
        let tasks = await session.allTasks
        return tasks.filter { task in
            guard task.state != .canceling,
                  task.state != .completed,
                  let identity = MediaStagingContract.parseUploadTaskDescription(
                    task.taskDescription
                  ) else {
                return false
            }
            return identity.syncGeneration == generation
        }.count
    }

    func isCurrentUploadSync(_ generation: UUID) -> Bool {
        syncGeneration == generation
    }

    @discardableResult
    func finishUploadSync(generation: UUID?) -> Bool {
        if let generation {
            guard syncGeneration == generation else {
                MerianLog.data.debug(
                    "finishUploadSync: ignored stale generation=\(generation.uuidString, privacy: .private)"
                )
                return false
            }
            SyncStateManager.shared.completeUploadPhase(generation: generation)
        } else {
            // Compatibility for upload tasks attached by an older app build.
            guard syncGeneration == nil else { return false }
        }

        syncGeneration = nil
        syncTask = nil
        isSyncing = false
        return true
    }

    func expireUploadSync(generation: UUID) {
        guard isCurrentUploadSync(generation) else {
            MerianLog.data.debug(
                "expireUploadSync: ignored stale generation=\(generation.uuidString, privacy: .private)"
            )
            return
        }
        syncTask?.cancel()
        uploadPreparationGenerations = uploadPreparationGenerations.filter {
            $0.value != generation
        }
        _ = finishUploadSync(generation: generation)
    }

    private func trackUploadPreparation(
        scanIds: Set<String>,
        generation: UUID
    ) {
        for scanId in scanIds {
            uploadPreparationGenerations[scanId] = generation
        }
    }

    private func clearUploadPreparation(
        scanIds: Set<String>,
        generation: UUID
    ) {
        for scanId in scanIds
        where uploadPreparationGenerations[scanId] == generation {
            uploadPreparationGenerations[scanId] = nil
        }
    }

    // MARK: - Upload Helpers

    nonisolated func currentMediaStagingUserId() async -> String {
        // The persisted Auth session is the source of truth even while
        // SupabaseManager.currentUser is still hydrating after a cold launch.
        // This also keeps the pre-V33 staged-key recovery path on the same owner
        // namespace that the authenticated upload endpoint used.
        let sessionUserId = try? await SupabaseManager.shared.client.auth.session.user.id.uuidString
        let (hydratedUserId, deviceId) = await MainActor.run {
            (
                SupabaseManager.shared.currentUser?.id.uuidString,
                DeviceIdentityManager.shared.deviceId
            )
        }

        return MediaStagingContract.preferredOwnerId(
            sessionUserId: sessionUserId,
            hydratedUserId: hydratedUserId,
            deviceId: deviceId
        )
    }

    nonisolated private func prepareUploadItems(
        from scans: [PendingScanPayload],
        userId: String
    ) -> MediaStagingPreparation {
        var uploadItems: [ScanUploadItem] = []
        var uploadFiles: [StagingUploadFile] = []
        var rejectedScanIds: [String] = []

        for scan in scans {
            let scanItems = MediaStagingContract.uploadItems(for: scan, userId: userId)
            do {
                try MediaStagingContract.validateUploadBudget(scanItems)
                let scanUploadFiles = try MediaStagingContract.uploadFiles(for: scanItems)
                uploadItems.append(contentsOf: scanItems)
                uploadFiles.append(contentsOf: scanUploadFiles)
            } catch {
                MerianLog.data.error("prepareUploadItems: rejecting staged media for \(scan.id, privacy: .private): \(error, privacy: .private)")
                rejectedScanIds.append(scan.id)
            }
        }

        return MediaStagingPreparation(
            uploadItems: uploadItems,
            uploadFiles: uploadFiles,
            rejectedScanIds: rejectedScanIds
        )
    }

    nonisolated func selectUploadBatch(
        from scans: [PendingScanPayload]
    ) -> [PendingScanPayload] {
        let maxPresignedURLsPerRequest = MediaStagingContract.maxUploadItemsPerRequest
        var selected: [PendingScanPayload] = []
        selected.reserveCapacity(MerianConfig.uploadBatchSize)
        var uploadItemCount = 0

        for scan in scans {
            guard selected.count < MerianConfig.uploadBatchSize else { break }
            let scanUploadCount = scan.localUploadPaths.count
            guard scanUploadCount > 0 else { continue }
            if uploadItemCount + scanUploadCount > maxPresignedURLsPerRequest {
                // Let the normal media-contract validator quarantine one
                // oversized head row, but do not let a later non-fitting row
                // prevent still-smaller work from filling the batch.
                if selected.isEmpty {
                    selected.append(scan)
                    break
                }
                continue
            }
            selected.append(scan)
            uploadItemCount += scanUploadCount
            if uploadItemCount >= maxPresignedURLsPerRequest {
                break
            }
        }

        return selected
    }

    private func dispatchUploadTasks(
        session: URLSession,
        uploadItems: [ScanUploadItem],
        presignedUrls: [PreSignedURL],
        syncGeneration: UUID,
        forcedExpensiveVideoUploadScanIds: Set<String>
    ) async -> Set<String> {
        let playbackVideoScanIds = Set(uploadItems.lazy.filter {
            $0.mediaKind == .video
        }.map(\.scanId))
        var entriesByScanId: [String: [UploadDispatchEntry]] = [:]
        var scanOrder: [String] = []
        var rejectedScanIds = Set<String>()

        // Validate the complete signed manifest and every local source before
        // creating any task. A scan is one logical upload unit: either all of
        // its members are resumed in one main-actor turn or none are.
        for (index, item) in uploadItems.enumerated() {
            guard !Task.isCancelled else { return [] }
            guard index < presignedUrls.count,
                  let remoteURL = URL(
                    string: presignedUrls[index].signedUrl
                  ) else {
                rejectedScanIds.insert(item.scanId)
                continue
            }
            let presignedURL = presignedUrls[index]
            guard presignedURL.fileName == item.fileName,
                  MediaStagingContract.isCanonicalObjectKey(
                    presignedURL.objectKey,
                    fileName: item.fileName
                  ),
                  MediaStagingContract.objectKey(
                    fromPresignedURLPath: remoteURL.path
                  ) == presignedURL.objectKey else {
                MerianLog.data.error(
                    "dispatchUploadTasks: staging contract mismatch for \(item.scanId, privacy: .private)"
                )
                rejectedScanIds.insert(item.scanId)
                continue
            }
            guard FileManager.default.fileExists(
                atPath: item.fileURL.path
            ) else {
                MerianLog.data.debug(
                    "dispatchUploadTasks: source missing for \(item.fileURL.lastPathComponent, privacy: .private)"
                )
                rejectedScanIds.insert(item.scanId)
                continue
            }
            if entriesByScanId[item.scanId] == nil {
                scanOrder.append(item.scanId)
            }
            entriesByScanId[item.scanId, default: []].append(
                UploadDispatchEntry(
                item: item,
                presignedURL: presignedURL,
                remoteURL: remoteURL
                )
            )
        }

        for scanId in rejectedScanIds {
            guard isCurrentUploadSync(syncGeneration),
                  latestUploadGenerations[scanId] == syncGeneration else {
                continue
            }
            softDeleteQueuedScan(
                scanId: scanId,
                reason: "Queued media or its upload destination could not be verified.",
                errorCode: "queued_upload_manifest_invalid"
            )
        }

        var dispatchedScanIds = Set<String>()
        for scanId in scanOrder where !rejectedScanIds.contains(scanId) {
            let pathAllowsScan =
                !playbackVideoScanIds.contains(scanId)
                    || allowsLargeQueuedUploadsOnCurrentNetwork
                    || forcedExpensiveVideoUploadScanIds.contains(scanId)
            guard !Task.isCancelled,
                  isOnline,
                  !isCurrentNetworkConstrained,
                  isCurrentUploadSync(syncGeneration),
                  latestUploadGenerations[scanId] == syncGeneration,
                  pathAllowsScan,
                  let entries = entriesByScanId[scanId],
                  !entries.isEmpty else {
                continue
            }

            let uploadTasks = entries.map { entry in
                let request = queuedUploadRequest(
                    remoteURL: entry.remoteURL,
                    item: entry.item,
                    scanContainsPlaybackVideo:
                        playbackVideoScanIds.contains(scanId),
                    allowsExpensiveVideoUpload:
                        forcedExpensiveVideoUploadScanIds.contains(scanId)
                )
                let task = session.uploadTask(
                    with: request,
                    fromFile: entry.item.fileURL
                )
                task.taskDescription =
                    MediaStagingContract.uploadTaskDescription(
                        scanId: scanId,
                        uploadIndex: entry.item.uploadIndex,
                        syncGeneration: syncGeneration,
                        objectKey: entry.presignedURL.objectKey
                    )
                return task
            }
            for uploadTask in uploadTasks {
                uploadTask.resume()
            }
            dispatchedScanIds.insert(scanId)
            MerianLog.data.debug(
                "🚀 BACKGROUND UPLOAD: Dispatched complete manifest for \(scanId, privacy: .private) members=\(uploadTasks.count, privacy: .public)"
            )
        }
        return dispatchedScanIds
    }

    /// Builds the final R2 PUT request with transport-level enforcement of the
    /// queue's path policy. A scan containing non-forced playback video cannot
    /// partially continue over cellular after a Wi-Fi handoff; standalone small
    /// image/audio work may.
    nonisolated func queuedUploadRequest(
        remoteURL: URL,
        item: ScanUploadItem,
        scanContainsPlaybackVideo: Bool,
        allowsExpensiveVideoUpload: Bool
    ) -> URLRequest {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "PUT"
        request.setValue(
            item.contentType,
            forHTTPHeaderField: "Content-Type"
        )
        request.allowsConstrainedNetworkAccess = false
        request.allowsExpensiveNetworkAccess =
            !scanContainsPlaybackVideo || allowsExpensiveVideoUpload
        return request
    }

    private func handleSyncNetworkFailure(
        error: Error,
        affectedScanIds: Set<String>,
        session: URLSession,
        dbActor: BackgroundDatabaseActor,
        syncGeneration: UUID,
        playbackVideoScanIds: Set<String>,
        forcedExpensiveVideoUploadScanIds: Set<String>
    ) async {
        MerianLog.data.debug("syncPendingScans: staging URL request failed: \(error, privacy: .private)")

        // A signing request can fail after connectivity or path policy
        // invalidates the process-local generation. Always release its exact
        // no-task claims first; a path handoff is not a failed queue attempt.
        let observedThrough = Date()
        let liveTasks = await session.allTasks
        let activeUploadIds = Set(liveTasks.compactMap { task in
            guard task.state != .canceling,
                  task.state != .completed else {
                return nil
            }
            return MediaStagingContract.parseUploadTaskDescription(
                task.taskDescription
            )?.scanId
        })
        _ = await dbActor.reconcileOrphanedUploadingScans(
            activeScanIds: activeUploadIds,
            candidateScanIds: affectedScanIds,
            observedThrough: observedThrough
        )
        let networkPolicyStillAllowsRetry =
            isCurrentUploadSync(syncGeneration)
                && isOnline
                && !isCurrentNetworkConstrained
                && (
                    allowsLargeQueuedUploadsOnCurrentNetwork
                        || playbackVideoScanIds.isSubset(
                            of: forcedExpensiveVideoUploadScanIds
                        )
                )
        guard networkPolicyStillAllowsRetry else {
            _ = finishUploadSync(generation: syncGeneration)
            return
        }

        var retryDelays: [TimeInterval] = []
        for scanId in affectedScanIds {
            let currentAttempt = queueAttemptCount(for: scanId)
            guard OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: currentAttempt) else {
                markQueuedScanNeedsAttention(
                    scanId: scanId,
                    code: "automatic_retry_limit_reached",
                    message: OfflineQueueRetryPolicy.automaticRetryLimitMessage()
                )
                continue
            }

            let delay = OfflineQueueRetryPolicy.jitteredDelay(forAttempt: currentAttempt + 1)
            let persistedAttempt = updateQueuedScanForRetry(
                scanId: scanId,
                code: "upload_url_generation_failed",
                message: error.localizedDescription,
                delay: delay,
                resetTo: .pending
            )
            if persistedAttempt == nil {
                // Keep a process-local fallback even when the durable retry
                // metadata could not be saved. The preceding orphan reconcile
                // leaves successfully persisted rows pending; foreground and
                // connectivity recovery remain additional wake opportunities.
                MerianLog.data.error(
                    "syncPendingScans: retry persistence failed scanId=\(scanId, privacy: .private)"
                )
            }
            retryDelays.append(delay)
        }

        guard let delay = retryDelays.min() else {
            finishUploadSync(generation: syncGeneration)
            retryBackoffTask?.cancel()
            retryBackoffTask = nil
            return
        }

        finishUploadSync(generation: syncGeneration)
        retryBackoffTask?.cancel()
        retryBackoffTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self.syncPendingScans()
        }
    }

    // MARK: - Collections

    /// Marks collections as needing sync and attempts to push them immediately if online.
    /// The "Favorites" collection is excluded — it is managed locally only.
    func enqueueCollectionSync() {
        markCollectionSyncPending()
        syncCollectionsIfPending()
    }

    var hasPendingCollectionSyncJob: Bool {
        guard let context = modelContext else {
            return UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        }
        guard let job = fetchCollectionSyncJob(context: context) else { return false }
        return isActiveCollectionSyncStatus(job.statusRaw)
    }

    private var isCollectionSyncJobRunnable: Bool {
        guard let context = modelContext else {
            return UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        }
        guard let job = fetchCollectionSyncJob(context: context),
              isActiveCollectionSyncStatus(job.statusRaw) else { return false }
        if let nextRunAt = job.nextRunAt, nextRunAt > Date() {
            return false
        }
        return true
    }

    private func fetchCollectionSyncJob(context: ModelContext) -> OfflineJobRecord? {
        let jobId = Self.collectionSyncJobId
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func isActiveCollectionSyncStatus(_ statusRaw: String) -> Bool {
        statusRaw == OfflineJobStatus.pending.rawValue ||
            statusRaw == OfflineJobStatus.waiting.rawValue ||
            statusRaw == OfflineJobStatus.running.rawValue
    }

    /// Pushes local `ScanCollection` records to the `sync-collections` Edge function if changes are pending.
    /// No-ops when offline or unauthenticated.
    func syncCollectionsIfPending() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.drainCollectionSyncIfPossible()
        }
    }

    /// Shared collection-sync drain used by both fire-and-forget UI edits and the
    /// launch-time historical sync. This guarantees all collection pushes pass through
    /// the same single-flight latch, so a stale upsert can never race a newer tombstone.
    @discardableResult
    func drainCollectionSyncIfPossible() async -> Bool {
        while hasPendingCollectionSyncJob {
            guard isOnline, SupabaseManager.shared.isAuthenticated else { return false }
            guard isCollectionSyncJobRunnable else { return false }

            if let existingTask = collectionSyncTask {
                let didSucceed = await existingTask.value
                guard didSucceed else { return false }
                continue
            }

            guard let container = modelContext?.container else { return false }

            let capturedRevision = collectionSyncRevision
            isCollectionSyncing = true
            markCollectionSyncStarted()

            let task = BackgroundTaskWrapper.execute(name: "CollectionSync") { [weak self] _ in
                guard let self else { return false }
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                let success = await dbActor.pushCollectionsToEdge()

                await MainActor.run {
                    self.finishCollectionSyncAttempt(success: success, capturedRevision: capturedRevision)
                }

                return success
            }

            collectionSyncTask = task
            let didSucceed = await task.value
            guard didSucceed else { return false }
        }

        return true
    }

    func markCollectionSyncPending() {
        collectionSyncRevision &+= 1
        guard let context = modelContext else {
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
            return
        }
        do {
            let job = try context.ensureOfflineJobRecord(
                id: Self.collectionSyncJobId,
                kind: .collectionSync,
                priority: 80
            )
            job.status = .pending
            job.attemptCount = 0
            job.updatedAt = Date()
            job.nextRunAt = nil
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            context.insert(OfflineQueueEvent(
                jobId: job.id,
                kind: .queued,
                message: "Queued collection sync."
            ))
            try context.save()
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.needsCollectionSync)
        } catch {
            context.rollback()
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
            MerianLog.data.error("markCollectionSyncPending: save failed: \(error, privacy: .private)")
        }
    }

    func finishCollectionSyncAttempt(success: Bool, capturedRevision: UInt64) {
        isCollectionSyncing = false
        collectionSyncTask = nil

        guard let context = modelContext else {
            if success, collectionSyncRevision == capturedRevision {
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.needsCollectionSync)
            }
            return
        }

        let jobId = Self.collectionSyncJobId
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        guard let job = (try? context.fetch(descriptor))?.first else { return }
        job.updatedAt = Date()
        if success, collectionSyncRevision == capturedRevision {
            job.status = .complete
            job.nextRunAt = nil
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.needsCollectionSync)
            context.insert(OfflineQueueEvent(jobId: job.id, kind: .completed, message: "Collection sync completed."))
        } else if !success {
            job.lastAttemptAt = Date()
            if OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: job.attemptCount) {
                job.attemptCount += 1
                job.status = .waiting
                job.nextRunAt = Date().addingTimeInterval(
                    OfflineQueueRetryPolicy.jitteredDelay(forAttempt: job.attemptCount)
                )
                job.lastErrorCode = "collection_sync_failed"
                context.insert(OfflineQueueEvent(
                    jobId: job.id,
                    kind: .retryScheduled,
                    message: "Collection sync will retry.",
                    errorCode: "collection_sync_failed"
                ))
            } else {
                job.status = .needsAttention
                job.nextRunAt = nil
                job.lastErrorCode = "collection_sync_retry_limit_reached"
                context.insert(OfflineQueueEvent(
                    jobId: job.id,
                    kind: .needsAttention,
                    message: "Collection sync paused after repeated failures.",
                    errorCode: "collection_sync_retry_limit_reached"
                ))
            }
        }
        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.error("finishCollectionSyncAttempt: save failed: \(error, privacy: .private)")
        }
    }

    private func markCollectionSyncStarted() {
        guard let context = modelContext else { return }
        let jobId = Self.collectionSyncJobId
        var descriptor = FetchDescriptor<OfflineJobRecord>(
            predicate: #Predicate { $0.id == jobId }
        )
        descriptor.fetchLimit = 1
        guard let job = (try? context.fetch(descriptor))?.first else { return }
        job.status = .running
        job.updatedAt = Date()
        job.lastAttemptAt = Date()
        job.nextRunAt = nil
        context.insert(OfflineQueueEvent(jobId: job.id, kind: .claimed, message: "Collection sync started."))
        do {
            try context.save()
            OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        } catch {
            context.rollback()
            MerianLog.data.error("markCollectionSyncStarted: save failed: \(error, privacy: .private)")
        }
    }
}
