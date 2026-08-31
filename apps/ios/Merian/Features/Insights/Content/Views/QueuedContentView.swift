import SwiftData
import SwiftUI

/// Shown inside `InsightSheetView` when the sheet is presenting an `OfflineQueuedScan`
/// resting in the background-upload batch queue.
///
/// Queue lifecycle and recovery remain isolated here, while the visible scanning
/// experience is shared with foreground analysis through `ScanningExperienceView`.
struct QueuedContentView: View {
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: InsightSheetViewModel

    let queuedContext: QueuedScanContext
    @State private var operationViewModel: QueuedContentViewModel
    @State private var phaseIndex = 0
    @State private var retryReferenceDate = Date()

    init(
        viewModel: InsightSheetViewModel,
        queuedContext: QueuedScanContext,
        dependencies: QueuedContentDependencies? = nil
    ) {
        self.viewModel = viewModel
        self.queuedContext = queuedContext
        _operationViewModel = State(
            initialValue: QueuedContentViewModel(dependencies: dependencies)
        )
    }

    private var serverJobStatus: ScanIngestionJobStatus? {
        offlineQueueManager.scanIngestionJobStates[queuedContext.id]
    }

    private var queuedScanHasVideo: Bool {
        !queuedContext.capturedMediaSnapshot.videoPaths.isEmpty
    }

    /// True when this queued view replaced the live analyzing sheet after the
    /// foreground request lost connectivity or relinquished ownership.
    private var isLiveQueueHandoff: Bool {
        inferenceEngine.hasLiveVisualQueueHandoff(for: queuedContext.id)
    }

    private var phaseRotationID: QueuedScanningPresentation.RotationID {
        QueuedScanningPresentation.rotationID(
            scanID: queuedContext.id,
            isLiveVisualHandoff: isLiveQueueHandoff,
            queueState: queuedContext.queueState,
            isOnline: offlineQueueManager.isOnline,
            serverJobStatus: serverJobStatus,
            needsAttention: queuedContext.queueNeedsAttention,
            hasScheduledRetry: queuedContext.queueNextRetryAt != nil
        )
    }

    /// Honest queue-aware phases presented through the same rotating badge used
    /// by foreground analysis.
    private var scanningPhasePhrases: [String] {
        QueuedScanningPresentation.phrases(
            queueState: queuedContext.queueState,
            isOnline: offlineQueueManager.isOnline,
            serverJobStatus: serverJobStatus,
            needsAttention: queuedContext.queueNeedsAttention,
            hasScheduledRetry: queuedContext.queueNextRetryAt != nil,
            hasVideo: queuedScanHasVideo,
            isLiveVisualHandoff: isLiveQueueHandoff,
            contextualPhrases: inferenceEngine.liveQueueHandoffScanningPhrases(
                for: queuedContext.id
            ),
            genericPhrases: InferenceEngine.genericScanningPhasePhrases
        )
    }

    private var badgePhrase: String {
        guard !scanningPhasePhrases.isEmpty else {
            return "Scanning subject"
        }
        return scanningPhasePhrases[phaseIndex % scanningPhasePhrases.count]
    }

    private var retryPresentation: QueuedRetryPresentation? {
        QueuedRetryPresentation.resolve(
            queueState: queuedContext.queueState,
            nextRetryAt: queuedContext.queueNextRetryAt,
            errorCode: queuedContext.queueLastErrorCode,
            needsAttention: queuedContext.queueNeedsAttention,
            canRetryNow: queuedContext.canRetryNow,
            isOnline: offlineQueueManager.isOnline,
            now: retryReferenceDate
        )
    }

    private var isRetrying: Bool {
        operationViewModel.isRetrying(scanID: queuedContext.id)
    }

    var body: some View {
        let queuedGeneration = viewModel.scanBoundActionGeneration

        ScanningExperienceView(
            viewModel: viewModel,
            analyzingPhrase: badgePhrase,
            fieldNotesPromptContext: viewModel.fieldNotesPromptContext,
            timestamp: queuedContext.timestamp,
            fallbackLocationName: queuedContext.locationName,
            fallbackTemperature: queuedContext.weatherTemperatureF,
            fallbackCondition: queuedContext.weatherCondition,
            fallbackElevation: queuedContext.gpsElevation,
            fallbackLatitude: queuedContext.gpsLatitude,
            fallbackLongitude: queuedContext.gpsLongitude,
            onAnalyzingBadgeTap: {
                #if DEBUG
                guard UITestSeedCoordinator.isEnabled else { return }
                MerianLog.general.info(
                    "QueuedContentView received the queued audio handoff request."
                )
                guard UITestSeedCoordinator.completeQueuedAudioHandoffIfNeeded(
                    scanId: queuedContext.id,
                    modelContext: modelContext
                ) else {
                    return
                }
                let didPromoteQueuedScan = viewModel.promoteQueuedScanIfLocalRecordExists(
                    scanId: queuedContext.id,
                    modelContext: modelContext,
                    inferenceEngine: inferenceEngine
                )

                guard didPromoteQueuedScan else {
                    MerianLog.data.error(
                        "QueuedContentView: seeded completed record was not visible for deterministic handoff scanId=\(queuedContext.id, privacy: .private)"
                    )
                    return
                }

                // Stabilize the open destination before synchronously refreshing its parent.
                // The Scans navigation route intentionally retains a queued value snapshot;
                // publishing first can make a rebuilt destination bind that stale snapshot.
                operationViewModel.publishSeededHandoffCompletion()
                MerianLog.general.info(
                    "QueuedContentView promoted the queued audio handoff before parent refresh."
                )
                #endif
            }
        ) {
            if let retryPresentation {
                QueuedRetryStatusView(
                    presentation: retryPresentation,
                    isRetrying: isRetrying,
                    onRetry: {
                        retryQueuedScanNow(
                            expectedGeneration: queuedGeneration
                        )
                    },
                    onViewPlans: {
                        viewModel.state.showPaywall = true
                    }
                )
            }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if UITestSeedCoordinator.isEnabled && isLiveQueueHandoff {
                Color.clear
                    .frame(width: 1, height: 1)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Queued presentation")
                    .accessibilityIdentifier(
                        "QueuedPresentation_\(queuedContext.id)"
                    )
            }
        }
        #endif
        .task(id: queuedContext.id) {
            operationViewModel.scheduleNextPersistedWake(
                using: offlineQueueManager
            )
            while !Task.isCancelled {
                retryReferenceDate = Date()
                refreshQueuedContext(scanId: queuedContext.id)
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
        .task(id: phaseRotationID) {
            phaseIndex = 0
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: MerianConfig.scanningPhaseRotationIntervalNs
                    )
                } catch {
                    return
                }
                let phraseCount = scanningPhasePhrases.count
                guard phraseCount > 1 else {
                    continue
                }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    phaseIndex = (phaseIndex + 1) % phraseCount
                }
            }
        }
        .task(id: operationViewModel.retryRefreshRequest?.id) {
            guard let request = operationViewModel.retryRefreshRequest else {
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  operationViewModel.retryRefreshRequest?.id == request.id else {
                return
            }
            guard viewModel.isPresentingScan(
                scanId: request.scanID,
                generation: request.generation
            ) else {
                operationViewModel.completeRefresh(request)
                return
            }
            refreshQueuedContext(scanId: request.scanID)
            operationViewModel.completeRefresh(request)
        }
    }
}

private extension QueuedContentView {
    @MainActor
    func retryQueuedScanNow(expectedGeneration: UInt64) {
        let scanId = queuedContext.id
        guard !isRetrying,
              viewModel.isPresentingScan(
                  scanId: scanId,
                  generation: expectedGeneration
              ) else {
            return
        }

        switch operationViewModel.startRetry(
            scanID: scanId,
            generation: expectedGeneration,
            queueManager: offlineQueueManager
        ) {
        case .ignored:
            return
        case .failed:
            if viewModel.isPresentingScan(
                scanId: scanId,
                generation: expectedGeneration
            ) {
                viewModel.state.toastMessage = .error("Retry could not start")
            }
            return
        case .started:
            refreshQueuedContext(scanId: scanId)
            if viewModel.isPresentingScan(
                scanId: scanId,
                generation: expectedGeneration
            ) {
                viewModel.state.toastMessage = .success("Retry queued")
            }
        }
    }

    @MainActor
    func refreshQueuedContext(scanId: String) {
        guard viewModel.queuedContext?.id
            .caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        guard let refreshed = operationViewModel.refreshedContext(
            scanID: scanId,
            modelContainer: modelContext.container
        ) else {
            return
        }
        viewModel.refreshQueuedContextIfCurrent(
            refreshed,
            expectedScanId: scanId
        )
    }
}
