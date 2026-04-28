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

    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name("ScanRequiresSearchIndexUpdate"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let scanId = notification.userInfo?["scanId"] as? String else { return }
                Task { @MainActor [weak self] in
                    self?.forceReindex(scanId: scanId)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Ingestion
    var allScans: [LocalScanRecord] = [] {
        didSet { updateSearchableData(oldScans: oldValue) }
    }
    
    @ObservationIgnored private var searchableData: [SearchableScan] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var indexingTask: Task<Void, Never>?
    
    // MARK: - Data Indexing Pipeline
    private func updateSearchableData(oldScans: [LocalScanRecord]) {
        indexingTask?.cancel()
        
        guard let firstScan = allScans.first, let container = firstScan.modelContext?.container else {
            self.searchableData = []
            return
        }
        
        let oldIds = Set(oldScans.map { $0.id })
        let newIds = Set(allScans.map { $0.id })

        let addedScans = allScans.filter { !oldIds.contains($0.id) }
        let removedIds = oldIds.subtracting(newIds)
        
        // 1. Instantly prune deleted UUIDs out of the string cache natively without touching the background thread!
        if !removedIds.isEmpty {
            self.searchableData.removeAll { removedIds.contains($0.id) }
        }
        
        // 2. Short circuit if there are no new scans explicitly needing heavy String Extraction!
        if addedScans.isEmpty && self.searchableData.count == allScans.count {
            return
        }
        
        let needsFullRebuild = self.searchableData.isEmpty && !allScans.isEmpty

        if needsFullRebuild {
            // Full rebuild: allScans is already resident in @MainActor memory via @Query.
            // Extract lightweight Sendable snapshots here rather than passing IDs to
            // SearchDatabaseActor, which would fetch the same rows a second time into a
            // separate ModelContext — doubling memory usage for the initial library load.
            let snapshots = allScans.map { record in
                RawScanSnapshot(
                    id: record.id,
                    commonName: record.commonName,
                    scientificName: record.scientificName,
                    ecologyType: record.ecologyType,
                    semanticTags: record.semanticTags,
                    customTags: record.customTags,
                    isInvasive: record.isInvasive,
                    taxonomyKingdom: record.taxonomyKingdom,
                    taxonomyClass: record.taxonomyClass,
                    taxonomyOrder: record.taxonomyOrder,
                    taxonomyFamily: record.taxonomyFamily,
                    aiReasoning: record.aiReasoning,
                    locationName: record.locationName,
                    habitatDescription: record.habitatDescription,
                    weatherCondition: record.weatherCondition,
                    lifeStage: record.lifeStage,
                    reproductiveCondition: record.reproductiveCondition,
                    similarSpecies: record.similarSpecies,
                    iucnRedListStatus: record.iucnRedListStatus,
                    hazardType: record.hazardType,
                    ecologicalInteractions: record.ecologicalInteractions
                )
            }
            indexingTask = Task.detached(priority: .utility) { [weak self] in
                let processed = SearchDatabaseActor.buildSearchablePayloads(from: snapshots)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.searchableData = processed
                }
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
                    self?.searchableData.append(contentsOf: processedNewScans)
                }
            }
        }
    }
    
    // MARK: - Dedicated Reindexing
    private func forceReindex(scanId: String) {
        guard let scan = allScans.first(where: { $0.id == scanId }), let container = scan.modelContext?.container else { return }
        self.searchableData.removeAll { $0.id == scanId }

        // Cancel any prior reindex so two rapid calls cannot both append to searchableData,
        // which would produce duplicate SearchableScan entries in the search index.
        indexingTask?.cancel()
        indexingTask = Task { [weak self] in
            let dbActor = SearchDatabaseActor(modelContainer: container)
            let newPayload = await dbActor.extractSearchablePayloads(from: [scanId])
            if Task.isCancelled { return }

            await MainActor.run { [weak self] in
                self?.searchableData.append(contentsOf: newPayload)
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
            let transientMap = Dictionary(uniqueKeysWithValues: self.allScans.map { ($0.id, $0) })

            if text.isEmpty && catMatch == "all" {
                let sortOpt = self.sortOption
                let recordsPrimitives = transientMap.values.map { ScanSortPrimitive(id: $0.id, timestamp: $0.timestamp, commonName: $0.commonName) }
                
                let sortedIds = await Task.detached(priority: .userInitiated) {
                    return ScansManager.executeDetachedSort(on: recordsPrimitives, sortOption: sortOpt).map { $0.id }
                }.value

                if Task.isCancelled { return }
                
                let finalSorted = sortedIds.compactMap { transientMap[$0] }
                withAnimation { 
                    self.filteredScans = finalSorted 
                    self.isFiltering = false
                }
                return
            }
            
            let searchData = self.searchableData
            if searchData.isEmpty {
                withAnimation {
                    self.filteredScans = []
                    self.isFiltering = false
                }
                return
            }
            
            let filterActor = SearchFilterActor()
            let matchingIds = await filterActor.filter(text: text, searchData: searchData, catMatch: catMatch)
            
            if Task.isCancelled { return }
            
            let filteredSubset = matchingIds.compactMap { transientMap[$0] }
            let sortOpt = self.sortOption
            let subsetPrimitives = filteredSubset.map { ScanSortPrimitive(id: $0.id, timestamp: $0.timestamp, commonName: $0.commonName) }
            
            let sortedIds = await Task.detached(priority: .userInitiated) {
                return ScansManager.executeDetachedSort(on: subsetPrimitives, sortOption: sortOpt).map { $0.id }
            }.value
            
            if Task.isCancelled { return }
            
            let finalSorted = sortedIds.compactMap { transientMap[$0] }
            
            withAnimation {
                self.filteredScans = finalSorted
                self.isFiltering = false
            }
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

    func shareToExplore(scan: LocalScanRecord) async {
        do {
            _ = try await MerianNetworkClient.shared.shareScanToExplore(scan: scan)
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasUnseenExplorePost)
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
    let similarSpecies: [String]?
    let iucnRedListStatus: String?
    let hazardType: String
    let ecologicalInteractions: [String]?
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

        return "\(commonName) \(scientificName) \(ecologyType) \(tags) \(customTags.joined(separator: " ")) \(isInvasive ? "invasive" : "") \(taxonomyTerms) \(groupName) \(aiReasoning ?? "") \(locationName ?? "") \(habitatDescription ?? "") \(weatherCondition ?? "") \(lifeStage ?? "") \(reproductiveCondition ?? "") \(similarSpecies?.joined(separator: " ") ?? "") \(iucnRedListStatus ?? "") \(hazard) \(ecologicalInteractions?.joined(separator: " ") ?? "")".lowercased()
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
    func filter(text: String, searchData: [SearchableScan], catMatch: String) -> [String] {
        let tokens = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let matched = searchData.filter { scan in
            if Task.isCancelled { return false }
            let matchesCategory: Bool
            switch catMatch {
            case "all": 
                matchesCategory = true
            case "plants": 
                matchesCategory = scan.kingdom == "plantae"
            case "fungi": 
                matchesCategory = scan.kingdom == "fungi"
            case "insects": 
                matchesCategory = scan.className == "insecta" || scan.className == "entognatha" || scan.className == "arachnida"
            case "birds": 
                matchesCategory = scan.className == "aves"
            case "mammals": 
                matchesCategory = scan.className == "mammalia"
            case "reptiles": 
                matchesCategory = scan.className == "reptilia" || scan.className == "squamata" || scan.className == "amphibia"
            case "other":
                let isP = scan.kingdom == "plantae"
                let isF = scan.kingdom == "fungi"
                let isI = scan.className == "insecta" || scan.className == "entognatha" || scan.className == "arachnida"
                let isB = scan.className == "aves"
                let isM = scan.className == "mammalia"
                let isR = scan.className == "reptilia" || scan.className == "squamata" || scan.className == "amphibia"
                matchesCategory = !(isP || isF || isI || isB || isM || isR)
            default: 
                matchesCategory = false
            }
            
            if !matchesCategory { return false }
            if tokens.isEmpty { return true }
            
            return tokens.allSatisfy { token in
                scan.searchString.contains(token)
            }
        }
        
        if Task.isCancelled { return [] }
        return matched.map { $0.id }
    }
}
