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
    private var indexingTask: Task<Void, Never>?
    
    private func updateSearchableData() {
        indexingTask?.cancel()
        
        struct ScanPayload: Sendable {
            let id: String
            let semanticTags: [String]
            let commonName: String
            let scientificName: String
            let ecologyType: String
            let insightDescription: String
            let taxonomyKingdom: String?
            let taxonomyClass: String?
        }
        
        let payloads = allScans.map { record in
            ScanPayload(
                id: record.id,
                semanticTags: record.semanticTags,
                commonName: record.commonName,
                scientificName: record.scientificName,
                ecologyType: record.ecologyType,
                insightDescription: record.insightDescription,
                taxonomyKingdom: record.taxonomyKingdom,
                taxonomyClass: record.taxonomyClass
            )
        }
        
        indexingTask = Task.detached(priority: .userInitiated) {
            var processed: [SearchableScan] = []
            processed.reserveCapacity(payloads.count)
            
            for record in payloads {
                if Task.isCancelled { return }
                
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
            
            if Task.isCancelled { return }
            
            // Create an immutable copy to satisfy Swift 6 Sendable closure isolation bounds
            let finalProcessed = processed
            
            await MainActor.run {
                self.searchableData = finalProcessed
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

// 3. LifeList Semantic View Interface
enum LifeListTab {
    case library
    case collections
}

struct LifeListSearchView: View {
    @StateObject private var searchManager = LifeListSearchManager()
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allRecords: [LocalScanRecord]
    @Query(sort: \ScanCollection.createdAt, order: .reverse) private var collections: [ScanCollection]
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @Environment(\.dismiss) var dismiss
    @Binding var isInsightSheetOpen: Bool
    
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @Binding var activeTab: LifeListTab
    
    @Binding var showNewCollectionAlert: Bool
    @Binding var newCollectionName: String
    
    @State private var scanToDelete: LocalScanRecord? = nil
    @State private var showDeleteConfirmation = false
    @State private var isSearchFocused = false
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    private let filterCategories = ["All", "Plants", "Fungi", "Insects", "Birds", "Mammals", "Reptiles"]
    
    var body: some View {
        VStack(spacing: 8) {
            
            // Tab Toggle & Create Button Header
            HStack {
                Spacer() // Balance the clear color on the right
                    .frame(width: 24)
                    
                Spacer()
                
                Picker("View", selection: $activeTab) {
                    Text("Scans").tag(LifeListTab.library)
                    Text("Collections").tag(LifeListTab.collections)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                Spacer()
                
                if activeTab == .collections {
                    Button(action: { showNewCollectionAlert = true }) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .frame(width: 24)
                } else {
                    Color.clear.frame(width: 24)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

                if activeTab == .library && searchManager.searchQuery.isEmpty && !isSearchFocused {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filterCategories, id: \.self) { category in
                                Button(action: {
                                    withAnimation {
                                        if !searchManager.searchQuery.isEmpty {
                                            searchManager.activeCategoryFilter = category 
                                            searchManager.searchQuery = "" // This assignment explicitly triggers the .onChange modifier which launches the debounced search
                                        } else {
                                            searchManager.performSearch(query: "", category: category)
                                        }
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
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .background(Color(UIColor.systemBackground))
                }
                
                ScrollView {
                    if activeTab == .library {
                        renderLibraryTab()
                    } else if activeTab == .collections {
                        renderCollectionsTab()
                    }
                }
            .sheet(item: $selectedScanForInsight) { scan in
                InsightSheetView(isPresented: Binding(
                    get: { selectedScanForInsight != nil },
                    set: { if !$0 { selectedScanForInsight = nil } }
                ))
            }
            }
            // Extracted toolbar items to MainTabView
            .alert("New collection", isPresented: $showNewCollectionAlert) {
                TextField("Collection name", text: $newCollectionName)
                Button("Cancel", role: .cancel) { newCollectionName = "" }
                Button("Create") {
                    let collection = ScanCollection(name: newCollectionName.isEmpty ? "Untitled" : newCollectionName)
                    modelContext.insert(collection)
                    try? modelContext.save()
                    newCollectionName = ""
                }
            } message: {
                Text("Enter a name for this new collection.")
            }
        .onAppear {
            searchManager.allScans = allRecords
            searchManager.performSearch(query: searchManager.searchQuery)
        }
        .onChange(of: allRecords) { _, newRecords in
            searchManager.allScans = newRecords
            searchManager.performSearch(query: searchManager.searchQuery)
        }
        .confirmationDialog(
            "Delete scan",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible,
            presenting: scanToDelete
        ) { scan in
            Button("Delete scan permanently", role: .destructive) {
                HapticManager.shared.triggerErrorThump()
                ScanRepository.shared.eradicateScan(record: scan, modelContext: modelContext)
                scanToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                scanToDelete = nil
            }
        } message: { _ in
            Text("Are you sure you want to delete this scan? This will permanently remove the photo and data from your device and the global biological archive.")
        }
    }
    
    @ViewBuilder
    private func renderLibraryTab() -> some View {
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
                
                Text("No scans found")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if !searchManager.searchQuery.isEmpty {
                    Text("No results for \"\(searchManager.searchQuery)\" in \(searchManager.activeCategoryFilter)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                } else if searchManager.activeCategoryFilter != "All" {
                    Text("You haven't documented any \(searchManager.activeCategoryFilter.lowercased()) yet")
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
                            LifeListThumbnailView(imagePath: scan.localImagePath, fallbackImageUrl: scan.referenceImageUrl)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                scanToDelete = scan
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete scan permanently", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func renderCollectionsTab() -> some View {
        if collections.isEmpty {
            VStack(spacing: 16) {
                Spacer().frame(height: 80)
                Image(systemName: "folder")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.secondary)
                Text("No collections")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("Create your first collection to start organizing your scans.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(collections) { collection in
                    NavigationLink {
                        CollectionDetailView(collection: collection, isInsightSheetOpen: $isInsightSheetOpen)
                    } label: {
                        ZStack {
                            if let firstScan = collection.scans?.first {
                                GeometryReader { geo in
                                    LifeListThumbnailView(imagePath: firstScan.localImagePath, fallbackImageUrl: firstScan.referenceImageUrl)
                                        .frame(width: geo.size.width, height: geo.size.width)
                                        .clipped()
                                }
                                .aspectRatio(1.0, contentMode: .fill)
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .aspectRatio(1.0, contentMode: .fill)
                                    .overlay(
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.system(size: 24))
                                            .foregroundColor(.secondary)
                                    )
                            }
                            
                            VStack {
                                Spacer()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(collection.name)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text("\(collection.scans?.count ?? 0) Scans")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                            }
                        }
                        .cornerRadius(12)
                        .clipped()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
    }
}

struct LifeListThumbnailView: View {
    let imagePath: String?
    var fallbackImageUrl: String? = nil
    
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
                                Text("Visuals archived")
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
        .task(id: imagePath ?? fallbackImageUrl ?? UUID().uuidString) {
            if thumbnail == nil {
                let cacheKey = imagePath ?? fallbackImageUrl ?? UUID().uuidString
                // 1. Check RAM immediately for existing decoded array bytes
                if let cached = ImageCache.shared.get(forKey: cacheKey) {
                    self.thumbnail = cached
                    return
                }
                
                // 2. Local File extraction attempting to load natively
                if let safePath = imagePath {
                    let filename = (safePath as NSString).lastPathComponent
                    let fullPathURL = URL.documentsDirectory.appendingPathComponent(filename)
                    if let generatedThumb = await generateThumbnail(for: fullPathURL, cacheKey: cacheKey) {
                        await MainActor.run { self.thumbnail = generatedThumb }
                        return
                    }
                }
                
                // 3. Local File is Missing/Archived off R2 -> trigger robust network fallback
                if let fallbackUrlString = fallbackImageUrl, let fallbackUrl = URL(string: fallbackUrlString) {
                    if let networkImage = await fetchNetworkFallback(url: fallbackUrl, cacheKey: cacheKey) {
                        await MainActor.run { self.thumbnail = networkImage }
                    } else {
                        await MainActor.run { self.hasFailedToLoad = true }
                    }
                } else {
                    await MainActor.run { self.hasFailedToLoad = true }
                }
            }
        }
    }
}

nonisolated func generateThumbnail(for url: URL, cacheKey: String) async -> UIImage? {
    if Task.isCancelled { return nil }
    
    return await Task.detached(priority: .userInitiated) {
        if Task.isCancelled { return nil }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300
        ]
        
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            let fallback = UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 300, height: 300))
            if let fb = fallback { ImageCache.shared.set(fb, forKey: cacheKey) }
            return fallback
        }
        
        let img = UIImage(cgImage: cgImage)
        ImageCache.shared.set(img, forKey: cacheKey)
        return img
    }.value
}

nonisolated func fetchNetworkFallback(url: URL, cacheKey: String) async -> UIImage? {
    if Task.isCancelled { return nil }
    
    do {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        if Task.isCancelled { return nil }
        
        return await Task.detached(priority: .userInitiated) {
            if let cgImage = ImageDownsampler.downsample(data: data, maxSize: 500) {
                let thumbnail = UIImage(cgImage: cgImage)
                ImageCache.shared.set(thumbnail, forKey: cacheKey)
                return thumbnail
            } else {
                let fallback = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 500, height: 500))
                if let fb = fallback { ImageCache.shared.set(fb, forKey: cacheKey) }
                return fallback
            }
        }.value
    } catch {
        return nil
    }
}


