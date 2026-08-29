@testable import Merian
import SwiftData
import XCTest

private final class SharedExplorePostLookup {
    var scanIDs: Set<String> = []
}

@MainActor
final class ScansManagerTests: XCTestCase {
    private static let asynchronousDebugEventTimeout: TimeInterval = 10
    
    var searchManager: ScansManager!
    var container: ModelContainer!
    var context: ModelContext!
    private var sharedExplorePostLookup: SharedExplorePostLookup!
    private var eventPublisher: AppEventPublisher!
    
    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: LocalScanRecord.self, ScanCollection.self, OfflineQueuedScan.self, configurations: configuration)
        context = ModelContext(container)
        sharedExplorePostLookup = SharedExplorePostLookup()
        eventPublisher = AppEventPublisher()
        searchManager = ScansManager(sharedPostIDProvider: { [weak sharedExplorePostLookup] scanID in
            sharedExplorePostLookup?.scanIDs.contains(scanID) == true ? "post-\(scanID)" : nil
        }, eventStream: eventPublisher)
    }
    
    override func tearDown() async throws {
        searchManager = nil
        context = nil
        container = nil
        sharedExplorePostLookup = nil
        eventPublisher = nil
    }

    func testNewManagerStartsIdleSoEmptyLibraryCanShowItsEmptyState() {
        XCTAssertTrue(searchManager.allScans.isEmpty)
        XCTAssertTrue(searchManager.filteredScans.isEmpty)
        XCTAssertFalse(searchManager.isFiltering)
    }

    func testBatchMediaSaveLocksSelectionMutationsUntilExportCompletes() {
        searchManager.isSelectionMode = true
        searchManager.selectedScans = ["scan-a"]
        searchManager.isDownloading = true

        XCTAssertTrue(searchManager.toggleSelection(for: "scan-a"))
        XCTAssertTrue(searchManager.toggleSelection(for: "scan-b"))
        searchManager.selectAll()
        searchManager.exitSelectionMode()

        XCTAssertEqual(searchManager.selectedScans, Set(["scan-a"]))
        XCTAssertTrue(searchManager.isSelectionMode)

        searchManager.isDownloading = false
        XCTAssertTrue(searchManager.toggleSelection(for: "scan-a"))
        searchManager.exitSelectionMode()

        XCTAssertTrue(searchManager.selectedScans.isEmpty)
        XCTAssertFalse(searchManager.isSelectionMode)
    }

    func testUnavailableMediaFilterCompletesForEmptyLibrary() async {
        await waitForFilterCompletion {
            $0.explorePostFilters = [.unavailableMedia]
        }

        XCTAssertTrue(searchManager.filteredScans.isEmpty)
        XCTAssertFalse(searchManager.isFiltering)
    }

    func testCategoryFiltersSortByLibraryFrequencyWithStablePriority() async throws {
        let birds = try (0..<2).map { index in
            try createTestScan(
                commonName: "Bird \(index)",
                scientificName: "Aves \(index)",
                ecologyType: "wild",
                taxonomyClass: "Aves"
            )
        }
        let fungi = try (0..<2).map { index in
            try createTestScan(
                commonName: "Fungus \(index)",
                scientificName: "Fungi \(index)",
                ecologyType: "fungus",
                taxonomyKingdom: "Fungi"
            )
        }
        let plant = try createTestScan(
            commonName: "Oak",
            scientificName: "Quercus alba",
            ecologyType: "plant",
            taxonomyKingdom: "Plantae"
        )
        let reptile = try createTestScan(
            commonName: "Lizard",
            scientificName: "Anolis carolinensis",
            ecologyType: "wild",
            taxonomyClass: "Reptilia"
        )

        await waitForFilterIndexing(expectedDocumentCount: 6) {
            searchManager.allScans = birds + fungi + [plant, reptile]
        }

        XCTAssertEqual(
            searchManager.orderedCategoryFilters,
            ["All", "Birds", "Fungi", "Plants", "Reptiles", "Insects", "Mammals", "Other"]
        )
    }

    func testEmptyLibraryCopyExplainsSafeModeUnavailable() {
        let copy = ScanLibraryEmptyStateCopy.make(
            startupStoreState: .safeMode,
            hasLibraryContent: false,
            searchQuery: "",
            hasActiveFilters: false
        )

        XCTAssertEqual(copy.title, "Local library unavailable")
        XCTAssertEqual(
            copy.message,
            "Naturebook is running in safe mode because the local database did not open. Your saved scans have not loaded in this session, and new local changes are temporary. Restart Naturebook to try reopening the library."
        )
        XCTAssertEqual(copy.actionTitle, "Back to camera")
        XCTAssertEqual(copy.action, .dismiss)
    }

    func testEmptyLibraryCopyPreservesNormalFirstScanMessage() {
        let copy = ScanLibraryEmptyStateCopy.make(
            startupStoreState: .normal,
            hasLibraryContent: false,
            searchQuery: "",
            hasActiveFilters: false
        )

        XCTAssertEqual(copy.title, "No scans found")
        XCTAssertEqual(copy.message, "Start exploring and capture your first scan!")
        XCTAssertEqual(copy.actionTitle, "Start scanning")
        XCTAssertEqual(copy.action, .dismiss)
    }

    func testSafeModeCopyDoesNotOverrideTemporarySessionContentSearch() {
        let copy = ScanLibraryEmptyStateCopy.make(
            startupStoreState: .safeMode,
            hasLibraryContent: true,
            searchQuery: "lichen",
            hasActiveFilters: false
        )

        XCTAssertEqual(copy.title, "No scans found")
        XCTAssertEqual(copy.message, "No results for \"lichen\"")
        XCTAssertNil(copy.actionTitle)
        XCTAssertEqual(copy.action, .none)
    }
    
    func createTestScan(
        commonName: String,
        scientificName: String,
        ecologyType: String,
        semanticTags: [String] = [],
        taxonomyClass: String? = nil,
        taxonomyKingdom: String? = nil
    ) throws -> LocalScanRecord {
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
        try context.save()
        return record
    }

    func testExploreShareEligibilityRequiresResolvedBiologicalIdentification() throws {
        let resolved = try createTestScan(
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            ecologyType: "wild"
        )
        let taxonomyUnavailable = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: LocalScanRecord.unresolvedBiologicalScientificName,
            commonName: "Unknown subject",
            isBiological: true
        )
        let unknownCommonName = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Danaus plexippus",
            commonName: LocalScanRecord.unresolvedBiologicalCommonName,
            isBiological: true
        )
        let nonBiological = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            isBiological: false
        )
        let human = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Homo sapiens",
            commonName: "Human",
            isBiological: true
        )
        let malformedHistoricalHuman = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Homo sapien",
            commonName: "Unknown Subject",
            isBiological: true
        )
        let humanOverride = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: "Turdus migratorius",
            commonName: "American Robin",
            isBiological: true,
            userIdentificationOverride: "Human"
        )
        let userCorrected = LocalScanRecord(
            speciesId: UUID().uuidString,
            scientificName: LocalScanRecord.unresolvedBiologicalScientificName,
            commonName: LocalScanRecord.unresolvedBiologicalCommonName,
            isBiological: true,
            userIdentificationOverride: "Danaus plexippus",
            confirmedSpeciesId: UUID().uuidString
        )

        XCTAssertTrue(resolved.isExploreShareEligible)
        XCTAssertFalse(taxonomyUnavailable.isExploreShareEligible)
        XCTAssertFalse(unknownCommonName.isExploreShareEligible)
        XCTAssertFalse(nonBiological.isExploreShareEligible)
        XCTAssertFalse(human.isExploreShareEligible)
        XCTAssertFalse(malformedHistoricalHuman.isExploreShareEligible)
        XCTAssertFalse(humanOverride.isExploreShareEligible)
        XCTAssertTrue(userCorrected.isExploreShareEligible)
    }

    private func waitForIndexing(
        expectedDocumentCount: Int? = nil,
        after trigger: @MainActor () -> Void
    ) async {
        await waitForDebugEvent(description: "search indexing completed", after: trigger) { event in
            guard case let .indexingCompleted(documentCount) = event else { return false }
            guard let expectedDocumentCount else { return true }
            return documentCount == expectedDocumentCount
        }
    }

    private func waitForFilterIndexing(
        expectedDocumentCount: Int? = nil,
        after trigger: @MainActor () -> Void
    ) async {
        await waitForDebugEvent(description: "filter indexing completed", after: trigger) { event in
            guard case let .filterIndexingCompleted(documentCount) = event else { return false }
            guard let expectedDocumentCount else { return true }
            return documentCount == expectedDocumentCount
        }
    }

    private func waitForSearchCompletion(
        for query: String,
        after trigger: @MainActor () -> Void
    ) async {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG
        trigger()

        guard let completion = await searchManager.waitForCurrentSearchCompletionForTesting() else {
            XCTFail("The current search task exited without completing.")
            return
        }
        guard case let .searchCompleted(completedQuery, _) = completion else {
            XCTFail("The current search task returned an unexpected debug event.")
            return
        }

        XCTAssertEqual(completedQuery, normalizedQuery)
        XCTAssertFalse(searchManager.isFiltering)
        #else
        XCTFail("ScansManager debug hooks are unavailable outside DEBUG builds.")
        trigger()
        #endif
    }

    private func waitForDebugEvent(
        description: String,
        after trigger: @MainActor () -> Void,
        matching predicate: @escaping @MainActor (ScansManager.SearchDebugEvent) -> Bool
    ) async {
        #if DEBUG
        let expectation = expectation(description: description)
        var fulfilled = false

        searchManager.debugEventHandler = { event in
            guard !fulfilled, predicate(event) else { return }
            fulfilled = true
            expectation.fulfill()
        }
        defer { searchManager.debugEventHandler = nil }

        trigger()
        await fulfillment(
            of: [expectation],
            timeout: Self.asynchronousDebugEventTimeout
        )
        #else
        XCTFail("ScansManager debug hooks are unavailable outside DEBUG builds.")
        trigger()
        #endif
    }

    private func waitForFilterCompletion(
        after update: @MainActor (inout ScanLibraryFilters) -> Void
    ) async {
        await waitForSearchCompletion(for: searchManager.searchQuery) {
            var updated = searchManager.filters
            update(&updated)
            searchManager.filters = updated
        }
    }
    
    func testEmptySearchReturnsAllScans() async throws {
        let olderScan = try createTestScan(
            commonName: "Older Robin",
            scientificName: "Turdus migratorius",
            ecologyType: "wild"
        )
        olderScan.timestamp = Date(timeIntervalSince1970: 100)

        let newerScan = try createTestScan(
            commonName: "Newer Sparrow",
            scientificName: "Passer domesticus",
            ecologyType: "wild"
        )
        newerScan.timestamp = Date(timeIntervalSince1970: 200)

        searchManager.allScans = [olderScan, newerScan]
        await waitForSearchCompletion(for: "") {
            searchManager.performSearch(query: "")
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [newerScan.id, olderScan.id])
    }
    
    func testTextSearchFiltering() async throws {
        let taggedBird = try createTestScan(
            commonName: "Backyard Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild",
            semanticTags: ["garden"],
            taxonomyClass: "Aves"
        )
        taggedBird.customTags = ["backyard"]
        let mushroom = try createTestScan(
            commonName: "Forest Mushroom",
            scientificName: "Amanita muscaria",
            ecologyType: "fungus",
            taxonomyKingdom: "Fungi"
        )

        await waitForIndexing(expectedDocumentCount: 2) {
            searchManager.allScans = [taggedBird, mushroom]
        }

        await waitForSearchCompletion(for: "backyard") {
            searchManager.performSearch(query: "backyard")
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [taggedBird.id])
    }

    func testSubstringSearchFilteringPreservesContainsSemantics() async throws {
        let taggedBird = try createTestScan(
            commonName: "Backyard Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild"
        )
        let mushroom = try createTestScan(
            commonName: "Forest Mushroom",
            scientificName: "Amanita muscaria",
            ecologyType: "fungus",
            taxonomyKingdom: "Fungi"
        )

        await waitForIndexing(expectedDocumentCount: 2) {
            searchManager.allScans = [taggedBird, mushroom]
        }

        await waitForSearchCompletion(for: "yard") {
            searchManager.performSearch(query: "yard")
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [taggedBird.id])
    }

    func testSingleCharacterCandidateIndexUsesUnigramPostingList() {
        let zebra = SearchableScan(
            id: "zebra",
            searchString: "zebra finch taeniopygia guttata",
            ecologyType: "wild",
            kingdom: "",
            className: "aves"
        )
        let oak = SearchableScan(
            id: "oak",
            searchString: "oak quercus alba",
            ecologyType: "plant",
            kingdom: "plantae",
            className: ""
        )

        let snapshot = SearchIndexSnapshot(searchableScans: [zebra, oak])

        XCTAssertEqual(Set(snapshot.candidateIDs(matching: "z")), [zebra.id])
        XCTAssertEqual(Set(snapshot.candidateIDs(matching: "q")), [oak.id])
    }

    func testSingleCharacterSearchUsesUnigramIndex() async throws {
        let zebra = try createTestScan(
            commonName: "Zebra Finch",
            scientificName: "Taeniopygia guttata",
            ecologyType: "wild"
        )
        let oak = try createTestScan(
            commonName: "Oak",
            scientificName: "Quercus alba",
            ecologyType: "plant",
            taxonomyKingdom: "Plantae"
        )

        await waitForIndexing(expectedDocumentCount: 2) {
            searchManager.allScans = [zebra, oak]
        }

        await waitForSearchCompletion(for: "z") {
            searchManager.performSearch(query: "z")
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [zebra.id])
    }

    func testFullRebuildIgnoresStaleSnapshotAfterRapidReplacement() async throws {
        let finch = try createTestScan(
            commonName: "Garden Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild"
        )
        let mushroom = try createTestScan(
            commonName: "Forest Mushroom",
            scientificName: "Amanita muscaria",
            ecologyType: "fungus",
            taxonomyKingdom: "Fungi"
        )
        let oak = try createTestScan(
            commonName: "Bur Oak",
            scientificName: "Quercus macrocarpa",
            ecologyType: "plant",
            taxonomyKingdom: "Plantae"
        )

        await waitForIndexing(expectedDocumentCount: 1) {
            searchManager.allScans = [finch, mushroom]
            searchManager.allScans = [oak]
        }

        await waitForSearchCompletion(for: "oak") {
            searchManager.performSearch(query: "oak")
        }
        XCTAssertEqual(searchManager.filteredScans.map(\.id), [oak.id])

        await waitForSearchCompletion(for: "finch") {
            searchManager.performSearch(query: "finch")
        }
        XCTAssertTrue(searchManager.filteredScans.isEmpty)
    }
    
    func testTaxonomicCategoryFiltering() async throws {
        let bird = try createTestScan(
            commonName: "Blue Jay",
            scientificName: "Cyanocitta cristata",
            ecologyType: "wild",
            taxonomyClass: "Aves"
        )
        let plant = try createTestScan(
            commonName: "Oak",
            scientificName: "Quercus alba",
            ecologyType: "plant",
            taxonomyKingdom: "Plantae"
        )

        await waitForIndexing(expectedDocumentCount: 2) {
            searchManager.allScans = [bird, plant]
        }

        await waitForSearchCompletion(for: "") {
            searchManager.performSearch(query: "", category: "Birds")
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [bird.id])
        XCTAssertEqual(searchManager.activeCategoryFilter, "Birds")
    }

    func testExpandedDateLocationAndTagFiltersStackWithSort() async throws {
        let older = try createTestScan(
            commonName: "Older Backyard Oak",
            scientificName: "Quercus alba",
            ecologyType: "wild"
        )
        older.captureDate = Date(timeIntervalSince1970: 100)
        older.timestamp = Date(timeIntervalSince1970: 100)
        older.gpsLatitude = 41.0
        older.customTags = ["backyard"]

        let newer = try createTestScan(
            commonName: "Newer Backyard Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild"
        )
        newer.captureDate = Date(timeIntervalSince1970: 200)
        newer.timestamp = Date(timeIntervalSince1970: 200)
        newer.gpsLongitude = -87.0
        newer.customTags = ["backyard"]

        let noLocation = try createTestScan(
            commonName: "Indoor Mushroom",
            scientificName: "Amanita muscaria",
            ecologyType: "wild"
        )
        noLocation.captureDate = Date(timeIntervalSince1970: 300)
        noLocation.timestamp = Date(timeIntervalSince1970: 300)
        noLocation.customTags = ["backyard"]

        searchManager.sortOption = .oldest
        searchManager.allScans = [newer, noLocation, older]

        await waitForFilterCompletion {
            $0.dateFilters = [.custom]
            $0.customStartDate = Date(timeIntervalSince1970: 50)
            $0.customEndDate = Date(timeIntervalSince1970: 250)
            $0.locationFilters = [.hasLocation]
            $0.customTags = ["backyard"]
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [older.id, newer.id])
    }

    func testExpandedNaturalistQualityIdentificationAndNotesFilters() async throws {
        let matching = try createTestScan(
            commonName: "Matching Lanternfly",
            scientificName: "Lycorma delicatula",
            ecologyType: "wild"
        )
        matching.isInvasive = true
        matching.hazardType = "irritant"
        matching.iucnRedListStatus = "Least Concern"
        matching.lifeStage = "Adult"
        matching.imageQualityScore = 90
        matching.userConfirmedIdentification = true

        let nonMatching = try createTestScan(
            commonName: "Plain Oak",
            scientificName: "Quercus alba",
            ecologyType: "wild"
        )
        nonMatching.imageQualityScore = 45

        searchManager.allScans = [matching, nonMatching]

        await waitForFilterCompletion {
            $0.isInvasive = true
            $0.hazardTypes = ["irritant"]
            $0.conservationStatuses = ["Least Concern"]
            $0.lifeStages = ["Adult"]
            $0.ecologyFilters = [.wild]
            $0.qualityFilters = [.highQuality]
            $0.identificationFilters = [.confirmed]
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [matching.id])
    }

    func testExpandedQualityFilterIncludesMediumRange() async throws {
        let high = try createTestScan(
            commonName: "Sharp Oak",
            scientificName: "Quercus alba",
            ecologyType: "wild"
        )
        high.imageQualityScore = 85

        let medium = try createTestScan(
            commonName: "Usable Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild"
        )
        medium.imageQualityScore = 70

        let low = try createTestScan(
            commonName: "Blurry Rose",
            scientificName: "Rosa arkansana",
            ecologyType: "wild"
        )
        low.imageQualityScore = 50

        searchManager.allScans = [high, medium, low]

        await waitForFilterCompletion {
            $0.qualityFilters = [.mediumQuality]
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [medium.id])
    }

    func testExpandedWeatherSeasonAndTaxonomyFilters() async throws {
        let matching = try createTestScan(
            commonName: "Summer Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild",
            taxonomyClass: "Aves"
        )
        matching.captureDate = DateComponents(calendar: Calendar.current, year: 2026, month: 6, day: 15).date
        matching.weatherCondition = "Sunny"
        matching.taxonomyOrder = "Passeriformes"
        matching.taxonomyFamily = "Fringillidae"
        matching.taxonomyGenus = "Haemorhous"

        let nonMatching = try createTestScan(
            commonName: "Rainy Finch",
            scientificName: "Haemorhous purpureus",
            ecologyType: "wild",
            taxonomyClass: "Aves"
        )
        nonMatching.captureDate = DateComponents(calendar: Calendar.current, year: 2026, month: 6, day: 16).date
        nonMatching.weatherCondition = "Rainy"
        nonMatching.taxonomyOrder = "Passeriformes"
        nonMatching.taxonomyFamily = "Fringillidae"
        nonMatching.taxonomyGenus = "Haemorhous"

        searchManager.allScans = [matching, nonMatching]

        await waitForFilterCompletion {
            $0.weatherConditions = ["Sunny"]
            $0.seasons = [.summer]
            $0.taxonomyClasses = ["Aves"]
            $0.taxonomyOrders = ["Passeriformes"]
            $0.taxonomyFamilies = ["Fringillidae"]
            $0.taxonomyGenera = ["Haemorhous"]
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [matching.id])
    }

    func testExplorePostFilterUsesSharedPostLookup() async throws {
        let shared = try createTestScan(
            commonName: "Shared Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild"
        )
        shared.timestamp = Date(timeIntervalSince1970: 200)

        let unshared = try createTestScan(
            commonName: "Private Oak",
            scientificName: "Quercus alba",
            ecologyType: "wild"
        )
        unshared.timestamp = Date(timeIntervalSince1970: 300)

        sharedExplorePostLookup.scanIDs = [shared.id]
        searchManager.allScans = [shared, unshared]

        await waitForFilterCompletion {
            $0.explorePostFilters = [.shared]
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [shared.id])
        XCTAssertTrue(searchManager.hasActiveFilters)
        XCTAssertEqual(searchManager.activeFilterCount, 1)
    }

    func testUnavailableExploreMediaFilterUsesIncidentScanIDs() async throws {
        let unavailable = try createTestScan(
            commonName: "Unavailable Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild"
        )
        unavailable.timestamp = Date(timeIntervalSince1970: 200)

        let available = try createTestScan(
            commonName: "Available Oak",
            scientificName: "Quercus alba",
            ecologyType: "wild"
        )
        available.timestamp = Date(timeIntervalSince1970: 300)

        searchManager.allScans = [unavailable, available]
        searchManager.setUnavailableExploreMediaScanIDs([unavailable.id])

        await waitForFilterCompletion {
            $0.explorePostFilters = [.unavailableMedia]
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [unavailable.id])
        XCTAssertTrue(searchManager.hasActiveFilters)
        XCTAssertEqual(searchManager.activeFilterCount, 1)

        await waitForSearchCompletion(for: "") {
            searchManager.setUnavailableExploreMediaScanIDs([available.id])
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [available.id])
    }

    func testMediaFiltersSeparateImagesVideosAndAudio() async throws {
        let imageScan = try createTestScan(
            commonName: "Still Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild"
        )
        imageScan.replaceCapturedMedia(with: [.image(.documents("still-photo.webp"))])
        imageScan.timestamp = Date(timeIntervalSince1970: 100)

        let legacyImageScan = try createTestScan(
            commonName: "Legacy Finch",
            scientificName: "Haemorhous cassinii",
            ecologyType: "wild"
        )
        legacyImageScan.coverImagePath = "legacy-photo.webp"
        legacyImageScan.timestamp = Date(timeIntervalSince1970: 150)

        let videoScan = try createTestScan(
            commonName: "Video Finch",
            scientificName: "Haemorhous purpureus",
            ecologyType: "wild"
        )
        videoScan.replaceCapturedMedia(with: [
            .image(.documents("video-cover.webp")),
            .video(StoredVideoMediaReference(.documents("video-clip.mp4")))
        ])
        videoScan.timestamp = Date(timeIntervalSince1970: 200)

        let audioScan = try createTestScan(
            commonName: "Audio Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild"
        )
        audioScan.replaceCapturedMedia(with: [.audio(.documents("field-recording.m4a"))])
        audioScan.timestamp = Date(timeIntervalSince1970: 250)
        try context.save()

        searchManager.allScans = [imageScan, legacyImageScan, videoScan, audioScan]

        await waitForFilterCompletion {
            $0.mediaFilters = [.image]
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [legacyImageScan.id, imageScan.id])
        XCTAssertEqual(searchManager.activeFilterCount, 1)

        await waitForFilterCompletion {
            $0.mediaFilters = [.video]
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [videoScan.id])
        XCTAssertEqual(searchManager.activeFilterCount, 1)

        await waitForFilterCompletion {
            $0.mediaFilters = [.audio]
        }

        XCTAssertEqual(searchManager.filteredScans.map(\.id), [audioScan.id])
        XCTAssertEqual(searchManager.activeFilterCount, 1)

        await waitForFilterCompletion {
            $0.mediaFilters = [.image, .video, .audio]
        }

        XCTAssertEqual(
            searchManager.filteredScans.map(\.id),
            [audioScan.id, videoScan.id, legacyImageScan.id, imageScan.id]
        )
        XCTAssertEqual(searchManager.activeFilterCount, 3)
    }

    func testExpandedFilterOptionsAndClearFilters() async throws {
        let scan = try createTestScan(
            commonName: "Tagged Oak",
            scientificName: "Quercus alba",
            ecologyType: "wild",
            taxonomyClass: "Magnoliopsida"
        )
        scan.customTags = ["yard"]
        scan.hazardType = "none"
        scan.iucnRedListStatus = "Least Concern"
        scan.lifeStage = "Adult"
        scan.weatherCondition = "Cloudy"
        scan.taxonomyOrder = "Fagales"
        scan.taxonomyFamily = "Fagaceae"
        scan.taxonomyGenus = "Quercus"
        await waitForFilterIndexing(expectedDocumentCount: 1) {
            searchManager.allScans = [scan]
        }

        let options = searchManager.filterOptions
        XCTAssertEqual(options.customTags, ["yard"])
        XCTAssertEqual(options.hazardTypes, [])
        XCTAssertEqual(options.conservationStatuses, ["Least Concern"])
        XCTAssertEqual(options.lifeStages, ["Adult"])
        XCTAssertEqual(options.weatherConditions, ["Cloudy"])
        XCTAssertEqual(options.taxonomyClasses, ["Magnoliopsida"])
        XCTAssertEqual(options.taxonomyOrders, ["Fagales"])
        XCTAssertEqual(options.taxonomyFamilies, ["Fagaceae"])
        XCTAssertEqual(options.taxonomyGenera, ["Quercus"])

        searchManager.searchQuery = "oak"
        searchManager.performSearch(query: "oak", category: "Plants")
        await waitForFilterCompletion {
            $0.customTags = ["yard"]
            $0.qualityFilters = [.noScore]
        }
        XCTAssertTrue(searchManager.hasActiveFilters)
        XCTAssertEqual(searchManager.activeFilterCount, 3)

        await waitForSearchCompletion(for: "oak") {
            searchManager.clearFilters()
        }

        XCTAssertFalse(searchManager.hasActiveFilters)
        XCTAssertEqual(searchManager.activeCategoryFilter, "All")
        XCTAssertEqual(searchManager.searchQuery, "oak")
    }

    func testTargetedReindexRefreshesCachedFilterDimensions() async throws {
        let scan = try createTestScan(
            commonName: "Tagged Oak",
            scientificName: "Quercus alba",
            ecologyType: "wild"
        )
        scan.customTags = ["backyard"]
        scan.hazardType = "irritant"
        scan.weatherCondition = "Cloudy"

        await waitForFilterIndexing(expectedDocumentCount: 1) {
            searchManager.allScans = [scan]
        }
        XCTAssertEqual(searchManager.filterOptions.customTags, ["backyard"])
        XCTAssertEqual(searchManager.filterOptions.weatherConditions, ["Cloudy"])

        scan.customTags = ["woodland"]
        scan.weatherCondition = "Rainy"
        try context.save()

        await waitForFilterIndexing(expectedDocumentCount: 1) {
            eventPublisher.send(.scanSearchIndexInvalidated(scanId: scan.id))
        }

        XCTAssertEqual(searchManager.filterOptions.customTags, ["woodland"])
        XCTAssertEqual(searchManager.filterOptions.weatherConditions, ["Rainy"])

        await waitForFilterCompletion {
            $0.customTags = ["  WOODLAND  "]
            $0.weatherConditions = [" rainy "]
        }
        XCTAssertEqual(searchManager.filteredScans.map(\.id), [scan.id])

        await waitForFilterCompletion {
            $0.hazardTypes = [" unknown "]
        }
        XCTAssertTrue(searchManager.filteredScans.isEmpty)
    }

    func testRapidTargetedReindexesDoNotDropSupersededDocuments() async throws {
        let first = try createTestScan(
            commonName: "First Oak",
            scientificName: "Quercus alba",
            ecologyType: "wild"
        )
        let second = try createTestScan(
            commonName: "Second Oak",
            scientificName: "Quercus rubra",
            ecologyType: "wild"
        )

        await waitForIndexing(expectedDocumentCount: 2) {
            searchManager.allScans = [first, second]
        }

        first.customTags = ["alpha_reindex"]
        second.customTags = ["beta_reindex"]
        try context.save()

        await waitForIndexing(expectedDocumentCount: 2) {
            eventPublisher.send(.scanSearchIndexInvalidated(scanId: first.id))
            eventPublisher.send(.scanSearchIndexInvalidated(scanId: second.id))
        }

        await waitForSearchCompletion(for: "alpha_reindex") {
            searchManager.performSearch(query: "alpha_reindex")
        }
        XCTAssertEqual(searchManager.filteredScans.map(\.id), [first.id])

        await waitForSearchCompletion(for: "beta_reindex") {
            searchManager.performSearch(query: "beta_reindex")
        }
        XCTAssertEqual(searchManager.filteredScans.map(\.id), [second.id])
    }

    func testDebounceCancellation() async throws {
        let bird = try createTestScan(
            commonName: "Backyard Finch",
            scientificName: "Haemorhous mexicanus",
            ecologyType: "wild"
        )
        let oak = try createTestScan(
            commonName: "Oak",
            scientificName: "Quercus alba",
            ecologyType: "plant",
            taxonomyKingdom: "Plantae"
        )

        await waitForIndexing(expectedDocumentCount: 2) {
            searchManager.allScans = [bird, oak]
        }

        #if DEBUG
        let cancelledQueryExpectation = expectation(description: "superseded query should not complete")
        cancelledQueryExpectation.isInverted = true
        let replacementQueryExpectation = expectation(description: "replacement query completes")
        var completedQueries: [String] = []

        searchManager.debugEventHandler = { event in
            guard case let .searchCompleted(query, _) = event else { return }
            completedQueries.append(query)

            if query == "backyard" {
                cancelledQueryExpectation.fulfill()
            }

            if query == "oak" {
                replacementQueryExpectation.fulfill()
            }
        }
        defer { searchManager.debugEventHandler = nil }

        searchManager.performSearch(query: "backyard")
        searchManager.performSearch(query: "oak")

        await fulfillment(of: [replacementQueryExpectation, cancelledQueryExpectation], timeout: 0.5, enforceOrder: false)

        XCTAssertEqual(completedQueries, ["oak"])
        XCTAssertEqual(searchManager.filteredScans.map(\.id), [oak.id])
        #else
        XCTFail("ScansManager debug hooks are unavailable outside DEBUG builds.")
        #endif
    }
    
    func testCustomTag_DynamicHotSwap() async throws {
        // 1. Create a dummy scan with default empty custom tags
        let scan = try createTestScan(commonName: "Test Bird", scientificName: "Testius avius", ecologyType: "wild")
        await waitForIndexing(expectedDocumentCount: 1) {
            searchManager.allScans = [scan]
        }

        // Perform an initial empty search
        await waitForSearchCompletion(for: "") {
            searchManager.performSearch(query: "")
        }
        XCTAssertEqual(searchManager.filteredScans.count, 1)
        
        // 2. Add a custom tag directly modifying the object
        scan.customTags.append("backyard")
        try context.save()
        
        // Perform a search for the new tag before firing the notification — Should yield 0 results
        // because SearchDatabaseActor runs ONLY on delta inserts normally.
        await waitForSearchCompletion(for: "backyard") {
            searchManager.performSearch(query: "backyard")
        }
        XCTAssertEqual(searchManager.filteredScans.count, 0)
        
        // 3. Emit the hot-swap trigger precisely simulating UserTagsCard behavior
        await waitForIndexing(expectedDocumentCount: 1) {
            eventPublisher.send(.scanSearchIndexInvalidated(scanId: scan.id))
        }

        // Perform search again for backyard
        await waitForSearchCompletion(for: "backyard") {
            searchManager.performSearch(query: "backyard")
        }
        
        // The tag should now be correctly indexed via the background thread swapping logic!
        XCTAssertEqual(searchManager.filteredScans.count, 1)
        XCTAssertEqual(searchManager.filteredScans.first?.id, scan.id)
    }
    
    func testSearchDatabaseActor_IndexPayloadExtraction() async throws {
        // Create a model with various nils and complex tags
        let scan = try createTestScan(commonName: "Spotted Lanternfly", scientificName: "Lycorma delicatula", ecologyType: "insect")
        scan.semanticTags = ["insect", "red", "spotted"]
        scan.customTags = ["invasive_alert", "backyard"]
        scan.taxonomyClass = "Insecta"
        scan.aiReasoning = nil // Ensure nil handling works securely
        
        try context.save()
        
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

    func testSearchDatabaseActorIndexesPetIdentificationLabel() async throws {
        let scan = try createTestScan(
            commonName: "Domestic Dog",
            scientificName: "Canis lupus familiaris",
            ecologyType: "mammal"
        )
        scan.petIdentificationData = try JSONEncoder().encode(PetIdentification(
            speciesGroup: "dog",
            label: "Australian Cattle Dog",
            labelType: "breed",
            confidenceScore: 0.91,
            evidence: ["blue roan coat"]
        ))

        try context.save()

        let actor = SearchDatabaseActor(modelContainer: container)
        let payloads = await actor.extractSearchablePayloads(from: [scan.id])
        let payloadString = try XCTUnwrap(payloads.first?.searchString)

        XCTAssertTrue(payloadString.contains("australian cattle dog"))
        XCTAssertTrue(payloadString.contains("domestic dog"))
        XCTAssertTrue(payloadString.contains("canis lupus familiaris"))
    }

}
