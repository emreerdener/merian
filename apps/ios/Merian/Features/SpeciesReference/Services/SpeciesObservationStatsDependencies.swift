import SwiftData

struct SpeciesObservationStatsDependencies {
    let loadLocalStats: @MainActor (
        _ scientificName: String,
        _ speciesId: String?,
        _ modelContainer: ModelContainer,
        _ now: Date
    ) async throws -> SpeciesObservationLocalStats
    let loadPublicStats: @MainActor (
        _ speciesId: String,
        _ scientificName: String
    ) async throws -> SpeciesObservationStatsEntry
    let publicErrorMessage: @MainActor (_ error: any Error) -> String

    init(
        loadLocalStats: @escaping @MainActor (
            _ scientificName: String,
            _ speciesId: String?,
            _ modelContainer: ModelContainer,
            _ now: Date
        ) async throws -> SpeciesObservationLocalStats,
        loadPublicStats: @escaping @MainActor (
            _ speciesId: String,
            _ scientificName: String
        ) async throws -> SpeciesObservationStatsEntry,
        publicErrorMessage: @escaping @MainActor (
            _ error: any Error
        ) -> String
    ) {
        self.loadLocalStats = loadLocalStats
        self.loadPublicStats = loadPublicStats
        self.publicErrorMessage = publicErrorMessage
    }

    static let live = Self(
        loadLocalStats: { scientificName, speciesId, container, now in
            let actor = SpeciesObservationStatsDatabaseActor(
                modelContainer: container
            )
            return await actor.fetchLocalStats(
                scientificName: scientificName,
                speciesId: speciesId,
                now: now
            )
        },
        loadPublicStats: { speciesId, scientificName in
            try await MerianNetworkClient.shared.getSpeciesObservationStats(
                speciesId: speciesId,
                scientificName: scientificName
            )
        },
        publicErrorMessage: { error in
            ExploreErrorFormatter.speciesStatsMessage(for: error)
        }
    )
}
