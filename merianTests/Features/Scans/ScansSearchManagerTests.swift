import XCTest
import SwiftData
@testable import Merian

@MainActor
final class ScansSearchManagerTests: XCTestCase {
    
    var searchManager: ScansSearchManager!
    
    override func setUp() async throws {
        searchManager = ScansSearchManager()
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
            isPoisonous: false,
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
    
    func testEmptySearchReturnsAllScans() async throws {
        // Given
        let scan1 = createTestScan(commonName: "Test Species A", scientificName: "Testus specia", ecologyType: "Plant", taxonomyKingdom: "Plantae")
        let scan2 = createTestScan(commonName: "Test Species B", scientificName: "Testus specib", ecologyType: "Insect", semanticTags: ["tag1"], taxonomyClass: "Insecta", taxonomyKingdom: "Animalia")
        
        searchManager.allScans = [scan1, scan2]
        
        // When
        searchManager.performSearch(query: "", category: "All")
        
        // Let the detached task execute
        try await Task.sleep(nanoseconds: 200_000_000) 
        
        // Then
        XCTAssertEqual(searchManager.filteredScans.count, 2)
        XCTAssertEqual(searchManager.activeCategoryFilter, "All")
    }
    
    func testTextSearchFiltering() async throws {
        // Given
        let scan1 = createTestScan(
            commonName: "Purple Coneflower",
            scientificName: "Echinacea purpurea",
            ecologyType: "Plant",
            semanticTags: ["purple", "flower", "tall"]
        )
        let scan2 = createTestScan(
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            ecologyType: "Insect",
            semanticTags: ["orange", "black", "flying"]
        )
        
        searchManager.allScans = [scan1, scan2]
        
        // When searching for "purple flower"
        searchManager.performSearch(query: "purple flower", category: "All")
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        XCTAssertEqual(searchManager.filteredScans.count, 1)
        XCTAssertEqual(searchManager.filteredScans.first?.commonName, "Purple Coneflower")
        
        // When searching for "Danaus" (scientific name)
        searchManager.performSearch(query: "Danaus", category: "All")
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        XCTAssertEqual(searchManager.filteredScans.count, 1)
        XCTAssertEqual(searchManager.filteredScans.first?.commonName, "Monarch Butterfly")
    }
    
    func testTaxonomicCategoryFiltering() async throws {
        // Given
        let plantScan = createTestScan(commonName: "Plant", scientificName: "Plantae", ecologyType: "Plant", taxonomyKingdom: "Plantae")
        let insectScan1 = createTestScan(commonName: "Beetle", scientificName: "Coleoptera", ecologyType: "Insect", taxonomyClass: "Insecta", taxonomyKingdom: "Animalia")
        let insectScan2 = createTestScan(commonName: "Spider", scientificName: "Araneae", ecologyType: "Insect", taxonomyClass: "Arachnida", taxonomyKingdom: "Animalia")
        let reptileScan = createTestScan(commonName: "Snake", scientificName: "Serpentes", ecologyType: "Reptile", taxonomyClass: "Squamata", taxonomyKingdom: "Animalia")
        
        searchManager.allScans = [plantScan, insectScan1, insectScan2, reptileScan]
        
        // When filtering by Insects
        searchManager.performSearch(query: "", category: "Insects")
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        XCTAssertEqual(searchManager.filteredScans.count, 2)
        let filterNames = searchManager.filteredScans.map { $0.commonName }
        XCTAssertTrue(filterNames.contains("Beetle"))
        XCTAssertTrue(filterNames.contains("Spider"))
        
        // When filtering by Reptiles
        searchManager.performSearch(query: "", category: "Reptiles")
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        XCTAssertEqual(searchManager.filteredScans.count, 1)
        XCTAssertEqual(searchManager.filteredScans.first?.commonName, "Snake")
    }

    func testDebounceCancellation() async throws {
        // Given
        let scan = createTestScan(commonName: "Test Species", scientificName: "Testus specia", ecologyType: "Plant")
        searchManager.allScans = [scan]
        
        // When rapidly changing the query
        searchManager.performSearch(query: "t", category: "All")
        searchManager.performSearch(query: "te", category: "All")
        searchManager.performSearch(query: "tes", category: "All")
        searchManager.performSearch(query: "test", category: "All")
        
        // Ensure the debounce completes for the *last* query
        try await Task.sleep(nanoseconds: 200_000_000) 
        
        // Then
        XCTAssertEqual(searchManager.filteredScans.count, 1)
        XCTAssertEqual(searchManager.activeCategoryFilter, "All")
    }
}
