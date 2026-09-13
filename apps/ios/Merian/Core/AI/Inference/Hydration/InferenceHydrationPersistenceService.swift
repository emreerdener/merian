import Foundation
import SwiftData

/// Applies already-admitted inference hydration snapshots to local storage.
///
/// Presentation generation and identification-review fencing remain owned by
/// `InferenceEngine` and `InferenceWriteCoordinator`; this service receives
/// work only after those owners admit it.
struct InferenceHydrationPersistenceService: Sendable {
    struct ReferenceSnapshot: Equatable, Sendable {
        let scanId: String
        let extract: String?
        let url: String?
        let imageUrl: String?
        let expectedScientificName: String
    }

    struct MetadataSnapshot: Sendable {
        let scanId: String
        let habitatDescription: String?
        let gbifTaxonKey: Int?
        let taxonomy: TaxonomyData?
        let alternativeCommonNames: [String]?
        let expectedScientificName: String
    }

    struct LookalikesSnapshot: Sendable {
        let scanId: String
        let entries: [SimilarSpeciesEntry]
        let expectedScientificName: String
    }

    struct Dependencies: Sendable {
        let persistReference: @MainActor @Sendable (
            _ snapshot: ReferenceSnapshot,
            _ modelContainer: ModelContainer
        ) async -> Void
        let persistMetadata: @MainActor @Sendable (
            _ snapshot: MetadataSnapshot,
            _ modelContainer: ModelContainer
        ) async -> Void
        let persistLookalikes: @MainActor @Sendable (
            _ snapshot: LookalikesSnapshot,
            _ modelContainer: ModelContainer
        ) async -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @MainActor
    func persistReference(
        _ snapshot: ReferenceSnapshot,
        in modelContainer: ModelContainer
    ) async {
        await dependencies.persistReference(snapshot, modelContainer)
    }

    @MainActor
    func persistMetadata(
        _ snapshot: MetadataSnapshot,
        in modelContainer: ModelContainer
    ) async {
        await dependencies.persistMetadata(snapshot, modelContainer)
    }

    @MainActor
    func persistLookalikes(
        _ snapshot: LookalikesSnapshot,
        in modelContainer: ModelContainer
    ) async {
        await dependencies.persistLookalikes(snapshot, modelContainer)
    }
}
