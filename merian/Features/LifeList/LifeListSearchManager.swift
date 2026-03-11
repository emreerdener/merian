import Foundation
import SwiftData
import SwiftUI
import ImageIO


struct SearchableScan: Sendable {
    let id: String
    let searchString: String
}

@MainActor
class LifeListSearchManager: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var filteredScans: [LocalScanRecord] = []
    
    var allScans: [LocalScanRecord] = [] {
        didSet { updateSearchableData() }
    }
    
    private var searchableData: [SearchableScan] = []
    private var searchTask: Task<Void, Never>?
    
    private func updateSearchableData() {
        self.searchableData = allScans.map { record in
            let tags = record.semanticTags.joined(separator: " ")
            let rawString = "\(record.commonName) \(record.scientificName) \(record.ecologyType) \(record.insightDescription) \(tags)".lowercased()
            return SearchableScan(id: record.id, searchString: rawString)
        }
    }
    
    func performSearch(query: String) {
        searchTask?.cancel()
        
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // Debounce typing
            if Task.isCancelled { return }
            
            let text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                self.filteredScans = allScans
                return
            }
            
            if searchableData.isEmpty {
                self.filteredScans = []
                return
            }
            
            // Offload heavy multi-token String matching entirely off the UI thread
            let searchData = self.searchableData
            let matchingIds = await Task.detached(priority: .userInitiated) {
                let tokens = text.components(separatedBy: .whitespaces)
                return Set(searchData.filter { scan in
                    tokens.allSatisfy { token in
                        scan.searchString.contains(token)
                    }
                }.map { $0.id })
            }.value
            
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
                            Button(action: {
                                selectedScanForInsight = scan
                                inferenceEngine.load(from: scan)
                            }) {
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
                        }
                    }
                }
                .sheet(item: $selectedScanForInsight) { scan in
                    InsightSheetView(isPresented: Binding(
                        get: { selectedScanForInsight != nil },
                        set: { if !$0 { selectedScanForInsight = nil } }
                    ), showCloseButton: true)
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
                let cacheKey = imagePath
                if let cached = ImageCache.shared.get(forKey: cacheKey) {
                    self.thumbnail = cached
                    return
                }
                
                let fullPathURL = URL.documentsDirectory.appendingPathComponent(imagePath)
                if let generatedThumb = await generateThumbnail(for: fullPathURL, cacheKey: cacheKey) {
                    await MainActor.run { self.thumbnail = generatedThumb }
                }
            }
        }
    }
}

nonisolated func generateThumbnail(for url: URL, cacheKey: String) async -> UIImage? {
    if Task.isCancelled { return nil }
    
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 300
    ]
    
    if Task.isCancelled { return nil }
    
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
        let fallback = UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 300, height: 300))
        if let fb = fallback { ImageCache.shared.set(fb, forKey: cacheKey) }
        return fallback
    }
    
    let img = UIImage(cgImage: cgImage)
    ImageCache.shared.set(img, forKey: cacheKey)
    return img
}
