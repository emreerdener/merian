import Combine
import ImageIO
import SwiftData
import SwiftUI

enum ScanSortOption: String, CaseIterable, Identifiable, Sendable {
    case newest = "Newest"
    case oldest = "Oldest"
    case aToZ = "A to Z"
    case zToA = "Z to A"
    var id: String { self.rawValue }
}

@MainActor
@Observable final class ScansManager {
    private static let rawSnapshotExtractionBatchSize = 128

    #if DEBUG
    enum SearchDebugEvent: Equatable {
        case indexingCompleted(documentCount: Int)
        case searchCompleted(query: String, resultCount: Int)
    }
    #endif

    // MARK: - UI Published State
    var searchQuery: String = ""
    var filteredScans: [LocalScanRecord] = []
    var isFiltering: Bool = true
    var activeCategoryFilter: String = "All"
    var isSelectionMode: Bool = false
    var selectedScans: Set<String> = []

    var sortOption: ScanSortOption = .newest {
        didSet { 
            if oldValue != sortOption { applySort() }
        }
    }

    var collectionSortOption: ScanSortOption = .newest
    
    var collections: [ScanCollection] = []
    
    // MARK: - Collection Engine Bounds
    var sortedCollections: [ScanCollection] {
        collections.sorted { c1, c2 in
            switch collectionSortOption {
            case .newest: return c1.createdAt > c2.createdAt
            case .oldest: return c1.createdAt < c2.createdAt
            case .aToZ: return c1.name.localizedCaseInsensitiveCompare(c2.name) == .orderedAscending
            case .zToA: return c1.name.localizedCaseInsensitiveCompare(c2.name) == .orderedDescending
            }
        }
    }
    
    // MARK: - Static Bounds
    let maxBatchSelectionLimit = 20

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var appSettings: AppSettings

    init(appSettings: AppSettings? = nil) {
        self.appSettings = appSettings ?? AppSettings.shared
        ScanLibraryEvents.searchIndexUpdatePublisher()
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let scanId = ScanLibraryEvents.scanId(from: notification) else { return }
                Task { @MainActor [weak self] in
                    self?.forceReindex(scanId: scanId)
                }
            }
            .store(in: &cancellables)
    }

    func bindSettings(_ appSettings: AppSettings) {
        self.appSettings = appSettings
    }
    
    // MARK: - Data Ingestion
    var allScans: [LocalScanRecord] = [] {
        didSet { rebuildSearchCaches(oldScans: oldValue) }
    }
    
    @ObservationIgnored private var searchIndexSnapshot = SearchIndexSnapshot.empty
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var indexingTask: Task<Void, Never>?
    @ObservationIgnored private var scanIndexById: [String: Int] = [:]
    @ObservationIgnored private var scanRecordById: [String: LocalScanRecord] = [:]
    @ObservationIgnored private var sortPrimitivesById: [String: ScanSortPrimitive] = [:]
    @ObservationIgnored private var allScanSortPrimitives: [ScanSortPrimitive] = []
    @ObservationIgnored private var sortedAllScanIDsCache: [String: [String]] = [:]
    @ObservationIgnored private var searchCacheGeneration: UInt64 = 0
    #if DEBUG
    @ObservationIgnored var debugEventHandler: ((SearchDebugEvent) -> Void)?
    #endif
    
    // MARK: - Data Indexing Pipeline
    private func rebuildSearchCaches(oldScans: [LocalScanRecord]) {
        var updatedScanIndexById: [String: Int] = [:]
        updatedScanIndexById.reserveCapacity(allScans.count)
        var updatedScanRecordById: [String: LocalScanRecord] = [:]
        updatedScanRecordById.reserveCapacity(allScans.count)

        var updatedSortPrimitivesById: [String: ScanSortPrimitive] = [:]
        updatedSortPrimitivesById.reserveCapacity(allScans.count)

        var updatedAllScanSortPrimitives: [ScanSortPrimitive] = []
        updatedAllScanSortPrimitives.reserveCapacity(allScans.count)

        for (index, scan) in allScans.enumerated() {
            let primitive = ScanSortPrimitive(
                id: scan.id,
                timestamp: scan.timestamp,
                commonName: scan.commonName
            )
            updatedScanIndexById[scan.id] = index
            updatedScanRecordById[scan.id] = scan
            updatedSortPrimitivesById[scan.id] = primitive
            updatedAllScanSortPrimitives.append(primitive)
        }

        scanIndexById = updatedScanIndexById
        scanRecordById = updatedScanRecordById
        sortPrimitivesById = updatedSortPrimitivesById
        allScanSortPrimitives = updatedAllScanSortPrimitives
        sortedAllScanIDsCache.removeAll(keepingCapacity: true)
        searchCacheGeneration &+= 1

        updateSearchableData(oldScans: oldScans)
    }

    private func updateSearchableData(oldScans: [LocalScanRecord]) {
        indexingTask?.cancel()
        
        let oldIds = Set(oldScans.map { $0.id })
        let newIds = Set(allScans.map { $0.id })

        let addedScans = allScans.filter { !oldIds.contains($0.id) }
        let removedIds = oldIds.subtracting(newIds)
        var workingSnapshot = searchIndexSnapshot

        if !removedIds.isEmpty {
            workingSnapshot = workingSnapshot.removing(ids: removedIds)
        }

        guard let firstScan = allScans.first, let container = firstScan.modelContext?.container else {
            commitSearchIndexSnapshot(.empty)
            return
        }

        if addedScans.isEmpty && workingSnapshot.count == allScans.count {
            commitSearchIndexSnapshot(workingSnapshot)
            return
        }

        if workingSnapshot.count != searchIndexSnapshot.count {
            setSearchIndexSnapshot(workingSnapshot, emitCompletion: false)
        }

        let needsFullRebuild = self.searchIndexSnapshot.isEmpty && !allScans.isEmpty

        let cacheGeneration = searchCacheGeneration

        if needsFullRebuild {
            // Full rebuild: keep SwiftData model reads on @MainActor, but split the
            // extraction into yielding chunks so a large @Query snapshot does not monopolize
            // the UI thread before detached string/index construction begins.
            indexingTask = Task { [weak self] in
                guard let self else { return }
                guard let snapshots = await self.extractRawScanSnapshotsCooperatively(
                    cacheGeneration: cacheGeneration
                ) else { return }
                guard !Task.isCancelled else { return }

                let processed = await Task.detached(priority: .utility) {
                    SearchDatabaseActor.buildSearchablePayloads(from: snapshots)
                }.value
                guard !Task.isCancelled else { return }

                let snapshot = SearchIndexSnapshot(searchableScans: processed)
                guard self.searchCacheGeneration == cacheGeneration else { return }
                self.commitSearchIndexSnapshot(snapshot)
            }
        } else {
            // Incremental: only newly added scans. These IDs may not be faulted yet in the
            // @Query result (sync wrote them to the store while we were mid-frame), so
            // let SearchDatabaseActor fetch them fresh from its own ModelContext.
            let idsToExtract = addedScans.map { $0.id }
            if idsToExtract.isEmpty { return }
            indexingTask = Task { [weak self] in
                let dbActor = SearchDatabaseActor(modelContainer: container)
                let processedNewScans = await dbActor.extractSearchablePayloads(from: idsToExtract)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.searchCacheGeneration == cacheGeneration else { return }
                    self.commitSearchIndexSnapshot(self.searchIndexSnapshot.upserting(processedNewScans))
                }
            }
        }
    }

    private func extractRawScanSnapshotsCooperatively(cacheGeneration: UInt64) async -> [RawScanSnapshot]? {
        let expectedCount = allScans.count
        var snapshots: [RawScanSnapshot] = []
        snapshots.reserveCapacity(expectedCount)

        var startIndex = 0
        while startIndex < expectedCount {
            guard !Task.isCancelled, searchCacheGeneration == cacheGeneration else { return nil }

            let endIndex = min(startIndex + Self.rawSnapshotExtractionBatchSize, expectedCount)
            for index in startIndex..<endIndex {
                snapshots.append(RawScanSnapshot(record: allScans[index]))
            }

            startIndex = endIndex
            if startIndex < expectedCount {
                await Task.yield()
            }
        }

        guard !Task.isCancelled, searchCacheGeneration == cacheGeneration else { return nil }
        return snapshots
    }
    
    // MARK: - Dedicated Reindexing
    private func forceReindex(scanId: String) {
        guard let scan = record(for: scanId), let container = scan.modelContext?.container else { return }
        setSearchIndexSnapshot(self.searchIndexSnapshot.removing(ids: Set([scanId])), emitCompletion: false)

        // Cancel any prior reindex so two rapid calls cannot both append to searchableData,
        // which would produce duplicate SearchableScan entries in the search index.
        indexingTask?.cancel()
        indexingTask = Task { [weak self] in
            let dbActor = SearchDatabaseActor(modelContainer: container)
            let newPayload = await dbActor.extractSearchablePayloads(from: [scanId])
            if Task.isCancelled { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.commitSearchIndexSnapshot(self.searchIndexSnapshot.upserting(newPayload))
            }
        }
    }
    
    // MARK: - Search Execution
    func performSearch(query: String, category: String? = nil) {
        searchTask?.cancel()
        
        let trimmedText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let category = category {
            self.activeCategoryFilter = category
        } else if !trimmedText.isEmpty {
            self.activeCategoryFilter = "All"
        }
        
        let currentCategory = self.activeCategoryFilter
        
        let text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let catMatch = currentCategory.lowercased()
        
        self.isFiltering = true
        
        searchTask = Task { [weak self] in
            if !text.isEmpty {
                try? await Task.sleep(nanoseconds: 150_000_000) // Debounce typing
            }
            if Task.isCancelled { return }

            guard let self = self else { return }

            if text.isEmpty && catMatch == "all" {
                let sortedIds = await self.sortedAllScanIDs(for: self.sortOption)
                if Task.isCancelled { return }
                
                let finalSorted = self.records(for: sortedIds)
                self.completeSearch(with: finalSorted, query: text)
                return
            }
            
            let searchIndex = self.searchIndexSnapshot
            if searchIndex.isEmpty {
                self.completeSearch(with: [], query: text)
                return
            }
            
            let filterActor = SearchFilterActor()
            let matchingIds = await filterActor.filter(text: text, searchIndex: searchIndex, catMatch: catMatch)
            
            if Task.isCancelled { return }
            
            let sortOpt = self.sortOption
            let subsetPrimitives = self.sortPrimitives(for: matchingIds)
            
            let sortedIds = await Task.detached(priority: .userInitiated) {
                return ScansManager.executeDetachedSort(on: subsetPrimitives, sortOption: sortOpt).map { $0.id }
            }.value
            
            if Task.isCancelled { return }
            
            let finalSorted = self.records(for: sortedIds)
            
            self.completeSearch(with: finalSorted, query: text)
        }
    }
    
    // MARK: - Detached Primitive Sort Engine
    struct ScanSortPrimitive: Sendable {
        let id: String
        let timestamp: Date
        let commonName: String
    }
    
    private nonisolated static func executeDetachedSort(on subset: [ScanSortPrimitive], sortOption: ScanSortOption) -> [ScanSortPrimitive] {
        switch sortOption {
        case .newest: return subset.sorted { $0.timestamp > $1.timestamp }
        case .oldest: return subset.sorted { $0.timestamp < $1.timestamp }
        case .aToZ: return subset.sorted { $0.commonName.localizedCaseInsensitiveCompare($1.commonName) == .orderedAscending }
        case .zToA: return subset.sorted { $0.commonName.localizedCaseInsensitiveCompare($1.commonName) == .orderedDescending }
        }
    }
    
    private func applySort() {
        // Run sort without query context
        performSearch(query: self.searchQuery)
    }

    private func sortPrimitives(for ids: [String]) -> [ScanSortPrimitive] {
        ids.compactMap { sortPrimitivesById[$0] }
    }

    private func records(for ids: [String]) -> [LocalScanRecord] {
        ids.compactMap { record(for: $0) }
    }

    private func record(for id: String) -> LocalScanRecord? {
        guard let index = scanIndexById[id], allScans.indices.contains(index) else {
            return scanRecordById[id]
        }

        let record = allScans[index]
        return record.id == id ? record : scanRecordById[id]
    }

    private func sortedAllScanIDs(for sortOption: ScanSortOption) async -> [String] {
        if let cached = sortedAllScanIDsCache[sortOption.rawValue] {
            return cached
        }

        let primitives = allScanSortPrimitives
        let sortedIds = await Task.detached(priority: .userInitiated) {
            ScansManager.executeDetachedSort(on: primitives, sortOption: sortOption).map(\.id)
        }.value

        if !Task.isCancelled {
            sortedAllScanIDsCache[sortOption.rawValue] = sortedIds
        }
        return sortedIds
    }

    private func commitSearchIndexSnapshot(_ snapshot: SearchIndexSnapshot) {
        setSearchIndexSnapshot(snapshot, emitCompletion: true)
    }

    private func setSearchIndexSnapshot(_ snapshot: SearchIndexSnapshot, emitCompletion: Bool) {
        searchIndexSnapshot = snapshot
        if emitCompletion {
            emitIndexingCompletedEvent()
        }
    }

    private func completeSearch(with scans: [LocalScanRecord], query: String) {
        withAnimation {
            filteredScans = scans
            isFiltering = false
        }
        emitSearchCompletedEvent(query: query, resultCount: scans.count)
    }

    private func emitIndexingCompletedEvent() {
        #if DEBUG
        debugEventHandler?(.indexingCompleted(documentCount: searchIndexSnapshot.count))
        #endif
    }

    private func emitSearchCompletedEvent(query: String, resultCount: Int) {
        #if DEBUG
        debugEventHandler?(.searchCompleted(query: query, resultCount: resultCount))
        #endif
    }
    
    // MARK: - Batch Selection Operations
    func toggleSelection(for scanId: String) -> Bool {
        if selectedScans.contains(scanId) {
            selectedScans.remove(scanId)
            return true
        } else {
            if selectedScans.count >= maxBatchSelectionLimit {
                return false
            } else {
                selectedScans.insert(scanId)
                return true
            }
        }
    }
    
    func selectAll() {
        let maximumScans = Array(filteredScans.prefix(maxBatchSelectionLimit))
        if selectedScans.count == maximumScans.count {
            selectedScans.removeAll()
        } else {
            selectedScans = Set(maximumScans.map { $0.id })
        }
    }
    
    func exitSelectionMode() {
        isSelectionMode = false
        selectedScans.removeAll()
    }
    
    func getSelectedLocalRecords() -> [LocalScanRecord] {
        return filteredScans.filter { selectedScans.contains($0.id) }
    }
    
    // MARK: - Batch Operations (Async)
    var isDownloading = false
    var toastMessage: String?
    
    func batchShare(scans: [LocalScanRecord]) async {
        await withCheckedContinuation { continuation in
            InsightMediaExportManager.shared.batchShareDiscovery(records: scans) { items in
                ShareSheetUtility.present(items: items)
                continuation.resume()
            }
        }
    }
    
    func batchSavePhotos(scans: [LocalScanRecord]) async {
        await MainActor.run { isDownloading = true }
        
        let savedCount = await withCheckedContinuation { continuation in
            InsightMediaExportManager.shared.batchSaveUserPhotos(records: scans) { count in
                continuation.resume(returning: count)
            }
        }
        
        await MainActor.run {
            isDownloading = false
            exitSelectionMode()
            HapticManager.shared.triggerSuccessPulse()
            showToast(message: "Saved \(savedCount) photo\(savedCount == 1 ? "" : "s") to your Camera Roll")
        }
    }

    func shareToExplore(scanId: String, modelContext: ModelContext) async {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1

        guard let scan = try? modelContext.fetch(descriptor).first else {
            HapticManager.shared.triggerErrorThump()
            showToast(message: "This scan is no longer available.")
            return
        }

        guard scan.isExploreShareEligible else {
            HapticManager.shared.triggerErrorThump()
            showToast(message: "Reanalyze this scan before sharing to Explore.")
            return
        }

        do {
            let response = try await MerianNetworkClient.shared.shareScanToExplore(scan: scan)
            ExploreShareStateStore.setSharedPostId(response.postId, for: scanId)
            AppEventPublisher.shared.send(.exploreShareStateChanged(scanId: scanId, postId: response.postId))
            HapticManager.shared.triggerSuccessPulse()
            showToast(message: "Shared to Explore")
        } catch {
            HapticManager.shared.triggerErrorThump()
            showToast(message: ExploreErrorFormatter.message(for: error))
        }
    }
    
    private func showToast(message: String) {
        withAnimation(.spring()) { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut) { if toastMessage == message { toastMessage = nil } }
            }
        }
    }
}

// MARK: - Actor Isolation Bounds
// MARK: - Sendable Snapshot for Full-Rebuild Path

/// Lightweight value-type mirror of `LocalScanRecord` used when building the search index
/// from records already loaded in the `@MainActor` `@Query` result. All fields are `Sendable`
/// so the snapshot can safely cross into a `Task.detached` for CPU-bound string processing
/// without fetching the same records twice from SwiftData.
struct RawScanSnapshot: Sendable {
    let id: String
    let commonName: String
    let scientificName: String
    let ecologyType: String
    let semanticTags: [String]
    let customTags: [String]
    let isInvasive: Bool
    let taxonomyKingdom: String?
    let taxonomyClass: String?
    let taxonomyOrder: String?
    let taxonomyFamily: String?
    let aiReasoning: String?
    let locationName: String?
    let habitatDescription: String?
    let weatherCondition: String?
    let lifeStage: String?
    let reproductiveCondition: String?
    let sex: String?
    let sexEvidence: String?
    let similarSpecies: [String]?
    let iucnRedListStatus: String?
    let hazardType: String
    let ecologicalInteractions: [String]?

    @MainActor
    init(record: LocalScanRecord) {
        self.id = record.id
        self.commonName = record.commonName
        self.scientificName = record.scientificName
        self.ecologyType = record.ecologyType
        self.semanticTags = record.semanticTags
        self.customTags = record.customTags
        self.isInvasive = record.isInvasive
        self.taxonomyKingdom = record.taxonomyKingdom
        self.taxonomyClass = record.taxonomyClass
        self.taxonomyOrder = record.taxonomyOrder
        self.taxonomyFamily = record.taxonomyFamily
        self.aiReasoning = record.aiReasoning
        self.locationName = record.locationName
        self.habitatDescription = record.habitatDescription
        self.weatherCondition = record.weatherCondition
        self.lifeStage = record.lifeStage
        self.reproductiveCondition = record.reproductiveCondition
        self.sex = record.sex
        self.sexEvidence = record.sexEvidence
        self.similarSpecies = record.similarSpecies
        self.iucnRedListStatus = record.iucnRedListStatus
        self.hazardType = record.hazardType
        self.ecologicalInteractions = record.ecologicalInteractions
    }
}

@ModelActor
actor SearchDatabaseActor {
    private static func buildSearchString(
        commonName: String,
        scientificName: String,
        ecologyType: String,
        semanticTags: [String],
        customTags: [String],
        isInvasive: Bool,
        taxonomyClass: String?,
        taxonomyOrder: String?,
        taxonomyFamily: String?,
        aiReasoning: String?,
        locationName: String?,
        habitatDescription: String?,
        weatherCondition: String?,
        lifeStage: String?,
        reproductiveCondition: String?,
        sex: String?,
        sexEvidence: String?,
        similarSpecies: [String]?,
        iucnRedListStatus: String?,
        hazardType: String,
        ecologicalInteractions: [String]?
    ) -> String {
        let tags = semanticTags.joined(separator: " ")
        let taxonomyTerms = [taxonomyClass, taxonomyOrder, taxonomyFamily]
            .compactMap { $0 }
            .joined(separator: " ")
        let groupName = commonGroupName(for: taxonomyClass)
        let hazard = hazardType == "none" ? "" : hazardType

        return "\(commonName) \(scientificName) \(ecologyType) \(tags) \(customTags.joined(separator: " ")) \(isInvasive ? "invasive" : "") \(taxonomyTerms) \(groupName) \(aiReasoning ?? "") \(locationName ?? "") \(habitatDescription ?? "") \(weatherCondition ?? "") \(lifeStage ?? "") \(reproductiveCondition ?? "") \(sex ?? "") \(sexEvidence ?? "") \(similarSpecies?.joined(separator: " ") ?? "") \(iucnRedListStatus ?? "") \(hazard) \(ecologicalInteractions?.joined(separator: " ") ?? "")".lowercased()
    }

    /// Builds `SearchableScan` payloads from pre-extracted `RawScanSnapshot` values.
    ///
    /// Called on the full-rebuild path where `allScans` is already resident in `@MainActor`
    /// memory. Snapshots are extracted on `@MainActor` and processed here off the main thread,
    /// avoiding a second SwiftData fetch into a separate `ModelContext`.
    static func buildSearchablePayloads(from snapshots: [RawScanSnapshot]) -> [SearchableScan] {
        var processed: [SearchableScan] = []
        processed.reserveCapacity(snapshots.count)
        for snapshot in snapshots {
            if Task.isCancelled { break }
            processed.append(SearchableScan(
                id: snapshot.id,
                searchString: Self.buildSearchString(
                    commonName: snapshot.commonName,
                    scientificName: snapshot.scientificName,
                    ecologyType: snapshot.ecologyType,
                    semanticTags: snapshot.semanticTags,
                    customTags: snapshot.customTags,
                    isInvasive: snapshot.isInvasive,
                    taxonomyClass: snapshot.taxonomyClass,
                    taxonomyOrder: snapshot.taxonomyOrder,
                    taxonomyFamily: snapshot.taxonomyFamily,
                    aiReasoning: snapshot.aiReasoning,
                    locationName: snapshot.locationName,
                    habitatDescription: snapshot.habitatDescription,
                    weatherCondition: snapshot.weatherCondition,
                    lifeStage: snapshot.lifeStage,
                    reproductiveCondition: snapshot.reproductiveCondition,
                    sex: snapshot.sex,
                    sexEvidence: snapshot.sexEvidence,
                    similarSpecies: snapshot.similarSpecies,
                    iucnRedListStatus: snapshot.iucnRedListStatus,
                    hazardType: snapshot.hazardType,
                    ecologicalInteractions: snapshot.ecologicalInteractions
                ),
                ecologyType: snapshot.ecologyType.lowercased(),
                kingdom: snapshot.taxonomyKingdom?.lowercased() ?? "",
                className: snapshot.taxonomyClass?.lowercased() ?? ""
            ))
        }
        return processed
    }

    /// Batch-fetches `LocalScanRecord` rows for the given string IDs in a single SQLite query,
    /// then maps each record to a `SearchableScan` payload.
    ///
    /// Using a `FetchDescriptor` with an `#Predicate` avoids the N individual `model(for:)`
    /// calls that each fault a full row from SQLite. For a 50-scan delta the old approach
    /// issued 50 separate reads; this issues exactly 1.
    func extractSearchablePayloads(from ids: [String]) -> [SearchableScan] {
        guard !ids.isEmpty else { return [] }

        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        descriptor.fetchLimit = ids.count

        let records = (try? modelContext.fetch(descriptor)) ?? []
        let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })

        var processed: [SearchableScan] = []
        processed.reserveCapacity(ids.count)

        for id in ids {
            if Task.isCancelled { break }
            guard let record = recordMap[id] else { continue }

            processed.append(SearchableScan(
                id: record.id,
                searchString: Self.buildSearchString(
                    commonName: record.commonName,
                    scientificName: record.scientificName,
                    ecologyType: record.ecologyType,
                    semanticTags: record.semanticTags,
                    customTags: record.customTags,
                    isInvasive: record.isInvasive,
                    taxonomyClass: record.taxonomyClass,
                    taxonomyOrder: record.taxonomyOrder,
                    taxonomyFamily: record.taxonomyFamily,
                    aiReasoning: record.aiReasoning,
                    locationName: record.locationName,
                    habitatDescription: record.habitatDescription,
                    weatherCondition: record.weatherCondition,
                    lifeStage: record.lifeStage,
                    reproductiveCondition: record.reproductiveCondition,
                    sex: record.sex,
                    sexEvidence: record.sexEvidence,
                    similarSpecies: record.similarSpecies,
                    iucnRedListStatus: record.iucnRedListStatus,
                    hazardType: record.hazardType,
                    ecologicalInteractions: record.ecologicalInteractions
                ),
                ecologyType: record.ecologyType.lowercased(),
                kingdom: record.taxonomyKingdom?.lowercased() ?? "",
                className: record.taxonomyClass?.lowercased() ?? ""
            ))
        }

        return processed
    }

    /// Maps a taxonomy class name to plain-English group synonyms so users can search
    /// "bird", "mammal", "spider" etc. without knowing the Latin class name.
    static func commonGroupName(for taxonomyClass: String?) -> String {
        switch taxonomyClass?.lowercased() {
        case "aves":                                        return "bird birds avian"
        case "mammalia":                                    return "mammal mammals"
        case "insecta", "entognatha":                       return "insect insects bug bugs"
        case "arachnida":                                   return "spider spiders arachnid arachnids"
        case "reptilia", "squamata":                        return "reptile reptiles"
        case "amphibia":                                    return "amphibian amphibians frog frogs toad toads"
        case "actinopterygii", "chondrichthyes",
             "sarcopterygii":                               return "fish"
        default:                                            return ""
        }
    }
}

actor SearchFilterActor {
    func filter(text: String, searchIndex: SearchIndexSnapshot, catMatch: String) -> [String] {
        let tokens = SearchIndexTokenizer.queryTokens(from: text)
        let categoryMatches = searchIndex.ids(matching: catMatch)

        if tokens.isEmpty {
            return Task.isCancelled ? [] : categoryMatches
        }

        let categorySet = catMatch == "all" ? nil : Set(categoryMatches)
        var candidateSet: Set<String>?

        for token in tokens {
            if Task.isCancelled { return [] }

            var tokenMatches = Set(searchIndex.candidateIDs(matching: token))
            guard !tokenMatches.isEmpty else { return [] }

            if let categorySet {
                tokenMatches.formIntersection(categorySet)
                guard !tokenMatches.isEmpty else { return [] }
            }

            if let existingCandidateSet = candidateSet {
                let narrowed = existingCandidateSet.intersection(tokenMatches)
                guard !narrowed.isEmpty else { return [] }
                candidateSet = narrowed
            } else {
                candidateSet = tokenMatches
            }
        }

        guard let candidateSet, !Task.isCancelled else { return [] }

        return candidateSet.filter { id in
            guard let scan = searchIndex.documentsById[id] else { return false }
            return tokens.allSatisfy { scan.searchString.contains($0) }
        }
    }
}
