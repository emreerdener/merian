import Foundation
import SwiftData

private enum CompletedServerResultHydrationOutcome: Equatable, Sendable {
    case recovered
    case retryable
    case contractMismatch
}

extension OfflineQueueManager {
    // MARK: - Background Inference Server Recovery

    private func clearServerIngestionState(
        scanId: String,
        preservingPollToken: UUID? = nil
    ) {
        if preservingPollToken == nil {
            serverIngestionPollTasks.cancel(scanId)
        }
        scanIngestionJobStates[scanId] = nil
    }

    private func scheduleRetryableServerFailure(
        scanId: String,
        delay: TimeInterval,
        reason: String,
        expectedGeneration: UUID?,
        serverPollToken: UUID?,
        resetMediaUploads: Bool
    ) async {
        guard allowsAutomaticNetworkWorkOnCurrentPath,
              let container = modelContext?.container else {
            return
        }
        guard let authority = durableQueueAuthorityIfReadable(
            scanId: scanId,
            operation: "scheduleRetryableServerFailure"
        ) else { return }
        let currentAttempt = authority.maximumAttemptCount
        guard OfflineQueueRetryPolicy.canScheduleAutomaticRetry(
            currentAttempt: currentAttempt
        ) else {
            markQueuedScanNeedsAttention(
                scanId: scanId,
                code: "automatic_retry_limit_reached",
                message: OfflineQueueRetryPolicy.automaticRetryLimitMessage()
            )
            serverIngestionPollTasks.cancel(scanId)
            MerianLog.data.debug(
                "scheduleRetryableServerFailure: retry limit reached scanId=\(scanId, privacy: .public) attempts=\(currentAttempt, privacy: .public)"
            )
            return
        }
        let retryActor = resolvedQueueDbActor(container: container)
        guard let retries = await retryActor.scheduleInferenceRetry(
            id: scanId,
            expectedGeneration: expectedGeneration,
            code: Self.serverRetryableFailureCode,
            message: reason,
            delay: delay,
            resetMediaUploads: resetMediaUploads
        ) else {
            // Another serialized owner may already have committed the same
            // retreat, or a cloud-complete marker may have superseded it. Both
            // are expected coalescing outcomes, not an error worth repeating
            // on every library/scheduler wake.
            guard let authority = durableQueueAuthorityIfReadable(
                scanId: scanId,
                operation: "scheduleRetryableServerFailure"
            ) else { return }
            if authority.containsErrorCode(
                matching: Self.isServerRetryableFailureCode
            ) || authority.containsErrorCode(
                matching: Self.isCompletedServerResultRecoveryCode
            ) {
                return
            }
            MerianLog.data.debug(
                "scheduleRetryableServerFailure: persistence generation changed scanId=\(scanId, privacy: .public)"
            )
            return
        }
        OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
        guard !Task.isCancelled,
              allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(scanId: scanId, token: serverPollToken),
              isInferenceGenerationCurrent(
                  scanId: scanId, expectedGeneration: expectedGeneration
              ) else { return }
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

                guard !Task.isCancelled,
                      self.serverIngestionPollTasks.isCurrent(
                        scanId,
                        token: token
                      ),
                      self.activeInferenceGenerations[scanId] == nil else {
                    return
                }
                self.updateUnsyncedItemCount()
                if resetMediaUploads {
                    self.syncPendingScans()
                } else {
                    self.replayInferenceForUploadedScans()
                }
            }
        }
        MerianLog.data.debug(
            "scheduleRetryableServerFailure: scheduled scanId=\(scanId, privacy: .public) delay=\(String(format: "%.1f", delay), privacy: .public)s retry=\(retries, privacy: .public) reason=\(reason, privacy: .public)"
        )
    }

    func recoverCompletedInferenceFromServer(
        scanId: String,
        reason: String,
        expectedGeneration: UUID?,
        serverPollToken: UUID? = nil,
        reuseScheduledServerFailureRetry: Bool = false
    ) async -> ScanStatusRecoveryAction {
        guard let authority = durableQueueAuthorityIfReadable(
            scanId: scanId,
            operation: "recoverCompletedInferenceFromServer"
        ) else {
            return .waitForServer(1)
        }
        let hadDurableCompletedServerResult = authority.containsErrorCode(
            matching: Self.isCompletedServerResultRecoveryCode
        )
        let requiredVideoCount = authority.requiredVideoCount
        guard !Task.isCancelled,
              allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return hadDurableCompletedServerResult
                ? .waitForServer(1)
                : .unresolved
        }
        let response: ScanStatusResponse
        do {
            response = try await MerianNetworkClient.shared.checkScanStatusDetails(
                scanId: scanId,
                requiredVideoCount: requiredVideoCount
            )
        } catch {
            MerianLog.data.debug(
                "recoverCompletedInferenceFromServer: status check failed scanId=\(scanId, privacy: .public) reason=\(reason, privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            if hadDurableCompletedServerResult {
                return await deferCompletedServerResultRecovery(
                    scanId: scanId,
                    expectedGeneration: expectedGeneration,
                    serverPollToken: serverPollToken
                )
            }
            return .unresolved
        }

        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return response.isFound || hadDurableCompletedServerResult
                ? .waitForServer(1)
                : .unresolved
        }

        if let jobStatus = response.jobStatus {
            scanIngestionJobStates[scanId] = jobStatus
        } else {
            scanIngestionJobStates[scanId] = nil
        }
        persistServerStatus(scanId: scanId, response: response)

        let action = BackgroundInferencePolicy.scanStatusRecoveryAction(
            for: response
        )
        guard allowsAutomaticNetworkWorkOnCurrentPath else {
            // Keep exact completed-owner evidence persisted, but do not begin
            // another automatic network request or consume recovery budget
            // after a satisfied path becomes constrained.
            return response.isFound || hadDurableCompletedServerResult
                ? .waitForServer(1)
                : .unresolved
        }
        MerianLog.data.debug(
            "recoverCompletedInferenceFromServer: scanId=\(scanId, privacy: .public) reason=\(reason, privacy: .public) status=\(response.status.rawValue, privacy: .public) jobStatus=\((response.jobStatus?.rawValue ?? "nil"), privacy: .public) jobStage=\((response.jobStage ?? "nil"), privacy: .public) requiredVideos=\(requiredVideoCount, privacy: .public)"
        )
        guard let currentAuthority = durableQueueAuthorityIfReadable(
            scanId: scanId,
            operation: "recoverCompletedInferenceFromServer"
        ) else {
            return .waitForServer(1)
        }
        let stillHasDurableCompletedServerResult = currentAuthority
            .containsErrorCode(
                matching: Self.isCompletedServerResultRecoveryCode
            )
        if action != .recovered, stillHasDurableCompletedServerResult {
            // A prior exact-owner `found` observation is stronger than a later
            // unavailable or temporarily inconsistent status response. Keep
            // this row server-owned and bound recovery rather than allowing a
            // second inference dispatch.
            return await deferCompletedServerResultRecovery(
                scanId: scanId,
                expectedGeneration: expectedGeneration,
                serverPollToken: serverPollToken
            )
        }
        switch action {
        case .recovered:
            let hydrationOutcome = await recoverFoundScanFromServer(
                scanId: scanId,
                reason: reason,
                expectedGeneration: expectedGeneration,
                serverPollToken: serverPollToken
            )
            switch hydrationOutcome {
            case .recovered:
                return .recovered
            case .retryable:
                return await deferCompletedServerResultRecovery(
                    scanId: scanId,
                    expectedGeneration: expectedGeneration,
                    serverPollToken: serverPollToken
                )
            case .contractMismatch:
                let didPause = markCompletedServerResultContractMismatch(
                    scanId: scanId
                )
                guard didPause else {
                    return await deferCompletedServerResultRecovery(
                        scanId: scanId,
                        expectedGeneration: expectedGeneration,
                        serverPollToken: serverPollToken
                    )
                }
                clearServerIngestionState(
                    scanId: scanId,
                    preservingPollToken: serverPollToken
                )
                return .terminalFailure(
                    Self.completedServerResultContractMismatchMessage
                )
            }
        case .waitForServer(let delay):
            scheduleServerIngestionPoll(
                scanId: scanId,
                delay: delay,
                reason: "server ingestion poll"
            )
            return action
        case .retryAfter(let delay):
            if !reuseScheduledServerFailureRetry {
                await scheduleRetryableServerFailure(
                    scanId: scanId,
                    delay: delay,
                    reason: reason,
                    expectedGeneration: expectedGeneration,
                    serverPollToken: serverPollToken,
                    resetMediaUploads:
                        BackgroundInferencePolicy.requiresMediaRestagingAfterServerFailure(
                            response
                        )
                )
            } else {
                MerianLog.data.debug(
                    "recoverCompletedInferenceFromServer: exact scheduled retry is ready to reclaim failed server attempt scanId=\(scanId, privacy: .public)"
                )
            }
            return action
        case .terminalFailure(let message):
            MerianLog.data.debug(
                "recoverCompletedInferenceFromServer: terminal server failure scanId=\(scanId, privacy: .public) message=\((message ?? "nil"), privacy: .private)"
            )
            _ = softDeleteQueuedScan(
                scanId: scanId,
                reason: message,
                errorCode: "server_terminal_failure",
                needsAttention: true
            )
            clearServerIngestionState(
                scanId: scanId,
                preservingPollToken: serverPollToken
            )
            return action
        case .unresolved:
            return .unresolved
        }
    }

    private func recoverFoundScanFromServer(
        scanId: String,
        reason: String,
        expectedGeneration: UUID?,
        serverPollToken: UUID?
    ) async -> CompletedServerResultHydrationOutcome {
        guard !Task.isCancelled,
              allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return .retryable
        }
        // A server-side completion is not yet a local recovery success. Keep
        // both its latest status and persisted retry/backoff history until the
        // result has been hydrated, promoted, and the queue row has been
        // deleted. Clearing either here made a failed local sync look like a
        // fresh attempt and discarded useful recovery state.
        let targetedSyncOutcome: HistoricalScanDownOutcome
        if let context = modelContext {
            targetedSyncOutcome = await AppDIContainer.shared.scanRepository.syncHistoricalScanDown(
                scanId: scanId,
                modelContext: context
            )
        } else {
            targetedSyncOutcome = .transientFailure
        }

        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return .retryable
        }

        guard targetedSyncOutcome != .contractMismatch else {
            MerianLog.data.error(
                "recoverCompletedInferenceFromServer: completed cloud row violates the captured-media contract scanId=\(scanId, privacy: .public)"
            )
            return .contractMismatch
        }

        var recoveredLocalRecord = promoteRecoveredLocalScan(scanId: scanId)
        if recoveredLocalRecord == nil,
           targetedSyncOutcome != .reconciled,
           let context = modelContext {
            guard allowsAutomaticNetworkWorkOnCurrentPath else {
                return .retryable
            }
            await AppDIContainer.shared.scanRepository.syncHistoricalScansDown(
                modelContext: context
            )
            guard !Task.isCancelled,
                  isServerIngestionPollCurrent(
                      scanId: scanId,
                      token: serverPollToken
                  ),
                  isInferenceGenerationCurrent(
                      scanId: scanId,
                      expectedGeneration: expectedGeneration
                  ) else {
                return .retryable
            }
            AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
            recoveredLocalRecord = promoteRecoveredLocalScan(scanId: scanId)
        }
        guard let recoveredLocalRecord else {
            MerianLog.data.debug(
                "recoverCompletedInferenceFromServer: server found scan but no local record after targeted/full sync scanId=\(scanId, privacy: .public) targetedOutcome=\(String(describing: targetedSyncOutcome), privacy: .public)"
            )
            return .retryable
        }

        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return .retryable
        }

        let didDeleteQueue = await deleteQueuedScan(
            scanId: scanId,
            preservePreferredGoalHint: true,
            inferenceExpectation: InferenceGenerationExpectation(
                generation: expectedGeneration
            ),
            serverPollTokenToPreserve: serverPollToken
        )
        guard didDeleteQueue else {
            MerianLog.data.debug(
                "recoverCompletedInferenceFromServer: queue deletion lost ownership or failed scanId=\(scanId, privacy: .public)"
            )
            return .retryable
        }
        do {
            let preferredGoal = try modelContext?.preferredGoalHint(
                scanId: scanId
            )
            await AppDIContainer.shared.scanMilestoneCoordinator
                .processCompletedScan(
                    scanId: scanId,
                    speciesData: nil,
                    modelContainer: modelContext?.container,
                    preferredGoal: preferredGoal
                )
        } catch {
            MerianLog.data.error(
                "recoverCompletedInferenceFromServer: preferred goal fetch failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
        }
        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return .retryable
        }
        updateUnsyncedItemCount()
        AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
        let didHydratePresentedResult =
            AppDIContainer.shared.inferenceEngine.commitRecoveredQueuedRecord(
                recoveredLocalRecord,
                for: scanId
            )
        MerianLog.data.debug(
            "recoverCompletedInferenceFromServer: recovered scanId=\(scanId, privacy: .public) targetedOutcome=\(String(describing: targetedSyncOutcome), privacy: .public) promotedLocal=true deletedQueue=\(didDeleteQueue, privacy: .public) hydratedPresentation=\(didHydratePresentedResult, privacy: .public)"
        )

        return .recovered
    }

    private func deferCompletedServerResultRecovery(
        scanId: String,
        expectedGeneration: UUID?,
        serverPollToken: UUID?
    ) async -> ScanStatusRecoveryAction {
        guard !Task.isCancelled,
              allowsAutomaticNetworkWorkOnCurrentPath,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            // The definitive server result still makes a second provider
            // dispatch unsafe. A replacement owner will continue recovery.
            return .waitForServer(1)
        }

        guard let authority = durableQueueAuthorityIfReadable(
            scanId: scanId,
            operation: "deferCompletedServerResultRecovery"
        ) else {
            return .waitForServer(1)
        }
        let currentAttempt = authority.maximumAttemptCount
        guard OfflineQueueRetryPolicy.canScheduleAutomaticRetry(
            currentAttempt: currentAttempt
        ) else {
            let message = [
                "Naturebook found this completed analysis in the cloud but",
                "could not restore it on this device after several attempts.",
                "You can retry manually when the connection is stable."
            ].joined(separator: " ")
            markQueuedScanNeedsAttention(
                scanId: scanId,
                code: "server_result_local_recovery_exhausted",
                message: message
            )
            return .terminalFailure(message)
        }

        let delay = OfflineQueueRetryPolicy.jitteredDelay(
            forAttempt: currentAttempt + 1
        )
        let retryMessage =
            Self.completedServerResultRecoveryMessage
        if let container = modelContext?.container {
            let retryActor = resolvedQueueDbActor(container: container)
            let retries = await retryActor.scheduleServerResultRecoveryRetry(
                id: scanId,
                expectedGeneration: expectedGeneration,
                code: Self.completedServerResultRecoveryCode,
                message: retryMessage,
                delay: delay
            )
            if let retries {
                MerianLog.data.debug(
                    "deferCompletedServerResultRecovery: scheduled scanId=\(scanId, privacy: .public) retry=\(retries, privacy: .public)"
                )
                OfflineJobScheduler.shared.scheduleNextPersistedWake(using: self)
            } else {
                MerianLog.data.debug(
                    "deferCompletedServerResultRecovery: durable owner changed or retry save failed scanId=\(scanId, privacy: .public)"
                )
            }
        }

        guard !Task.isCancelled,
              isServerIngestionPollCurrent(
                  scanId: scanId,
                  token: serverPollToken
              ),
              isInferenceGenerationCurrent(
                  scanId: scanId,
                  expectedGeneration: expectedGeneration
              ) else {
            return .waitForServer(delay)
        }
        scheduleServerIngestionPoll(
            scanId: scanId,
            delay: delay,
            reason: "completed cloud result local recovery"
        )
        return .waitForServer(delay)
    }

    private func promoteRecoveredLocalScan(
        scanId: String
    ) -> LocalScanRecord? {
        guard let context = modelContext else { return nil }
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let record: LocalScanRecord?
        do {
            record = try context.fetch(descriptor).first
        } catch {
            MerianLog.data.debug(
                "promoteRecoveredLocalScan: fetch failed scanId=\(scanId, privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
        guard let record else { return nil }
        if record.captureDate == nil {
            record.captureDate = record.timestamp
        }
        record.timestamp = Date()
        do {
            try context.save()
            MerianLog.data.debug("promoteRecoveredLocalScan: promoted scanId=\(scanId, privacy: .public)")
            return record
        } catch {
            context.rollback()
            MerianLog.data.error(
                "promoteRecoveredLocalScan: save failed scanId=\(scanId, privacy: .public) error=\(error.localizedDescription, privacy: .private)"
            )
            return nil
        }
    }
}
