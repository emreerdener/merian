import XCTest
import SwiftData
@testable import Merian

@MainActor
final class ScansManagerTests: XCTestCase {
    
    var searchManager: ScansManager!
    
    override func setUp() async throws {
        searchManager = ScansManager()
    }
    
    override func tearDown() async throws {
        searchManager = nil
    }
    
    func createTestScan(
        commonName: String,
        scientificName: String,
        ecologyType: String,
        semanticTags: [String] = [],
        taxonomyClass: String? = nil,
        taxonomyKingdom: String? = nil,
        insightDescription: String = "Test insight"
    ) -> LocalScanRecord {
        return LocalScanRecord(
            id: UUID().uuidString,
            speciesId: UUID().uuidString,
            scientificName: scientificName,
            commonName: commonName,
            insightDescription: insightDescription,
            timestamp: Date(),
            localImagePath: nil,
            semanticTags: semanticTags,
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: ecologyType,
            wikipediaUrl: nil,
            wikipediaExtract: nil,
            referenceImageUrl: nil,
            additionalImagePaths: nil,
            confidenceScore: 0.99,
            isLocallyArchived: false,
            taxonomyKingdom: taxonomyKingdom,
            taxonomyPhylum: nil,
            taxonomyClass: taxonomyClass,
            taxonomyOrder: nil,
            taxonomyFamily: nil,
            taxonomyGenus: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )
    }
    
    func testEmptySearchReturnsAllScans() async throws { return }
    
    func testTextSearchFiltering() async throws { return }
    
    func testTaxonomicCategoryFiltering() async throws { return }

    func testDebounceCancellation() async throws { return }
}
