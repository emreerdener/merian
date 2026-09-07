import Foundation
import SwiftData

// MARK: - Uploaded Scan Replay

extension OfflineQueueManager {

    /// Re-triggers inference for scans in `.staged` state — images confirmed in R2 but whose
    /// inference pipeline was interrupted by an app kill, crash, suspension, or connectivity loss.
    ///
    /// On every call: resets `.inferencing` orphans to `.staged` before querying, so scans
    /// interrupted mid-inference (e.g. by backgrounding) are immediately visible to replay.
    ///
    /// On first call per process only: runs a cold-start upload reconcile gated to that window
    /// because it must run before any new upload tasks are dispatched (ensures the live-task
    /// cross-reference captures only pre-existing tasks from the previous process).
    /// On every subsequent call: also reconciles `.uploading` orphans via a live-task
    /// cross-reference to catch scans stuck in `.uploading` when `generateUploadURLs` failed
    /// or the `syncPendingScans` Task was killed before its catch block could run.
    func replayInferenceForUploadedScans() {
        guard isOnline else {
            MerianLog.data.debug("replayInferenceForUploadedScans: skipped because network is offline")
            return
        }
        guard !isCurrentNetworkConstrained else {
            MerianLog.data.debug(
                "replayInferenceForUploadedScans: skipped because network is constrained"
            )
            return
        }
        guard let context = modelContext else {
            MerianLog.data.error("replayInferenceForUploadedScans: skipped because modelContext is nil")
            return
        }
        let container = context.container
        guard beginInferenceReplayReconciliation() else {
            return
        }
        MerianLog.data.debug(
            "replayInferenceForUploadedScans: starting startupReconciled=\(self.hasReconciledStartupState, privacy: .public)"
        )

        // One-time cold-start reconciliation for orphaned .uploading scans.
        // The task snapshot is timestamp-fenced, so a scan claimed while this pass
        // awaits the shared queue actor cannot be reset as an orphan.
        if !hasReconciledStartupState {
            hasReconciledStartupState = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    // Cold-start upload reconciliation must always be followed
                    // by the normal inference pass. That one pass also
                    // satisfies every wake coalesced while startup work ran.
                    _ = self.finishInferenceReplayReconciliation()
                    self.replayInferenceForUploadedScans()
                }
                let observedThrough = Date()
                let allTasks = await backgroundSession.allTasks
                let activeIds = Set<String>(allTasks.compactMap { task -> String? in
                    MediaStagingContract.parseUploadTaskDescription(
                        task.taskDescription
                    )?.scanId
                })
                let preparingUploadIds = await MainActor.run { self.uploadPreparationScanIds }
                let completingUploadIds = await MainActor.run { self.uploadCompletionScanIds }
                MerianLog.data.debug(
                    "replayInferenceForUploadedScans: cold-start live upload tasks=\(activeIds.count, privacy: .public) preparing=\(preparingUploadIds.count, privacy: .public) completing=\(completingUploadIds.count, privacy: .public)"
                )
                let dbActor = self.resolvedQueueDbActor(container: container)
                let hadOrphans = await dbActor.reconcileOrphanedUploadingScans(
                    activeScanIds: activeIds.union(preparingUploadIds).union(completingUploadIds),
                    observedThrough: observedThrough
                )
                // Only call syncPendingScans if the reconcile actually reset scans from
                // .uploading → .pending. Without this, the initial syncPendingScans call
                // (from handleActivePhase) already ran and found nothing — .uploading scans
                // are invisible to its .pending-only fetch — so the reconciled scan would
                // sit in .pending permanently until the next connectivity event or foreground.
                // Guarding on hadOrphans avoids a spurious second sync when the common case
                // (no orphaned uploads) does not require one.
                await MainActor.run {
                    if hadOrphans { self.syncPendingScans() }
                }
            }
            return
        }

        // Reconcile .inferencing orphans on every call by cross-referencing live background
        // URLSession inference tasks. Background download tasks survive app suspension, so a
        // simple in-process counter (activeInferencePipelineCount) can no longer tell us whether
        // an .inferencing scan is legitimately owned by a live OS task — we must ask the session.
        //
        // CRITICAL: use the shared actor (not a fresh one) for the reset. If a fresh actor
        // saves .inferencing → .staged to the persistent store, the shared actor's in-memory
        // copy of the object may still show .inferencing (Core Data returns cached faults
        // rather than hitting the store). tryClaimForInference — which runs on the shared
        // actor — would then fail its state guard and return false on every cycle, leaving
        // the scan stuck indefinitely. Running the reset on the same actor guarantees the
        // in-memory object is updated before tryClaimForInference reads it.
        let sharedActor = resolvedQueueDbActor(container: container)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.finishInferenceReplayReconciliation() {
                    self.replayInferenceForUploadedScans()
                }
            }
            let observedThrough = Date()
            let allTasks = await backgroundSession.allTasks

            // Safety-net: reconcile orphaned .uploading scans on every replay.
            // The primary reset happens in syncPendingScans's catch block when
            // generateUploadURLs fails, but this covers any interruption that bypasses
            // that path (e.g. the Swift Task being killed before the catch runs).
            // Cross-referencing allTasks ensures scans with live URLSession tasks are
            // not reset — only true orphans (no task, stuck in .uploading) are affected.
            // Safety-net: run upload reconcile on sharedActor (not a fresh one) so that
            // the in-memory object graph is coherent when tryClaimForInference runs below.
            // A fresh actor's save() can invalidate sharedActor's cached fault objects
            // (§6 of swiftdata-and-api-gotchas), causing tryClaimForInference to miss a
            // scan it just transitioned if it still shows the stale pre-save state.
            let activeUploadScanIds = Set<String>(allTasks.compactMap { task -> String? in
                MediaStagingContract.parseUploadTaskDescription(task.taskDescription)?.scanId
            })
            let preparingUploadScanIds = await MainActor.run { self.uploadPreparationScanIds }
            let completingUploadScanIds = await MainActor.run { self.uploadCompletionScanIds }
            MerianLog.data.debug(
                "replayInferenceForUploadedScans: activeUploadTasks=\(activeUploadScanIds.count, privacy: .public) preparingUpload=\(preparingUploadScanIds.count, privacy: .public) completingUpload=\(completingUploadScanIds.count, privacy: .public)"
            )
            let hadUploadOrphans = await sharedActor.reconcileOrphanedUploadingScans(
                activeScanIds: activeUploadScanIds.union(preparingUploadScanIds).union(completingUploadScanIds),
                observedThrough: observedThrough
            )

            let activeInferenceScanIds = Set<String>(allTasks.compactMap { task -> String? in
                guard task.state != .canceling,
                      task.state != .completed,
                      let identity = InferenceURLSessionTaskContract.parse(
                        task.taskDescription
                      ) else { return nil }
                return identity.scanId
            })
            let preparingInferenceScanIds = await MainActor.run { self.inferencePreparationScanIds }
            let completingInferenceScanIds = await MainActor.run { self.inferenceCompletionScanIds }
            let pollingInferenceScanIds = await MainActor.run {
                self.serverIngestionPollTasks.keys
            }
            let generationOwnedInferenceScanIds = await MainActor.run {
                Set(self.activeInferenceGenerations.keys)
            }
            let locallyActiveInferenceScanIds = activeInferenceScanIds
                .union(preparingInferenceScanIds)
                .union(completingInferenceScanIds)
                .union(pollingInferenceScanIds)
                .union(generationOwnedInferenceScanIds)
            let serverOwnedInferenceScanIds = await self.serverOwnedInferencingScanIds(
                excluding: locallyActiveInferenceScanIds,
                reason: "orphan reconcile",
                observedThrough: observedThrough
            )
            MerianLog.data.debug(
                "replayInferenceForUploadedScans: activeInferenceTasks=\(activeInferenceScanIds.count, privacy: .public) preparing=\(preparingInferenceScanIds.count, privacy: .public) completing=\(completingInferenceScanIds.count, privacy: .public) generationOwned=\(generationOwnedInferenceScanIds.count, privacy: .public) polling=\(pollingInferenceScanIds.count, privacy: .public) serverOwned=\(serverOwnedInferenceScanIds.count, privacy: .public)"
            )
            await sharedActor.reconcileOrphanedInferencingScans(
                activeInferenceScanIds: locallyActiveInferenceScanIds
                    .union(serverOwnedInferenceScanIds),
                observedThrough: observedThrough
            )
            await MainActor.run {
                // A reset row is pending-only and therefore invisible to staged
                // replay. Restart signing in the same recovery pass instead of
                // waiting for another foreground or connectivity transition.
                if hadUploadOrphans {
                    self.updateUnsyncedItemCount()
                    self.syncPendingScans()
                }
                self.replayInferenceStagedScans()
            }
        }
    }

    /// Fetches all `.staged` scans and dispatches a background inference download task for each one.
    ///
    /// Called by `replayInferenceForUploadedScans` after `reconcileOrphanedInferencingScans`
    /// completes, ensuring any orphaned `.inferencing` scans (not owned by a live URLSession task)
    /// are visible as `.staged` before the query runs.
    private func replayInferenceStagedScans() {
        guard isOnline else { return }
        guard let context = modelContext else { return }
        restoreFundingReservationsForCurrentAccount()
        let container = context.container

        let stagedRaw = ScanQueueState.staged.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.scanStateRaw == stagedRaw }
        )
        guard let fetched = try? context.fetch(descriptor), !fetched.isEmpty else {
            MerianLog.data.debug("replayInferenceStagedScans: no staged scans")
            return
        }
        let legacyAudioRepairScanIds = Set(fetched.compactMap { scan in
            scan.capturedMediaSnapshot.legacyQueuedAudioReferences.isEmpty
                ? nil
                : scan.id
        })
        if !legacyAudioRepairScanIds.isEmpty {
            let dbActor = resolvedQueueDbActor(container: container)
            let orderedScanIds = legacyAudioRepairScanIds.sorted()
            Task { [weak self] in
                guard let self else { return }
                let repairResult = await self.repairLegacyQueuedAudio(
                    scanIds: orderedScanIds,
                    dbActor: dbActor
                )
                if repairResult.didMutate {
                    self.syncPendingScans()
                }
            }
        }
        let now = Date()
        let staged = fetched.filter { scan in
            !legacyAudioRepairScanIds.contains(scan.id) &&
                !foregroundInferenceScanIds.contains(scan.id) &&
                activeInferenceGenerations[scan.id] == nil &&
                inferencePreparationGenerations[scan.id] == nil &&
                inferenceCompletionGenerations[scan.id] == nil &&
                EntitlementManager.shared.fundingAllowsDispatch(
                    scanId: scan.id
                ) &&
                !scan.queueNeedsAttention &&
                (scan.queueNextRetryAt == nil || (scan.queueNextRetryAt ?? now) <= now)
        }.sorted { lhs, rhs in
            let leftPriority = EntitlementManager.shared.fundingPriority(
                scanId: lhs.id
            )
            let rightPriority = EntitlementManager.shared.fundingPriority(
                scanId: rhs.id
            )
            if leftPriority != rightPriority {
                return leftPriority < rightPriority
            }
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id < rhs.id
        }
        guard !staged.isEmpty else {
            MerianLog.data.debug("replayInferenceStagedScans: no staged scans ready for retry")
            return
        }
        MerianLog.data.debug("replayInferenceStagedScans: staged scans=\(fetched.count, privacy: .public) runnable=\(staged.count, privacy: .public)")

        for scan in staged {
            let scanId = scan.id
            let extracted = buildExtractedScanData(from: scan, container: container)
            Task {
                let dbActor = resolvedQueueDbActor(container: container)
                // Atomic claim: transitions .staged → .inferencing.
                // If another path already claimed it, this returns false and we skip.
                guard let preparationGeneration = await MainActor.run(body: {
                    self.beginInferencePreparation(scanId: scanId)
                }) else {
                    MerianLog.data.debug(
                        "replayInferenceStagedScans: preparation already active scanId=\(scanId, privacy: .public)"
                    )
                    return
                }
                let didClaim = await dbActor.tryClaimForInference(
                    scanId: scanId,
                    generation: preparationGeneration
                )
                if !didClaim {
                    MerianLog.data.debug(
                        "replayInferenceStagedScans: claim skipped scanId=\(scanId, privacy: .public)"
                    )
                    await MainActor.run {
                        self.clearInferencePreparation(
                            scanId: scanId,
                            generation: preparationGeneration
                        )
                    }
                    return
                }
                await MainActor.run {
                    OfflineJobScheduler.shared.scheduleNextPersistedWake(
                        using: self
                    )
                }
                MerianLog.data.debug(
                    "replayInferenceStagedScans: claimed scanId=\(scanId, privacy: .public)"
                )

#if DEBUG
                // Increment before any network work so tests can observe this as a
                // network-free signal that the replay pipeline was triggered.
                await MainActor.run { self.replayedStagedScanCount += 1 }
#endif

                // Migration fallback: pre-V33 media scans have no stagedR2Keys.
                // Reconstruct from the current auth session — safe because the userId
                // embedded in the R2 key matches the session that performed the upload.
                // Describe-only scans intentionally have both r2Keys and localUploadPaths
                // empty — guard on !localImagePaths.isEmpty to skip this path for them.
                let finalExtracted: ExtractedScanData
                if extracted.r2Keys.isEmpty && !extracted.localUploadPaths.isEmpty {
                    guard let stagingUserId = await self
                        .currentMediaStagingUserId() else {
                        await self.handleInferenceRetry(
                            scanId: scanId,
                            generation: preparationGeneration,
                            reason: "auth transition pending"
                        )
                        return
                    }
                    let reconstructedKeys = MediaStagingContract.splitObjectKeys(
                        [],
                        scanId: scanId,
                        userId: stagingUserId,
                        localImagePaths: extracted.localImagePaths,
                        localAudioPaths: extracted.audioFilePaths ?? [],
                        localVideoPaths: extracted.videoFilePaths ?? []
                    ).all
                    finalExtracted = ExtractedScanData(
                        telemetry: extracted.telemetry,
                        r2Keys: reconstructedKeys,
                        container: extracted.container,
                        originalTimestamp: extracted.originalTimestamp,
                        capturedMediaItems: extracted.capturedMediaItems,
                        inferenceImagePaths: extracted.inferenceImagePaths,
                        visualMediaItemsJSON: extracted.visualMediaItemsJSON,
                        preferredGoal: extracted.preferredGoal
                    )
                } else {
                    finalExtracted = extracted
                }

                await self.dispatchInferenceDownloadTask(
                    scanId: scanId,
                    extracted: finalExtracted,
                    preparationGeneration: preparationGeneration
                )
            }
        }
    }
}
