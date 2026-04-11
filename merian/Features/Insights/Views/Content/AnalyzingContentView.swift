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

/// Shown inside `InsightSheetView` while the inference engine is actively processing
/// a live camera capture under edge resolution.
///
/// Queued offline scans are handled exclusively by `QueuedContentView` — this view
/// has no awareness of `OfflineQueueManager` or `QueuedScanContext`.
struct AnalyzingContentView: View {
    @Environment(InferenceEngine.self) var inferenceEngine

    var body: some View {
        VStack(alignment: .center, spacing: 24) {

            // Confidence badge slot — rotating scanning phase text drives the label.
            ConfidenceBadge(
                confidenceScore: nil,
                inferenceTier: nil,
                analyzingPhrase: inferenceEngine.scanningPhaseText
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

            ScanInformationCard(
                speciesData: nil,
                timestamp: Date(),
                fallbackLocationName: inferenceEngine.activeLocationName,
                fallbackTemperature: inferenceEngine.activeTemperatureF,
                fallbackCondition: inferenceEngine.activeWeatherCondition,
                fallbackElevation: inferenceEngine.activeElevation,
                fallbackLatitude: inferenceEngine.activeLatitude,
                fallbackLongitude: inferenceEngine.activeLongitude
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }
}
