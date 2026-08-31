import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SpeciesObservationStatsViewModel {
    private struct LoadIdentity: Equatable {
        let speciesId: String?
        let scientificName: String
    }

    private(set) var isLoading = false
    private(set) var localStats = SpeciesObservationLocalStats.empty()
    private(set) var publicStats: SpeciesObservationStatsEntry?
    private(set) var publicErrorMessage: String?

    private let dependencies: SpeciesObservationStatsDependencies
    private var activeLoadId: UUID?
    private var loadedIdentity: LoadIdentity?

    init(dependencies: SpeciesObservationStatsDependencies = .live) {
        self.dependencies = dependencies
    }

    var hasAnyData: Bool {
        Self.hasAnyData(localStats: localStats, publicStats: publicStats)
    }

    nonisolated static func hasAnyData(
        localStats: SpeciesObservationLocalStats,
        publicStats: SpeciesObservationStatsEntry?
    ) -> Bool {
        localStats.seasonality.contains(where: \.hasObservations) ||
            localStats.history.contains(where: \.hasObservations) ||
            localStats.lifeStage.contains(where: { series in
                series.values.contains(where: \.hasObservations)
            }) ||
            publicStats?.seasonality.contains(where: \.hasObservations) == true ||
            publicStats?.history.contains(where: \.hasObservations) == true ||
            publicStats?.lifeStage.contains(where: { series in
                series.values.contains(where: \.hasObservations)
            }) == true
    }

    func load(
        speciesId: String?,
        scientificName: String,
        modelContext: ModelContext,
        now: Date = Date()
    ) async {
        let normalizedName = SpeciesObservationStatsReducer
            .normalizedScientificName(scientificName)
        guard !normalizedName.isEmpty else {
            activeLoadId = UUID()
            loadedIdentity = nil
            isLoading = false
            localStats = .empty(now: now)
            publicStats = nil
            publicErrorMessage = nil
            return
        }
        guard !Task.isCancelled else { return }

        let identity = LoadIdentity(
            speciesId: SpeciesObservationStatsReducer
                .normalizedSpeciesId(speciesId),
            scientificName: normalizedName.lowercased()
        )
        let loadId = UUID()
        activeLoadId = loadId
        if loadedIdentity != identity {
            loadedIdentity = identity
            localStats = .empty(now: now)
            publicStats = nil
        }

        isLoading = true
        publicErrorMessage = nil
        defer {
            if activeLoadId == loadId {
                isLoading = false
            }
        }

        do {
            let local = try await dependencies.loadLocalStats(
                normalizedName,
                speciesId,
                modelContext.container,
                now
            )
            guard activeLoadId == loadId, !Task.isCancelled else { return }
            localStats = local
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadId == loadId, !Task.isCancelled else { return }
            localStats = .empty(now: now)
        }

        guard let dictionarySpeciesId = identity.speciesId else {
            guard activeLoadId == loadId else { return }
            publicStats = nil
            publicErrorMessage = nil
            return
        }

        do {
            let stats = try await dependencies.loadPublicStats(
                dictionarySpeciesId,
                normalizedName
            )
            guard activeLoadId == loadId, !Task.isCancelled else { return }
            publicStats = stats
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadId == loadId, !Task.isCancelled else { return }
            publicStats = nil
            publicErrorMessage = dependencies.publicErrorMessage(error)
        }
    }
}
