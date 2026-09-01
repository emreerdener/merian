import Foundation

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
