import Foundation
import SwiftData
import SwiftUI
import ImageIO

@MainActor
class LifeListSearchManager: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var filteredScans: [LocalScanRecord] = []
    @Published var activeCategoryFilter: String = "All"
    
    var allScans: [LocalScanRecord] = [] {
        didSet { updateSearchableData() }
    }
    
    private var searchableData: [SearchableScan] = []
    private var searchTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    
    private func updateSearchableData() {
        indexingTask?.cancel()
        
        guard let firstScan = allScans.first, let container = firstScan.modelContext?.container else {
            self.searchableData = []
            return
        }
        
        // Critically extract lightweight persistent identifiers natively keeping O(N) evaluations blazingly fast on UI bounds
        let ids = allScans.map { $0.persistentModelID }
        
        indexingTask = Task.detached(priority: .userInitiated) {
            let dbActor = SearchDatabaseActor(modelContainer: container)
            let processed = await dbActor.extractSearchablePayloads(from: ids)
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                self.searchableData = processed
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
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // Debounce typing
            if Task.isCancelled { return }
            
            let text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let catMatch = currentCategory.lowercased()
            
            if text.isEmpty && catMatch == "all" {
                withAnimation {
                    self.filteredScans = allScans
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
                return Set(searchData.filter { scan in
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
                }.map { $0.id })
            }.value
            
            if Task.isCancelled { return }
            let filteredSubset = self.allScans.filter { matchingIds.contains($0.id) }
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
            let registered: LocalScanRecord? = self.modelContext.registeredModel(for: id)
            let fetched: LocalScanRecord? = self.modelContext.model(for: id) as? LocalScanRecord
            
            if let record = registered ?? fetched {
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
