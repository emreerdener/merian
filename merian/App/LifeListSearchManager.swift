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
    var isPoisonous: Bool
    var wikipediaUrl: String?
    var referenceImageUrl: String?
    
    init(id: String = UUID().uuidString,
         speciesId: String,
         scientificName: String,
         commonName: String,
         insightDescription: String,
         timestamp: Date = Date(),
         localImagePath: String? = nil,
         semanticTags: [String] = [],
         isPoisonous: Bool = false,
         wikipediaUrl: String? = nil,
         referenceImageUrl: String? = nil) {
        
        self.id = id
        self.speciesId = speciesId
        self.scientificName = scientificName
        self.commonName = commonName
        self.insightDescription = insightDescription
        self.timestamp = timestamp
        self.localImagePath = localImagePath
        self.semanticTags = semanticTags
        self.isPoisonous = isPoisonous
        self.wikipediaUrl = wikipediaUrl
        self.referenceImageUrl = referenceImageUrl
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
        
        let searchableData = allScans.map { (id: $0.id, textData: [
            $0.commonName.lowercased(),
            $0.scientificName.lowercased(),
            $0.insightDescription.lowercased()
        ] + $0.semanticTags.map { $0.lowercased() }) }
        
        // Push the semantic filtering loop strictly to a background detached thread to ensure the UI scroll never stutters
        Task.detached(priority: .userInitiated) {
            let tokens = text.components(separatedBy: .whitespaces)
            let matchingIds = searchableData.filter { item in
                
                // Ensure all independent user query tokens resolve true against the compiled index bounds
                return tokens.allSatisfy { token in
                    item.textData.contains { $0.contains(token) }
                }
            }.map { $0.id }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.filteredScans = self.allScans.filter { matchingIds.contains($0.id) }
            }
        }
    }
}

// 3. LifeList Semantic View Interface
struct LifeListSearchView: View {
    @StateObject private var searchManager = LifeListSearchManager()
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allRecords: [LocalScanRecord]
    
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @Environment(\.dismiss) var dismiss
    @Binding var isInsightSheetOpen: Bool
    
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
                        .onTapGesture {
                            inferenceEngine.load(from: scan)
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                isInsightSheetOpen = true
                            }
                        }
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
