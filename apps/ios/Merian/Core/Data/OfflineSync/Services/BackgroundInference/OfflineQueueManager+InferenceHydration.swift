import Foundation
import SwiftData

enum CompletedServerResultHydrationOutcome: Equatable, Sendable {
    case recovered
    case retryable
    case contractMismatch
    case clientUpdateRequired
}

extension OfflineQueueManager {
    // MARK: - Completed Server Result Hydration

    func recoverFoundScanFromServer(
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
        // Preserve server ownership and retry history until hydration, promotion, and queue deletion commit.
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

        if targetedSyncOutcome == .clientUpdateRequired { return .clientUpdateRequired }
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
        BackgroundScanNotificationService.live.notify(
            speciesName: recoveredLocalRecord.commonName,
            scanId: scanId
        )
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
