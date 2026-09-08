import Foundation

extension OfflineQueueManager {
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
        restoreFundingReservationsForCurrentAccount()
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
            let currentScanData = scanData
            let fundingPolicy = await MainActor.run {
                Dictionary(uniqueKeysWithValues: currentScanData.map { scan in
                    (
                        scan.id,
                        (
                            EntitlementManager.shared.fundingAllowsDispatch(
                                scanId: scan.id
                            ),
                            EntitlementManager.shared.fundingPriority(
                                scanId: scan.id
                            )
                        )
                    )
                })
            }
            let eligibleScanData = scanData.filter { scan in
                !deferredLiveUploadIds.contains(scan.id) &&
                    fundingPolicy[scan.id]?.0 == true &&
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
                    for scanId in quarantinedScanIds {
                        self.releaseFundingForProvenPredispatchFailure(
                            scanId: scanId
                        )
                    }
                    self.updateUnsyncedItemCount()
                    AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
                }
            }
            let uploadCandidates = eligibleScanData.filter {
                !$0.localUploadPaths.isEmpty
            }.sorted { lhs, rhs in
                let leftPriority = fundingPolicy[lhs.id]?.1 ?? 4
                let rightPriority = fundingPolicy[rhs.id]?.1 ?? 4
                return leftPriority == rightPriority
                    ? lhs.id < rhs.id
                    : leftPriority < rightPriority
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

            guard let stagingUserId = await self.currentMediaStagingUserId()
            else {
                _ = await MainActor.run {
                    self.finishUploadSync(generation: generation)
                }
                return
            }
            guard let stagingAuthUserID = UUID(uuidString: stagingUserId) else {
                _ = await MainActor.run {
                    self.finishUploadSync(generation: generation)
                }
                return
            }
            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }
            let preparation = self.prepareUploadItems(from: filteredScans, userId: stagingUserId)

            if !preparation.rejectedScanIds.isEmpty {
                await MainActor.run {
                    guard self.isCurrentUploadSync(generation) else { return }
                    for scanId in preparation.rejectedScanIds {
                        self.quarantineInvalidQueuedMedia(scanId: scanId)
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
                        self.deferredLiveUploadScanIds,
                    fundingDispatchableScanIds: Set(filteredScans.compactMap {
                        EntitlementManager.shared.fundingAllowsDispatch(
                            scanId: $0.id
                        ) ? $0.id : nil
                    })
                )
            }
            guard await MainActor.run(body: {
                self.isCurrentUploadSync(generation)
            }) else { return }
            let finallyEligibleScanIds = Set(filteredScans.lazy.filter {
                finalPolicy.isOnline
                    && !finalPolicy.isConstrained
                    && finalPolicy.fundingDispatchableScanIds.contains($0.id)
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
                        self.deferredLiveUploadScanIds,
                    fundingDispatchableScanIds: Set(claimedScanIds.compactMap {
                        EntitlementManager.shared.fundingAllowsDispatch(
                            scanId: $0
                        ) ? $0 : nil
                    })
                )
            }
            let dispatchableClaimedScanIds = Set(claimedScanIds.lazy.filter {
                postClaimPolicy.isCurrent
                    && postClaimPolicy.isOnline
                    && !postClaimPolicy.isConstrained
                    && postClaimPolicy.fundingDispatchableScanIds.contains($0)
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
                let activeUploadIds = Set<String>(liveTasks.compactMap { task -> String? in
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
                    uploadFiles: claimedUploadFiles,
                    expectedAuthUserID: stagingAuthUserID
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
                let dispatchResult = await self.dispatchUploadTasks(
                    session: session,
                    uploadItems: claimedUploadItems,
                    presignedUrls: presignedUrls,
                    syncGeneration: generation,
                    expectedAuthUserID: stagingAuthUserID,
                    forcedExpensiveVideoUploadScanIds:
                        forcedExpensiveVideoUploadScanIds
                )
                let dispatchedScanIDs = dispatchResult.dispatchedScanIds
                let undispatchedScanIDs =
                    dispatchableClaimedScanIds.subtracting(dispatchedScanIDs)
                if !undispatchedScanIDs.isEmpty {
                    let observedThrough = Date()
                    let liveTasks = await session.allTasks
                    let activeUploadIds = Set<String>(liveTasks.compactMap { task -> String? in
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
                        if !dispatchResult.needsResigningScanIds.isEmpty {
                            Task { @MainActor [weak self] in
                                await Task.yield()
                                self?.syncPendingScans()
                            }
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
}
