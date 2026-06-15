import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Smart Default Collections")
@MainActor
struct SmartCollectionTests {
    let container: ModelContainer
    let context: ModelContext
    let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(
            for: LocalScanRecord.self, ScanCollection.self,
            OfflineQueuedScan.self, PendingCloudDeletionTask.self,
            configurations: configuration
        )
        self.context = container.mainContext
    }

    @Test("Empty and undersized libraries do not emit noisy suggestions")
    func testSmallLibrariesDoNotEmitSuggestions() throws {
        let scans = [
            try makeScan(name: "Single Bird", taxonomyClass: "aves", timestamp: referenceDate)
        ]

        let suggestions = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            referenceDate: referenceDate
        )

        #expect(suggestions.isEmpty)
    }

    @Test("Suggestions respect thresholds, ranking, and duplicate collection suppression")
    func testSuggestionRankingAndSuppression() throws {
        let existingBirds = ScanCollection(name: "Birds")
        context.insert(existingBirds)

        let reviewScans = try (0..<2).map {
            try makeScan(
                name: "Review Bird \($0)",
                taxonomyClass: "aves",
                confidenceScore: 0.82,
                candidatesData: Data([1]),
                timestamp: referenceDate.addingTimeInterval(TimeInterval(-$0))
            )
        }
        let recentPlants = try (0..<3).map {
            try makeScan(
                name: "Recent Plant \($0)",
                taxonomyKingdom: "plantae",
                timestamp: referenceDate.addingTimeInterval(TimeInterval(-100 - $0))
            )
        }
        let olderBirds = try (0..<3).map {
            try makeScan(
                name: "Older Bird \($0)",
                taxonomyClass: "aves",
                timestamp: referenceDate.addingTimeInterval(TimeInterval(-40 * 24 * 60 * 60 - $0))
            )
        }
        let invasive = try (0..<2).map {
            try makeScan(
                name: "Invasive Plant \($0)",
                taxonomyKingdom: "plantae",
                isInvasive: true,
                timestamp: referenceDate.addingTimeInterval(TimeInterval(-200 - $0))
            )
        }

        try context.save()

        let suggestions = SmartCollectionSuggester.suggestions(
            from: reviewScans + recentPlants + olderBirds + invasive,
            existingCollections: [existingBirds],
            referenceDate: referenceDate
        )

        #expect(suggestions.map(\.title).first == "Needs review")
        #expect(suggestions.map(\.title).contains("Recent finds"))
        #expect(suggestions.map(\.title).contains("Invasive finds"))
        #expect(!suggestions.map(\.title).contains("Birds"))
    }

    @Test("Location suggestions normalize punctuation and spacing")
    func testLocationNormalization() throws {
        let scans = [
            try makeScan(name: "Park Oak 1", locationName: "Central Park", timestamp: referenceDate),
            try makeScan(name: "Park Oak 2", locationName: "central-park", timestamp: referenceDate.addingTimeInterval(-10)),
            try makeScan(name: "Park Oak 3", locationName: "  Central   Park  ", timestamp: referenceDate.addingTimeInterval(-20))
        ]

        let suggestions = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            referenceDate: referenceDate
        )

        #expect(suggestions.map(\.title).contains("Central Park finds"))
        #expect(SmartCollectionSuggester.normalizedLocationName("central-park") == "central park")
    }

    @Test("Saving a smart collection creates a regular collection with collision-safe naming")
    func testSaveSmartCollectionCreatesSyncedCollectionSnapshot() throws {
        let existing = ScanCollection(name: "Recent finds")
        let existingTwo = ScanCollection(name: "Recent finds 2")
        context.insert(existing)
        context.insert(existingTwo)

        let scans = try (0..<3).map {
            try makeScan(
                name: "Recent \($0)",
                timestamp: referenceDate.addingTimeInterval(TimeInterval(-$0))
            )
        }
        try context.save()

        let snapshot = try #require(SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            referenceDate: referenceDate
        ).first { $0.title == "Recent finds" })

        let saved = try SmartCollectionSaver.save(
            snapshot: snapshot,
            existingCollections: [existing, existingTwo],
            modelContext: context,
            enqueueSync: false
        )

        #expect(saved.name == "Recent finds 3")
        #expect(saved.scans?.count == 3)
        #expect(scans.allSatisfy { scan in
            scan.collections?.contains(where: { $0.id == saved.id }) == true
        })
    }

    private func makeScan(
        name: String,
        taxonomyKingdom: String? = nil,
        taxonomyClass: String? = nil,
        locationName: String? = nil,
        isInvasive: Bool = false,
        hazardType: String = "none",
        confidenceScore: Double = 0.995,
        candidatesData: Data? = nil,
        userReviewState: UserReviewState = .unreviewed,
        timestamp: Date
    ) throws -> LocalScanRecord {
        let record = LocalScanRecord(
            id: UUID().uuidString,
            speciesId: UUID().uuidString,
            scientificName: "\(name.replacingOccurrences(of: " ", with: "")) testii",
            commonName: name,
            timestamp: timestamp,
            semanticTags: [name],
            hazardType: hazardType,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: isInvasive,
            ecologyType: "wild",
            confidenceScore: confidenceScore,
            taxonomyKingdom: taxonomyKingdom,
            taxonomyClass: taxonomyClass,
            locationName: locationName,
            candidatesData: candidatesData,
            inferenceTier: "pro",
            userReviewStateRaw: userReviewState.rawValue
        )
        context.insert(record)
        return record
    }
}
