import SwiftData
import SwiftUI

// MARK: - Previews
#if DEBUG
private extension QueuedScanContext {
    /// Debug-only memberwise initialiser — avoids constructing a live SwiftData model in previews.
    init(
        id: String,
        capturedMediaJSON: String? = nil,
        queueState: ScanQueueState = .pending,
        timestamp: Date,
        locationName: String?,
        weatherTemperatureF: Double?,
        weatherCondition: String?,
        gpsElevation: Double?,
        gpsLatitude: Double?,
        gpsLongitude: Double?,
        queueAttemptCount: Int = 0,
        queueNextRetryAt: Date? = nil,
        queueLastErrorCode: String? = nil,
        queueLastErrorMessage: String? = nil,
        queueNeedsAttention: Bool = false,
        approximateQueuedBytes: Int64 = 0
    ) {
        self.id = id
        self.capturedMediaItems = CapturedMediaSnapshot(jsonString: capturedMediaJSON).items
        self.queueState = queueState
        self.timestamp = timestamp
        self.locationName = locationName
        self.weatherTemperatureF = weatherTemperatureF
        self.weatherCondition = weatherCondition
        self.gpsElevation = gpsElevation
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
        self.queueAttemptCount = queueAttemptCount
        self.queueNextRetryAt = queueNextRetryAt
        self.queueLastErrorCode = queueLastErrorCode
        self.queueLastErrorMessage = queueLastErrorMessage
        self.queueNeedsAttention = queueNeedsAttention
        self.approximateQueuedBytes = approximateQueuedBytes
        self.visualMediaItemsJSON = nil
    }

    static var preview: QueuedScanContext {
        QueuedScanContext(
            id: "preview-id",
            capturedMediaJSON: nil,
            timestamp: Date(),
            locationName: "Muir Woods, CA",
            weatherTemperatureF: 61,
            weatherCondition: "partly cloudy",
            gpsElevation: 142,
            gpsLatitude: 37.8970,
            gpsLongitude: -122.5810
        )
    }
}

#Preview("Queued — online") {
    let manager = OfflineQueueManager.shared
    let queuedContext = QueuedScanContext.preview
    return ScrollView {
        QueuedContentView(
            viewModel: InsightSheetViewModel(queuedContext: queuedContext),
            queuedContext: queuedContext
        )
            .padding(.horizontal)
    }
    .environment(manager)
}

#Preview("Queued — offline") {
    let manager = OfflineQueueManager.shared
    manager.isOnline = false
    let queuedContext = QueuedScanContext.preview
    return ScrollView {
        QueuedContentView(
            viewModel: InsightSheetViewModel(queuedContext: queuedContext),
            queuedContext: queuedContext
        )
            .padding(.horizontal)
    }
    .environment(manager)
}
#endif

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
    @State private var phaseIndex = 0
    @State private var retryingScanId: String?
    @State private var retryReferenceDate = Date()

    private struct PhaseRotationID: Hashable {
        let scanId: String
        let queueStateRawValue: Int
        let isOnline: Bool
        let serverJobStatus: String?
        let needsAttention: Bool
        let hasScheduledRetry: Bool
    }

    private var serverJobStatus: ScanIngestionJobStatus? {
        offlineQueueManager.scanIngestionJobStates[queuedContext.id]
    }

    private var queuedScanHasVideo: Bool {
        !queuedContext.capturedMediaSnapshot.videoPaths.isEmpty
    }

    private var phaseRotationID: PhaseRotationID {
        PhaseRotationID(
            scanId: queuedContext.id,
            queueStateRawValue: queuedContext.queueState.rawValue,
            isOnline: offlineQueueManager.isOnline,
            serverJobStatus: serverJobStatus?.rawValue,
            needsAttention: queuedContext.queueNeedsAttention,
            hasScheduledRetry: queuedContext.queueNextRetryAt != nil
        )
    }

    /// Honest queue-aware phases presented through the same rotating badge used
    /// by foreground analysis.
    private var scanningPhasePhrases: [String] {
        guard offlineQueueManager.isOnline else {
            return ["Waiting for connection"]
        }
        guard !queuedContext.queueNeedsAttention,
              queuedContext.queueState != .failed else {
            return ["Scan needs attention"]
        }

        switch queuedContext.queueState {
        case .pending:
            return [
                "Preparing scan",
                "Securing media",
                "Preparing upload"
            ]
        case .uploading:
            return [
                "Uploading media",
                "Securing scan",
                "Preparing analysis"
            ]
        case .staged:
            if queuedContext.queueNextRetryAt != nil {
                return [
                    "Scan safely queued",
                    "Waiting to retry"
                ]
            }
            return [
                "Preparing analysis",
                "Checking uploaded media",
                "Starting identification"
            ]
        case .inferencing:
            switch serverJobStatus {
            case .finalizing:
                return queuedScanHasVideo
                    ? ["Finalizing video scan", "Saving video", "Preparing results"]
                    : ["Finalizing scan", "Saving scan", "Preparing results"]
            case .retrying, .failedRetryable:
                return ["Retrying analysis", "Reconnecting to analysis"]
            case .failed:
                return ["Scan needs attention"]
            case .complete:
                return ["Preparing results", "Finishing scan"]
            case .processing, nil:
                return InferenceEngine.genericScanningPhasePhrases
            }
        case .externalImport:
            return ["Recovering scan"]
        case .failed:
            return ["Scan needs attention"]
        }
    }

    private var badgePhrase: String {
        guard !scanningPhasePhrases.isEmpty else {
            return "Scanning subject"
        }
        return scanningPhasePhrases[phaseIndex % scanningPhasePhrases.count]
    }

    private var retryDetail: String? {
        guard let nextRetryAt = queuedContext.queueNextRetryAt else {
            return nil
        }
        guard offlineQueueManager.isOnline else {
            return "Retry when connection returns"
        }
        let remaining = nextRetryAt.timeIntervalSince(retryReferenceDate)
        if remaining <= 0 {
            return "Automatic retry is starting"
        }
        if remaining < 60 {
            let seconds = max(1, Int(ceil(remaining)))
            return "Automatic retry in \(seconds) sec"
        }
        let minutes = max(1, Int(ceil(remaining / 60)))
        return "Automatic retry in \(minutes) min"
    }

    private var friendlyErrorText: String? {
        guard queuedContext.queueNeedsAttention || queuedContext.queueState == .failed else { return nil }
        return queuedContext.queueLastErrorMessage ?? "This queued scan needs a fresh retry."
    }

    private var isRetrying: Bool {
        retryingScanId?
            .caseInsensitiveCompare(queuedContext.id) == .orderedSame
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
                guard UITestSeedCoordinator.completeQueuedAudioHandoffIfNeeded(
                    scanId: queuedContext.id,
                    modelContext: modelContext
                ) else {
                    return
                }
                guard viewModel.promoteQueuedScanIfLocalRecordExists(
                    scanId: queuedContext.id,
                    modelContext: modelContext,
                    inferenceEngine: inferenceEngine
                ) else {
                    MerianLog.data.error(
                        "QueuedContentView: seeded completed record was not visible for deterministic handoff scanId=\(queuedContext.id, privacy: .private)"
                    )
                    return
                }
            }
        ) {
            if retryDetail != nil || friendlyErrorText != nil || queuedContext.canRetryNow {
                VStack(spacing: 12) {
                    if let retryDetail {
                        Text(retryDetail)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if let friendlyErrorText {
                        Text(friendlyErrorText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if queuedContext.canRetryNow {
                        Button {
                            retryQueuedScanNow(expectedGeneration: queuedGeneration)
                        } label: {
                            Label(isRetrying ? "Retrying..." : "Retry now", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRetrying)
                        .labelStyle(.titleAndIcon)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .task(id: queuedContext.id) {
            OfflineJobScheduler.shared.scheduleNextPersistedWake(
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
        retryingScanId = scanId
        guard offlineQueueManager.retryQueuedScanNow(scanId: scanId) else {
            HapticManager.shared.triggerErrorThump()
            if viewModel.isPresentingScan(
                scanId: scanId,
                generation: expectedGeneration
            ) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    viewModel.state.toastMessage = "Retry could not start"
                }
            }
            if retryingScanId?
                .caseInsensitiveCompare(scanId) == .orderedSame {
                retryingScanId = nil
            }
            return
        }

        HapticManager.shared.triggerSelectionPulse()
        refreshQueuedContext(scanId: scanId)
        if viewModel.isPresentingScan(
            scanId: scanId,
            generation: expectedGeneration
        ) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.state.toastMessage = "Retry queued"
            }
        }

        Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard viewModel.isPresentingScan(
                scanId: scanId,
                generation: expectedGeneration
            ) else {
                return
            }
            refreshQueuedContext(scanId: scanId)
            if retryingScanId?
                .caseInsensitiveCompare(scanId) == .orderedSame {
                retryingScanId = nil
            }
        }
    }

    @MainActor
    func refreshQueuedContext(scanId: String) {
        guard viewModel.queuedContext?.id
            .caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        let readContext = ModelContext(modelContext.container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard let scan = (try? readContext.fetch(descriptor))?.first else {
            return
        }
        let refreshed = QueuedScanContext(from: scan)
        viewModel.refreshQueuedContextIfCurrent(
            refreshed,
            expectedScanId: scanId
        )
    }
}
