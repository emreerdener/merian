import SwiftUI
import SwiftData

// 3. Scans Semantic View Interface
enum ScansTab {
    case library
    case collections
}

struct ScansSearchView: View {
    @StateObject private var searchManager = ScansSearchManager()
    @Query(filter: #Predicate<LocalScanRecord> { $0.isBiological == true && $0.commonName != "Unknown Subject" }, sort: \.timestamp, order: .reverse) private var allRecords: [LocalScanRecord]
    @Query(sort: \ScanCollection.createdAt, order: .reverse) private var collections: [ScanCollection]
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @Environment(\.dismiss) var dismiss
    @Binding var isInsightSheetOpen: Bool
    
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @State private var activeTab: ScansTab = .library
    
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    
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
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                VStack(spacing: 8) {
                    if searchManager.searchQuery.isEmpty && !isSearchFocused {
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
                                            ScansThumbnailView(imagePath: scan.localImagePath, fallbackImageUrl: scan.referenceImageUrl)
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
                }
                .containerRelativeFrame(.horizontal)
                .id(ScansTab.library)
                
                ScrollView {
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
                                                    ScansThumbnailView(imagePath: firstScan.localImagePath, fallbackImageUrl: firstScan.referenceImageUrl)
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
                        
                        NavigationLink {
                            NonBiologicalScansView(isInsightSheetOpen: $isInsightSheetOpen)
                        } label: {
                            HStack {
                                Text("Non biological")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 32)
                }
                .containerRelativeFrame(.horizontal)
                .id(ScansTab.collections)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(get: { activeTab }, set: { if let val = $0 { activeTab = val } }))
            .sheet(item: $selectedScanForInsight) { scan in
                InsightSheetView(isPresented: Binding(
                    get: { selectedScanForInsight != nil },
                    set: { if !$0 { selectedScanForInsight = nil } }
                ))
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchManager.searchQuery, isPresented: $isSearchFocused, placement: .toolbar, prompt: "Search tags, habitats, colors...")
            //.searchDictationBehavior(.inline(activation: .onSelect))
            .onChange(of: searchManager.searchQuery) { _, newValue in
                searchManager.performSearch(query: newValue)
                if !newValue.isEmpty && activeTab != .library {
                    withAnimation {
                        activeTab = .library
                    }
                }
            }
            .onChange(of: isSearchFocused) { _, isFocused in
                if isFocused && activeTab != .library {
                    withAnimation {
                        activeTab = .library
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        if !searchManager.searchQuery.isEmpty {
                            searchManager.searchQuery = ""
                        } else {
                            dismiss()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if activeTab == .collections {
                        Button(action: {
                            showNewCollectionAlert = true
                        }) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $activeTab) {
                        Text("Scans").tag(ScansTab.library)
                        Text("Collections").tag(ScansTab.collections)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
                }
                
                //DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
            .toolbarBackground(.hidden, for: .bottomBar)
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
}
