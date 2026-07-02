import Foundation
@testable import Merian
import SwiftData
import Testing

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

    @Test("Featured scans snapshot is available outside normal suggestions")
    func testFeaturedSnapshotIsSeparateFromSuggestions() throws {
        let scans = [
            try makeScan(id: "featured-newest", name: "Newest Feature", timestamp: referenceDate),
            try makeScan(id: "featured-older", name: "Older Feature", timestamp: referenceDate.addingTimeInterval(-10))
        ]

        let featured = try #require(SmartCollectionSuggester.featuredSnapshot(from: scans))
        let suggestions = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            referenceDate: referenceDate
        )
        let refreshed = SmartCollectionSuggester.refreshedSnapshot(for: featured, from: scans)

        #expect(featured.title == "Featured scans")
        #expect(featured.count == 2)
        #expect(featured.coverScan?.id == "featured-newest")
        #expect(refreshed.scans.map(\.id) == ["featured-newest", "featured-older"])
        #expect(!suggestions.map(\.title).contains("Featured scans"))
        #expect(SmartCollectionSuggester.featuredSnapshot(
            from: scans,
            hiddenCollectionIDs: [featured.id]
        ) == nil)
    }

    @Test("Featured scans cap and rotate daily")
    func testFeaturedScansCapAndRotateDaily() throws {
        let scans = try (0..<30).map { index in
            try makeScan(
                id: "featured-\(index)",
                name: "Featured \(index)",
                timestamp: referenceDate.addingTimeInterval(TimeInterval(-index))
            )
        }
        try context.save()

        let today = try #require(SmartCollectionSuggester.featuredSnapshot(
            from: scans,
            referenceDate: referenceDate
        ))
        let sameDay = try #require(SmartCollectionSuggester.featuredSnapshot(
            from: scans,
            referenceDate: referenceDate.addingTimeInterval(60 * 60)
        ))
        let nextDay = try #require(SmartCollectionSuggester.featuredSnapshot(
            from: scans,
            referenceDate: referenceDate.addingTimeInterval(24 * 60 * 60)
        ))

        #expect(today.count == 24)
        #expect(Set(today.scans.map(\.id)).count == 24)
        #expect(today.scans.map(\.id) == sameDay.scans.map(\.id))
        #expect(today.scans.map(\.id) != nextDay.scans.map(\.id))
    }

    @Test("Suggestions respect thresholds, ranking, and duplicate collection suppression")
    func testSuggestionRankingAndSuppression() throws {
        let existingBirds = ScanCollection(name: "Birds")
        context.insert(existingBirds)

        let reviewScans = try (0..<2).map {
            try makeScan(
                name: "Review Bird \($0)",
                taxonomyClass: "aves",
                confidenceScore: 0.58,
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

        #expect(suggestions.map(\.title).contains("Central Park"))
        #expect(SmartCollectionSuggester.normalizedLocationName("central-park") == "central park")
    }

    @Test("Needs review is based on confidence, not candidate presence")
    func testNeedsReviewIgnoresCandidatesWhenConfidenceIsStrong() throws {
        let scans = try (0..<2).map {
            try makeScan(
                name: "Strong Candidate \($0)",
                confidenceScore: 0.92,
                candidatesData: Data([1]),
                timestamp: referenceDate.addingTimeInterval(TimeInterval(-$0))
            )
        }

        let suggestions = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            referenceDate: referenceDate
        )

        #expect(!suggestions.map(\.title).contains("Needs review"))
    }

    @Test("Needs review includes non-strong identifications even without competitive alternatives")
    func testNeedsReviewIncludesNonStrongIdentifications() throws {
        let candidates = try encodedCandidates(confidenceScores: [0.70])
        let scans = [
            try makeScan(
                name: "Possible Flash With Weak Alternative",
                confidenceScore: 0.90,
                candidatesData: candidates,
                inferenceTier: "flash",
                timestamp: referenceDate
            ),
            try makeScan(
                name: "Possible Flash Without Alternatives",
                confidenceScore: 0.90,
                inferenceTier: "flash",
                timestamp: referenceDate.addingTimeInterval(-1)
            )
        ]

        let suggestions = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            referenceDate: referenceDate
        )
        let snapshot = try #require(suggestions.first { $0.title == "Needs review" })

        #expect(snapshot.count == 2)
    }

    @Test("Needs review includes strong identifications only when an alternative is competitive")
    func testNeedsReviewIncludesStrongCompetitiveAlternatives() throws {
        let competitiveCandidates = try encodedCandidates(confidenceScores: [0.82])
        let weakCandidates = try encodedCandidates(confidenceScores: [0.70])
        let scans = [
            try makeScan(
                name: "Competitive Flash 1",
                confidenceScore: 0.96,
                candidatesData: competitiveCandidates,
                inferenceTier: "flash",
                timestamp: referenceDate
            ),
            try makeScan(
                name: "Competitive Flash 2",
                confidenceScore: 0.96,
                candidatesData: competitiveCandidates,
                inferenceTier: "flash",
                timestamp: referenceDate.addingTimeInterval(-1)
            ),
            try makeScan(
                name: "Weak Flash",
                confidenceScore: 0.96,
                candidatesData: weakCandidates,
                inferenceTier: "flash",
                timestamp: referenceDate.addingTimeInterval(-2)
            )
        ]

        let suggestions = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            referenceDate: referenceDate
        )
        let snapshot = try #require(suggestions.first { $0.title == "Needs review" })

        #expect(snapshot.count == 2)
        #expect(snapshot.scans.allSatisfy { $0.commonName.hasPrefix("Competitive Flash") })
    }

    @Test("Needs review suppresses reviewed or flagged scans")
    func testNeedsReviewSuppressesReviewedStates() throws {
        let candidates = try encodedCandidates(confidenceScores: [0.82])
        let scans = [
            try makeScan(
                name: "Confirmed Flash",
                confidenceScore: 0.90,
                candidatesData: candidates,
                userConfirmedIdentification: true,
                inferenceTier: "flash",
                timestamp: referenceDate
            ),
            try makeScan(
                name: "Overridden Flash",
                confidenceScore: 0.90,
                candidatesData: candidates,
                userIdentificationOverride: "Danaus plexippus",
                inferenceTier: "flash",
                timestamp: referenceDate.addingTimeInterval(-1)
            ),
            try makeScan(
                name: "Flagged Flash",
                confidenceScore: 0.90,
                candidatesData: candidates,
                isFlagged: true,
                inferenceTier: "flash",
                timestamp: referenceDate.addingTimeInterval(-2)
            )
        ]

        let suggestions = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            referenceDate: referenceDate
        )

        #expect(!suggestions.map(\.title).contains("Needs review"))
    }

    @Test("Shared scans emit a smart collection and respect duplicate suppression")
    func testSharedScansEmitSmartCollection() throws {
        let sharedScan = try makeScan(name: "Shared Oak", timestamp: referenceDate)
        let privateScan = try makeScan(name: "Private Oak", timestamp: referenceDate.addingTimeInterval(-10))
        let sharedPostIDProvider: (String) -> String? = { scanId in
            scanId == sharedScan.id ? "post-shared-oak" : nil
        }

        let suggestions = SmartCollectionSuggester.suggestions(
            from: [sharedScan, privateScan],
            existingCollections: [],
            sharedPostIDProvider: sharedPostIDProvider,
            referenceDate: referenceDate
        )
        let sharedSnapshot = try #require(suggestions.first { $0.title == "Explore posts" })

        #expect(sharedSnapshot.count == 1)
        #expect(sharedSnapshot.scans.first?.id == sharedScan.id)

        let duplicate = ScanCollection(name: "Explore posts")
        let suppressedSuggestions = SmartCollectionSuggester.suggestions(
            from: [sharedScan, privateScan],
            existingCollections: [duplicate],
            sharedPostIDProvider: sharedPostIDProvider,
            referenceDate: referenceDate
        )

        #expect(!suppressedSuggestions.map(\.title).contains("Explore posts"))
    }

    @Test("Non-recent smart collection covers use stable randomized matching scans")
    func testNonRecentCoversUseStableRandomizedScans() throws {
        let sharedScans = [
            try makeScan(id: "newest-shared", name: "Newest Shared Oak", timestamp: referenceDate),
            try makeScan(id: "older-shared", name: "Older Shared Oak", timestamp: referenceDate.addingTimeInterval(-10)),
            try makeScan(id: "oldest-shared", name: "Oldest Shared Oak", timestamp: referenceDate.addingTimeInterval(-20))
        ]
        let sharedIDs = Set(sharedScans.map(\.id))
        let sharedSuggestions = SmartCollectionSuggester.suggestions(
            from: sharedScans,
            existingCollections: [],
            sharedPostIDProvider: { sharedIDs.contains($0) ? "post-\($0)" : nil },
            referenceDate: referenceDate
        )
        let sharedSnapshot = try #require(sharedSuggestions.first { $0.title == "Explore posts" })

        #expect(sharedSnapshot.scans.first?.id == "newest-shared")
        #expect(sharedSnapshot.coverScan?.id == "oldest-shared")

        let locationScans = [
            try makeScan(id: "scan-a", name: "Park Oak A", locationName: "Central Park", timestamp: referenceDate),
            try makeScan(id: "scan-b", name: "Park Oak B", locationName: "Central Park", timestamp: referenceDate.addingTimeInterval(-10)),
            try makeScan(id: "scan-c", name: "Park Oak C", locationName: "Central Park", timestamp: referenceDate.addingTimeInterval(-20))
        ]
        let locationSuggestions = SmartCollectionSuggester.suggestions(
            from: locationScans,
            existingCollections: [],
            sharedPostIDProvider: { _ in nil },
            referenceDate: referenceDate
        )
        let locationSnapshot = try #require(locationSuggestions.first { $0.title == "Central Park" })

        #expect(locationSnapshot.scans.first?.id == "scan-a")
        #expect(locationSnapshot.coverScan?.id == "scan-b")

        let plantScans = [
            try makeScan(id: "newest-tax", name: "Newest Plant", taxonomyKingdom: "plantae", timestamp: referenceDate),
            try makeScan(id: "older-tax", name: "Older Plant", taxonomyKingdom: "plantae", timestamp: referenceDate.addingTimeInterval(-10)),
            try makeScan(id: "oldest-tax", name: "Oldest Plant", taxonomyKingdom: "plantae", timestamp: referenceDate.addingTimeInterval(-20))
        ]
        let taxonomySuggestions = SmartCollectionSuggester.suggestions(
            from: plantScans,
            existingCollections: [],
            sharedPostIDProvider: { _ in nil },
            referenceDate: referenceDate
        )
        let taxonomySnapshot = try #require(taxonomySuggestions.first { $0.title == "Plants" })

        #expect(taxonomySnapshot.scans.first?.id == "newest-tax")
        #expect(taxonomySnapshot.coverScan?.id == "older-tax")
    }

    @Test("Recent finds cover remains the newest matching scan")
    func testRecentFindsCoverUsesNewestScan() throws {
        let recentScans = [
            try makeScan(id: "recent-newest", name: "Newest Recent", timestamp: referenceDate),
            try makeScan(id: "recent-older", name: "Older Recent", timestamp: referenceDate.addingTimeInterval(-10)),
            try makeScan(id: "recent-oldest", name: "Oldest Recent", timestamp: referenceDate.addingTimeInterval(-20))
        ]
        let suggestions = SmartCollectionSuggester.suggestions(
            from: recentScans,
            existingCollections: [],
            sharedPostIDProvider: { _ in nil },
            referenceDate: referenceDate
        )
        let recentSnapshot = try #require(suggestions.first { $0.title == "Recent finds" })

        #expect(recentSnapshot.scans.first?.id == "recent-newest")
        #expect(recentSnapshot.coverScan?.id == "recent-newest")
    }

    @Test("Hidden smart collection ids suppress suggestions until reset")
    func testHiddenSmartCollectionIDsSuppressAndReset() throws {
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

        let hiddenSuggestions = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            hiddenCollectionIDs: [snapshot.id],
            referenceDate: referenceDate
        )
        #expect(!hiddenSuggestions.map(\.title).contains("Recent finds"))

        let suiteName = "SmartCollectionTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let storedIDs = SmartCollectionPreferences.hide(id: snapshot.id, defaults: defaults)
        #expect(storedIDs == [snapshot.id])
        #expect(SmartCollectionPreferences.hiddenIDs(defaults: defaults) == [snapshot.id])

        SmartCollectionPreferences.clearHiddenIDs(defaults: defaults)
        #expect(SmartCollectionPreferences.hiddenIDs(defaults: defaults).isEmpty)

        let restoredSuggestions = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            hiddenCollectionIDs: SmartCollectionPreferences.hiddenIDs(defaults: defaults),
            referenceDate: referenceDate
        )
        #expect(restoredSuggestions.map(\.title).contains("Recent finds"))
    }

    @Test("Needs review cannot be hidden")
    func testNeedsReviewCannotBeHidden() throws {
        let scans = try (0..<2).map {
            try makeScan(
                name: "Review \($0)",
                confidenceScore: 0.42,
                timestamp: referenceDate.addingTimeInterval(TimeInterval(-$0))
            )
        }
        try context.save()

        let snapshot = try #require(SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            referenceDate: referenceDate
        ).first { $0.title == "Needs review" })
        #expect(!snapshot.isHideable)

        let hiddenSuggestions = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: [],
            hiddenCollectionIDs: [snapshot.id],
            referenceDate: referenceDate
        )
        #expect(hiddenSuggestions.map(\.title).contains("Needs review"))

        let suiteName = "SmartCollectionNeedsReviewTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let storedIDs = SmartCollectionPreferences.hide(id: snapshot.id, defaults: defaults)
        #expect(storedIDs.isEmpty)
        #expect(SmartCollectionPreferences.hiddenIDs(defaults: defaults).isEmpty)
    }

    private func makeScan(
        id: String = UUID().uuidString,
        name: String,
        taxonomyKingdom: String? = nil,
        taxonomyClass: String? = nil,
        locationName: String? = nil,
        isInvasive: Bool = false,
        hazardType: String = "none",
        confidenceScore: Double = 0.995,
        candidatesData: Data? = nil,
        userIdentificationOverride: String? = nil,
        userConfirmedIdentification: Bool = false,
        isFlagged: Bool = false,
        userReviewState: UserReviewState = .unreviewed,
        inferenceTier: String = "pro",
        timestamp: Date
    ) throws -> LocalScanRecord {
        let record = LocalScanRecord(
            id: id,
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
            inferenceTier: inferenceTier,
            userIdentificationOverride: userIdentificationOverride,
            userConfirmedIdentification: userConfirmedIdentification,
            isFlagged: isFlagged,
            userReviewStateRaw: userReviewState.rawValue
        )
        context.insert(record)
        return record
    }

    private func encodedCandidates(confidenceScores: [Double]) throws -> Data {
        let candidates = confidenceScores.enumerated().map { index, confidenceScore in
            IdentificationCandidate(
                scientificName: "Candidate\(index) testii",
                confidenceScore: confidenceScore
            )
        }
        return try JSONEncoder().encode(candidates)
    }
}
