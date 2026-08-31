import SwiftData

struct SimilarSpeciesGalleryDependencies {
    let imageDependencies: SimilarSpeciesImageDependencies
    let selectionFeedback: @MainActor () -> Void

    init(
        imageDependencies: SimilarSpeciesImageDependencies,
        selectionFeedback: @escaping @MainActor () -> Void
    ) {
        self.imageDependencies = imageDependencies
        self.selectionFeedback = selectionFeedback
    }

    static let live = Self(
        imageDependencies: .live,
        selectionFeedback: {
            AppDIContainer.shared.hapticManager.triggerSelectionPulse()
        }
    )
}

struct HabitatDistributionDependencies {
    let requestEnrichment: @MainActor (
        _ inferenceEngine: InferenceEngine,
        _ modelContext: ModelContext
    ) async -> Void

    init(
        requestEnrichment: @escaping @MainActor (
            _ inferenceEngine: InferenceEngine,
            _ modelContext: ModelContext
        ) async -> Void
    ) {
        self.requestEnrichment = requestEnrichment
    }

    static let live = Self { inferenceEngine, modelContext in
        await inferenceEngine.fetchAndApplyEnrichment(
            modelContext: modelContext,
            needsMetadata: true,
            needsLookalikes: false
        )
    }
}
