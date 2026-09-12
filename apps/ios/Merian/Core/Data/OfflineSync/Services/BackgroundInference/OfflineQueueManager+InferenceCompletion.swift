import Foundation

extension OfflineQueueManager {
    // MARK: - Inference Result Processing

    /// Processes the JSON file delivered by a completed background inference download task.
    ///
    /// Mirrors the success/failure routing of the former `runInferencePipeline`:
    /// - exact handler-owned policy rejection → terminal tombstone
    /// - consent rejection → preserve media and return to required disclosure
    /// - other handler-owned HTTP 4xx → preserve media for retry/cancel
    /// - Supabase platform route 404 / HTTP 5xx / missing data → durable retry
    /// - HTTP 200 → persist `LocalScanRecord`, delete `OfflineQueuedScan`, fire notifications
    func processInferenceDownloadResult(
        scanId: String,
        generation proposedGeneration: UUID?,
        resultFileURL: URL,
        statusCode: Int?,
        functionRouteEvidence: EdgeFunctionRouteResponseEvidence? = nil
    ) async {
        defer { try? FileManager.default.removeItem(at: resultFileURL) }
        guard let generation = claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: proposedGeneration
        ) else {
            MerianLog.data.debug(
                "processInferenceDownloadResult: ignored stale result scanId=\(scanId, privacy: .public)"
            )
            return
        }
        defer {
            finishInferenceGeneration(scanId: scanId, generation: generation)
        }

        inferenceCompletionGenerations[scanId] = generation
        defer {
            if inferenceCompletionGenerations[scanId] == generation {
                inferenceCompletionGenerations[scanId] = nil
                MerianLog.data.debug(
                    "processInferenceDownloadResult: cleared inference completion lock scanId=\(scanId, privacy: .public)"
                )
            } else {
                MerianLog.data.debug(
                    "processInferenceDownloadResult: preserved replacement inference completion lock scanId=\(scanId, privacy: .public)"
                )
            }
        }
        cancelInferenceStatusProbe(
            scanId: scanId,
            generation: generation
        )
        MerianLog.data.debug(
            "processInferenceDownloadResult: scanId=\(scanId, privacy: .public) status=\(statusCode ?? -1, privacy: .public) file=\(resultFileURL.path, privacy: .private)"
        )

        let resultData = try? Data(contentsOf: resultFileURL)
        let responseDisposition =
            BackgroundInferencePolicy.backgroundInferenceResponseDisposition(
            statusCode: statusCode,
            functionRouteEvidence: functionRouteEvidence,
            responseData: resultData ?? Data()
        )

        switch responseDisposition {
        case .success:
            break
        case .retry:
            let code = statusCode ?? 0
            MerianLog.data.debug(
                "Background inference returned a retryable response [\(code)] for \(scanId, privacy: .private) — preserving scan."
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: generation,
                reason: "Retryable inference response",
                minimumRetryDelay: functionRouteEvidence?.retryAfterSeconds
            )
            return
        case .consentRequired:
            do {
                try ConsentManager.shared
                    .requireCurrentConsentReapprovalAfterServerRejection()
            } catch {
                MerianLog.auth.error(
                    "Background inference consent reapproval could not be persisted; the in-memory gate remains closed: \(error.localizedDescription, privacy: .private)"
                )
            }
            MerianLog.data.debug(
                "Background inference requires consent reapproval for \(scanId, privacy: .private) — preserving queued media."
            )
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: BackgroundInferencePolicy.requiredConsentAttentionMessage,
                errorCode: "ai_consent_required",
                httpStatus: statusCode,
                needsAttention: true
            )
            return
        case .needsAttention:
            let code = statusCode ?? 0
            if statusCode == 402 {
                EntitlementManager.shared
                    .invalidateComplimentaryProofAfterPaymentRequired()
                await EntitlementManager.shared.refreshCurrentSession()
            }
            MerianLog.data.debug(
                "Background inference needs user attention [\(code)] for \(scanId, privacy: .private) — preserving queued media."
            )
            await MainActor.run {
                _ = OfflineQueueManager.shared.softDeleteQueuedScan(
                    scanId: scanId,
                    reason: "We couldn’t process this queued observation. Please retry it or cancel it.",
                    errorCode: EdgeFunctionErrorPolicy.stableCode(
                        responseData: resultData ?? Data()
                    ) ?? "inference_http_\(code)",
                    httpStatus: statusCode,
                    needsAttention: true
                )
            }
            return
        case .terminal:
            let code = statusCode ?? 0
            MerianLog.data.debug(
                "Background inference was rejected by policy [\(code)] for \(scanId, privacy: .private)."
            )
            await MainActor.run {
                _ = OfflineQueueManager.shared.softDeleteQueuedScan(
                    scanId: scanId,
                    reason: "We couldn’t process this observation. Please try a different photo or recording.",
                    errorCode: "observation_rejected",
                    httpStatus: statusCode,
                    needsAttention: false
                )
            }
            return
        }

        guard let resultData, !resultData.isEmpty else {
            MerianLog.data.error("Background inference download: result file unreadable for \(scanId, privacy: .private)")
            await handleInferenceRetry(
                scanId: scanId,
                generation: generation,
                reason: "empty response file"
            )
            return
        }

        // Fetch the latest durable scan snapshot so finalization uses the telemetry
        // persisted before background task dispatch.
        let extracted: ExtractedScanData?
        do {
            extracted = try extractedQueuedScanData(scanId: scanId)
        } catch {
            MerianLog.data.error(
                "Background inference: durable snapshot fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: generation,
                reason: "Durable inference snapshot could not be read"
            )
            return
        }

        guard let extracted else {
            // Scan was already cleaned up (e.g., live path completed first). Nothing to do.
            MerianLog.data.debug("Background inference: scan \(scanId, privacy: .private) already removed — skipping cleanup")
            return
        }

        let pipelineStart = CFAbsoluteTimeGetCurrent()
        await MainActor.run {
            SyncStateManager.shared.beginFinalizing(generation: generation)
        }

        // Use a fresh actor so a failed atomic save doesn't corrupt the shared actor's context.
        let cleanupActor = BackgroundDatabaseActor(
            modelContainer: extracted.container
        )
        let processingResult = await BackgroundInferenceFinalizationService.live
            .processAndCleanupOfflineScan(
                resultData: resultData,
                originalImagePaths: extracted.localImagePaths,
                scanId: scanId,
                originalTimestamp: extracted.originalTimestamp,
                telemetry: extracted.telemetry,
                observationContextsJSON: extracted.observationContextsJSON,
                audioFilePaths: extracted.audioFilePaths,
                videoFilePaths: extracted.videoFilePaths,
                capturedMediaJSON: extracted.capturedMediaJSON,
                expectedGeneration: generation,
                persistenceActor: cleanupActor
            )

        guard isInferenceGenerationCurrent(
            scanId: scanId,
            expectedGeneration: generation
        ) else {
            MerianLog.data.debug(
                "processInferenceDownloadResult: ownership changed during finalization scanId=\(scanId, privacy: .public)"
            )
            return
        }
        guard processingResult.wasCleaned else {
            MerianLog.data.error(
                "processInferenceDownloadResult: local persistence rejected response scanId=\(scanId, privacy: .public)"
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: generation,
                reason: "Local inference persistence did not complete"
            )
            return
        }

        // Delete the OfflineQueuedScan from the main ModelContext so @Query re-evaluates in
        // any open sheet. The background actor intentionally left it alive (see wasCleaned doc);
        // this deletion guarantees the main context has a real pending change when it saves —
        // the only reliable @Query trigger in a presented sheet (SwiftData platform limitation).
        //
        // Route through deleteQueuedScan rather than flushOfflineQueuedScan so queue-only
        // inference frames can be purged while media adopted by the final LocalScanRecord survives.
        let didDeleteQueuedScan: Bool
        let adoptedMediaPaths = processingResult.finalScanId == nil
            ? []
            : extracted.capturedMediaSnapshot.thumbnailImagePaths
                + (extracted.audioFilePaths ?? [])
                + (extracted.videoFilePaths ?? [])
        didDeleteQueuedScan = await OfflineQueueManager.shared.deleteQueuedScan(
            scanId: scanId,
            explicitlyAdoptedMediaPaths: adoptedMediaPaths,
            preservePreferredGoalHint: true,
            inferenceExpectation: InferenceGenerationExpectation(
                generation: generation
            )
        )
        guard didDeleteQueuedScan else {
            MerianLog.data.error(
                "processInferenceDownloadResult: durable result saved but queue cleanup failed scanId=\(scanId, privacy: .public)"
            )
            await handleInferenceRetry(
                scanId: scanId,
                generation: generation,
                reason: "Completed inference queue cleanup did not commit"
            )
            return
        }

        if let speciesName = processingResult.resolvedSpeciesName,
           let dbScanId = processingResult.finalScanId {
            MerianLog.data.debug(
                "processInferenceDownloadResult: finalized scanId=\(scanId, privacy: .private) dbScanId=\(dbScanId, privacy: .private) species=\(speciesName, privacy: .private)"
            )
            let capturedContainer = extracted.container
            await MainActor.run {
                // Only set the badge when the insight sheet is not already open.
                // If suppressInferenceBanners is true the user is viewing results in the
                // sheet — the badge would appear and immediately need clearing on dismiss.
                if !AppSettings.shared.suppressInferenceBanners {
                    AppSettings.shared.hasUnseenScan = true
                    AppIconBadgeCoordinator.updateAppIconBadge()
                }
                if processingResult.isNewDiscovery {
                    GamificationManager.shared.recordNewSpeciesDiscovered()
                }
                if AppSettings.shared.isPushNotificationsEnabled {
                    PushNotificationManager.shared.sendInferenceCompleteNotification(speciesName: speciesName, scanId: dbScanId)
                }
                Task {
                    await AppDIContainer.shared.scanMilestoneCoordinator.processCompletedScan(
                        scanId: dbScanId,
                        speciesData: processingResult.speciesData,
                        modelContainer: capturedContainer,
                        preferredGoal: extracted.preferredGoal
                    )
                }

                // If the background path completed the same scan the live InferenceEngine is
                // currently processing, hydrate the engine directly. This fixes the case where
                // the user backgrounds the app immediately after capture: the live inference Task
                // is suspended (no BackgroundTaskWrapper protects it), the background URLSession
                // path races ahead and wins, but isProcessing stays true — leaving the insight
                // sheet in "Analyzing..." until the live task eventually times out and shows
                // "Network timeout" even though the scan completed successfully.
                //
                // The recovered-result commit first invalidates the exact live
                // presentation slot and publishes species data. Cooperative
                // cancellation happens afterward, so the old task's defer and
                // error handlers fail their generation check and become no-ops.
                if let speciesData = processingResult.speciesData {
                    let engine = AppDIContainer.shared.inferenceEngine
                    // Hydrate when the engine is still waiting for a result for this exact scan.
                    // `isProcessing` covers the case where the live path is still in flight.
                    // `engine.speciesData?.scanId == nil` covers the case where the live path
                    // already failed (timeout/network error) — those placeholders have scanId = nil.
                    // We must NOT overwrite a successful live result (speciesData.scanId != nil).
                    if engine.activeScanId == scanId,
                       engine.isProcessing || engine.speciesData?.scanId == nil,
                       let presentationGeneration =
                           engine.activeLiveInferenceAttemptGeneration {
                        let releasedForegroundGeneration =
                            engine.activeForegroundInferenceGeneration
                        let didHydrate =
                            engine.commitRecoveredBackgroundResult(
                                for: scanId,
                                replacingAttemptGeneration:
                                    presentationGeneration,
                                expectedForegroundGeneration:
                                    releasedForegroundGeneration,
                                speciesData: speciesData
                            )
                        if didHydrate {
                            engine.inferenceTask?.cancel()
                        }
                    } else if engine.commitRecoveredQueuedResult(
                        for: scanId,
                        speciesData: speciesData
                    ) {
                        engine.inferenceTask?.cancel()
                    }
                }
            }
        }

        guard isInferenceGenerationCurrent(
            scanId: scanId,
            expectedGeneration: generation
        ) else {
            MerianLog.data.debug(
                "processInferenceDownloadResult: skipped stale post-finalization state scanId=\(scanId, privacy: .public)"
            )
            return
        }
        MerianLog.data.debug("⏱️ Background pipeline total: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")
        await MainActor.run {
            CircuitBreakerManager.shared.recordSuccess()
        }
    }

    // MARK: - Inference Task Failure

    /// Handles a background inference download task network-level failure.
    ///
    /// Called from `urlSession(_:task:didCompleteWithError:)` when the download task fails
    /// with a transport error (the server never responded). Resets the scan to `.staged` after
    /// a persisted backoff window so app relaunches do not lose retry state.
    ///
    /// Code=-999 (NSURLErrorCancelled) is special-cased: it means an owner path explicitly
    /// cancelled the task. Either the parallel live inference path already succeeded, the user
    /// deleted the queued scan, or the inference watchdog reset the scan to `.staged`.
    func handleInferenceTaskNetworkFailure(
        scanId: String,
        generation proposedGeneration: UUID?,
        error: Error
    ) async {
        guard let generation = claimInferenceGeneration(
            scanId: scanId,
            proposedGeneration: proposedGeneration
        ) else {
            MerianLog.data.debug(
                "handleInferenceTaskNetworkFailure: ignored stale failure scanId=\(scanId, privacy: .public)"
            )
            return
        }
        defer {
            finishInferenceGeneration(scanId: scanId, generation: generation)
        }

        cancelInferenceStatusProbe(
            scanId: scanId,
            generation: generation
        )
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            MerianLog.data.debug("Background inference cancelled for \(scanId, privacy: .private) — owner path handled retry or cleanup")
            return
        }
        MerianLog.data.debug("Background inference download failed for \(scanId, privacy: .private): \(error, privacy: .private)")
        await handleInferenceRetry(
            scanId: scanId,
            generation: generation,
            reason: "network failure"
        )
    }

    private func cancelInferenceStatusProbe(
        scanId: String,
        generation: UUID
    ) {
        inferenceStatusProbeTasks.cancel(
            scanId,
            ifOwnedBy: generation
        )
        if activeInferenceGenerations[scanId] == generation {
            inferenceDispatchDates[scanId] = nil
        }
        MerianLog.data.debug("cancelInferenceStatusProbe: cancelled scanId=\(scanId, privacy: .public)")
    }
}
