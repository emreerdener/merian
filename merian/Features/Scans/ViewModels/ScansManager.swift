import Foundation
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
    
    init() {
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ScanRequiresSearchIndexUpdate"), object: nil, queue: .main) { [weak self] notification in
            guard let scanId = notification.userInfo?["scanId"] as? String else { return }
            Task { @MainActor [weak self] in
                self?.forceReindex(scanId: scanId)
            }
        }
    }
    
    // MARK: - Data Ingestion
    var allScans: [LocalScanRecord] = [] {
        didSet { updateSearchableData(oldScans: oldValue) }
    }
    
    // MARK: - Cache & Threading State
    @ObservationIgnored private var scanMap: [String: LocalScanRecord] = [:]
    @ObservationIgnored private var searchableData: [SearchableScan] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var indexingTask: Task<Void, Never>?
    
    // MARK: - Data Indexing Pipeline
    private func updateSearchableData(oldScans: [LocalScanRecord]) {
        indexingTask?.cancel()
        
        guard let firstScan = allScans.first, let container = firstScan.modelContext?.container else {
            self.searchableData = []
            self.scanMap = [:]
            return
        }
        
        let oldIds = Set(oldScans.map { $0.id })
        let newIds = Set(allScans.map { $0.id })

        let addedScans = allScans.filter { !oldIds.contains($0.id) }
        let removedIds = oldIds.subtracting(newIds)

        // Incrementally patch scanMap instead of rebuilding the whole dictionary.
        // A full rebuild is O(n) on @MainActor on every scan mutation; incremental updates
        // are O(delta) — typically O(1) for a single add or delete.
        for scan in addedScans { self.scanMap[scan.id] = scan }
        for id in removedIds { self.scanMap.removeValue(forKey: id) }
        
        // 1. Instantly prune deleted UUIDs out of the string cache natively without touching the background thread!
        if !removedIds.isEmpty {
            self.searchableData.removeAll { removedIds.contains($0.id) }
        }
        
        // 2. Short circuit if there are no new scans explicitly needing heavy String Extraction!
        if addedScans.isEmpty && self.searchableData.count == allScans.count {
            return
        }
        
        // If we have an initial load mismatch, execute a unified global sync organically!
        let needsFullRebuild = self.searchableData.isEmpty && !allScans.isEmpty
        let targetScans = needsFullRebuild ? allScans : addedScans
        
        // Extract lightweight string IDs so the background actor can batch-fetch all records
        // in a single SQLite query rather than N individual `model(for:)` faults.
        let idsToExtract = targetScans.map { $0.id }
        
        if idsToExtract.isEmpty { return }
        
        indexingTask = Task { [weak self] in
            let dbActor = SearchDatabaseActor(modelContainer: container)
            let processedNewScans = await dbActor.extractSearchablePayloads(from: idsToExtract)
            
            if Task.isCancelled { return }
            
            await MainActor.run { [weak self] in
                if needsFullRebuild {
                    self?.searchableData = processedNewScans
                } else {
                    self?.searchableData.append(contentsOf: processedNewScans)
                }
            }
        }
    }
    
    // MARK: - Dedicated Reindexing
    private func forceReindex(scanId: String) {
        guard let scan = scanMap[scanId], let container = scan.modelContext?.container else { return }
        self.searchableData.removeAll { $0.id == scanId }

        Task { [weak self] in
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
        
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000) // Debounce typing
            if Task.isCancelled { return }

            guard let self = self else { return }

            if text.isEmpty && catMatch == "all" {
                let sortOpt = self.sortOption
                let recordsPrimitives = self.allScans.map { ScanSortPrimitive(id: $0.id, timestamp: $0.timestamp, commonName: $0.commonName) }
                
                let sortedIds = await Task.detached(priority: .userInitiated) {
                    return ScansManager.executeDetachedSort(on: recordsPrimitives, sortOption: sortOpt).map { $0.id }
                }.value

                if Task.isCancelled { return }
                let finalSorted = sortedIds.compactMap { self.scanMap[$0] }
                withAnimation { self.filteredScans = finalSorted }
                return
            }
            
            let searchData = self.searchableData
            if searchData.isEmpty {
                withAnimation {
                    self.filteredScans = []
                }
                return
            }
            
            let filterActor = SearchFilterActor()
            let matchingIds = await filterActor.filter(text: text, searchData: searchData, catMatch: catMatch)
            
            if Task.isCancelled { return }
            
            let filteredSubset = matchingIds.compactMap { self.scanMap[$0] }
            let sortOpt = self.sortOption
            let subsetPrimitives = filteredSubset.map { ScanSortPrimitive(id: $0.id, timestamp: $0.timestamp, commonName: $0.commonName) }
            
            let sortedIds = await Task.detached(priority: .userInitiated) {
                return ScansManager.executeDetachedSort(on: subsetPrimitives, sortOption: sortOpt).map { $0.id }
            }.value
            
            if Task.isCancelled { return }
            
            let finalSorted = sortedIds.compactMap { self.scanMap[$0] }
            
            withAnimation {
                self.filteredScans = finalSorted
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
@ModelActor
actor SearchDatabaseActor {
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

            let tags = record.semanticTags.joined(separator: " ")
            // Taxonomy class/order/family are appended so users can search Latin names
            // (e.g. "aves", "passeriformes"). commonGroupName maps the class to plain
            // English synonyms (e.g. "aves" → "bird birds") so casual queries work too.
            let taxonomyTerms = [record.taxonomyClass, record.taxonomyOrder, record.taxonomyFamily]
                .compactMap { $0 }.joined(separator: " ")
            let groupName = SearchDatabaseActor.commonGroupName(for: record.taxonomyClass)

            let reasoning = record.aiReasoning ?? ""
            let location = record.locationName ?? ""
            let habitat = record.habitatDescription ?? ""
            let weather = record.weatherCondition ?? ""
            let lifeStage = record.lifeStage ?? ""
            let reproductive = record.reproductiveCondition ?? ""
            let lookalike = record.similarSpecies?.joined(separator: " ") ?? ""
            let iucn = record.iucnRedListStatus ?? ""
            let hazard = record.hazardType == "none" ? "" : record.hazardType
            let interactions = record.ecologicalInteractions?.joined(separator: " ") ?? ""

            let rawString = "\(record.commonName) \(record.scientificName) \(record.ecologyType) \(tags) \(record.customTags.joined(separator: " ")) \(record.isInvasive ? "invasive" : "") \(taxonomyTerms) \(groupName) \(reasoning) \(location) \(habitat) \(weather) \(lifeStage) \(reproductive) \(lookalike) \(iucn) \(hazard) \(interactions)".lowercased()

            processed.append(SearchableScan(
                id: record.id,
                searchString: rawString,
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
