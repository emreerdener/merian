import Foundation
import SwiftData
import SwiftUI
import ImageIO


struct SearchableScan: Sendable {
    let id: String
    let searchString: String
    let ecologyType: String
    let kingdom: String
    let className: String
}

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
    
    private func updateSearchableData() {
        self.searchableData = allScans.map { record in
            let tags = record.semanticTags.joined(separator: " ")
            let rawString = "\(record.commonName) \(record.scientificName) \(record.ecologyType) \(record.insightDescription) \(tags)".lowercased()
            return SearchableScan(
                id: record.id,
                searchString: rawString,
                ecologyType: record.ecologyType.lowercased(),
                kingdom: record.taxonomyKingdom?.lowercased() ?? "",
                className: record.taxonomyClass?.lowercased() ?? ""
            )
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
                let tokens = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                return Set(searchData.filter { scan in
                    let matchesCategory: Bool
                    switch catMatch {
                        case "all": 
                            matchesCategory = true
                        case "plants": 
                            matchesCategory = scan.kingdom == "plantae" || scan.searchString.contains("plant")
                        case "fungi": 
                            matchesCategory = scan.kingdom == "fungi" || scan.searchString.contains("fungi") || scan.searchString.contains("mushroom")
                        case "insects": 
                            matchesCategory = scan.className == "insecta" || scan.className == "entognatha" || scan.className == "arachnida" || scan.searchString.contains("insect") || scan.searchString.contains("bug") || scan.searchString.contains("spider")
                        case "birds": 
                            matchesCategory = scan.className == "aves" || scan.searchString.contains("bird")
                        case "mammals": 
                            matchesCategory = scan.className == "mammalia" || scan.searchString.contains("mammal")
                        case "reptiles": 
                            matchesCategory = scan.className == "reptilia" || scan.className == "squamata" || scan.className == "amphibia" || scan.searchString.contains("reptile") || scan.searchString.contains("amphibian")
                        default: 
                            matchesCategory = scan.searchString.contains(catMatch)
                    }
                    
                    if !matchesCategory { return false }
                    if tokens.isEmpty { return true }
                    
                    return tokens.allSatisfy { token in
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
enum LifeListTab {
    case library
    case collections
}

struct LifeListSearchView: View {
    @StateObject private var searchManager = LifeListSearchManager()
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allRecords: [LocalScanRecord]
    
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @Environment(\.dismiss) var dismiss
    @Binding var isInsightSheetOpen: Bool
    
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @FocusState private var isSearchFocused: Bool
    
    @State private var isSearchExpanded: Bool = false
    @State private var activeTab: LifeListTab = .library
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    private let filterCategories = ["All", "Plants", "Fungi", "Insects", "Birds", "Mammals", "Reptiles"]
    
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
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filterCategories, id: \.self) { category in
                            Button(action: {
                                withAnimation {
                                    if !searchManager.searchQuery.isEmpty {
                                        searchManager.searchQuery = "" // Clear the search so the filter works!
                                    }
                                    searchManager.performSearch(query: "", category: category)
                                }
                            }) {
                                Text(category)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(searchManager.activeCategoryFilter == category ? Color.primary : Color.secondary.opacity(0.15))
                                    .foregroundColor(searchManager.activeCategoryFilter == category ? Color(UIColor.systemBackground) : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 12)
                .background(Color(UIColor.systemBackground))
                
                ScrollView {
                    if searchManager.filteredScans.isEmpty {
                        VStack(spacing: 16) {
                            Spacer().frame(height: 80)
                            
                            ZStack {
                                Circle()
                                    .fill(searchManager.activeCategoryFilter == "All" ? Color.secondary.opacity(0.1) : Color.primary.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "camera.macro")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(searchManager.activeCategoryFilter == "All" ? .secondary : .primary)
                            }
                            
                            Text("No Scans Found")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            if !searchManager.searchQuery.isEmpty {
                                Text("No results for \"\(searchManager.searchQuery)\" in \(searchManager.activeCategoryFilter).")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            } else if searchManager.activeCategoryFilter != "All" {
                                Text("You haven't documented any \(searchManager.activeCategoryFilter.lowercased()) yet.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            } else {
                                Text("Start exploring and capture your first scan!")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
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
                if isSearchExpanded {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search tags, habitats, colors...", text: $searchManager.searchQuery)
                            .focused($isSearchFocused)
                            .textFieldStyle(.plain)
                            .onChange(of: searchManager.searchQuery) { _, newValue in
                                searchManager.performSearch(query: newValue)
                            }
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if searchManager.searchQuery.isEmpty {
                                    isSearchExpanded = false
                                    isSearchFocused = false
                                } else {
                                    searchManager.searchQuery = ""
                                }
                            }
                        }) {
                            Image(systemName: searchManager.searchQuery.isEmpty ? "xmark" : "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .padding(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.opacity)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.3)) // Darker fallback
                    .background(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark) // Force elegant dark glass
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    HStack {
                        // Left section: Library / Collections Segmented Glass Pill
                        HStack(spacing: 0) {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    activeTab = .library
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: activeTab == .library ? "photo.on.rectangle.fill" : "photo.on.rectangle")
                                        .font(.system(size: 20, weight: .regular))
                                    Text("Library")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(activeTab == .library ? .blue : .white)
                                .frame(width: 80, height: 50)
                                .background(
                                    activeTab == .library ? Color.black.opacity(0.4) : Color.clear
                                )
                                .clipShape(Capsule())
                            }
                            
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    activeTab = .collections
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "rectangle.stack")
                                        .font(.system(size: 20, weight: .regular))
                                    Text("Collections")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(activeTab == .collections ? .blue : .white)
                                .frame(width: 80, height: 50)
                                .background(
                                    activeTab == .collections ? Color.black.opacity(0.4) : Color.clear
                                )
                                .clipShape(Capsule())
                            }
                        }
                        .padding(4)
                        .background(Color.black.opacity(0.3)) // Dark base for glass
                        .background(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark) // Force sleek dark glass look
                        .clipShape(Capsule())
                        
                        Spacer()
                        
                        // Right Section: Floating Glass Search Button
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isSearchExpanded = true
                                isSearchFocused = true
                            }
                        }) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 22, weight: .regular))
                                .foregroundColor(.white)
                                .frame(width: 58, height: 58)
                                .background(Color.black.opacity(0.3))
                                .background(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark) // Force sleek dark glass look
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
    @State private var hasFailedToLoad: Bool = false
    
    var body: some View {
        Color.clear
            .aspectRatio(1.0, contentMode: .fit)
            .overlay(
                Group {
                    if let uiImage = thumbnail {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                    } else if hasFailedToLoad {
                        ZStack {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                            
                            VStack(spacing: 4) {
                                Image(systemName: "archivebox.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white.opacity(0.7))
                                Text("Visuals Archived")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
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
                } else {
                    await MainActor.run { self.hasFailedToLoad = true }
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
