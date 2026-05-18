import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
struct SpeciesObservationStatsViewModelTests {
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        return ModelContext(container)
    }

    @Test func testLocalAggregationMatchesSpeciesAndBucketsByMonth() throws {
        let context = try createIsolatedContext()
        let speciesId = "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let now = date(year: 2026, month: 5, day: 17)

        context.insert(LocalScanRecord(
            speciesId: "legacy-a",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            timestamp: date(year: 2026, month: 1, day: 1),
            captureDate: date(year: 2026, month: 5, day: 3),
            lifeStage: "Adult"
        ))
        context.insert(LocalScanRecord(
            speciesId: "legacy-b",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            timestamp: date(year: 2025, month: 8, day: 4),
            lifeStage: "larva"
        ))
        context.insert(LocalScanRecord(
            speciesId: "legacy-c",
            scientificName: "Incorrectus testus",
            commonName: "Override",
            timestamp: date(year: 2026, month: 5, day: 10),
            lifeStage: "unknown",
            userIdentificationOverride: "Danaus plexippus"
        ))
        context.insert(LocalScanRecord(
            speciesId: "legacy-d",
            scientificName: "Other species",
            commonName: "Confirmed",
            timestamp: date(year: 2024, month: 4, day: 15),
            lifeStage: "pupa",
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

        let stats = SpeciesObservationStatsViewModel.fetchLocalStats(
            scientificName: "  Danaus   plexippus ",
            speciesId: speciesId,
            modelContext: context,
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

    @Test func testLocalHistoryUsesRollingSevenYearsThroughCurrentMonth() throws {
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

        let stats = SpeciesObservationStatsViewModel.fetchLocalStats(
            scientificName: "Danaus plexippus",
            speciesId: nil,
            modelContext: context,
            now: now
        )

        #expect(stats.history.first == SpeciesObservationHistoryCount(year: 2020, month: 1, count: 0))
        #expect(stats.history.last == SpeciesObservationHistoryCount(year: 2026, month: 5, count: 1))
        #expect(stats.history.count == 77)
        #expect(stats.seasonality.first(where: { $0.month == 12 })?.count == 1)
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
