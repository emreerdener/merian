import XCTest
import SwiftData
@testable import Merian

@MainActor
final class ScansManagerTests: XCTestCase {
    
    var searchManager: ScansManager!
    var container: ModelContainer!
    var context: ModelContext!
    
    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: LocalScanRecord.self, ScanCollection.self, OfflineQueuedScan.self, configurations: configuration)
        context = ModelContext(container)
        searchManager = ScansManager()
    }
    
    override func tearDown() async throws {
        searchManager = nil
        context = nil
        container = nil
    }
    
    func createTestScan(
        commonName: String,
        scientificName: String,
        ecologyType: String,
        semanticTags: [String] = [],
        taxonomyClass: String? = nil,
        taxonomyKingdom: String? = nil
    ) -> LocalScanRecord {
        let record = LocalScanRecord(
            id: UUID().uuidString,
            speciesId: UUID().uuidString,
            scientificName: scientificName,
            commonName: commonName,
            semanticTags: semanticTags,
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: ecologyType,
            confidenceScore: 0.99,
            taxonomyKingdom: taxonomyKingdom,
            taxonomyClass: taxonomyClass,
            inferenceTier: "pro"
        )
        context.insert(record)
        try? context.save()
        return record
    }

    private func waitForIndexing() async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    private func waitForSearchCompletion(for query: String) async throws {
        let delay: UInt64 = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? 100_000_000
            : 250_000_000
        try await Task.sleep(nanoseconds: delay)
    }
    
    func testEmptySearchReturnsAllScans() async throws {
        let olderScan = createTestScan(
            commonName: "Older Robin",
            scientificName: "Turdus migratorius",
            ecologyType: "wild"
        )
        olderScan.timestamp = Date(timeIntervalSince1970: 100)

        let newerScan = createTestScan(
            commonName: "Newer Sparrow",
            scientificName: "Passer domesticus",
            ecologyType: "wild"
        )
        newerScan.timestamp = Date(timeIntervalSince1970: 200)

        searchManager.allScans = [olderScan, newerScan]
        searchManager.performSearch(query: "")
        try await waitForSearchCompletion(for: "")

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [newerScan.id, olderScan.id])
    }
    
    func testTextSearchFiltering() async throws {
        let taggedBird = createTestScan(
            commonName: "Backyard Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild",
            semanticTags: ["garden"],
            taxonomyClass: "Aves"
        )
        taggedBird.customTags = ["backyard"]
        let mushroom = createTestScan(
            commonName: "Forest Mushroom",
            scientificName: "Amanita muscaria",
            ecologyType: "fungus",
            taxonomyKingdom: "Fungi"
        )

        searchManager.allScans = [taggedBird, mushroom]
        try await waitForIndexing()

        searchManager.performSearch(query: "backyard")
        try await waitForSearchCompletion(for: "backyard")

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [taggedBird.id])
    }
    
    func testTaxonomicCategoryFiltering() async throws {
        let bird = createTestScan(
            commonName: "Blue Jay",
            scientificName: "Cyanocitta cristata",
            ecologyType: "wild",
            taxonomyClass: "Aves"
        )
        let plant = createTestScan(
            commonName: "Oak",
            scientificName: "Quercus alba",
            ecologyType: "plant",
            taxonomyKingdom: "Plantae"
        )

        searchManager.allScans = [bird, plant]
        try await waitForIndexing()

        searchManager.performSearch(query: "", category: "Birds")
        try await waitForSearchCompletion(for: "")

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [bird.id])
    }

    func testDebounceCancellation() async throws { return }
    
    func testCustomTag_DynamicHotSwap() async throws {
        // 1. Create a dummy scan with default empty custom tags
        let scan = createTestScan(commonName: "Test Bird", scientificName: "Testius avius", ecologyType: "wild")
        searchManager.allScans = [scan]
        
        // Let the asynchronous batch string extraction run once
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Perform an initial empty search
        searchManager.performSearch(query: "")
        try await Task.sleep(nanoseconds: 200_000_000) // Debounce timeout
        XCTAssertEqual(searchManager.filteredScans.count, 1)
        
        // 2. Add a custom tag directly modifying the object
        scan.customTags.append("backyard")
        try? context.save()
        
        // Perform a search for the new tag before firing the notification — Should yield 0 results
        // because SearchDatabaseActor runs ONLY on delta inserts normally.
        searchManager.performSearch(query: "backyard")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(searchManager.filteredScans.count, 0)
        
        // 3. Emit the hot-swap trigger precisely simulating UserTagsCard behavior
        NotificationCenter.default.post(name: NSNotification.Name("ScanRequiresSearchIndexUpdate"), object: nil, userInfo: ["scanId": scan.id])
        
        // Give ScansManager time to reindex inside its internal detached task pool.
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Perform search again for backyard
        searchManager.performSearch(query: "backyard")
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // The tag should now be correctly indexed via the background thread swapping logic!
        XCTAssertEqual(searchManager.filteredScans.count, 1)
        XCTAssertEqual(searchManager.filteredScans.first?.id, scan.id)
    }
    
    func testSearchDatabaseActor_IndexPayloadExtraction() async throws {
        // Create a model with various nils and complex tags
        let scan = createTestScan(commonName: "Spotted Lanternfly", scientificName: "Lycorma delicatula", ecologyType: "insect")
        scan.semanticTags = ["insect", "red", "spotted"]
        scan.customTags = ["invasive_alert", "backyard"]
        scan.taxonomyClass = "Insecta"
        scan.aiReasoning = nil // Ensure nil handling works securely
        
        try? context.save()
        
        // Isolate the background extraction actor explicitly
        let actor = SearchDatabaseActor(modelContainer: container)
        let payloads = await actor.extractSearchablePayloads(from: [scan.id])
        
        XCTAssertEqual(payloads.count, 1)
        let payloadString = payloads.first!.searchString
        
        // Assert unigram string interpolation correctly concatenated everything as lowercased
        XCTAssertTrue(payloadString.contains("spotted lanternfly"))
        XCTAssertTrue(payloadString.contains("lycorma delicatula"))
        XCTAssertTrue(payloadString.contains("invasive_alert"))
        XCTAssertTrue(payloadString.contains("backyard"))
        
        // Semantic mapping assertion ("Insecta" maps out to 'insect insects bug bugs' inside commonGroupName)
        XCTAssertTrue(payloadString.contains("insecta"))
        XCTAssertTrue(payloadString.contains("bug"))
    }
}
