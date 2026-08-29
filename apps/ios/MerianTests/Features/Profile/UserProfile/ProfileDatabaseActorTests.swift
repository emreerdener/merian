import SwiftData
import XCTest

@testable import Merian

@MainActor
final class ProfileDatabaseActorTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([LocalScanRecord.self])
        container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    override func tearDownWithError() throws {
        container = nil
    }

    private func insertScans(
        dayOffsets: [Int]
    ) throws -> ProfileDatabaseActor {
        let context = container.mainContext
        let calendar = Calendar.current
        let noonToday = try XCTUnwrap(
            calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: Date()
            )
        )

        for offset in dayOffsets {
            let targetDate = try XCTUnwrap(
                calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: noonToday
                )
            )
            let scan = LocalScanRecord(
                speciesId: UUID().uuidString,
                scientificName: "Test Species \(offset)_\(UUID().uuidString.prefix(4))",
                commonName: "Test",
                timestamp: targetDate,
                ecologyType: "unknown"
            )
            context.insert(scan)
        }

        try context.save()
        return ProfileDatabaseActor(modelContainer: container)
    }

    func testNewAccountStillReturnsLockedAchievements() async {
        let actor = ProfileDatabaseActor(modelContainer: container)
        let payload: ProfileAllStatsPayload = await actor.calculateAll()

        XCTAssertEqual(payload.awards.count, AchievementType.allCases.count)
        XCTAssertTrue(
            payload.awards.allSatisfy {
                !$0.isCompleted && $0.currentCount == 0
            }
        )
        XCTAssertEqual(payload.heatmap.totalCaptures, 0)
        XCTAssertEqual(payload.heatmap.currentMonthCaptures, 0)
        XCTAssertEqual(payload.heatmap.weeks.count, 52)
        XCTAssertTrue(
            payload.heatmap.weeks.allSatisfy { $0.days.count == 7 }
        )
        XCTAssertTrue(
            payload.heatmap.weeks
                .flatMap(\.days)
                .allSatisfy { $0.count < 1 }
        )
    }

    func testProfileProjectionCacheRefreshesAfterInsertedScan() async throws {
        let context = container.mainContext
        let firstScan = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Quercus alba",
            commonName: "White Oak",
            timestamp: Date().addingTimeInterval(-60),
            ecologyType: "forest",
            taxonomyKingdom: "Plantae"
        )
        context.insert(firstScan)
        try context.save()

        let actor = ProfileDatabaseActor(modelContainer: container)
        let initialPayload = await actor.calculateAll()
        XCTAssertEqual(initialPayload.speciesCount, 1)
        XCTAssertEqual(initialPayload.heatmap.totalCaptures, 1)

        let secondScan = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Amanita muscaria",
            commonName: "Fly Agaric",
            timestamp: Date(),
            ecologyType: "forest",
            taxonomyKingdom: "Fungi"
        )
        context.insert(secondScan)
        try context.save()

        let refreshedStats = await actor.calculateProfileStats()
        let refreshedHeatmap = await actor.calculateHeatmapData()
        let refreshedAwards = await actor.calculateAwardsProjection()
        let explorerAward = refreshedAwards.first { $0.type == .explorer }

        XCTAssertEqual(refreshedStats.speciesCount, 2)
        XCTAssertEqual(refreshedHeatmap.totalCaptures, 2)
        XCTAssertEqual(explorerAward?.currentCount, 2)

        await actor.invalidateCachedProfileProjections()
        let invalidatedPayload = await actor.calculateAll()
        XCTAssertEqual(invalidatedPayload.speciesCount, 2)
    }

    func testPostInferenceAwardsRefreshAfterInPlaceScanMutation() async throws {
        let context = container.mainContext
        let scan = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Amanita muscaria",
            commonName: "Fly Agaric",
            ecologyType: "forest",
            taxonomyKingdom: "Plantae"
        )
        context.insert(scan)
        try context.save()

        let actor = ProfileDatabaseActor(modelContainer: container)
        let initialAwards = await actor.calculateAwards()
        XCTAssertEqual(
            initialAwards.first { $0.type == .fungi }?.currentCount,
            0
        )

        scan.taxonomyKingdom = "Fungi"
        try context.save()

        let refreshedAwards = await actor.calculateAwards()
        XCTAssertEqual(
            refreshedAwards.first { $0.type == .fungi }?.currentCount,
            1
        )
    }

    func testStreakUsesYesterdayAsGraceAnchor() async throws {
        let actor = try insertScans(dayOffsets: [-1, -2, -3])
        let payload: ProfileAllStatsPayload = await actor.calculateAll()

        XCTAssertEqual(payload.streak, 3)
    }

    func testStreakBreaksAfterMissedYesterday() async throws {
        let actor = try insertScans(dayOffsets: [-2, -3, -4])
        let payload: ProfileAllStatsPayload = await actor.calculateAll()

        XCTAssertEqual(payload.streak, 0)
    }

    func testStreakDeduplicatesMultipleScansOnSameDay() async throws {
        let actor = try insertScans(dayOffsets: [-1, -1, -2, -3])
        let payload: ProfileAllStatsPayload = await actor.calculateAll()

        XCTAssertEqual(payload.streak, 3)
    }

    func testHeatmapMatrixBounds() async throws {
        let dayOffsets = (0..<500).map { -($0 % 351) }

        let actor = try insertScans(dayOffsets: dayOffsets)
        let heatmap = await actor.calculateHeatmapData()

        XCTAssertEqual(heatmap.weeks.count, 52)
        XCTAssertEqual(heatmap.totalCaptures, 500)

        for week in heatmap.weeks {
            XCTAssertEqual(week.days.count, 7)
        }
    }
}
