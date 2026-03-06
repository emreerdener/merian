import Foundation
import SwiftData
import SwiftUI

// 1. Semantic Gamification Caching Model
@Model
final class LocalScanRecord {
    @Attribute(.unique) var id: String
    var speciesId: String
    var scientificName: String
    var commonName: String
    var insightDescription: String
    var timestamp: Date
    var localImagePath: String?
    
    // The Semantic Index explicitly driven by Gemini tags, enabling full Natural Language queries completely off-network.
    var semanticTags: [String]
    
    init(id: String = UUID().uuidString,
         speciesId: String,
         scientificName: String,
         commonName: String,
         insightDescription: String,
         timestamp: Date = Date(),
         localImagePath: String? = nil,
         semanticTags: [String] = []) {
        
        self.id = id
        self.speciesId = speciesId
        self.scientificName = scientificName
        self.commonName = commonName
        self.insightDescription = insightDescription
        self.timestamp = timestamp
        self.localImagePath = localImagePath
        self.semanticTags = semanticTags
    }
}

// 2. MainActor Search Engine Queue Manager
@MainActor
class LifeListSearchManager: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var filteredScans: [LocalScanRecord] = []
    
    var allScans: [LocalScanRecord] = []
    
    func performSearch(query: String) {
        let text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            self.filteredScans = allScans
            return
        }
        
        let scansToSearch = allScans
        
        // Push the semantic filtering loop strictly to a background detached thread to ensure the UI scroll never stutters
        Task.detached(priority: .userInitiated) {
            let tokens = text.components(separatedBy: .whitespaces)
            let result = scansToSearch.filter { scan in
                
                // Aggregate all core semantic metrics into a searchable scalar array
                let scanData = [
                    scan.commonName.lowercased(),
                    scan.scientificName.lowercased(),
                    scan.insightDescription.lowercased()
                ] + scan.semanticTags.map { $0.lowercased() }
                
                // Ensure all independent user query tokens resolve true against the compiled index bounds
                return tokens.allSatisfy { token in
                    scanData.contains { $0.contains(token) }
                }
            }
            
            await MainActor.run { [weak self] in
                self?.filteredScans = result
            }
        }
    }
}

// 3. LifeList Semantic View Interface
struct LifeListSearchView: View {
    @StateObject private var searchManager = LifeListSearchManager()
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allRecords: [LocalScanRecord]
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack {
            // Glassmorphic Semantic Input Bar
            TextField("Search tags, habitats, colors...", text: $searchManager.searchQuery)
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .padding(.horizontal)
                .onChange(of: searchManager.searchQuery) { _, newValue in
                    searchManager.performSearch(query: newValue)
                }
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(searchManager.filteredScans) { scan in
                        VStack(alignment: .leading) {
                            if let imagePath = scan.localImagePath,
                               let uiImage = UIImage(contentsOfFile: imagePath) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 120)
                                    .clipped()
                                    .cornerRadius(8)
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 120)
                                    .cornerRadius(8)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scan.commonName)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                Text(scan.scientificName)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .italic()
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                            .padding(.top, 4)
                        }
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            searchManager.allScans = allRecords
            searchManager.performSearch(query: searchManager.searchQuery)
        }
        .onChange(of: allRecords) { _, newRecords in
            searchManager.allScans = newRecords
            searchManager.performSearch(query: searchManager.searchQuery)
        }
    }
}
