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
@Observable class ScansManager {
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
    
    // MARK: - Static Bounds
    let maxBatchSelectionLimit = 20
    
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
        
        var newMap: [String: LocalScanRecord] = [:]
        for scan in allScans { newMap[scan.id] = scan }
        self.scanMap = newMap
        
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
        
        // If we have an initial load mismatch, execute a unified global sync organically!
        let needsFullRebuild = self.searchableData.isEmpty && !allScans.isEmpty
        let targetScans = needsFullRebuild ? allScans : addedScans
        
        // Critically extract ONLY lightweight persistent identifiers from the delta, bounding CPU execution down to practically zero!
        let idsToExtract = targetScans.map { $0.persistentModelID }
        
        if idsToExtract.isEmpty { return }
        
        indexingTask = Task.detached(priority: .userInitiated) { [weak self] in
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
                let sortedAll = self.executeSort(on: self.allScans)
                
                withAnimation {
                    self.filteredScans = sortedAll
                }
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
            
            let matchingIds = await Task.detached(priority: .userInitiated) {
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
                
                if Task.isCancelled { return [String]() }
                // Return explicitly primitive Sendable boundaries preventing Swift 6 PersistentModel crossing errors natively
                return matched.map { $0.id }
            }.value
            
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
                let rawString = "\(record.commonName) \(record.scientificName) \(record.ecologyType) \(record.insightDescription) \(tags)".lowercased()
                
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
}
