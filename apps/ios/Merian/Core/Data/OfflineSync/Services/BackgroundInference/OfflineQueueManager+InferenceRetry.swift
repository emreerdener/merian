import Foundation

// MARK: - Background Inference Retry and Poll Lifetime

extension OfflineQueueManager {
    func isServerIngestionPollCurrent(
        scanId: String,
        token: UUID?
    ) -> Bool {
        guard let token else { return true }
        return serverIngestionPollTasks.isCurrent(
            scanId,
            token: token
        )
    }

    func scheduleServerIngestionPoll(
        scanId: String,
        delay: TimeInterval,
        reason: String
    ) {
        serverIngestionPollTasks.replace(
            for: scanId,
            ownerGeneration: nil
        ) { [weak self] token in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    _ = self.serverIngestionPollTasks.clearIfCurrent(
                        scanId,
                        token: token
                    )
                }
                let nanoseconds = UInt64(max(1, delay) * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                guard self.serverIngestionPollTasks.isCurrent(
                    scanId,
                    token: token
                ),
                self.activeInferenceGenerations[scanId] == nil,
                self.allowsAutomaticNetworkWorkOnCurrentPath else {
                    return
                }
                await self.handleInferenceRetry(
                    scanId: scanId,
                    generation: nil,
                    reason: reason,
                    serverPollToken: token
                )
            }
        }
        MerianLog.data.debug(
            "scheduleServerIngestionPoll: scheduled scanId=\(scanId, privacy: .public) delay=\(String(format: "%.1f", delay), privacy: .public)s reason=\(reason, privacy: .public)"
        )
    }

    /// Records durable retry metadata for a scan after the persisted backoff
    /// window. Transient inference failures retreat to `.staged`; a definitive
    /// cloud result stays `.inferencing` and retries only owner-result recovery.
    ///
    /// Before retrying, polls `/check-scan-status` to detect the outbox gap: if the edge
    /// function already persisted the scan but the background download task never delivered
    /// the response, a naive retry would re-run inference and insert a duplicate row. When
    /// the scan is found server-side, targeted historical sync restores the `LocalScanRecord`
    /// and the queue entry is deleted.
    func handleInferenceRetry(
        scanId: String,
        generation: UUID?,
        reason: String = "retry",
        serverPollToken: UUID? = nil,
        minimumRetryDelay: TimeInterval? = nil
    ) async {
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(
            scanId: scanId,
            token: serverPollToken
        ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: generation
              ) else {
            return
        }
        guard let container = modelContext?.container else { return }

        let recoveryAction = await recoverCompletedInferenceFromServer(
            scanId: scanId,
            reason: reason,
            expectedGeneration: generation,
            serverPollToken: serverPollToken
        )
        guard !Task.isCancelled,
              allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ) else {
            return
        }
        if recoveryAction != .unresolved {
            return
        }
        guard isInferenceGenerationCurrent(
            scanId: scanId,
            expectedGeneration: generation
        ) else {
            return
        }

        let currentAttempt: Int
        do {
            currentAttempt = try queueAttemptCount(for: scanId)
        } catch {
            MerianLog.data.error(
                "handleInferenceRetry: durable attempt fetch failed for \(scanId, privacy: .private): \(error, privacy: .private)"
            )
            return
        }
        guard OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: currentAttempt) else {
            markQueuedScanNeedsAttention(
                scanId: scanId,
                code: "automatic_retry_limit_reached",
                message: OfflineQueueRetryPolicy.automaticRetryLimitMessage()
            )
            MerianLog.data.debug(
                "Inference retry limit reached for \(scanId, privacy: .private) after \(currentAttempt, privacy: .public) attempts"
            )
            return
        }

        let delay = OfflineQueueRetryPolicy.scanRetryDelay(
            forAttempt: currentAttempt + 1,
            serverMinimumDelay: minimumRetryDelay
        )
        let retryActor = resolvedQueueDbActor(container: container)
        guard let retries = await retryActor.scheduleInferenceRetry(
            id: scanId,
            expectedGeneration: generation,
            code: "inference_retry",
            message: reason,
            delay: delay
        ) else {
            MerianLog.data.debug(
                "handleInferenceRetry: persistence generation changed scanId=\(scanId, privacy: .public)"
            )
            return
        }
        // The actor has committed the authoritative retry date. Restore its
        // central wake before consulting process-local cancellation or owner
        // state so a replaced callback cannot strand durable work.
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: generation
              ) else {
            return
        }
        MerianLog.data.debug("Inference failed for \(scanId, privacy: .private) — scheduled durable retry \(retries, privacy: .public) reason=\(reason, privacy: .private)")
        updateUnsyncedItemCount()
        inferenceRetryTasks.replace(
            for: scanId,
            ownerGeneration: nil
        ) { [weak self] token in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard self.inferenceRetryTasks.clearIfCurrent(
                    scanId,
                    token: token
                ),
                self.activeInferenceGenerations[scanId] == nil else {
                    return
                }
                self.replayInferenceForUploadedScans()
            }
        }
    }
}
