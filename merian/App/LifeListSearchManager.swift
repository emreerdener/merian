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

// Background Detached Actor natively mapping Semantic Index loops exclusively to prevent MainActor SQLite faulting freezes
@ModelActor
actor BackgroundSearchActor {
    func performSemanticSearch(query: String) -> Set<String> {
        let text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return [] }
        let tokens = text.components(separatedBy: .whitespaces)
        
        let descriptor = FetchDescriptor<LocalScanRecord>()
        let records = (try? modelContext.fetch(descriptor)) ?? []
        
        return Set(records.filter { record in
            let tags = record.semanticTags
            let searchSpace = [
                record.commonName.lowercased(),
                record.scientificName.lowercased(),
                record.ecologyType.lowercased(),
                record.insightDescription.lowercased()
            ] + tags.map { $0.lowercased() }
            
            return tokens.allSatisfy { token in
                searchSpace.contains { $0.contains(token) }
            }
        }.map { $0.id })
    }
}
// 2. MainActor Search Engine Queue Manager
@MainActor
class LifeListSearchManager: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var filteredScans: [LocalScanRecord] = []
    
    var allScans: [LocalScanRecord] = []
    private var searchTask: Task<Void, Never>?
    
    func performSearch(query: String) {
        searchTask?.cancel()
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            
            let text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                self.filteredScans = allScans
                return
            }
            
            if allScans.isEmpty {
                self.filteredScans = []
                return
            }
            
            guard let container = allScans.first?.modelContext?.container else { return }
            let backgroundActor = BackgroundSearchActor(modelContainer: container)
            let matchingIds = await backgroundActor.performSemanticSearch(query: text)
            
            if Task.isCancelled { return }
            self.filteredScans = self.allScans.filter { matchingIds.contains($0.id) }
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
    
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @FocusState private var isSearchFocused: Bool
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom Header mapping exactly to prevent layout shifts on iOS Nav Transitions
                ZStack {
                    HStack {
                        GlassCircularButton(iconName: "xmark") {
                            dismiss()
                        }
                        Spacer()
                    }
                    
                    Text("Life List")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .background(Color(UIColor.systemBackground))
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(searchManager.filteredScans) { scan in
                            NavigationLink(value: scan) {
                                Group {
                                    if let imagePath = scan.localImagePath {
                                        LifeListThumbnailView(imagePath: imagePath)
                                    } else {
                                        Color.clear
                                            .aspectRatio(1.0, contentMode: .fit)
                                            .overlay(
                                                Rectangle().fill(Color.gray.opacity(0.3))
                                            )
                                            .clipped()
                                    }
                                }
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                inferenceEngine.load(from: scan)
                            })
                        }
                    }
                }
                .navigationDestination(for: LocalScanRecord.self) { scan in
                    InsightSheetView(isPresented: .constant(true), showCloseButton: false)
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
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
                .background(Color(UIColor.tertiarySystemFill).opacity(0.9))
                .background(.ultraThinMaterial)
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.2), value: searchManager.searchQuery.isEmpty)
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

struct LifeListThumbnailView: View {
    let imagePath: String
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        Color.clear
            .aspectRatio(1.0, contentMode: .fit)
            .overlay(
                Group {
                    if let uiImage = thumbnail {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                }
            )
            .clipped()
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
