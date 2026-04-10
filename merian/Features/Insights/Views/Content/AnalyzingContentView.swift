import SwiftUI

// MARK: - Previews
#if DEBUG
#Preview("Analyzing — badge only") {
    let engine = InferenceEngine()
    engine.isProcessing = true
    engine.scanningPhaseText = "Wing venation"
    return ScrollView {
        AnalyzingContentView().padding(.horizontal)
    }.environment(engine)
}

#Preview("Analyzing — vision streaming") {
    let engine = InferenceEngine()
    engine.isProcessing = true
    engine.scanningPhaseText = "Arthropod"
    return ScrollView {
        AnalyzingContentView().padding(.horizontal)
    }.environment(engine)
}

#Preview("Analyzing — vision complete") {
    let engine = InferenceEngine()
    engine.isProcessing = true
    engine.scanningPhaseText = "Confirming..."
    return ScrollView {
        AnalyzingContentView().padding(.horizontal)
    }.environment(engine)
}
#endif

/// Shown inside `InsightSheetView` while the inference engine is processing,
/// or when an `OfflineQueuedScan` is being viewed from the library pending upload.
///
/// When `queuedScan` is non-nil the badge phrase reflects the scan's per-scan
/// queue state derived from `OfflineQueuedScan.queueState`. The `ScanInformationCard`
/// reads telemetry from the queued scan's stored fields rather than the live engine context.
struct AnalyzingContentView: View {
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    var queuedContext: QueuedScanContext?

    /// The phrase displayed inside `ConfidenceBadge`'s analyzing capsule.
    /// For live scans this is the engine's rotating `scanningPhaseText`.
    /// For queued scans the phrase is derived from `OfflineQueueManager` state rather than
    /// the per-scan `queueState` field: the context is a value-type snapshot and holds no
    /// live `OfflineQueuedScan` reference, so no SwiftData attribute access occurs here.
    private var analyzingPhrase: String {
        guard queuedContext != nil else {
            return inferenceEngine.scanningPhaseText
        }
        guard offlineQueueManager.isOnline else { return "Waiting for connection" }
        return offlineQueueManager.isSyncing ? "Uploading..." : "Processing..."
    }

    var body: some View {
        VStack(alignment: .center, spacing: 24) {

            // Confidence badge slot — rotating analysis phrase drives the label for
            // live scans; per-scan queue state drives it for offline queued scans.
            ConfidenceBadge(
                confidenceScore: nil,
                inferenceTier: nil,
                analyzingPhrase: analyzingPhrase
            )

            // MARK: - Title
            Text("Analyzing")
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            // Fun-fact carousel — gives users something to read while processing
            DidYouKnowCard()
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            // Render telemetry from the queued scan's stored fields when available,
            // falling back to the live engine context for active camera captures.
            ScanInformationCard(
                speciesData: nil,
                timestamp: queuedContext?.timestamp ?? Date(),
                fallbackLocationName: queuedContext?.locationName ?? inferenceEngine.activeLocationName,
                fallbackTemperature: queuedContext?.weatherTemperatureF ?? inferenceEngine.activeTemperatureF,
                fallbackCondition: queuedContext?.weatherCondition ?? inferenceEngine.activeWeatherCondition,
                fallbackElevation: queuedContext?.gpsElevation ?? inferenceEngine.activeElevation,
                fallbackLatitude: queuedContext?.gpsLatitude ?? inferenceEngine.activeLatitude,
                fallbackLongitude: queuedContext?.gpsLongitude ?? inferenceEngine.activeLongitude
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }
}
