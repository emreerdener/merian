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
    engine.visionAnalysisText = "Arthropod subject detected with high confidence. Evaluating wing venation, body segmentation, and diagnostic field markers. Preparing entomological context for species-level identification."
    engine.isVisionStreaming = true
    return ScrollView {
        AnalyzingContentView().padding(.horizontal)
    }.environment(engine)
}

#Preview("Analyzing — vision complete") {
    let engine = InferenceEngine()
    engine.isProcessing = true
    engine.scanningPhaseText = "Confirming..."
    engine.visionAnalysisText = "Arthropod subject detected with high confidence. Evaluating wing venation, body segmentation, and diagnostic field markers. Preparing entomological context for species-level identification."
    engine.isVisionStreaming = false
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

            // Description slot — Vision paragraph streamed character-by-character
            if !inferenceEngine.visionAnalysisText.isEmpty || inferenceEngine.isVisionStreaming {
                VisionStreamingParagraph(
                    text: inferenceEngine.visionAnalysisText,
                    isStreaming: inferenceEngine.isVisionStreaming
                )
                .transition(.opacity.combined(with: .offset(y: 8)))
                .animation(.easeInOut(duration: 0.3), value: inferenceEngine.visionAnalysisText.isEmpty)
            }
            
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
        .padding(.top, 16)
    }
}

// MARK: - Subcomponents

private struct VisionStreamingParagraph: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        Text(text)
            .font(.system(.body))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            // Soft opacity crossfade creates that fluid AI text reveal
            // rather than snapping or looking like a terminal
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.25), value: text)
    }
}
