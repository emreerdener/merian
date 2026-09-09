import Foundation

enum BackgroundInferencePreparationRace {
    enum Failure: Error {
        case timedOut
    }

    @MainActor
    static func firstValue<Value: Sendable>(
        timeout: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .seconds(30))
        },
        operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let stream = AsyncThrowingStream<Value, Error>(
            bufferingPolicy: .bufferingNewest(1)
        ) { continuation in
            let preparationTask = Task { @MainActor in
                do {
                    let value = try await operation()
                    continuation.yield(value)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            let timeoutTask = Task {
                do {
                    try await timeout()
                    continuation.finish(throwing: Failure.timedOut)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                preparationTask.cancel()
                timeoutTask.cancel()
            }
        }

        var iterator = stream.makeAsyncIterator()
        guard let value = try await iterator.next() else {
            throw CancellationError()
        }
        try Task.checkCancellation()
        return value
    }
}

// MARK: - Background Inference Dispatch

extension OfflineQueueManager {
    /// Builds an authenticated request from durable queued telemetry and dispatches it as a
    /// background URLSession download task so inference results arrive while the app is suspended.
    ///
    /// Task description carries both scan ID and a UUID generation so stale delegate,
    /// watchdog, and retry paths cannot act on a replacement attempt.
    func dispatchInferenceDownloadTask(
        scanId: String,
        extracted: ExtractedScanData,
        preparationGeneration: UUID
    ) async {
        var ownsInferenceGeneration = false
        var didDispatch = false
        var mustPreserveDurableInferenceOwnership = false
        defer {
            clearInferencePreparation(
                scanId: scanId,
                generation: preparationGeneration
            )
            if ownsInferenceGeneration,
               !didDispatch,
               !mustPreserveDurableInferenceOwnership {
                finishInferenceGeneration(
                    scanId: scanId,
                    generation: preparationGeneration
                )
            }
        }
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              isInferencePreparationCurrent(
                scanId: scanId,
                generation: preparationGeneration
              ) else {
            return
        }
        MerianLog.data.debug(
            "dispatchInferenceDownloadTask: requested scanId=\(scanId, privacy: .public) r2Keys=\(extracted.r2Keys.count, privacy: .public)"
        )

        let existingInferenceTasks = await backgroundSession.allTasks
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              isInferencePreparationCurrent(
                scanId: scanId,
                generation: preparationGeneration
              ) else {
            return
        }
        if existingInferenceTasks.contains(where: { isLiveInferenceTask($0, scanId: scanId) }) {
            MerianLog.data.debug("dispatchInferenceDownloadTask: inference task already active for \(scanId, privacy: .private); skipping duplicate dispatch")
            return
        }
        guard claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: preparationGeneration
        ) != nil else {
            return
        }
        ownsInferenceGeneration = true

        // The app may have backgrounded or relaunched after the foreground body
        // reached Edge but before its response returned. Consult the durable
        // ingestion ledger before starting recovery inference so the two paths
        // cannot normally issue a second primary Gemini call. If the status
        // endpoint itself is unavailable, preserve zero-data-loss behavior by
        // allowing the queued recovery request to proceed.
        let hasScheduledServerFailureRetry: Bool
        do {
            hasScheduledServerFailureRetry = try
                hasDurableScheduledServerFailureRetry(scanId: scanId)
        } catch {
            MerianLog.data.error(
                "dispatchInferenceDownloadTask: durable authority fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return
        }
        let serverRecovery = await recoverCompletedInferenceFromServer(
            scanId: scanId,
            reason: "pre-background-inference dispatch",
            expectedGeneration: preparationGeneration,
            reuseScheduledServerFailureRetry:
                hasScheduledServerFailureRetry
        )
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              isInferencePreparationCurrent(
                scanId: scanId,
                generation: preparationGeneration
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: preparationGeneration
              ) else {
            return
        }
        guard BackgroundInferencePolicy.scanStatusActionPermitsInferenceDispatch(
            serverRecovery,
            hasScheduledServerFailureRetry:
                hasScheduledServerFailureRetry
        ) else {
            MerianLog.data.debug(
                "dispatchInferenceDownloadTask: server owns or completed scanId=\(scanId, privacy: .public); skipping duplicate inference"
            )
            return
        }

        let authenticatedRequest: AuthenticatedInferenceRequest
        do {
            authenticatedRequest = try await prepareInferenceDownloadRequestWithTimeout(
                scanId: scanId,
                extracted: extracted
            )
        } catch MerianError.aiConsentRequired {
            do {
                try ConsentManager.shared
                    .requireCurrentConsentReapprovalAfterServerRejection()
            } catch {
                MerianLog.auth.error(
                    "Queued inference consent reapproval could not be persisted; the in-memory gate remains closed: \(error.localizedDescription, privacy: .private)"
                )
            }
            MerianLog.data.debug(
                "dispatchInferenceDownloadTask: consent reapproval required before dispatch scanId=\(scanId, privacy: .private)"
            )
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: BackgroundInferencePolicy.requiredConsentAttentionMessage,
                errorCode: "ai_consent_required",
                needsAttention: true
            )
            return
        } catch BackgroundInferencePreparationRace.Failure.timedOut {
            MerianLog.data.error(
                "dispatchInferenceDownloadTask: preparation timed out scanId=\(scanId, privacy: .public)"
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: preparationGeneration,
                reason: "pre-dispatch timeout"
            )
            return
        } catch is CancellationError {
            MerianLog.data.error(
                "dispatchInferenceDownloadTask: preparation cancelled scanId=\(scanId, privacy: .public)"
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: preparationGeneration,
                reason: "pre-dispatch cancelled"
            )
            return
        } catch {
            MerianLog.data.error("dispatchInferenceDownloadTask: failed to build request for \(scanId, privacy: .private): \(error, privacy: .private)")
            await handleInferenceRetry(
                scanId: scanId,
                generation: preparationGeneration,
                reason: "request build failed"
            )
            return
        }
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              isInferencePreparationCurrent(
                scanId: scanId,
                generation: preparationGeneration
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: preparationGeneration
              ) else {
            return
        }

        guard let accountWorkLease = try? SupabaseManager.shared
            .beginUnownedAccountBoundWork(
                expectedUserID: authenticatedRequest.expectedAuthUserID
            ) else {
            return
        }
        var transferredAccountWorkLease = false
        defer {
            if !transferredAccountWorkLease {
                SupabaseManager.shared.finishAccountBoundWork(
                    accountWorkLease
                )
            }
        }

        // Dispatch the background download task. The OS serializes the URLRequest (including
        // httpBody) at resume() time — safe to use inline httpBody on background sessions.
        let tasksBeforeDispatch = await backgroundSession.allTasks
        guard authenticatedRequest.isBound(to: accountWorkLease.session),
              allowsAutomaticNetworkWorkOnCurrentPath,
              SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(
                accountWorkLease
              ),
              isInferencePreparationCurrent(
                scanId: scanId,
                generation: preparationGeneration
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: preparationGeneration
              ) else {
            return
        }
        if tasksBeforeDispatch.contains(where: { isLiveInferenceTask($0, scanId: scanId) }) {
            MerianLog.data.debug("dispatchInferenceDownloadTask: inference task appeared for \(scanId, privacy: .private); skipping duplicate dispatch")
            return
        }

        let durableOwnership = BackgroundAccountWorkOwnership(
            ownerUserID: authenticatedRequest.expectedAuthUserID,
            generation: preparationGeneration,
            phase: .inference
        )
        let queueActor = resolvedQueueDbActor(
            container: extracted.container
        )
        guard await queueActor.activateBackgroundAccountWork(
            scanId: scanId,
            ownership: durableOwnership
        ) else {
            return
        }

        let task = backgroundSession.downloadTask(
            with: authenticatedRequest.request
        )
        task.taskDescription = InferenceURLSessionTaskContract.taskDescription(
            scanId: scanId,
            generation: preparationGeneration,
            ownerUserID: authenticatedRequest.expectedAuthUserID
        )
        guard SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(
            accountWorkLease
        ), retainBackgroundAccountWork(
            accountWorkLease,
            for: task.taskIdentifier
        ) else {
            // Durable ownership was already moved to `.inferencing`, but this
            // unresumed task is not guaranteed to receive a terminal delegate
            // callback. Requeue it before cancellation so relaunch cannot find
            // a permanently stranded inference owner.
            let didRetire = await Self.awaitDurableBackgroundWorkRetirement(
                retire: {
                    await self.retireRejectedBackgroundAccountWork(
                        scanId: scanId,
                        generation: preparationGeneration,
                        ownerUserID:
                            authenticatedRequest.expectedAuthUserID,
                        phase: .inference
                    )
                },
                waitBeforeRetry: {
                    await Self
                        .waitForDurableBackgroundWorkRetirementRetry()
                }
            )
            if didRetire {
                task.cancel()
            } else {
                // Keep process-local state aligned with the durable
                // `.inferencing` owner. The suspended task remains available
                // to a later Auth-transition sweep or relaunch recovery.
                mustPreserveDurableInferenceOwnership = true
            }
            return
        }
        transferredAccountWorkLease = true
        inferenceDispatchDates[scanId] = Date()
        didDispatch = true
        task.resume()
        scheduleInferenceStatusProbe(
            scanId: scanId,
            generation: preparationGeneration
        )

        MerianLog.data.debug("🚀 BACKGROUND INFERENCE: Dispatched download task for \(scanId, privacy: .public)")
    }

    private func prepareInferenceDownloadRequestWithTimeout(
        scanId: String,
        extracted: ExtractedScanData
    ) async throws -> AuthenticatedInferenceRequest {
        try await BackgroundInferencePreparationRace.firstValue {
            try await self.buildInferenceDownloadRequest(
                scanId: scanId,
                extracted: extracted
            )
        }
    }

    private func buildInferenceDownloadRequest(
        scanId: String,
        extracted: ExtractedScanData
    ) async throws -> AuthenticatedInferenceRequest {
        MerianLog.data.debug(
            "dispatchInferenceDownloadTask: building request scanId=\(scanId, privacy: .public)"
        )

        // All scans natively route through the unified /identify-multimodal endpoint,
        // securely supporting arrays over legacy properties.
        let audioPaths = extracted.audioFilePaths ?? []
        let videoPaths = extracted.videoFilePaths ?? []
        let stagedKeys = MediaStagingContract.splitObjectKeys(
            extracted.r2Keys,
            scanId: scanId,
            localImagePaths: extracted.localImagePaths,
            localAudioPaths: audioPaths,
            localVideoPaths: videoPaths
        )
        let visualMediaItems = extracted.visualMediaItems
        let validVisualMediaItems = visualMediaItems?.count == extracted.localImagePaths.count
            ? visualMediaItems
            : nil
        let videoFrameCount = validVisualMediaItems?
            .filter { $0.kind == .videoFrame }
            .count ?? (videoPaths.isEmpty ? nil : extracted.localImagePaths.count)
        let request = try await MerianNetworkClient.shared.buildMultiModalRequest(
            r2ObjectKeys: stagedKeys.imageR2ObjectKeys,
            audioR2ObjectKeys: stagedKeys.audioR2ObjectKeys,
            videoR2ObjectKeys: stagedKeys.videoR2ObjectKeys,
            base64ImageDatas: [], // Uploads rely purely on references through R2 object keys.
            audioFilePaths: stagedKeys.audioR2ObjectKeys.isEmpty ? audioPaths : [],
            videoFrameCount: videoFrameCount,
            visualMediaItems: validVisualMediaItems,
            audioMediaItems: extracted.audioMediaItems,
            ownerMediaTimeline: extracted.ownerMediaTimeline,
            observationContextsJSON: extracted.observationContextsJSON ?? [],
            telemetry: extracted.telemetry,
            clientScanId: scanId,
            preferredGoal: extracted.preferredGoal
        )
        MerianLog.data.debug(
            "dispatchInferenceDownloadTask: built request scanId=\(scanId, privacy: .public) imageKeys=\(stagedKeys.imageR2ObjectKeys.count, privacy: .public) audioKeys=\(stagedKeys.audioR2ObjectKeys.count, privacy: .public) videoKeys=\(stagedKeys.videoR2ObjectKeys.count, privacy: .public)"
        )
        return request
    }
}
