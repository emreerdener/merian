import SwiftData
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
    @Environment(\.modelContext) private var modelContext

    @Bindable var viewModel: InsightSheetViewModel

    var body: some View {
        ScanningExperienceView(
            viewModel: viewModel,
            analyzingPhrase: inferenceEngine.scanningPhaseText,
            fieldNotesPromptContext: .analyzing,
            timestamp: Date(),
            fallbackLocationName: inferenceEngine.activeLocationName,
            fallbackTemperature: inferenceEngine.activeTemperatureF,
            fallbackCondition: inferenceEngine.activeWeatherCondition,
            fallbackElevation: inferenceEngine.activeElevation,
            fallbackLatitude: inferenceEngine.activeLatitude,
            fallbackLongitude: inferenceEngine.activeLongitude,
            onAnalyzingBadgeTap: analyzingBadgeTestAction
        ) {
            EmptyView()
        }
    }

    private var analyzingBadgeTestAction: (() -> Void)? {
        #if DEBUG
        if UITestSeedCoordinator.isProgressiveAnalyzingTriggerEnabled {
            return {
                UITestSeedCoordinator.advanceProgressiveAnalyzingIfNeeded(
                    inferenceEngine: inferenceEngine
                )
            }
        }
        guard UITestSeedCoordinator.isLiveQueueHandoffTriggerEnabled else {
            return nil
        }
        return {
            _ = UITestSeedCoordinator.performLiveQueueHandoffIfNeeded(
                inferenceEngine: inferenceEngine,
                modelContext: modelContext
            )
        }
        #else
        return nil
        #endif
    }
}
