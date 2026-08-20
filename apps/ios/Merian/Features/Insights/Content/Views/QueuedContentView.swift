import SwiftData
import SwiftUI

struct QueuedRetryPresentation: Equatable {
    enum Action: Equatable {
        case retryNow
        case viewPlans
    }

    let message: String
    let action: Action?

    static func resolve(
        queueState: ScanQueueState,
        nextRetryAt: Date?,
        errorCode: String?,
        needsAttention: Bool,
        canRetryNow: Bool,
        isOnline: Bool,
        now: Date
    ) -> QueuedRetryPresentation? {
        let requiresAttention = needsAttention || queueState == .failed
        if requiresAttention {
            let category = reasonCategory(for: errorCode)
            return QueuedRetryPresentation(
                message: category.message,
                action: attentionAction(
                    for: category,
                    canRetryNow: canRetryNow,
                    isOnline: isOnline
                )
            )
        }

        guard let nextRetryAt else { return nil }
        guard isOnline else {
            return QueuedRetryPresentation(
                message: [
                    ReasonCategory.connection.message,
                    "It will retry when your connection returns."
                ].joined(separator: " "),
                action: nil
            )
        }

        let remaining = nextRetryAt.timeIntervalSince(now)
        guard remaining > 0 else {
            // The queue state and analyzing badge already communicate that the
            // due retry is starting. Avoid a redundant transient label/button.
            return nil
        }
        let category = reasonCategory(for: errorCode)
        return QueuedRetryPresentation(
            message: [
                category.message,
                "It will retry automatically in \(countdown(remaining))."
            ].joined(separator: " "),
            action: canRetryNow ? .retryNow : nil
        )
    }

    private enum ReasonCategory: Equatable {
        case connection
        case service
        case processing
        case missingMedia
        case consent
        case entitlement
        case retryLimit
        case terminal
        case unknown

        var message: String {
            switch self {
            case .connection:
                "The analysis paused because the connection was interrupted."
            case .service:
                "The analysis couldn’t complete because Naturebook’s analysis service was temporarily unavailable."
            case .processing:
                "The analysis is taking longer than expected."
            case .missingMedia:
                "The analysis couldn’t continue because its photo or recording is no longer available on this device."
            case .consent:
                "AI analysis is paused until you review the required AI consent."
            case .entitlement:
                "This analysis needs an active plan before it can continue."
            case .retryLimit:
                "Automatic retries paused after several unsuccessful attempts."
            case .terminal:
                "Naturebook couldn’t process this observation. Try a different photo or recording."
            case .unknown:
                "The analysis couldn’t complete this time."
            }
        }
    }

    private static func reasonCategory(for errorCode: String?) -> ReasonCategory {
        let code = errorCode?.lowercased() ?? ""
        if code == "ai_consent_required" { return .consent }
        if code == "pro_required" ||
            code == "payment_required" ||
            code == "plan_required" ||
            code == "http_402" ||
            code == "inference_http_402" ||
            code.contains("entitlement") ||
            code.contains("quota") ||
            code.contains("scan_limit") {
            return .entitlement
        }
        if code == "automatic_retry_limit_reached" ||
            code.contains("recovery_exhausted") ||
            code.contains("retry_limit") {
            return .retryLimit
        }
        if code.contains("local_media_missing") ||
            code.contains("queued_media_missing") ||
            code.contains("queued_media_invalid") ||
            code.contains("source_file_missing") ||
            code.contains("legacy_external_import") {
            return .missingMedia
        }
        if code.contains("observation_rejected") ||
            code.contains("failed_terminal") ||
            code.contains("upload_rejected") ||
            code.contains("terminal") ||
            code.contains("manifest_invalid") ||
            code.contains("staging_object_key_invalid") ||
            code.contains("staging_capture_identity_mismatch") {
            return .terminal
        }
        if code.contains("network") ||
            code.contains("transport") ||
            code.contains("timed_out") ||
            code.contains("connection") ||
            code.contains("http_408") {
            return .connection
        }
        if code.contains("server_result") ||
            code.contains("processing") ||
            code.contains("finalizing") ||
            code.contains("server_retryable_failure") {
            return .processing
        }
        if code.contains("http_5") ||
            code.contains("http_425") ||
            code.contains("http_429") ||
            code.contains("service") ||
            code.contains("inference") ||
            code.contains("failed_retryable") ||
            code.contains("upload_url_generation") ||
            code.contains("upload_error") ||
            code.contains("background_ingestion_failed") ||
            code.contains("media_finalization_failed") ||
            code.contains("video_promotion_failed") {
            return .service
        }
        return .unknown
    }

    private static func attentionAction(
        for category: ReasonCategory,
        canRetryNow: Bool,
        isOnline: Bool
    ) -> Action? {
        switch category {
        case .entitlement:
            .viewPlans
        case .consent, .missingMedia, .terminal:
            nil
        case .connection, .service, .processing, .retryLimit, .unknown:
            isOnline && canRetryNow ? .retryNow : nil
        }
    }

    private static func countdown(_ interval: TimeInterval) -> String {
        if interval < 60 {
            let seconds = max(1, Int(ceil(interval)))
            return "\(seconds) \(seconds == 1 ? "second" : "seconds")"
        }
        let minutes = max(1, Int(ceil(interval / 60)))
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
}

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
    @State private var retryRefreshRequest: RetryRefreshRequest?

    private struct RetryRefreshRequest: Equatable {
        let id = UUID()
        let scanId: String
        let generation: UInt64
    }

    struct PhaseRotationID: Hashable {
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

    /// True when this queued view replaced the live analyzing sheet after the
    /// foreground request lost connectivity or relinquished ownership.
    private var isLiveQueueHandoff: Bool {
        inferenceEngine.hasLiveVisualQueueHandoff(for: queuedContext.id)
    }

    private var phaseRotationID: PhaseRotationID {
        Self.phaseRotationID(
            scanId: queuedContext.id,
            isLiveVisualHandoff: isLiveQueueHandoff,
            queueState: queuedContext.queueState,
            isOnline: offlineQueueManager.isOnline,
            serverJobStatus: serverJobStatus,
            needsAttention: queuedContext.queueNeedsAttention,
            hasScheduledRetry: queuedContext.queueNextRetryAt != nil
        )
    }

    nonisolated static func phaseRotationID(
        scanId: String,
        isLiveVisualHandoff: Bool,
        queueState: ScanQueueState,
        isOnline: Bool,
        serverJobStatus: ScanIngestionJobStatus?,
        needsAttention: Bool,
        hasScheduledRetry: Bool
    ) -> PhaseRotationID {
        if isLiveVisualHandoff {
            // Durable upload and save-state changes belong to the same visible
            // analysis. Offline copy is a temporary overlay, so neither queue
            // state nor connectivity may restart its phrase cursor.
            return PhaseRotationID(
                scanId: scanId,
                queueStateRawValue: -1,
                isOnline: false,
                serverJobStatus: nil,
                needsAttention: false,
                hasScheduledRetry: false
            )
        }
        return PhaseRotationID(
            scanId: scanId,
            queueStateRawValue: queueState.rawValue,
            isOnline: isOnline,
            serverJobStatus: serverJobStatus?.rawValue,
            needsAttention: needsAttention,
            hasScheduledRetry: hasScheduledRetry
        )
    }

    /// Honest queue-aware phases presented through the same rotating badge used
    /// by foreground analysis.
    private var scanningPhasePhrases: [String] {
        if isLiveQueueHandoff {
            return Self.liveQueueHandoffPhrases(
                isOnline: offlineQueueManager.isOnline,
                contextualPhrases:
                    inferenceEngine.liveQueueHandoffScanningPhrases(
                        for: queuedContext.id
                    )
            )
        }
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

    /// An online durable handoff is still the same active analysis from the
    /// user's perspective. Continue its ephemeral contextual deck instead of
    /// restarting generic copy. Offline handoffs retain the only state change
    /// the user can act on: the scan is waiting for connectivity.
    nonisolated static func liveQueueHandoffPhrases(
        isOnline: Bool,
        contextualPhrases: [String]
    ) -> [String] {
        guard isOnline else {
            return ["Waiting for connection"]
        }
        return contextualPhrases.isEmpty
            ? InferenceEngine.genericScanningPhasePhrases
            : contextualPhrases
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
                AppDIContainer.shared.appEventPublisher.send(.scanLibraryChanged)
                MerianLog.general.info(
                    "QueuedContentView promoted the queued audio handoff before parent refresh."
                )
                #endif
            }
        ) {
            if let retryPresentation {
                VStack(spacing: 12) {
                    Text(retryPresentation.message)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if let action = retryPresentation.action {
                        Button {
                            switch action {
                            case .retryNow:
                                retryQueuedScanNow(
                                    expectedGeneration: queuedGeneration
                                )
                            case .viewPlans:
                                viewModel.state.showPaywall = true
                            }
                        } label: {
                            switch action {
                            case .retryNow:
                                Label(
                                    isRetrying ? "Retrying..." : "Retry now",
                                    systemImage: "arrow.clockwise"
                                )
                            case .viewPlans:
                                Label("View plans", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(action == .retryNow && isRetrying)
                        .labelStyle(.titleAndIcon)
                    }
                }
                .padding(.horizontal, 8)
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
        .task(id: retryRefreshRequest?.id) {
            guard let request = retryRefreshRequest else { return }
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  retryRefreshRequest?.id == request.id else {
                return
            }
            guard viewModel.isPresentingScan(
                scanId: request.scanId,
                generation: request.generation
            ) else {
                retryRefreshRequest = nil
                if retryingScanId?
                    .caseInsensitiveCompare(request.scanId) == .orderedSame {
                    retryingScanId = nil
                }
                return
            }
            refreshQueuedContext(scanId: request.scanId)
            if retryingScanId?
                .caseInsensitiveCompare(request.scanId) == .orderedSame {
                retryingScanId = nil
            }
            retryRefreshRequest = nil
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
                viewModel.state.toastMessage = .error("Retry could not start")
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
            viewModel.state.toastMessage = .success("Retry queued")
        }

        retryRefreshRequest = RetryRefreshRequest(
            scanId: scanId,
            generation: expectedGeneration
        )
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
