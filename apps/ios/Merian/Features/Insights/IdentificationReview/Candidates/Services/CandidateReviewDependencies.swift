import SwiftData

struct CandidateReviewDependencies {
    let feedback: IdentificationReviewFeedbackDependencies
    let imageDependencies: SimilarSpeciesImageDependencies
    let isProActive: @MainActor () -> Bool
    let confirmOriginal: @MainActor (
        _ inferenceEngine: InferenceEngine,
        _ scanId: String,
        _ modelContext: ModelContext
    ) async -> Void
    let applyOverride: @MainActor (
        _ inferenceEngine: InferenceEngine,
        _ scientificName: String,
        _ scanId: String,
        _ modelContext: ModelContext
    ) async -> Void
    let resetReview: @MainActor (
        _ inferenceEngine: InferenceEngine,
        _ scanId: String,
        _ modelContext: ModelContext
    ) async -> Void
    let markAlternativesExhausted: @MainActor (
        _ inferenceEngine: InferenceEngine,
        _ scanId: String
    ) -> Void

    init(
        feedback: IdentificationReviewFeedbackDependencies = .init(),
        imageDependencies: SimilarSpeciesImageDependencies = .init { _ in
            SimilarSpeciesImageLoadOutput(images: [], commonName: nil)
        },
        isProActive: @escaping @MainActor () -> Bool = { false },
        confirmOriginal: @escaping @MainActor (
            _ inferenceEngine: InferenceEngine,
            _ scanId: String,
            _ modelContext: ModelContext
        ) async -> Void = { _, _, _ in },
        applyOverride: @escaping @MainActor (
            _ inferenceEngine: InferenceEngine,
            _ scientificName: String,
            _ scanId: String,
            _ modelContext: ModelContext
        ) async -> Void = { _, _, _, _ in },
        resetReview: @escaping @MainActor (
            _ inferenceEngine: InferenceEngine,
            _ scanId: String,
            _ modelContext: ModelContext
        ) async -> Void = { _, _, _ in },
        markAlternativesExhausted: @escaping @MainActor (
            _ inferenceEngine: InferenceEngine,
            _ scanId: String
        ) -> Void = { _, _ in }
    ) {
        self.feedback = feedback
        self.imageDependencies = imageDependencies
        self.isProActive = isProActive
        self.confirmOriginal = confirmOriginal
        self.applyOverride = applyOverride
        self.resetReview = resetReview
        self.markAlternativesExhausted = markAlternativesExhausted
    }

    static let live = Self(
        feedback: .live,
        imageDependencies: .live,
        isProActive: {
            AppDIContainer.shared.revenueCatManager.isProActive
        },
        confirmOriginal: { inferenceEngine, scanId, modelContext in
            await inferenceEngine.confirmAIIdentification(
                expectedScanId: scanId,
                modelContext: modelContext
            )
        },
        applyOverride: { inferenceEngine, scientificName, scanId, modelContext in
            await inferenceEngine.applyIdentificationOverride(
                scientificName: scientificName,
                expectedScanId: scanId,
                modelContext: modelContext
            )
        },
        resetReview: { inferenceEngine, scanId, modelContext in
            await inferenceEngine.resetIdentificationReview(
                expectedScanId: scanId,
                modelContext: modelContext
            )
        },
        markAlternativesExhausted: { inferenceEngine, scanId in
            inferenceEngine.markAlternativesExhausted(
                expectedScanId: scanId
            )
        }
    )
}
