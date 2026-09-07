import Foundation

private struct UploadDispatchEntry {
    let item: ScanUploadItem
    let presignedURL: PreSignedURL
    let remoteURL: URL
}

extension OfflineQueueManager {
    func dispatchUploadTasks(
        session: URLSession,
        uploadItems: [ScanUploadItem],
        presignedUrls: [PreSignedURL],
        syncGeneration: UUID,
        expectedAuthUserID: UUID,
        forcedExpensiveVideoUploadScanIds: Set<String>
    ) async -> (
        dispatchedScanIds: Set<String>,
        needsResigningScanIds: Set<String>
    ) {
        guard let accountWorkLease = try? SupabaseManager.shared
            .beginUnownedAccountBoundWork(
                expectedUserID: expectedAuthUserID
            ) else {
            return (
                dispatchedScanIds: [],
                needsResigningScanIds: []
            )
        }
        defer {
            SupabaseManager.shared.finishAccountBoundWork(accountWorkLease)
        }

        let playbackVideoScanIds = Set(uploadItems.lazy.filter {
            $0.mediaKind == .video
        }.map(\.scanId))
        var entriesByScanId: [String: [UploadDispatchEntry]] = [:]
        var scanOrder: [String] = []
        var rejectedScanIds = Set<String>()
        var needsResigningScanIds = Set<String>()

        // Validate the complete signed manifest and every local source before
        // creating any task. A scan is one logical upload unit: either all of
        // its members are resumed in one main-actor turn or none are.
        for (index, item) in uploadItems.enumerated() {
            guard !Task.isCancelled else {
                return (
                    dispatchedScanIds: [],
                    needsResigningScanIds: []
                )
            }
            guard index < presignedUrls.count,
                  let remoteURL = URL(
                    string: presignedUrls[index].signedUrl
                  ) else {
                rejectedScanIds.insert(item.scanId)
                continue
            }
            let presignedURL = presignedUrls[index]
            guard presignedURL.fileName == item.fileName,
                  presignedURL.objectKey == item.objectKey,
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
            guard MediaStagingContract.fileSizeMatchesSigningSnapshot(item) else {
                MerianLog.data.info(
                    "dispatchUploadTasks: source size changed after signing for \(item.scanId, privacy: .private); discarding URL"
                )
                needsResigningScanIds.insert(item.scanId)
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
            releaseFundingForProvenPredispatchFailure(scanId: scanId)
            softDeleteQueuedScan(
                scanId: scanId,
                reason: "Queued media or its upload destination could not be verified.",
                errorCode: "queued_upload_manifest_invalid"
            )
        }

        var dispatchedScanIds = Set<String>()
        for scanId in scanOrder
        where !rejectedScanIds.contains(scanId)
            && !needsResigningScanIds.contains(scanId) {
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
                  !entries.isEmpty,
                  entries.allSatisfy({
                      MediaStagingContract.fileSizeMatchesSigningSnapshot($0.item)
                  }) else {
                if let entries = entriesByScanId[scanId],
                   !entries.isEmpty,
                   !entries.allSatisfy({
                       MediaStagingContract.fileSizeMatchesSigningSnapshot($0.item)
                   }) {
                    needsResigningScanIds.insert(scanId)
                }
                continue
            }

            guard let container = modelContext?.container else { continue }
            let durableOwnership = BackgroundAccountWorkOwnership(
                ownerUserID: expectedAuthUserID,
                generation: syncGeneration,
                phase: .upload
            )
            let queueActor = resolvedQueueDbActor(container: container)
            guard await queueActor.activateBackgroundAccountWork(
                scanId: scanId,
                ownership: durableOwnership
            ) else {
                continue
            }

            var uploadTasks: [URLSessionUploadTask] = []
            var retainedTaskIdentifiers: [Int] = []
            var manifestPreparationFailed = false
            for entry in entries {
                let request = queuedUploadRequest(
                    remoteURL: entry.remoteURL,
                    item: entry.item,
                    requiredHeaders: entry.presignedURL.requiredHeaders,
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
                        objectKey: entry.presignedURL.objectKey,
                        ownerUserID: expectedAuthUserID
                    )
                uploadTasks.append(task)
                guard let terminalLease = try? SupabaseManager.shared
                    .beginUnownedAccountBoundWork(
                        expectedUserID: expectedAuthUserID
                    ) else {
                    manifestPreparationFailed = true
                    break
                }
                guard retainBackgroundAccountWork(
                    terminalLease,
                    for: task.taskIdentifier
                ) else {
                    SupabaseManager.shared.finishAccountBoundWork(
                        terminalLease
                    )
                    manifestPreparationFailed = true
                    break
                }
                retainedTaskIdentifiers.append(task.taskIdentifier)
            }
            guard !manifestPreparationFailed,
                  uploadTasks.count == entries.count else {
                // A manifest is all-or-nothing. Persist the retreat before any
                // suspended task is cancelled so its terminal callback cannot
                // promote a partial source-account upload.
                let didRetire = await Self
                    .awaitDurableBackgroundWorkRetirement(
                    retire: {
                        await queueActor.retireBackgroundAccountWork(
                            scanId: scanId,
                            expectedOwnerUserID: expectedAuthUserID,
                            expectedGeneration: syncGeneration,
                            phase: .upload
                        )
                    },
                    waitBeforeRetry: {
                        await Self
                            .waitForDurableBackgroundWorkRetirementRetry()
                    }
                )
                guard didRetire else {
                    // Keep suspended transports and their Auth leases intact.
                    // The transition quiescer re-reads the durable ownership
                    // and is not allowed to mutate Auth until retirement can
                    // be committed.
                    continue
                }
                invalidateUploadGeneration(
                    scanId: scanId,
                    generation: syncGeneration
                )
                for retainedIdentifier in retainedTaskIdentifiers {
                    finishBackgroundAccountWork(
                        for: retainedIdentifier
                    )
                }
                for uploadTask in uploadTasks {
                    uploadTask.cancel()
                }
                continue
            }
            for uploadTask in uploadTasks {
                uploadTask.resume()
            }
            dispatchedScanIds.insert(scanId)
            MerianLog.data.debug(
                "🚀 BACKGROUND UPLOAD: Dispatched complete manifest for \(scanId, privacy: .private) members=\(uploadTasks.count, privacy: .public)"
            )
        }
        return (
            dispatchedScanIds: dispatchedScanIds,
            needsResigningScanIds: needsResigningScanIds
        )
    }

    /// Builds the final R2 PUT request with transport-level enforcement of the
    /// queue's path policy. A scan containing non-forced playback video cannot
    /// partially continue over cellular after a Wi-Fi handoff; standalone small
    /// image/audio work may.
    nonisolated func queuedUploadRequest(
        remoteURL: URL,
        item: ScanUploadItem,
        requiredHeaders: [String: String],
        scanContainsPlaybackVideo: Bool,
        allowsExpensiveVideoUpload: Bool
    ) -> URLRequest {
        var request = URLRequest(url: remoteURL)
        request.httpMethod = "PUT"
        for (field, value) in requiredHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.allowsConstrainedNetworkAccess = false
        request.allowsExpensiveNetworkAccess =
            !scanContainsPlaybackVideo || allowsExpensiveVideoUpload
        return request
    }

    func handleSyncNetworkFailure(
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
}
