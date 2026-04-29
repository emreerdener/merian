import XCTest
@testable import Merian

final class AchievementsCalculatorTests: XCTestCase {
    
    // MARK: - Mock Factory
    
    /// Generates a strictly isolated, pure-memory instance of LocalScanRecord
    /// safely bypassing the SwiftData actor context allocations.
    private func mockScan(
        id: String = UUID().uuidString,
        scientificName: String = "Test Species",
        timestamp: Date = Date(),
        weatherTemperatureF: Double? = nil,
        gpsElevation: Double? = nil,
        taxonomyKingdom: String? = nil,
        taxonomyClass: String? = nil,
        ecologyType: String = "unknown",
        isInvasive: Bool = false,
        hazardType: String = "none",
        confidenceScore: Double? = nil,
        iucnRedListStatus: String? = nil
    ) -> LocalScanRecord {
        return LocalScanRecord(
            id: id,
            speciesId: "s_\(id)",
            scientificName: scientificName,
            commonName: "Common \(scientificName)",
            timestamp: timestamp,
            hazardType: hazardType,
            isInvasive: isInvasive,
            ecologyType: ecologyType,
            confidenceScore: confidenceScore,
            taxonomyKingdom: taxonomyKingdom,
            taxonomyClass: taxonomyClass,
            weatherTemperatureF: weatherTemperatureF,
            iucnRedListStatus: iucnRedListStatus,
            gpsElevation: gpsElevation
        )
    }
    
    // MARK: - Validation Suites
    
    func testFrostWalker() {
        let scans = [
            mockScan(scientificName: "Snowbed Willow", weatherTemperatureF: 31.9), // Triggers
            mockScan(scientificName: "Alpine Fir", weatherTemperatureF: 32.0), // Does not trigger (< 32.0 required)
            mockScan(scientificName: "Normal Tree", weatherTemperatureF: nil), // Does not trigger
            mockScan(scientificName: "Hot Plant", weatherTemperatureF: 80.0) // Does not trigger
        ]
        
        let awards = AchievementsCalculator.calculate(from: scans)
        let frostAward = awards.first { $0.type == "frost_walker" }
        
        XCTAssertNotNil(frostAward, "Frost Walker payload must always be mapped and returned")
        XCTAssertEqual(frostAward?.currentCount, 1, "Only exact bounds under 32.0°F should calculate")
    }
    
    func testPerfectLens() {
        let scans = [
            mockScan(scientificName: "High Res Plant", confidenceScore: 0.99), // Triggers
            mockScan(scientificName: "Perfect Plant", confidenceScore: 0.98), // Triggers (inclusive bounds)
            mockScan(scientificName: "Close Plant", confidenceScore: 0.979), // Does not trigger
            mockScan(scientificName: "No Image Plant", confidenceScore: nil) // Does not trigger
        ]
        
        let awards = AchievementsCalculator.calculate(from: scans)
        let perfectLensAward = awards.first { $0.type == "perfect_lens" }
        
        XCTAssertEqual(perfectLensAward?.currentCount, 2, "Only 98%+ confidence scores evaluate correctly")
    }
    
    func testAlpineNaturalist() {
        let scans = [
            mockScan(scientificName: "Mountain Flower", gpsElevation: 2500.1), // Triggers
            mockScan(scientificName: "Borderline Tree", gpsElevation: 2500.0), // Does not trigger (> 2500.0 required)
            mockScan(scientificName: "Lowland Bush", gpsElevation: 100.0) // Does not trigger
        ]
        
        let awards = AchievementsCalculator.calculate(from: scans)
        let alpineAward = awards.first { $0.type == "alpine" }
        
        XCTAssertEqual(alpineAward?.currentCount, 1, "Only elevations strictly greater than 2500m evaluate correctly")
    }
    
    func testTaxonomyAwards() {
        let scans = [
            mockScan(scientificName: "Mushroom", taxonomyKingdom: "fungi"), // Mycologist
            mockScan(scientificName: "Mold", taxonomyKingdom: "Fungi"), // Case-insensitive Mycologist
            mockScan(scientificName: "Tree", taxonomyKingdom: "plantae"), // Botanist
            mockScan(scientificName: "Beetle", taxonomyClass: "insecta"), // Zoologist
            mockScan(scientificName: "Spider", taxonomyClass: "arachnida"), // Zoologist (arachnida maps into insecta tracking boundary)
            mockScan(scientificName: "Bird", taxonomyClass: "aves") // Ignored
        ]
        
        let awards = AchievementsCalculator.calculate(from: scans)
        
        XCTAssertEqual(awards.first { $0.type == "fungi" }?.currentCount, 2, "Mycologist evaluation fails")
        XCTAssertEqual(awards.first { $0.type == "plantae" }?.currentCount, 1, "Botanist evaluation fails")
        XCTAssertEqual(awards.first { $0.type == "insecta" }?.currentCount, 2, "Zoologist evaluation fails to map internal taxonomy subsets")
    }
    
    func testGuardianAndToxicologist() {
        let scans = [
            mockScan(scientificName: "Asian Carp", isInvasive: true, hazardType: "none"), // Guardian
            mockScan(scientificName: "Poison Ivy", hazardType: "irritant"), // Toxicologist
            mockScan(scientificName: "Venomous Snake", hazardType: "venomous"), // Toxicologist
            mockScan(scientificName: "Safe Plant", isInvasive: false, hazardType: "none") // Ignored
        ]
        
        let awards = AchievementsCalculator.calculate(from: scans)
        
        XCTAssertEqual(awards.first { $0.type == "guardian" }?.currentCount, 1, "Guardian explicit flag missing")
        XCTAssertEqual(awards.first { $0.type == "toxicologist" }?.currentCount, 2, "Toxicologist array mapping failure")
    }
    
    func testDeduplicationIntegrity() {
        let scans = [
            mockScan(scientificName: "Identical Fungi", taxonomyKingdom: "fungi"),
            mockScan(scientificName: "Identical Fungi", taxonomyKingdom: "fungi"), // Duplicate scientific name
            mockScan(scientificName: "Identical Fungi", taxonomyKingdom: "fungi")
        ]
        
        let awards = AchievementsCalculator.calculate(from: scans)
        
        XCTAssertEqual(awards.first { $0.type == "fungi" }?.currentCount, 1, "Memory expansion vulnerability! Badges must be strictly deduplicated by absolute String equality maps.")
    }
    
    // MARK: - Appended Coverage
    
    func testFirstScanAndExplorer() {
        let scans = [
            mockScan(scientificName: "A"), mockScan(scientificName: "B"), mockScan(scientificName: "B")
        ]
        let awards = AchievementsCalculator.calculate(from: scans)
        
        XCTAssertEqual(awards.first { $0.type == "first_scan" }?.currentCount, 1, "First scan is binary and must be exactly 1 if any scan exists")
        XCTAssertEqual(awards.first { $0.type == "explorer" }?.currentCount, 2, "Explorer should count absolutely unique scientific names mathematically")
    }

    func testUrbanEcologist() {
        let scans = [
            mockScan(scientificName: "Urban Plant", ecologyType: "urban"),
            mockScan(scientificName: "Domesticated Cat", ecologyType: "domesticated"),
            mockScan(scientificName: "Wild Tree", ecologyType: "wild")
        ]
        let awards = AchievementsCalculator.calculate(from: scans)
        XCTAssertEqual(awards.first { $0.type == "urban" }?.currentCount, 2, "Both urban and domesticated ecologies count toward Urban Ecologist")
    }

    func testNocturnalObserver() {
        let calendar = Calendar.current
        let midnight = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: Date())!
        let evening = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        
        let scans = [
            mockScan(scientificName: "Midnight Moth", timestamp: midnight), // between 22 and 5
            mockScan(scientificName: "Late Owl", timestamp: evening), // between 22 and 5
            mockScan(scientificName: "Day Bird", timestamp: noon) // Ignored
        ]
        let awards = AchievementsCalculator.calculate(from: scans)
        XCTAssertEqual(awards.first { $0.type == "nocturnal" }?.currentCount, 2, "Hours strictly >= 22 or <= 5 evaluate mapping correctly")
    }

    func testConservationist() {
        let scans = [
            mockScan(scientificName: "Endangered", iucnRedListStatus: "EN"), // Triggers
            mockScan(scientificName: "Vulnerable", iucnRedListStatus: "VU"), // Triggers
            mockScan(scientificName: "Least Concern", iucnRedListStatus: "LC"), // Ignored
            mockScan(scientificName: "Not Evaluated", iucnRedListStatus: "NE"), // Ignored
            mockScan(scientificName: "Data Deficient", iucnRedListStatus: "DD") // Ignored
        ]
        let awards = AchievementsCalculator.calculate(from: scans)
        XCTAssertEqual(awards.first { $0.type == "conservationist" }?.currentCount, 2, "Only legitimate IUCN vulnerability layers trigger Conservationist mathematically")
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

        let detail = AchievementsCalculator.detail(for: "fungi", from: scans)

        XCTAssertEqual(detail?.award.currentCount, 2)
        XCTAssertEqual(detail?.contributions.map(\.id), ["fungi_latest", "fungi_second"])
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

        let detail = AchievementsCalculator.detail(for: "first_scan", from: scans)

        XCTAssertEqual(detail?.contributions.map(\.id), ["oldest"])
        XCTAssertEqual(detail?.award.lastInteractionDate, oldest)
    }

    func testPerfectLensDetailIncludesQualifyingReason() {
        let scans = [
            mockScan(id: "perfect", scientificName: "Sharp Plant", confidenceScore: 0.991)
        ]

        let detail = AchievementsCalculator.detail(for: "perfect_lens", from: scans)

        XCTAssertEqual(detail?.contributions.first?.reasonText, "99% AI confidence")
    }
}
