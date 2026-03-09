import Foundation
import SwiftData
import SwiftUI
import ImageIO

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
    var isBiological: Bool
    var isLiveCapture: Bool
    var isInvasive: Bool
    var ecologyType: String
    var wikipediaUrl: String?
    var referenceImageUrl: String?
    var additionalImagePaths: [String]?
    var confidenceScore: Double?
    
    init(id: String = UUID().uuidString,
         speciesId: String,
         scientificName: String,
         commonName: String,
         insightDescription: String,
         timestamp: Date = Date(),
         localImagePath: String? = nil,
         semanticTags: [String] = [],
         isPoisonous: Bool = false,
         isBiological: Bool = true,
         isLiveCapture: Bool = true,
         isInvasive: Bool = false,
         ecologyType: String = "unknown",
         wikipediaUrl: String? = nil,
         referenceImageUrl: String? = nil,
         additionalImagePaths: [String]? = nil,
         confidenceScore: Double? = nil) {
        
        self.id = id
        self.speciesId = speciesId
        self.scientificName = scientificName
        self.commonName = commonName
        self.insightDescription = insightDescription
        self.timestamp = timestamp
        self.localImagePath = localImagePath
        self.semanticTags = semanticTags
        self.isPoisonous = isPoisonous
        self.isBiological = isBiological
        self.isLiveCapture = isLiveCapture
        self.isInvasive = isInvasive
        self.ecologyType = ecologyType
        self.wikipediaUrl = wikipediaUrl
        self.referenceImageUrl = referenceImageUrl
        self.additionalImagePaths = additionalImagePaths
        self.confidenceScore = confidenceScore
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
            $0.ecologyType.lowercased(),
            $0.insightDescription.lowercased()
        ] + $0.semanticTags.map { $0.lowercased() }) }
        
        // Push the semantic filtering loop strictly to a background detached thread to ensure the UI scroll never stutters
        Task.detached(priority: .userInitiated) {
            let tokens = text.components(separatedBy: .whitespaces)
            let matchingIds = Set(searchableData.filter { item in
                
                // Ensure all independent user query tokens resolve true against the compiled index bounds
                return tokens.allSatisfy { token in
                    item.textData.contains { $0.contains(token) }
                }
            }.map { $0.id })
            
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
    
    @State private var navPath = NavigationPath()
    @FocusState private var isSearchFocused: Bool
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationStack(path: $navPath) {
            VStack(spacing: 0) {
                ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(searchManager.filteredScans) { scan in
                        VStack(alignment: .leading) {
                            if let imagePath = scan.localImagePath {
                                LifeListThumbnailView(imagePath: imagePath)
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
                            navPath.append(scan)
                        }
                    }
                }
                .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            
            ToolbarItem(placement: .bottomBar) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search tags, habitats, colors...", text: $searchManager.searchQuery)
                        .focused($isSearchFocused)
                        .textFieldStyle(.plain)
                        .onChange(of: searchManager.searchQuery) { _, newValue in
                            searchManager.performSearch(query: newValue)
                        }
                    
                    if !searchManager.searchQuery.isEmpty {
                        Button(action: {
                            searchManager.searchQuery = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.tertiarySystemFill))
                .cornerRadius(10)
                .animation(.easeInOut(duration: 0.2), value: searchManager.searchQuery.isEmpty)
            }
        }
        .navigationTitle("Life List")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: LocalScanRecord.self) { scan in
            InsightSheetView(isPresented: .constant(true), showCloseButton: false)
        }
        .onAppear {
            searchManager.allScans = allRecords
            searchManager.performSearch(query: searchManager.searchQuery)
        }
        .onChange(of: allRecords) { _, newRecords in
            searchManager.allScans = newRecords
            searchManager.performSearch(query: searchManager.searchQuery)
        }
        } // Ends NavigationStack
    }
}

struct LifeListThumbnailView: View {
    let imagePath: String
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        Group {
            if let uiImage = thumbnail {
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
        }
        .task {
            if thumbnail == nil {
                let fullPathURL = URL.documentsDirectory.appendingPathComponent(imagePath)
                if let generatedThumb = await generateThumbnail(for: fullPathURL) {
                    await MainActor.run {
                        self.thumbnail = generatedThumb
                    }
                }
            }
        }
    }
}

nonisolated func generateThumbnail(for url: URL) async -> UIImage? {
    if Task.isCancelled { return nil }
    
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 300
    ]
    
    if Task.isCancelled { return nil }
    
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
        return UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 300, height: 300))
    }
    
    return UIImage(cgImage: cgImage)
}
