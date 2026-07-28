import Foundation
import Observation
import SwiftData

struct SpeciesObservationLocalStats: Equatable, Sendable {
    let seasonality: [SpeciesObservationMonthCount]
    let history: [SpeciesObservationHistoryCount]
    let lifeStage: [SpeciesObservationCategorySeries]
    let totalObservations: Int
    let lastObservationDate: Date?

    static func empty(now: Date = Date()) -> SpeciesObservationLocalStats {
        SpeciesObservationLocalStats(
            seasonality: SpeciesObservationStatsReducer.emptyMonthCounts(),
            history: SpeciesObservationStatsReducer.emptyHistoryCounts(now: now),
            lifeStage: [],
            totalObservations: 0,
            lastObservationDate: nil
        )
    }
}

@ModelActor
actor SpeciesObservationStatsDatabaseActor {
    func fetchLocalStats(
        scientificName: String,
        speciesId: String?,
        now: Date = Date()
    ) -> SpeciesObservationLocalStats {
        let normalizedName = SpeciesObservationStatsReducer.normalizedScientificName(scientificName)
        let targetSpeciesId = SpeciesObservationStatsReducer.normalizedSpeciesId(speciesId)
        var recordsById: [String: LocalScanRecord] = [:]

        if let targetSpeciesId {
            for record in fetchCandidates(matchingSpeciesId: targetSpeciesId) {
                recordsById[record.id] = record
            }
        }

        for record in fetchCandidates(matchingScientificName: normalizedName) {
            recordsById[record.id] = record
        }

        let records = recordsById.values.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.id > $1.id
            }
            return $0.timestamp > $1.timestamp
        }

        return SpeciesObservationStatsReducer.reduceLocalStats(
            scientificName: normalizedName,
            speciesId: targetSpeciesId,
            records: records,
            now: now
        )
    }

    private func fetchCandidates(matchingSpeciesId speciesId: String) -> [LocalScanRecord] {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { record in
                record.isBiological == true &&
                (record.speciesId == speciesId || record.confirmedSpeciesId == speciesId)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.propertiesToFetch = Self.projectionProperties
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchCandidates(matchingScientificName scientificName: String) -> [LocalScanRecord] {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { record in
                record.isBiological == true &&
                (record.scientificName == scientificName || record.userIdentificationOverride == scientificName)
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.propertiesToFetch = Self.projectionProperties
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static let projectionProperties: [PartialKeyPath<LocalScanRecord>] = [
        \LocalScanRecord.id,
        \LocalScanRecord.speciesId,
        \LocalScanRecord.scientificName,
        \LocalScanRecord.userIdentificationOverride,
        \LocalScanRecord.confirmedSpeciesId,
        \LocalScanRecord.captureDate,
        \LocalScanRecord.timestamp,
        \LocalScanRecord.lifeStage,
        \LocalScanRecord.isBiological
    ]
}

@MainActor
@Observable
final class SpeciesObservationStatsViewModel {
    private(set) var isLoading = false
    private(set) var localStats = SpeciesObservationLocalStats.empty()
    private(set) var publicStats: SpeciesObservationStatsEntry?
    private(set) var publicErrorMessage: String?
    private var activeLoadId: UUID?

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
        let normalizedName = Self.normalizedScientificName(scientificName)
        guard !normalizedName.isEmpty else {
            localStats = .empty(now: now)
            publicStats = nil
            publicErrorMessage = nil
            return
        }

        let loadId = UUID()
        activeLoadId = loadId
        isLoading = true
        defer {
            if activeLoadId == loadId {
                isLoading = false
            }
        }
        publicErrorMessage = nil
        let statsActor = SpeciesObservationStatsDatabaseActor(modelContainer: modelContext.container)
        let local = await statsActor.fetchLocalStats(
            scientificName: normalizedName,
            speciesId: speciesId,
            now: now
        )
        if activeLoadId == loadId {
            localStats = local
        }

        guard let dictionarySpeciesId = SpeciesObservationStatsReducer.normalizedSpeciesId(speciesId) else {
            if activeLoadId == loadId {
                publicStats = nil
                publicErrorMessage = nil
            }
            return
        }

        do {
            let stats = try await MerianNetworkClient.shared.getSpeciesObservationStats(
                speciesId: dictionarySpeciesId,
                scientificName: normalizedName
            )
            if activeLoadId == loadId {
                publicStats = stats
            }
        } catch is CancellationError {
            return
        } catch {
            if activeLoadId == loadId {
                publicStats = nil
                publicErrorMessage = ExploreErrorFormatter.speciesStatsMessage(for: error)
            }
        }
    }

    nonisolated static func fetchLocalStats(
        scientificName: String,
        speciesId: String?,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> SpeciesObservationLocalStats {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { record in
                record.isBiological == true
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.propertiesToFetch = [
            \.id,
            \.speciesId,
            \.scientificName,
            \.userIdentificationOverride,
            \.confirmedSpeciesId,
            \.captureDate,
            \.timestamp,
            \.lifeStage,
            \.isBiological
        ]

        let records = (try? modelContext.fetch(descriptor)) ?? []
        return SpeciesObservationStatsReducer.reduceLocalStats(
            scientificName: scientificName,
            speciesId: speciesId,
            records: records,
            now: now
        )
    }

    nonisolated static func reduceLocalStats(
        scientificName: String,
        speciesId: String?,
        records: [LocalScanRecord],
        now: Date = Date()
    ) -> SpeciesObservationLocalStats {
        SpeciesObservationStatsReducer.reduceLocalStats(
            scientificName: scientificName,
            speciesId: speciesId,
            records: records,
            now: now
        )
    }

    nonisolated static func emptyMonthCounts() -> [SpeciesObservationMonthCount] {
        SpeciesObservationStatsReducer.emptyMonthCounts()
    }

    nonisolated static func emptyHistoryCounts(now: Date = Date()) -> [SpeciesObservationHistoryCount] {
        SpeciesObservationStatsReducer.emptyHistoryCounts(now: now)
    }

    nonisolated static func normalizedScientificName(_ value: String) -> String {
        SpeciesObservationStatsReducer.normalizedScientificName(value)
    }

    nonisolated static func normalizedSpeciesId(_ value: String?) -> String? {
        SpeciesObservationStatsReducer.normalizedSpeciesId(value)
    }
}
