import Foundation
import SwiftData
import SwiftUI
import ImageIO

@MainActor
class ScansSearchManager: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var filteredScans: [LocalScanRecord] = []
    @Published var activeCategoryFilter: String = "All"
    
    var allScans: [LocalScanRecord] = [] {
        didSet { updateSearchableData() }
    }
    
    private var scanMap: [String: LocalScanRecord] = [:]
    private var searchableData: [SearchableScan] = []
    private var searchTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    
    private func updateSearchableData() {
        indexingTask?.cancel()
        
        guard let firstScan = allScans.first, let container = firstScan.modelContext?.container else {
            self.searchableData = []
            self.scanMap = [:]
            return
        }
        
        // Critically extract lightweight persistent identifiers natively keeping O(N) evaluations blazingly fast on UI bounds
        let ids = allScans.map { $0.persistentModelID }
        
        var newMap: [String: LocalScanRecord] = [:]
        for scan in allScans { newMap[scan.id] = scan }
        self.scanMap = newMap
        
        indexingTask = Task.detached(priority: .userInitiated) { [weak self] in
            let dbActor = SearchDatabaseActor(modelContainer: container)
            let processed = await dbActor.extractSearchablePayloads(from: ids)
            
            if Task.isCancelled { return }
            
            let capturedSelf = self
            await MainActor.run {
                capturedSelf?.searchableData = processed
            }
        }
    }
    
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
                withAnimation {
                    self.filteredScans = self.allScans
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
            
            withAnimation {
                self.filteredScans = filteredSubset
            }
        }
    }
}

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
