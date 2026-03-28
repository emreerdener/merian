import Foundation
import SwiftData
import SwiftUI
import ImageIO

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
            self?.forceReindex(scanId: scanId)
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
        for id in removedIds   { self.scanMap.removeValue(forKey: id) }
        
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
        
        // Critically extract ONLY lightweight persistent identifiers from the delta, bounding CPU execution down to practically zero!
        let idsToExtract = targetScans.map { $0.persistentModelID }
        
        if idsToExtract.isEmpty { return }
        
        indexingTask = Task { [weak self] in
            let dbActor = SearchDatabaseActor(modelContainer: container)
            let processedNewScans = await dbActor.extractSearchablePayloads(from: idsToExtract)
            
            if Task.isCancelled { return }
            
            let capturedSelf = self
            await MainActor.run {
                if needsFullRebuild {
                    capturedSelf?.searchableData = processedNewScans
                } else {
                    capturedSelf?.searchableData.append(contentsOf: processedNewScans)
                }
            }
        }
    }
    
    // MARK: - Dedicated Reindexing
    private func forceReindex(scanId: String) {
        guard let scan = scanMap[scanId], let container = scan.modelContext?.container else { return }
        let persistentId = scan.persistentModelID
        self.searchableData.removeAll { $0.id == scanId }
        
        Task { [weak self] in
            let dbActor = SearchDatabaseActor(modelContainer: container)
            let newPayload = await dbActor.extractSearchablePayloads(from: [persistentId])
            if Task.isCancelled { return }
            
            await MainActor.run {
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
        
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000) // Debounce typing
            if Task.isCancelled { return }

            guard let self = self else { return }

            let text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let catMatch = currentCategory.lowercased()

            if text.isEmpty && catMatch == "all" {
                // LocalScanRecord is a @Model and not Sendable, so it cannot cross a
                // Task.detached boundary. The sort (Date/String comparisons over the
                // existing array) is fast enough to run on the main actor directly.
                let sortedAll = self.allScans.sorted { lhs, rhs in
                    switch self.sortOption {
                    case .newest: return lhs.timestamp > rhs.timestamp
                    case .oldest: return lhs.timestamp < rhs.timestamp
                    case .aToZ:   return lhs.commonName.localizedCaseInsensitiveCompare(rhs.commonName) == .orderedAscending
                    case .zToA:   return lhs.commonName.localizedCaseInsensitiveCompare(rhs.commonName) == .orderedDescending
                    }
                }
                if Task.isCancelled { return }
                withAnimation { self.filteredScans = sortedAll }
                return
            }
            
            if searchableData.isEmpty {
                withAnimation {
                    self.filteredScans = []
                }
                return
            }
            
            // Offload heavy multi-token String matching entirely off the UI thread
            let searchData = self.searchableData
            
            let filterActor = SearchFilterActor()
            let matchingIds = await filterActor.filter(text: text, searchData: searchData, catMatch: catMatch)
            
            if Task.isCancelled { return }
            
            // Decouple native UI starvation by extracting perfectly O(1) subset arrays completely securely
            let filteredSubset = matchingIds.compactMap { self.scanMap[$0] }
            
            let sortedSubset = self.executeSort(on: filteredSubset)
            
            withAnimation {
                self.filteredScans = sortedSubset
            }
        }
    }
    
    // MARK: - Dedicated Sorting Execution
    private func executeSort(on subset: [LocalScanRecord]) -> [LocalScanRecord] {
        switch self.sortOption {
            case .newest: return subset.sorted { $0.timestamp > $1.timestamp }
            case .oldest: return subset.sorted { $0.timestamp < $1.timestamp }
            case .aToZ: return subset.sorted { $0.commonName.localizedCaseInsensitiveCompare($1.commonName) == .orderedAscending }
            case .zToA: return subset.sorted { $0.commonName.localizedCaseInsensitiveCompare($1.commonName) == .orderedDescending }
        }
    }
    
    private func applySort() {
        let sorted = executeSort(on: self.filteredScans)
        withAnimation {
            self.filteredScans = sorted
        }
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
    var toastMessage: String? = nil
    
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
    func extractSearchablePayloads(from ids: [PersistentIdentifier]) -> [SearchableScan] {
        var processed: [SearchableScan] = []
        processed.reserveCapacity(ids.count)

        for id in ids {
            if Task.isCancelled { break }

            if let record = self.modelContext.model(for: id) as? LocalScanRecord {
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
                let lookalike = record.diagnosticLookalikeName ?? ""
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
