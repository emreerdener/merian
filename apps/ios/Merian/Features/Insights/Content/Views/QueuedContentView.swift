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
/// This view is intentionally isolated from `AnalyzingContentView` so the UI clearly
/// distinguishes a scan purposefully waiting in queue from one actively under edge resolution.
struct QueuedContentView: View {
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: InsightSheetViewModel

    let queuedContext: QueuedScanContext
    @State private var isRetrying = false

    private var serverJobStatus: ScanIngestionJobStatus? {
        offlineQueueManager.scanIngestionJobStates[queuedContext.id]
    }

    private var queuedScanHasVideo: Bool {
        !queuedContext.capturedMediaSnapshot.videoPaths.isEmpty
    }

    /// The phrase displayed inside `ConfidenceBadge`'s analyzing capsule.
    /// Live system/connectivity status shown in the small `ConfidenceBadge` capsule.
    /// Always distinct from `displayTitle` so the two never duplicate each other:
    /// offline → "No connection" | online waiting → "In queue" | syncing → "Uploading..."
    private var badgePhrase: String {
        guard offlineQueueManager.isOnline else { return "No connection" }
        switch queuedContext.queueState {
        case .pending:
            return "In queue"
        case .uploading:
            return "Uploading..."
        case .staged:
            return "Preparing analysis"
        case .inferencing:
            switch serverJobStatus {
            case .finalizing:
                return "Finishing..."
            case .retrying, .failedRetryable:
                return "Retrying..."
            case .failed:
                return "Needs attention"
            case .processing, .complete, nil:
                break
            }
            return "Analyzing..."
        case .externalImport:
            return "Waiting..."
        case .failed:
            return "Needs attention"
        }
    }

    /// The large serif title describes what this scan *is*, not the network state.
    /// Stable noun phrase so the badge above can report live status independently.
    private var displayTitle: String {
        switch queuedContext.queueState {
        case .pending:
            return "Queued for upload"
        case .uploading:
            return "Uploading"
        case .staged:
            return "Queued for analysis"
        case .inferencing:
            switch serverJobStatus {
            case .finalizing:
                return queuedScanHasVideo ? "Finishing video scan" : "Finishing scan"
            case .retrying, .failedRetryable:
                return queuedScanHasVideo ? "Retrying video save" : "Retrying scan"
            case .processing, .complete, .failed, nil:
                break
            }
            return "Analyzing"
        case .externalImport:
            return "Waiting"
        case .failed:
            return "Upload paused"
        }
    }

    private var helperText: String {
        switch queuedContext.queueState {
        case .pending, .uploading:
            return "This scan is saved locally and will be uploaded to Merian in the background."
        case .staged:
            return "The scan media has uploaded and is waiting for identification."
        case .inferencing:
            switch serverJobStatus {
            case .finalizing:
                return queuedScanHasVideo
                    ? "Merian is saving the playable video and will show results automatically."
                    : "Merian is finishing this scan and will show results automatically."
            case .retrying, .failedRetryable:
                return "Merian is waiting for the server retry window before trying this scan again."
            case .processing, .complete, .failed, nil:
                break
            }
            return "Merian is identifying this scan. Results will appear here automatically."
        case .externalImport:
            return "This scan is waiting for local recovery."
        case .failed:
            return "Merian could not finish processing this scan."
        }
    }

    private var queueDetails: [String] {
        var details: [String] = []
        if !queuedContext.mediaKinds.isEmpty {
            details.append(queuedContext.mediaKinds.joined(separator: " + "))
        }
        if let nextRetryAt = queuedContext.queueNextRetryAt {
            details.append("Automatic retry \(nextRetryAt.formatted(date: .omitted, time: .shortened))")
        }
        if queuedContext.approximateQueuedBytes > 0 {
            details.append(ByteCountFormatter.string(
                fromByteCount: queuedContext.approximateQueuedBytes,
                countStyle: .file
            ))
        }
        return details
    }

    private var friendlyErrorText: String? {
        guard queuedContext.queueNeedsAttention || queuedContext.queueState == .failed else { return nil }
        return queuedContext.queueLastErrorMessage ?? "This queued scan needs a fresh retry."
    }

    var body: some View {
        VStack(alignment: .center, spacing: 24) {

            // Queue-state badge — driven by live OfflineQueueManager connectivity
            ConfidenceBadge(
                confidenceScore: nil,
                inferenceTier: nil,
                analyzingPhrase: badgePhrase
            )

            // MARK: - Title
            Text(displayTitle)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayTitle)

            // MARK: - Helper Text
            Text(helperText)
                .font(.system(.subheadline))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if !queueDetails.isEmpty || friendlyErrorText != nil || queuedContext.canRetryNow {
                VStack(spacing: 12) {
                    if !queueDetails.isEmpty {
                        Text(queueDetails.joined(separator: " • "))
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
                            retryQueuedScanNow()
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

            if viewModel.shouldShowFieldNotesCard {
                FieldNotesCard(
                    previewText: viewModel.fieldNotesText,
                    promptContext: viewModel.fieldNotesPromptContext,
                    onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.dismissFieldNotesCard()
                        }
                    },
                    action: {
                        viewModel.state.isFieldNotesSheetPresented = true
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Scan telemetry from the queued context snapshot
            ScanInformationCard(
                speciesData: nil,
                timestamp: queuedContext.timestamp,
                fallbackLocationName: queuedContext.locationName,
                fallbackTemperature: queuedContext.weatherTemperatureF,
                fallbackCondition: queuedContext.weatherCondition,
                fallbackElevation: queuedContext.gpsElevation,
                fallbackLatitude: queuedContext.gpsLatitude,
                fallbackLongitude: queuedContext.gpsLongitude
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }
}

private extension QueuedContentView {
    @MainActor
    func retryQueuedScanNow() {
        guard !isRetrying else { return }
        isRetrying = true

        let scanId = queuedContext.id
        guard offlineQueueManager.retryQueuedScanNow(scanId: scanId) else {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.state.toastMessage = "Retry could not start"
            }
            isRetrying = false
            return
        }

        HapticManager.shared.triggerSelectionPulse()
        refreshQueuedContext(scanId: scanId)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            viewModel.state.toastMessage = "Retry queued"
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            refreshQueuedContext(scanId: scanId)
            isRetrying = false
        }
    }

    @MainActor
    func refreshQueuedContext(scanId: String) {
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard let scan = (try? modelContext.fetch(descriptor))?.first else { return }
        viewModel.queuedContext = QueuedScanContext(from: scan)
    }
}
