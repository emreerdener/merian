@testable import Merian
import XCTest

final class AchievementsCalculatorTests: XCTestCase {

    // MARK: - Mock Factory

    private func mockScan(
        id: String = UUID().uuidString,
        speciesId: String? = nil,
        scientificName: String = "Test Species",
        commonName: String? = nil,
        timestamp: Date = Date(),
        captureDate: Date? = nil,
        weatherTemperatureF: Double? = nil,
        gpsElevation: Double? = nil,
        taxonomyKingdom: String? = nil,
        taxonomyClass: String? = nil,
        ecologyType: String = "unknown",
        isInvasive: Bool = false,
        hazardType: String = "none",
        confidenceScore: Double? = nil,
        iucnRedListStatus: String? = nil,
        userIdentificationOverride: String? = nil,
        confirmedSpeciesId: String? = nil
    ) -> LocalScanRecord {
        LocalScanRecord(
            id: id,
            speciesId: speciesId ?? scientificName.lowercased().replacingOccurrences(of: " ", with: "_"),
            scientificName: scientificName,
            commonName: commonName ?? "Common \(scientificName)",
            timestamp: timestamp,
            captureDate: captureDate,
            hazardType: hazardType,
            isInvasive: isInvasive,
            ecologyType: ecologyType,
            confidenceScore: confidenceScore,
            taxonomyKingdom: taxonomyKingdom,
            taxonomyClass: taxonomyClass,
            weatherTemperatureF: weatherTemperatureF,
            iucnRedListStatus: iucnRedListStatus,
            gpsElevation: gpsElevation,
            userIdentificationOverride: userIdentificationOverride,
            confirmedSpeciesId: confirmedSpeciesId
        )
    }

    // MARK: - Validation Suites

    func testFrostWalker() {
        let scans = [
            mockScan(scientificName: "Snowbed Willow", weatherTemperatureF: 31.9),
            mockScan(scientificName: "Alpine Fir", weatherTemperatureF: 32.0),
            mockScan(scientificName: "Normal Tree", weatherTemperatureF: nil),
            mockScan(scientificName: "Hot Plant", weatherTemperatureF: 80.0)
        ]

        let awards = AchievementsCalculator.calculate(from: scans)
        let frostAward = awards.first { $0.type == .frostWalker }

        XCTAssertNotNil(frostAward, "Frost Walker payload must always be mapped and returned")
        XCTAssertEqual(frostAward?.currentCount, 1, "Only exact bounds under 32.0°F should calculate")
    }

    func testPerfectLens() {
        let scans = [
            mockScan(scientificName: "High Res Plant", confidenceScore: 0.99),
            mockScan(scientificName: "Perfect Plant", confidenceScore: 0.98),
            mockScan(scientificName: "Close Plant", confidenceScore: 0.979),
            mockScan(scientificName: "No Image Plant", confidenceScore: nil)
        ]

        let awards = AchievementsCalculator.calculate(from: scans)
        let perfectLensAward = awards.first { $0.type == .perfectLens }

        XCTAssertEqual(perfectLensAward?.currentCount, 2, "Only 98%+ confidence scores evaluate correctly")
    }

    func testAlpineNaturalist() {
        let scans = [
            mockScan(scientificName: "Mountain Flower", gpsElevation: 2500.1),
            mockScan(scientificName: "Borderline Tree", gpsElevation: 2500.0),
            mockScan(scientificName: "Lowland Bush", gpsElevation: 100.0)
        ]

        let awards = AchievementsCalculator.calculate(from: scans)
        let alpineAward = awards.first { $0.type == .alpine }

        XCTAssertEqual(alpineAward?.currentCount, 1, "Only elevations strictly greater than 2500m evaluate correctly")
    }

    func testTaxonomyAwards() {
        let scans = [
            mockScan(scientificName: "Mushroom", taxonomyKingdom: "fungi"),
            mockScan(scientificName: "Mold", taxonomyKingdom: "Fungi"),
            mockScan(scientificName: "Tree", taxonomyKingdom: "plantae"),
            mockScan(scientificName: "Beetle", taxonomyClass: "insecta"),
            mockScan(scientificName: "Spider", taxonomyClass: "arachnida"),
            mockScan(scientificName: "Bird", taxonomyClass: "aves")
        ]

        let awards = AchievementsCalculator.calculate(from: scans)

        XCTAssertEqual(awards.first { $0.type == .fungi }?.currentCount, 2, "Mycologist evaluation fails")
        XCTAssertEqual(awards.first { $0.type == .plantae }?.currentCount, 1, "Botanist evaluation fails")
        XCTAssertEqual(awards.first { $0.type == .insecta }?.currentCount, 2, "Zoologist evaluation fails to map internal taxonomy subsets")
    }

    func testGuardianAndToxicologist() {
        let scans = [
            mockScan(scientificName: "Asian Carp", isInvasive: true, hazardType: "none"),
            mockScan(scientificName: "Poison Ivy", hazardType: "irritant"),
            mockScan(scientificName: "Venomous Snake", hazardType: "venomous"),
            mockScan(scientificName: "Safe Plant", isInvasive: false, hazardType: "none")
        ]

        let awards = AchievementsCalculator.calculate(from: scans)

        XCTAssertEqual(awards.first { $0.type == .guardian }?.currentCount, 1, "Guardian explicit flag missing")
        XCTAssertEqual(awards.first { $0.type == .toxicologist }?.currentCount, 2, "Toxicologist array mapping failure")
    }

    func testDeduplicationIntegrity() {
        let scans = [
            mockScan(scientificName: "Identical Fungi", taxonomyKingdom: "fungi"),
            mockScan(scientificName: "Identical Fungi", taxonomyKingdom: "fungi"),
            mockScan(scientificName: "Identical Fungi", taxonomyKingdom: "fungi")
        ]

        let awards = AchievementsCalculator.calculate(from: scans)

        XCTAssertEqual(awards.first { $0.type == .fungi }?.currentCount, 1, "Badges must be strictly deduplicated by canonical species identity.")
    }

    func testUnlockedAtTracksUnlockingContributionNotLatestRepeatScan() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let scans = [
            mockScan(id: "a_first", scientificName: "Species A", timestamp: base.addingTimeInterval(1)),
            mockScan(id: "b_first", scientificName: "Species B", timestamp: base.addingTimeInterval(2)),
            mockScan(id: "c_first", scientificName: "Species C", timestamp: base.addingTimeInterval(3)),
            mockScan(id: "d_first", scientificName: "Species D", timestamp: base.addingTimeInterval(4)),
            mockScan(id: "e_first", scientificName: "Species E", timestamp: base.addingTimeInterval(5)),
            mockScan(id: "f_after_unlock", scientificName: "Species F", timestamp: base.addingTimeInterval(6)),
            mockScan(id: "a_latest", scientificName: "Species A", timestamp: base.addingTimeInterval(500))
        ]

        let awards = AchievementsCalculator.calculate(from: scans)
        let explorerAward = awards.first { $0.type == .explorer }
        let explorerDetail = AchievementsCalculator.detail(for: .explorer, from: scans)

        XCTAssertEqual(explorerAward?.unlockedAt, base.addingTimeInterval(5))
        XCTAssertEqual(explorerAward?.lastInteractionDate, base.addingTimeInterval(500))
        XCTAssertEqual(
            Set(explorerDetail?.contributions.map(\.scanID) ?? []),
            ["a_latest", "b_first", "c_first", "d_first", "e_first"]
        )
    }

    // MARK: - Appended Coverage

    func testFirstScanAndExplorer() {
        let scans = [
            mockScan(scientificName: "A"),
            mockScan(scientificName: "B"),
            mockScan(scientificName: "B")
        ]
        let awards = AchievementsCalculator.calculate(from: scans)

        XCTAssertEqual(awards.first { $0.type == .firstScan }?.currentCount, 1, "First scan is binary and must be exactly 1 if any scan exists")
        XCTAssertEqual(awards.first { $0.type == .explorer }?.currentCount, 2, "Explorer should count absolutely unique scientific names mathematically")
    }

    func testFirstFieldTripDefaultsToLockedWithoutServerProgress() {
        let awards = AchievementsCalculator.calculate(from: [
            mockScan(scientificName: "A")
        ])
        let detail = AchievementsCalculator.detail(
            for: .firstFieldTrip,
            from: [LocalScanRecord]()
        )

        XCTAssertEqual(awards.first { $0.type == .firstFieldTrip }?.currentCount, 0)
        XCTAssertEqual(detail?.award.currentCount, 0)
        XCTAssertTrue(detail?.contributions.isEmpty == true)
    }

    func testOnlyLockedFieldTripAchievementLinksToFieldTrips() {
        let lockedFieldTrip = AwardPayload(
            type: .firstFieldTrip,
            currentCount: 0,
            lastInteractionDate: nil
        )
        let completedFieldTrip = AwardPayload(
            type: .firstFieldTrip,
            currentCount: 1,
            lastInteractionDate: Date()
        )
        let lockedScan = AwardPayload(
            type: .firstScan,
            currentCount: 0,
            lastInteractionDate: nil
        )

        XCTAssertTrue(
            AchievementDetailNavigationPolicy.showsFieldTripsLink(
                for: lockedFieldTrip,
                fieldTripsEnabled: true
            )
        )
        XCTAssertFalse(
            AchievementDetailNavigationPolicy.showsFieldTripsLink(
                for: completedFieldTrip,
                fieldTripsEnabled: true
            )
        )
        XCTAssertFalse(
            AchievementDetailNavigationPolicy.showsFieldTripsLink(
                for: lockedScan,
                fieldTripsEnabled: true
            )
        )
        XCTAssertFalse(
            AchievementDetailNavigationPolicy.showsFieldTripsLink(
                for: lockedFieldTrip,
                fieldTripsEnabled: false
            )
        )
    }

    func testUrbanEcologist() {
        let scans = [
            mockScan(scientificName: "Urban Plant", ecologyType: "urban"),
            mockScan(scientificName: "Domesticated Cat", ecologyType: "domesticated"),
            mockScan(scientificName: "Wild Tree", ecologyType: "wild")
        ]
        let awards = AchievementsCalculator.calculate(from: scans)

        XCTAssertEqual(awards.first { $0.type == .urban }?.currentCount, 2, "Both urban and domesticated ecologies count toward Urban Ecologist")
    }

    func testDomesticPetAchievementsMatchCanonicalSpecies() {
        let scans = [
            mockScan(id: "cat", scientificName: "Felis catus"),
            mockScan(id: "dog", scientificName: "Canis lupus familiaris")
        ]

        let awards = AchievementsCalculator.calculate(from: scans)
        let catDetail = AchievementsCalculator.detail(for: .domesticCat, from: scans)
        let dogDetail = AchievementsCalculator.detail(for: .domesticDog, from: scans)

        XCTAssertEqual(awards.first { $0.type == .domesticCat }?.currentCount, 1, "Canonical domestic cat scans should unlock the cat achievement.")
        XCTAssertEqual(awards.first { $0.type == .domesticDog }?.currentCount, 1, "Canonical domestic dog scans should unlock the dog achievement.")
        XCTAssertEqual(catDetail?.contributions.first?.reasonText, "Domestic cat")
        XCTAssertEqual(dogDetail?.contributions.first?.reasonText, "Domestic dog")
    }

    func testDomesticPetAchievementsAcceptAliases() {
        let catAliases = [
            "Felis silvestris catus",
            "Felis domesticus",
            "Felis catus domesticus",
            "Felis silvestris domesticus"
        ]
        let dogAliases = [
            "Canis familiaris",
            "Canis familiaris domesticus"
        ]

        for alias in catAliases {
            let awards = AchievementsCalculator.calculate(from: [mockScan(scientificName: alias)])
            XCTAssertEqual(awards.first { $0.type == .domesticCat }?.currentCount, 1, "\(alias) should unlock the cat achievement.")
        }

        for alias in dogAliases {
            let awards = AchievementsCalculator.calculate(from: [mockScan(scientificName: alias)])
            XCTAssertEqual(awards.first { $0.type == .domesticDog }?.currentCount, 1, "\(alias) should unlock the dog achievement.")
        }
    }

    func testDomesticPetAchievementsRejectWildRelatives() {
        let scans = [
            mockScan(scientificName: "Felis silvestris"),
            mockScan(scientificName: "Canis lupus")
        ]
        let awards = AchievementsCalculator.calculate(from: scans)

        XCTAssertEqual(awards.first { $0.type == .domesticCat }?.currentCount, 0, "Wild cat relatives should not unlock the domestic cat achievement.")
        XCTAssertEqual(awards.first { $0.type == .domesticDog }?.currentCount, 0, "Wild dog relatives should not unlock the domestic dog achievement.")
    }

    func testNocturnalObserver() {
        let calendar = Calendar.current
        let midnight = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: Date())!
        let evening = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!

        let scans = [
            mockScan(scientificName: "Midnight Moth", timestamp: midnight),
            mockScan(scientificName: "Late Owl", timestamp: evening),
            mockScan(scientificName: "Day Bird", timestamp: noon)
        ]
        let awards = AchievementsCalculator.calculate(from: scans)

        XCTAssertEqual(awards.first { $0.type == .nocturnal }?.currentCount, 2, "Hours strictly >= 22 or <= 5 evaluate mapping correctly")
    }

    func testNocturnalUsesCaptureDateWhenAvailable() {
        let calendar = Calendar.current
        let saveTime = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let captureTime = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!

        let scans = [
            mockScan(
                id: "historic_night_scan",
                scientificName: "Night Bloom",
                timestamp: saveTime,
                captureDate: captureTime,
                taxonomyKingdom: "plantae"
            )
        ]

        let detail = AchievementsCalculator.detail(for: .nocturnal, from: scans)

        XCTAssertEqual(detail?.award.currentCount, 1, "After-dark qualification must use the observation capture time when available")
        XCTAssertEqual(detail?.contributions.first?.timestamp, captureTime, "Achievement detail rows must display the observation capture time, not the save time")
    }

    func testConservationist() {
        let scans = [
            mockScan(scientificName: "Endangered", iucnRedListStatus: "EN"),
            mockScan(scientificName: "Vulnerable", iucnRedListStatus: "VU"),
            mockScan(scientificName: "Least Concern", iucnRedListStatus: "LC"),
            mockScan(scientificName: "Not Evaluated", iucnRedListStatus: "NE"),
            mockScan(scientificName: "Data Deficient", iucnRedListStatus: "DD")
        ]
        let awards = AchievementsCalculator.calculate(from: scans)

        XCTAssertEqual(awards.first { $0.type == .conservationist }?.currentCount, 1, "Only legitimate IUCN vulnerability layers trigger Conservationist mathematically")
    }

    func testAchievementDetailDeduplicatesContributingScans() {
        let newest = Date()
        let older = newest.addingTimeInterval(-3600)
        let oldest = newest.addingTimeInterval(-7200)

        let scans = [
            mockScan(id: "fungi_latest", scientificName: "Amanita muscaria", timestamp: newest, taxonomyKingdom: "fungi"),
            mockScan(id: "fungi_duplicate", scientificName: "Amanita muscaria", timestamp: older, taxonomyKingdom: "fungi"),
            mockScan(id: "fungi_second", scientificName: "Boletus edulis", timestamp: oldest, taxonomyKingdom: "fungi")
        ]

        let detail = AchievementsCalculator.detail(for: .fungi, from: scans)

        XCTAssertEqual(detail?.award.currentCount, 2)
        XCTAssertEqual(detail?.contributions.map(\.id), ["fungi_latest", "fungi_second"])
    }

    func testCanonicalSpeciesKeyPrefersConfirmedSpeciesIdentifier() {
        let newest = Date()
        let older = newest.addingTimeInterval(-3600)

        let scans = [
            mockScan(
                id: "fungi_confirmed_latest",
                speciesId: "fungi_candidate_a",
                scientificName: "Amanita muscaria",
                timestamp: newest,
                taxonomyKingdom: "fungi",
                confirmedSpeciesId: "fungi_confirmed"
            ),
            mockScan(
                id: "fungi_confirmed_older",
                speciesId: "fungi_candidate_b",
                scientificName: "Amanita cf. muscaria",
                timestamp: older,
                taxonomyKingdom: "fungi",
                userIdentificationOverride: "Amanita muscaria",
                confirmedSpeciesId: "fungi_confirmed"
            )
        ]

        let detail = AchievementsCalculator.detail(for: .fungi, from: scans)

        XCTAssertEqual(detail?.award.currentCount, 1)
        XCTAssertEqual(detail?.contributions.map(\.scanID), ["fungi_confirmed_latest"])
    }

    func testFirstScanDetailUsesOldestScanInHistory() {
        let newest = Date()
        let middle = newest.addingTimeInterval(-3600)
        let oldest = newest.addingTimeInterval(-7200)

        let scans = [
            mockScan(id: "newest", scientificName: "Latest Species", timestamp: newest),
            mockScan(id: "middle", scientificName: "Middle Species", timestamp: middle),
            mockScan(id: "oldest", scientificName: "First Species", timestamp: oldest)
        ]

        let detail = AchievementsCalculator.detail(for: .firstScan, from: scans)

        XCTAssertEqual(detail?.contributions.map(\.id), ["oldest"])
        XCTAssertEqual(detail?.award.lastInteractionDate, oldest)
    }

    func testPerfectLensDetailIncludesQualifyingReason() {
        let scans = [
            mockScan(id: "perfect", scientificName: "Sharp Plant", confidenceScore: 0.991)
        ]

        let detail = AchievementsCalculator.detail(for: .perfectLens, from: scans)

        XCTAssertEqual(detail?.contributions.first?.reasonText, "99 percent AI confidence")
    }
}
