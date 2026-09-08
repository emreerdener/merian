import Foundation
import SwiftData

// MARK: - Upload Completion

extension OfflineQueueManager {
    /// Processes the result of a completed background upload, then kicks off inference
    /// for the scan once all expected media files have landed in R2 staging.
    func processUploadCompletion(
        taskDescription: String?,
        originalRequestUrlPath: String?,
        responseStatusCode: Int?,
        uploadError: Error?,
        taskIdentifier: Int,
        session: URLSession
    ) async {
        guard let uploadIdentity = MediaStagingContract.parseUploadTaskDescription(taskDescription) else { return }
        let scanId = uploadIdentity.scanId
        guard isUploadGenerationCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration
        ) else {
            MerianLog.data.debug(
                "processUploadCompletion: ignored stale upload generation scanId=\(scanId, privacy: .public)"
            )
            return
        }

        let completionToken = beginUploadCompletion(scanId: scanId)
        defer {
            _ = finishUploadCompletion(
                scanId: scanId,
                token: completionToken
            )
            MerianLog.data.debug(
                "processUploadCompletion: cleared upload completion lock scanId=\(scanId, privacy: .public)"
            )
        }
        let uploadIndex = uploadIdentity.uploadIndex ?? -1
        MerianLog.data.debug(
            "processUploadCompletion: scanId=\(scanId, privacy: .public) uploadIndex=\(uploadIndex, privacy: .public) status=\(responseStatusCode ?? -1, privacy: .public) error=\((uploadError?.localizedDescription ?? "nil"), privacy: .public)"
        )

        // Record this callback's outcome before the first suspension. URLSession
        // can remove a completed task before another callback's async handler
        // starts; yielding first would let a successful sibling inspect a
        // partial outcome set and mistake task disappearance for success.
        let didFail = handleUploadFallback(
            scanId: scanId,
            uploadError: uploadError,
            responseStatusCode: responseStatusCode,
            uploadGeneration: uploadIdentity.syncGeneration,
            completionToken: completionToken
        )
        if didFail {
            // One failed member invalidates the entire logical media manifest.
            // Otherwise a sibling that happens to complete last can observe no
            // active tasks and incorrectly advance the scan to `.staged`.
            invalidateUploadGeneration(
                scanId: scanId,
                generation: uploadIdentity.syncGeneration
            )
            let remainingTasks = await session.allTasks
            for task in remainingTasks where task.taskIdentifier != taskIdentifier {
                guard let identity = MediaStagingContract.parseUploadTaskDescription(
                    task.taskDescription
                ), identity.scanId == scanId,
                   identity.syncGeneration == uploadIdentity.syncGeneration else {
                    continue
                }
                task.cancel()
            }
            return
        }

        // The exact server-issued object key travels with current background
        // tasks. Legacy tasks recover it from the signed URL path.
        let confirmedObjectKey = uploadIdentity.objectKey ??
            MediaStagingContract.objectKey(
                fromPresignedURLPath: originalRequestUrlPath
            )
        guard let confirmedObjectKey,
              let stagingUserId = MediaStagingContract.ownerId(
                fromObjectKey: confirmedObjectKey
              ) else {
            MerianLog.data.error(
                "processUploadCompletion: scanId=\(scanId, privacy: .public) invalid staging destination"
            )
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: "The completed upload destination could not be verified.",
                errorCode: "staging_object_key_invalid"
            )
            return
        }
        recordSuccessfulUploadMember(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            objectKey: confirmedObjectKey
        )

        // Compute task state only after this callback's exact outcome has been
        // recorded. Every started sibling therefore publishes success or fences
        // failure before it can yield to this enumeration.
        let remainingTasks = await session.allTasks
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            token: completionToken
        ) else {
            MerianLog.data.debug(
                "processUploadCompletion: superseded while enumerating tasks scanId=\(scanId, privacy: .public)"
            )
            return
        }
        let hasReplacementTaskForScan = remainingTasks.contains {
            guard $0.taskIdentifier != taskIdentifier,
                  $0.state != .canceling,
                  $0.state != .completed,
                  let identity = MediaStagingContract.parseUploadTaskDescription(
                    $0.taskDescription
                  ) else {
                return false
            }
            return identity.scanId == scanId
                && identity.syncGeneration != uploadIdentity.syncGeneration
        }
        let hasReplacementPreparation = uploadPreparationGenerations[scanId]
            .map { $0 != uploadIdentity.syncGeneration } ?? false
        guard !hasReplacementTaskForScan, !hasReplacementPreparation else {
            MerianLog.data.debug(
                "processUploadCompletion: replacement upload owns scanId=\(scanId, privacy: .public)"
            )
            return
        }
        let hasActiveTasksForScan = remainingTasks.contains {
            guard $0.taskIdentifier != taskIdentifier,
                  let identity = MediaStagingContract.parseUploadTaskDescription(
                    $0.taskDescription
                  ) else {
                return false
            }
            return identity.scanId == scanId
                && identity.syncGeneration == uploadIdentity.syncGeneration
        }
        MerianLog.data.debug(
            "processUploadCompletion: scanId=\(scanId, privacy: .public) hasActiveTasksForScan=\(hasActiveTasksForScan, privacy: .public) remainingTasks=\(remainingTasks.count, privacy: .public)"
        )

        // Ensure no other upload tasks for this specific scan ID are still in flight.
        // If they are, allow them to finish (the last one handles the inference triggering).
        // Guard here — before the main-actor metadata fetch and auth session lookup — so that
        // multi-image scans don't pay those costs on every intermediate completion (only the last).
        guard !hasActiveTasksForScan else {
            MerianLog.data.debug(
                "processUploadCompletion: scanId=\(scanId, privacy: .public) waiting for remaining upload tasks"
            )
            return
        }

        // Fetch scan metadata on the main actor before handing off to background inference.
        let extracted = await fetchScanMetadata(for: scanId)
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            token: completionToken
        ) else {
            return
        }
        guard let extracted else {
            MerianLog.data.error(
                "processUploadCompletion: missing queued scan metadata scanId=\(scanId, privacy: .public)"
            )
            return
        }

        guard !QueuedInferenceMediaPolicy.containsUnsupportedAudio(
            in: extracted.capturedMediaSnapshot
        ) else {
            // A relaunched URLSession callback can outlive the source build.
            // Never advance an unsupported audio manifest to inference, even
            // though current queue admission cannot create this state.
            invalidateUploadGeneration(
                scanId: scanId,
                generation: uploadIdentity.syncGeneration
            )
            quarantineInvalidQueuedMedia(scanId: scanId)
            return
        }

        // Compute confirmed object keys through the shared media staging contract so
        // completion, replay, and request construction cannot drift on filename rules.
        let stagedKeys = MediaStagingContract.splitObjectKeys(
            [],
            scanId: scanId,
            userId: stagingUserId,
            localImagePaths: extracted.localImagePaths,
            localAudioPaths: extracted.audioFilePaths ?? [],
            localVideoPaths: extracted.videoFilePaths ?? []
        )
        let r2Keys = stagedKeys.all
        guard r2Keys.contains(confirmedObjectKey) else {
            MerianLog.data.error(
                "processUploadCompletion: scanId=\(scanId, privacy: .public) completed object no longer belongs to queued media"
            )
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: "The completed upload no longer matches the queued capture.",
                errorCode: "staging_capture_identity_mismatch"
            )
            return
        }
        guard hasConfirmedSuccessfulUploadManifest(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            expectedObjectKeys: r2Keys
        ) else {
            // A completed sibling can disappear from URLSession.allTasks before
            // its asynchronous callback records either success or failure.
            // Wait for that callback; failure invalidates this generation and
            // success completes the exact-key set above.
            MerianLog.data.debug(
                "processUploadCompletion: scanId=\(scanId, privacy: .public) waiting for sibling callback outcomes"
            )
            return
        }
        // Retry accounting belongs to the logical scan manifest, not an
        // individual file. The exact-key check above does not mutate durable
        // state; markScanAsStaged normally resets upload retry metadata in the
        // same save that commits the inference-ready transition. An exact
        // scheduled server-failure reclaim deliberately survives that save.
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            token: completionToken
        ) else {
            return
        }
        MerianLog.data.debug(
            "processUploadCompletion: scanId=\(scanId, privacy: .public) staging complete keys=\(r2Keys.count, privacy: .public)"
        )

        // Use the same shared actor as replayInferenceForUploadedScans so that
        // markScanAsStaged and tryClaimForInference are serialized on a single executor.
        // This closes the race where processUploadCompletion and replayInferenceForUploadedScans
        // could both see the scan in .staged and both dispatch concurrent inference tasks.
        let queueActor = resolvedQueueDbActor(container: extracted.container)
        let stagingOutcome = await queueActor.markScanAsStaged(
            scanId: scanId,
            r2Keys: r2Keys
        )
        switch stagingOutcome {
        case .staged, .alreadyAdvanced:
            clearUploadCompletionState(
                scanId: scanId,
                generation: uploadIdentity.syncGeneration
            )
        case .retryRequired:
            // Keep the exact successful-member set until the completion token
            // is released. The delegate envelope immediately replays from the
            // authoritative durable row: timestamp-fenced orphan recovery
            // resets a still-uploading row to pending and restarts signing,
            // while an already-staged row replays only its persisted keys.
            MerianLog.data.error(
                "processUploadCompletion: durable staging transition needs retry scanId=\(scanId, privacy: .private)"
            )
            return
        case .discarded:
            clearUploadCompletionState(
                scanId: scanId,
                generation: uploadIdentity.syncGeneration
            )
            MerianLog.data.debug(
                "processUploadCompletion: discarded non-runnable staging completion scanId=\(scanId, privacy: .private)"
            )
            return
        }
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            token: completionToken
        ) else {
            return
        }

        // The foreground request still owns identification for this
        // queue-backed live submission. Keep the durable row staged, but do not
        // dispatch a second Gemini call. Foreground failure/backgrounding
        // releases this claim and replay picks the staged row up immediately.
        if foregroundInferenceScanIds.contains(scanId) {
            MerianLog.data.debug(
                "processUploadCompletion: staged recovery media while foreground inference owns scanId=\(scanId, privacy: .public)"
            )
            return
        }

        // Atomically claim the scan for inference. If replayInferenceForUploadedScans already
        // claimed it between markScanAsStaged and here (same actor, so serialized), skip —
        // the replay path already dispatched the background download task.
        guard let preparationGeneration = await MainActor.run(body: {
            self.beginInferencePreparation(scanId: scanId)
        }) else {
            MerianLog.data.debug(
                "processUploadCompletion: preparation already active scanId=\(scanId, privacy: .public)"
            )
            return
        }
        let didClaimInference = await queueActor.tryClaimForInference(
            scanId: scanId,
            generation: preparationGeneration
        )
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadIdentity.syncGeneration,
            token: completionToken
        ) else {
            clearInferencePreparation(
                scanId: scanId,
                generation: preparationGeneration
            )
            return
        }
        if !didClaimInference {
            MerianLog.data.debug(
                "processUploadCompletion: inference claim skipped scanId=\(scanId, privacy: .public)"
            )
            await MainActor.run {
                self.clearInferencePreparation(
                    scanId: scanId,
                    generation: preparationGeneration
                )
            }
            return
        }
        MerianLog.data.debug(
            "processUploadCompletion: inference claimed scanId=\(scanId, privacy: .public)"
        )

        // Rebuild extracted with the confirmed R2 keys before dispatching.
        let extractedWithKeys = ExtractedScanData(
            telemetry: extracted.telemetry,
            r2Keys: r2Keys,
            container: extracted.container,
            originalTimestamp: extracted.originalTimestamp,
            capturedMediaItems: extracted.capturedMediaItems,
            inferenceImagePaths: extracted.inferenceImagePaths,
            visualMediaItemsJSON: extracted.visualMediaItemsJSON,
            preferredGoal: extracted.preferredGoal
        )
        await dispatchInferenceDownloadTask(
            scanId: scanId,
            extracted: extractedWithKeys,
            preparationGeneration: preparationGeneration
        )
    }

    // MARK: - Completion Helpers

    private func isUploadCompletionCurrent(
        scanId: String,
        generation: UUID?,
        token: UUID
    ) -> Bool {
        uploadCompletionTokens[scanId]?.contains(token) == true
            && isUploadGenerationCurrent(
                scanId: scanId,
                generation: generation
            )
    }

    /// Handles transport-level and HTTP-level upload errors.
    /// Returns `true` if an error was found and handled (caller should abort), `false` on success.
    private func handleUploadFallback(
        scanId: String,
        uploadError: Error?,
        responseStatusCode: Int?,
        uploadGeneration: UUID?,
        completionToken: UUID
    ) -> Bool {
        guard isUploadCompletionCurrent(
            scanId: scanId,
            generation: uploadGeneration,
            token: completionToken
        ) else {
            return true
        }
        let currentAttempt = queueAttemptCount(for: scanId)
        let disposition = OfflineQueueRetryPolicy.classifyUpload(
            error: uploadError,
            statusCode: responseStatusCode,
            currentAttempt: currentAttempt
        )

        switch disposition {
        case .success:
            recordQueueEvent(
                scanId: scanId,
                jobId: Self.scanIngestionJobId(scanId: scanId),
                kind: .uploadCompleted,
                message: "Queued scan media upload completed.",
                httpStatus: responseStatusCode
            )
            return false
        case .retry(let delay, let code, let message):
            let persistedAttempt = updateQueuedScanForRetry(
                scanId: scanId,
                code: code,
                message: message,
                httpStatus: responseStatusCode,
                delay: delay,
                resetTo: .pending
            )
            if let persistedAttempt {
                MerianLog.data.debug(
                    "handleUploadFallback: scheduled upload retry scanId=\(scanId, privacy: .private) attempt=\(persistedAttempt, privacy: .public) delay=\(String(format: "%.1f", delay), privacy: .public)s code=\(code, privacy: .public)"
                )
            } else {
                MerianLog.data.error(
                    "handleUploadFallback: retry persistence failed scanId=\(scanId, privacy: .private) delay=\(String(format: "%.1f", delay), privacy: .public)s code=\(code, privacy: .public)"
                )
            }
            return true
        case .needsAttention(let code, let message):
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: message,
                errorCode: code,
                httpStatus: responseStatusCode,
                needsAttention: true
            )
            return true
        case .terminal(let code, let message):
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: message,
                errorCode: code,
                httpStatus: responseStatusCode,
                needsAttention: false
            )
            return true
        case .waitForServer:
            return true
        }
    }

    /// Fetches the queued scan's snapshot and maps it to ExtractedScanData on the main actor.
    private func fetchScanMetadata(for scanId: String) async -> ExtractedScanData? {
        return await MainActor.run { () -> ExtractedScanData? in
            guard let context = modelContext else { return nil }
            let container = context.container
            var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
            descriptor.fetchLimit = 1
            let scan: OfflineQueuedScan?
            do {
                scan = try context.fetch(descriptor).first
            } catch {
                MerianLog.data.debug("urlSession: fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)")
                return nil
            }
            guard let scan else { return nil }
            return buildExtractedScanData(from: scan, container: container)
        }
    }
}
