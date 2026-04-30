import SwiftUI

// MARK: - Previews
#if DEBUG
private extension QueuedScanContext {
    /// Debug-only memberwise initialiser — avoids constructing a live SwiftData model in previews.
    init(
        id: String,
        capturedMediaJSON: String? = nil,
        timestamp: Date,
        locationName: String?,
        weatherTemperatureF: Double?,
        weatherCondition: String?,
        gpsElevation: Double?,
        gpsLatitude: Double?,
        gpsLongitude: Double?,
    ) {
        self.id = id
        self.capturedMediaItems = CapturedMediaSnapshot(jsonString: capturedMediaJSON).items
        self.timestamp = timestamp
        self.locationName = locationName
        self.weatherTemperatureF = weatherTemperatureF
        self.weatherCondition = weatherCondition
        self.gpsElevation = gpsElevation
        self.gpsLatitude = gpsLatitude
        self.gpsLongitude = gpsLongitude
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
            gpsLongitude: -122.5810,
        )
    }
}

#Preview("Queued — online") {
    let manager = OfflineQueueManager.shared
    return ScrollView {
        QueuedContentView(queuedContext: .preview)
            .padding(.horizontal)
    }
    .environment(manager)
}

#Preview("Queued — offline") {
    let manager = OfflineQueueManager.shared
    manager.isOnline = false
    return ScrollView {
        QueuedContentView(queuedContext: .preview)
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

    let queuedContext: QueuedScanContext

    /// The phrase displayed inside `ConfidenceBadge`'s analyzing capsule.
    /// Live system/connectivity status shown in the small `ConfidenceBadge` capsule.
    /// Always distinct from `displayTitle` so the two never duplicate each other:
    /// offline → "No connection" | online waiting → "In queue" | syncing → "Uploading..."
    private var badgePhrase: String {
        guard offlineQueueManager.isOnline else { return "No connection" }
        return offlineQueueManager.isSyncing ? "Uploading..." : "In queue"
    }

    /// The large serif title describes what this scan *is*, not the network state.
    /// Stable noun phrase so the badge above can report live status independently.
    private var displayTitle: String {
        return offlineQueueManager.isSyncing ? "Syncing" : "Queued for upload"
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
            Text("This scan is saved locally and will be automatically uploaded and analyzed in the background once a connection is available.")
                .font(.system(.subheadline))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

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
