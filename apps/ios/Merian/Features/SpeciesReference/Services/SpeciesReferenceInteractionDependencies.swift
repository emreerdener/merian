import SwiftData

struct SimilarSpeciesGalleryDependencies {
    let imageDependencies: SimilarSpeciesImageDependencies
    let selectionFeedback: @MainActor () -> Void
    var visibilityGeneration: @MainActor () -> UInt64 = { 0 }

    init(
        imageDependencies: SimilarSpeciesImageDependencies,
        selectionFeedback: @escaping @MainActor () -> Void,
        visibilityGeneration: @escaping @MainActor () -> UInt64 = { 0 }
    ) {
        self.imageDependencies = imageDependencies
        self.selectionFeedback = selectionFeedback
        self.visibilityGeneration = visibilityGeneration
    }

    static let live = Self(
        imageDependencies: .live,
        selectionFeedback: {
            AppDIContainer.shared.hapticManager.triggerSelectionPulse()
        },
        visibilityGeneration: { AppDIContainer.shared.exploreContentVisibility.generation }
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
