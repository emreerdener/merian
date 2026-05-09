import SwiftUI

// MARK: - Previews
#if DEBUG
#Preview("Analyzing — badge only") {
    let engine = InferenceEngine()
    engine.isProcessing = true
    engine.scanningPhaseText = "Wing venation"
    let viewModel = InsightSheetViewModel(inferenceEngine: engine)
    return ScrollView {
        AnalyzingContentView(viewModel: viewModel).padding(.horizontal)
    }.environment(engine)
}

#Preview("Analyzing — vision streaming") {
    let engine = InferenceEngine()
    engine.isProcessing = true
    engine.scanningPhaseText = "Arthropod"
    let viewModel = InsightSheetViewModel(inferenceEngine: engine)
    return ScrollView {
        AnalyzingContentView(viewModel: viewModel).padding(.horizontal)
    }.environment(engine)
}

#Preview("Analyzing — vision complete") {
    let engine = InferenceEngine()
    engine.isProcessing = true
    engine.scanningPhaseText = "Confirming..."
    let viewModel = InsightSheetViewModel(inferenceEngine: engine)
    return ScrollView {
        AnalyzingContentView(viewModel: viewModel).padding(.horizontal)
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

    @Bindable var viewModel: InsightSheetViewModel

    var body: some View {
        VStack(alignment: .center, spacing: 24) {

            ConfidenceBadge(
                confidenceScore: nil,
                inferenceTier: nil,
                analyzingPhrase: inferenceEngine.scanningPhaseText
            )

            if viewModel.shouldShowFieldNotesCard {
                FieldNotesCard(
                    previewText: viewModel.fieldNotesText,
                    promptContext: .analyzing,
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
