import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
struct SpeciesObservationStatsReducerTests {
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        return ModelContext(container)
    }

    @Test func testLocalAggregationMatchesSpeciesAndBucketsByMonth() async throws {
        let context = try createIsolatedContext()
        let speciesId = "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let now = date(year: 2026, month: 5, day: 17)

        context.insert(LocalScanRecord(
            speciesId: "legacy-a",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            timestamp: date(year: 2026, month: 1, day: 1),
            captureDate: date(year: 2026, month: 5, day: 3),
            lifeStage: "Adult",
            sex: "female"
        ))
        context.insert(LocalScanRecord(
            speciesId: "legacy-b",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            timestamp: date(year: 2025, month: 8, day: 4),
            lifeStage: "larva",
            sex: "male"
        ))
        context.insert(LocalScanRecord(
            speciesId: "legacy-c",
            scientificName: "Incorrectus testus",
            commonName: "Override",
            timestamp: date(year: 2026, month: 5, day: 10),
            lifeStage: "unknown",
            sex: "cannot_determine",
            userIdentificationOverride: "Danaus plexippus"
        ))
        context.insert(LocalScanRecord(
            speciesId: "legacy-d",
            scientificName: "Other species",
            commonName: "Confirmed",
            timestamp: date(year: 2024, month: 4, day: 15),
            lifeStage: "pupa",
            sex: "mixed",
            confirmedSpeciesId: speciesId
        ))
        context.insert(LocalScanRecord(
            speciesId: "nonbio",
            scientificName: "Danaus plexippus",
            commonName: "Nonbio",
            timestamp: date(year: 2026, month: 5, day: 12),
            isBiological: false,
            lifeStage: "Adult"
        ))
        context.insert(LocalScanRecord(
            speciesId: "other",
            scientificName: "Danaus gilippus",
            commonName: "Queen",
            timestamp: date(year: 2026, month: 5, day: 12),
            lifeStage: "Adult"
        ))
        try context.save()

        let actor = SpeciesObservationStatsDatabaseActor(modelContainer: context.container)
        let stats = await actor.fetchLocalStats(
            scientificName: "  Danaus   plexippus ",
            speciesId: speciesId,
            now: now
        )

        #expect(stats.totalObservations == 4)
        #expect(stats.seasonality.first(where: { $0.month == 4 })?.count == 1)
        #expect(stats.seasonality.first(where: { $0.month == 5 })?.count == 2)
        #expect(stats.seasonality.first(where: { $0.month == 8 })?.count == 1)
        #expect(stats.history.first(where: { $0.year == 2024 && $0.month == 4 })?.count == 1)
        #expect(stats.history.first(where: { $0.year == 2025 && $0.month == 8 })?.count == 1)
        #expect(stats.history.first(where: { $0.year == 2026 && $0.month == 5 })?.count == 2)
        #expect(stats.lifeStage.map(\.key).sorted() == ["adult", "larva", "pupa"])
        #expect(stats.lifeStage.first(where: { $0.key == "adult" })?.values.first(where: { $0.month == 5 })?.count == 1)
        #expect(stats.lifeStage.first(where: { $0.key == "larva" })?.values.first(where: { $0.month == 8 })?.count == 1)
    }

    @Test func testLocalHistoryUsesRollingSevenYearsThroughCurrentMonth() async throws {
        let context = try createIsolatedContext()
        let now = date(year: 2026, month: 5, day: 17)
        context.insert(LocalScanRecord(
            speciesId: "old",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            timestamp: date(year: 2019, month: 12, day: 31),
            lifeStage: "Adult"
        ))
        context.insert(LocalScanRecord(
            speciesId: "current-month",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            timestamp: date(year: 2026, month: 5, day: 1),
            lifeStage: "Adult"
        ))
        try context.save()

        let actor = SpeciesObservationStatsDatabaseActor(modelContainer: context.container)
        let stats = await actor.fetchLocalStats(
            scientificName: "Danaus plexippus",
            speciesId: nil,
            now: now
        )

        #expect(stats.history.first == SpeciesObservationHistoryCount(year: 2020, month: 1, count: 0))
        #expect(stats.history.last == SpeciesObservationHistoryCount(year: 2026, month: 5, count: 1))
        #expect(stats.history.count == 77)
        #expect(stats.seasonality.first(where: { $0.month == 12 })?.count == 1)
    }

    @Test func testReducerNormalizationAndEmptyBuckets() {
        #expect(SpeciesObservationStatsReducer.normalizedScientificName("  Danaus   plexippus ") == "Danaus plexippus")
        #expect(SpeciesObservationStatsReducer.normalizedSpeciesId("  ABC-123 ") == "abc-123")
        #expect(SpeciesObservationStatsReducer.emptyMonthCounts().count == 12)
        #expect(SpeciesObservationStatsReducer.emptyHistoryCounts(now: date(year: 2026, month: 5, day: 17)).count == 77)
    }

    @Test func testObservationCardRequiresChartDataRatherThanOnlyAPublicTotal() {
        let publicStatsWithoutChartData = publicStats(
            totalObservations: 7_791,
            seasonality: SpeciesObservationStatsReducer.emptyMonthCounts()
        )

        #expect(!SpeciesObservationStatsViewModel.hasAnyData(
            localStats: .empty(),
            publicStats: publicStatsWithoutChartData
        ))

        let publicStatsWithHistory = publicStats(
            totalObservations: 7_791,
            history: [SpeciesObservationHistoryCount(year: 2026, month: 7, count: 1)]
        )

        #expect(SpeciesObservationStatsViewModel.hasAnyData(
            localStats: .empty(),
            publicStats: publicStatsWithHistory
        ))
    }

    @Test func testSeasonalityHeatmapDerivesSparseAvailableMonths() {
        let model = SpeciesSeasonalityHeatmapModel.make(
            localValues: monthCounts([5: 1]),
            localTotal: 1,
            publicValues: nil,
            publicTotal: nil
        )

        #expect(model.hasContent)
        #expect(model.total == 1)
        #expect(model.cells.first(where: { $0.month == 5 })?.count == 1)
        #expect(model.cells.first(where: { $0.month == 5 })?.intensity == 1)
        #expect(model.cells.first(where: { $0.month == 4 })?.count == 0)
        #expect(model.totalLine == "1 observation")
        #expect(model.detailLine == "Peak May: 1 observation")
    }

    @Test func testSeasonalityHeatmapFadesAroundObservedMonths() {
        let model = SpeciesSeasonalityHeatmapModel.make(
            localValues: monthCounts([3: 1]),
            localTotal: 1,
            publicValues: nil,
            publicTotal: nil
        )

        #expect(model.cells.first(where: { $0.month == 3 })?.intensity == 1)
        #expect(model.cells.first(where: { $0.month == 3 })?.displayIntensity == 1)
        #expect(model.cells.first(where: { $0.month == 2 })?.count == 0)
        #expect(model.cells.first(where: { $0.month == 2 })?.displayIntensity == 0.42)
        #expect(model.cells.first(where: { $0.month == 1 })?.displayIntensity == 0.18)
        #expect(model.cells.first(where: { $0.month == 12 })?.displayIntensity == 0)
    }

    @Test func testSeasonalityHeatmapFadeWrapsAcrossYearBoundary() {
        let model = SpeciesSeasonalityHeatmapModel.make(
            localValues: monthCounts([12: 1]),
            localTotal: 1,
            publicValues: nil,
            publicTotal: nil
        )

        #expect(model.cells.first(where: { $0.month == 12 })?.displayIntensity == 1)
        #expect(model.cells.first(where: { $0.month == 1 })?.displayIntensity == 0.42)
        #expect(model.cells.first(where: { $0.month == 2 })?.displayIntensity == 0.18)
    }

    @Test func testSeasonalityHeatmapMarksMissingBucketsUnavailable() {
        let model = SpeciesSeasonalityHeatmapModel.make(
            localValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            localTotal: 0,
            publicValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            publicTotal: 89
        )

        #expect(model.hasContent)
        #expect(model.seasonalityUnavailable)
        #expect(model.hasObservations == false)
        #expect(model.detailLine == nil)
    }

    @Test func testSeasonalityHeatmapLabelsRepresentedTotalWhenBucketsAreMissing() {
        let model = SpeciesSeasonalityHeatmapModel.make(
            localValues: monthCounts([8: 1]),
            localTotal: 1,
            publicValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            publicTotal: 462
        )

        #expect(model.seasonalityUnavailable)
        #expect(model.total == 1)
        #expect(model.totalLine == "1 observation represented")
        #expect(model.detailLine == "Peak Aug: 1 observation")
    }

    @Test func testSeasonalityHeatmapCombinesAvailableSources() {
        let localAvailable = SpeciesSeasonalityHeatmapModel.make(
            localValues: monthCounts([4: 1]),
            localTotal: 1,
            publicValues: nil,
            publicTotal: nil
        )
        let externalAvailable = SpeciesSeasonalityHeatmapModel.make(
            localValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            localTotal: 0,
            publicValues: monthCounts([8: 12]),
            publicTotal: 12
        )
        let combined = SpeciesSeasonalityHeatmapModel.make(
            localValues: monthCounts([5: 1]),
            localTotal: 1,
            publicValues: monthCounts([5: 3, 6: 2]),
            publicTotal: 5
        )
        let empty = SpeciesSeasonalityHeatmapModel.make(
            localValues: SpeciesObservationStatsReducer.emptyMonthCounts(),
            localTotal: 0,
            publicValues: nil,
            publicTotal: nil
        )

        #expect(localAvailable.cells.first(where: { $0.month == 4 })?.count == 1)
        #expect(externalAvailable.total == 12)
        #expect(externalAvailable.cells.first(where: { $0.month == 8 })?.count == 12)
        #expect(combined.total == 6)
        #expect(combined.cells.first(where: { $0.month == 5 })?.count == 4)
        #expect(combined.cells.first(where: { $0.month == 6 })?.count == 2)
        #expect(combined.cells.first(where: { $0.month == 4 })?.displayIntensity == 0.42)
        #expect(combined.totalLine == "6 observations")
        #expect(combined.detailLine == "Peak May: 4 observations")
        #expect(empty.hasContent == false)
    }

    private func monthCounts(_ countsByMonth: [Int: Int]) -> [SpeciesObservationMonthCount] {
        (1...12).map { month in
            SpeciesObservationMonthCount(month: month, count: countsByMonth[month, default: 0])
        }
    }

    private func publicStats(
        totalObservations: Int,
        seasonality: [SpeciesObservationMonthCount] = [],
        history: [SpeciesObservationHistoryCount] = [],
        lifeStage: [SpeciesObservationCategorySeries] = []
    ) -> SpeciesObservationStatsEntry {
        SpeciesObservationStatsEntry(
            speciesId: "species-id",
            scientificName: "Muntiacus reevesi",
            source: SpeciesObservationStatsSource(
                provider: "inaturalist",
                scope: "global",
                inaturalistTaxonId: nil,
                fetchedAt: "2026-07-17T00:00:00Z"
            ),
            status: .partial,
            totalObservations: totalObservations,
            lastObservationDate: nil,
            fetchedAt: "2026-07-17T00:00:00Z",
            providerErrors: [],
            seasonality: seasonality,
            history: history,
            lifeStage: lifeStage
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date ?? Date()
    }
}
