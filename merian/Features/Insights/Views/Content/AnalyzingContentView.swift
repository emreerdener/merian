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

/// Shown inside `InsightSheetView` while the inference engine is processing.
///
/// Mirrors the structural position of `InsightHeader` — the `ConfidenceBadge` slot
/// shows the rotating analysis phrase; the description slot streams the Vision paragraph.
/// The scientific-name subtitle and common-name title are intentionally omitted.
struct AnalyzingContentView: View {
    @Environment(InferenceEngine.self) var inferenceEngine

    var body: some View {
        VStack(alignment: .center, spacing: 24) {

            // Confidence badge slot — rotating analysis phrase drives the label
            ConfidenceBadge(
                confidenceScore: nil,
                inferenceTier: nil,
                analyzingPhrase: inferenceEngine.scanningPhaseText
            )

            // Render basic scan telemetry immediately while waiting for Gemini analysis
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

// MARK: - Subcomponents
