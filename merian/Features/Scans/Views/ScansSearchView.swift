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
    
// Struct bounds maintained safely
    
    private let filterCategories = ["All", "Plants", "Fungi", "Insects", "Birds", "Mammals", "Reptiles"]
    
    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                ScansLibraryGridView(
                    searchManager: searchManager,
                    filterCategories: filterCategories,
                    isSearchFocused: isSearchFocused,
                    onSelect: { scan in
                        selectedScanForInsight = scan
                        inferenceEngine.load(from: scan)
                    },
                    onDelete: { scan in
                        scanToDelete = scan
                        showDeleteConfirmation = true
                    }
                )
                
                ScansCollectionsGridView(
                    collections: collections,
                    isInsightSheetOpen: $isInsightSheetOpen
                )
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(get: { activeTab }, set: { if let val = $0 { activeTab = val } }))
            .ignoresSafeArea(.keyboard, edges: .bottom)
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
            .scansSearchToolbar(
                searchManager: searchManager,
                activeTab: $activeTab,
                showNewCollectionAlert: $showNewCollectionAlert,
                dismiss: dismiss
            )
            //DefaultToolbarItem(kind: .search, placement: .bottomBar)
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
        .scanDeletionDialog(
            isPresented: $showDeleteConfirmation,
            record: scanToDelete,
            modelContext: modelContext
        ) {
            scanToDelete = nil
        }
    }
}
