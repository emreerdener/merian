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
            onAnalyzingBadgeTap: liveQueueHandoffTestAction
        ) {
            EmptyView()
        }
    }

    private var liveQueueHandoffTestAction: (() -> Void)? {
        #if DEBUG
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

/// Shared foreground and queued scanning presentation.
///
/// Keeping the badge, rotating fact, Field notes, and telemetry in one component
/// prevents the background-upload path from drifting away from the main scanner.
struct ScanningExperienceView<SupplementalContent: View>: View {
    @Bindable var viewModel: InsightSheetViewModel

    let analyzingPhrase: String
    let fieldNotesPromptContext: FieldNotesPromptContext
    let timestamp: Date
    let fallbackLocationName: String?
    let fallbackTemperature: Double?
    let fallbackCondition: String?
    let fallbackElevation: Double?
    let fallbackLatitude: Double?
    let fallbackLongitude: Double?
    let onAnalyzingBadgeTap: (() -> Void)?
    let supplementalContent: SupplementalContent

    init(
        viewModel: InsightSheetViewModel,
        analyzingPhrase: String,
        fieldNotesPromptContext: FieldNotesPromptContext,
        timestamp: Date,
        fallbackLocationName: String?,
        fallbackTemperature: Double?,
        fallbackCondition: String?,
        fallbackElevation: Double?,
        fallbackLatitude: Double?,
        fallbackLongitude: Double?,
        onAnalyzingBadgeTap: (() -> Void)? = nil,
        @ViewBuilder supplementalContent: () -> SupplementalContent
    ) {
        self.viewModel = viewModel
        self.analyzingPhrase = analyzingPhrase
        self.fieldNotesPromptContext = fieldNotesPromptContext
        self.timestamp = timestamp
        self.fallbackLocationName = fallbackLocationName
        self.fallbackTemperature = fallbackTemperature
        self.fallbackCondition = fallbackCondition
        self.fallbackElevation = fallbackElevation
        self.fallbackLatitude = fallbackLatitude
        self.fallbackLongitude = fallbackLongitude
        self.onAnalyzingBadgeTap = onAnalyzingBadgeTap
        self.supplementalContent = supplementalContent()
    }

    var body: some View {
        let fieldNotesScanId = viewModel.currentFieldNotesScanId
        let fieldNotesGeneration = viewModel.scanBoundActionGeneration

        VStack(alignment: .center, spacing: 24) {

            ConfidenceBadge(
                confidenceScore: nil,
                inferenceTier: nil,
                analyzingPhrase: analyzingPhrase,
                onAnalyzingTap: onAnalyzingBadgeTap
            )
            // ConfidenceBadge uses fixed-surface drawing and non-geometric text transitions.
            // Keep the composed label intrinsic so accessibility reports only the capsule.
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityIdentifier("ScanningStatusBadge")

            supplementalContent

            DidYouKnowCard()
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            if viewModel.shouldShowFieldNotesCard {
                FieldNotesCard(
                    previewText: viewModel.fieldNotesText,
                    promptContext: fieldNotesPromptContext,
                    onDismiss: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.dismissFieldNotesCard(
                                expectedScanId: fieldNotesScanId,
                                expectedGeneration: fieldNotesGeneration
                            )
                        }
                    },
                    action: {
                        viewModel.presentFieldNotes(
                            expectedScanId: fieldNotesScanId,
                            expectedGeneration: fieldNotesGeneration
                        )
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ScanInformationCard(
                speciesData: nil,
                timestamp: timestamp,
                fallbackLocationName: fallbackLocationName,
                fallbackTemperature: fallbackTemperature,
                fallbackCondition: fallbackCondition,
                fallbackElevation: fallbackElevation,
                fallbackLatitude: fallbackLatitude,
                fallbackLongitude: fallbackLongitude
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }
}
