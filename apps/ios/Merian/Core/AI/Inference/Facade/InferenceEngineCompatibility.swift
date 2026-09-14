import Foundation

/// Source-compatible value types and pure policy adapters retained by the
/// public inference facade.
extension InferenceEngine {
    enum ScanPresentationModality: Sendable {
        case visual
        case nonVisual

        var presentationValue: InferencePresentationCoordinator.Modality {
            switch self {
            case .visual:
                .visual
            case .nonVisual:
                .nonVisual
            }
        }
    }

    enum QueuedPresentationSource: Sendable {
        case prepared(attemptGeneration: UUID)
        case active(attemptGeneration: UUID)

        var presentationValue: InferencePresentationCoordinator.QueueSource {
            switch self {
            case .prepared(let attemptGeneration):
                .prepared(attemptGeneration: attemptGeneration)
            case .active(let attemptGeneration):
                .active(attemptGeneration: attemptGeneration)
            }
        }
    }

    nonisolated static func plannedEnrichmentScopes(
        needsMetadata: Bool,
        needsLookalikes: Bool,
        speciesIsEnriched: Bool
    ) -> (metadata: Bool, lookalikes: Bool) {
        InferenceSpeciesHydrationCoordinator.plannedEnrichmentScopes(
            needsMetadata: needsMetadata,
            needsLookalikes: needsLookalikes,
            speciesIsEnriched: speciesIsEnriched
        )
    }

    nonisolated static func normalizedReferenceURLs(
        from rawValue: String?
    ) -> [String] {
        ExternalReferenceImagePolicy.allowedURLStrings(from: rawValue)
    }

    /// Existing cloud-analysis phrases retained by queued, audio-only, and
    /// Describe flows. Foreground visual local analysis uses the morphology-
    /// only deck owned by `ScanningPhraseCoordinator`.
    nonisolated static var genericScanningPhasePhrases: [String] {
        ScanningPhrasePolicy.cloudAnalysisPhrases
    }
}
