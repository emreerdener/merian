import SwiftUI
import SwiftData

// 3. Scans Semantic View Interface
enum ScansTab {
    case library
    case collections
}

struct ScansSheetView: View {
    // MARK: - App State Engines
    @State private var searchManager = ScansManager()
    @Query(filter: #Predicate<LocalScanRecord> { $0.isBiological == true && $0.commonName != "Unknown Subject" }, sort: \.timestamp, order: .reverse) private var allRecords: [LocalScanRecord]
    @Query(sort: \ScanCollection.createdAt, order: .reverse) private var collections: [ScanCollection]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(\.dismiss) var dismiss
    @Binding var isInsightSheetOpen: Bool
    
    // MARK: - Navigation Control
    @State private var selectedScanForInsight: LocalScanRecord? = nil
    @State private var activeTab: ScansTab = .library
    
    // MARK: - Component State
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    
    @State private var scanToDelete: LocalScanRecord? = nil
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false
    @State private var showSelectionLimitAlert = false
    @State private var isSearchFocused = false
    
    // MARK: - Static Bounds
    private let filterCategories = ["All", "Plants", "Fungi", "Insects", "Birds", "Mammals", "Reptiles", "Other"]
    
    // MARK: - Core View Builder
    var body: some View {
        NavigationStack {
            TabView(selection: $activeTab) {
                LibraryTabContent(
                    searchManager: searchManager, filterCategories: filterCategories,
                    isSearchFocused: $isSearchFocused, selectedScanForInsight: $selectedScanForInsight,
                    showSelectionLimitAlert: $showSelectionLimitAlert, scanToDelete: $scanToDelete,
                    showDeleteConfirmation: $showDeleteConfirmation
                ).tag(ScansTab.library)
                
                CollectionsTabContent(
                    searchManager: searchManager, isSearchFocused: isSearchFocused,
                    sortedCollections: searchManager.sortedCollections, isInsightSheetOpen: $isInsightSheetOpen
                ).tag(ScansTab.collections)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .modifier(ScansSheetModifiers(
                searchManager: searchManager, activeTab: $activeTab, isSearchFocused: $isSearchFocused,
                selectedScanForInsight: $selectedScanForInsight, showNewCollectionAlert: $showNewCollectionAlert,
                newCollectionName: $newCollectionName, scanToDelete: $scanToDelete,
                showDeleteConfirmation: $showDeleteConfirmation, showBatchDeleteConfirmation: $showBatchDeleteConfirmation,
                showSelectionLimitAlert: $showSelectionLimitAlert, toastMessage: $searchManager.toastMessage,
                isDownloading: $searchManager.isDownloading, dismiss: dismiss, modelContext: modelContext,
                onBatchDelete: handleBatchDelete
            ))
            .toolbar {
                ScansSheetToolbar(
                    searchManager: searchManager, activeTab: $activeTab,
                    showNewCollectionAlert: $showNewCollectionAlert, dismiss: dismiss,
                    onShare: {
                        let selectedScans = searchManager.getSelectedLocalRecords()
                        Task { await searchManager.batchShare(scans: selectedScans) }
                    },
                    onDownload: {
                        let selectedScans = searchManager.getSelectedLocalRecords()
                        Task { await searchManager.batchSavePhotos(scans: selectedScans) }
                    },
                    onDelete: { showBatchDeleteConfirmation = true }
                )
            }
            .toolbarBackground(searchManager.isSelectionMode ? .visible : .hidden, for: .bottomBar)
        }
        .onAppear {
            searchManager.allScans = allRecords
            searchManager.performSearch(query: searchManager.searchQuery)
        }
        .onChange(of: allRecords) { _, newRecords in
            searchManager.allScans = newRecords
            searchManager.performSearch(query: searchManager.searchQuery)
        }
        .onChange(of: collections, initial: true) { _, newCollections in
            searchManager.collections = newCollections
        }
    }
    
    // MARK: - Action Handlers & Logic Blocks
    private func handleBatchDelete() {
        let itemsToDelete = searchManager.getSelectedLocalRecords()
        for item in itemsToDelete {
            AppDIContainer.shared.scanRepository.eradicateScan(record: item, modelContext: modelContext)
        }
        searchManager.exitSelectionMode()
    }
}

// MARK: - Private Structs

private struct LibraryTabContent: View {
    @Bindable var searchManager: ScansManager
    let filterCategories: [String]
    @Binding var isSearchFocused: Bool
    @Binding var selectedScanForInsight: LocalScanRecord?
    @Binding var showSelectionLimitAlert: Bool
    @Binding var scanToDelete: LocalScanRecord?
    @Binding var showDeleteConfirmation: Bool
    @Environment(InferenceEngine.self) var inferenceEngine

    var body: some View {
        LibraryView(
            searchManager: searchManager,
            filterCategories: filterCategories,
            isSearchFocused: isSearchFocused,
            isSelectionMode: searchManager.isSelectionMode,
            isSelected: { scan in searchManager.selectedScans.contains(scan.id) },
            onSelect: { scan in
                if searchManager.isSelectionMode {
                    let didToggle = searchManager.toggleSelection(for: scan.id)
                    if !didToggle {
                        HapticManager.shared.triggerErrorThump()
                        showSelectionLimitAlert = true
                    }
                } else {
                    selectedScanForInsight = scan
                    inferenceEngine.load(from: scan)
                }
            },
            onDelete: { scan in
                scanToDelete = scan
                showDeleteConfirmation = true
            }
        )
    }
}

private struct CollectionsTabContent: View {
    let searchManager: ScansManager
    let isSearchFocused: Bool
    let sortedCollections: [ScanCollection]
    @Binding var isInsightSheetOpen: Bool
    
    var body: some View {
        CollectionsView(
            searchQuery: searchManager.searchQuery,
            isSearchFocused: isSearchFocused,
            collections: sortedCollections,
            isInsightSheetOpen: $isInsightSheetOpen
        )
    }
}

private struct ScansSheetToolbar: ToolbarContent {
    @Bindable var searchManager: ScansManager
    @Binding var activeTab: ScansTab
    @Binding var showNewCollectionAlert: Bool
    let dismiss: DismissAction
    let onShare: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void
    
    @AppStorage("gridColumns") private var gridColumns: Int = 3

    var body: some ToolbarContent {
        if searchManager.isSelectionMode {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { searchManager.exitSelectionMode() }
            }
            ToolbarItem(placement: .principal) {
                Text("\(searchManager.selectedScans.count) Selected").font(.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select All") { searchManager.selectAll() }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button(action: onShare) { Image(systemName: "square.and.arrow.up") }
                .disabled(searchManager.selectedScans.isEmpty)
                Spacer()
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                    Text("Download").fontWeight(.semibold)
                }
                .disabled(searchManager.selectedScans.isEmpty)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .tint(searchManager.selectedScans.isEmpty ? .gray : .red)
                .disabled(searchManager.selectedScans.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    if !searchManager.searchQuery.isEmpty {
                        searchManager.searchQuery = ""
                    } else {
                        dismiss()
                    }
                }) {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if activeTab == .collections {
                        Button(action: { showNewCollectionAlert = true }) {
                            Label("New collection", systemImage: "folder.badge.plus")
                        }
                        Picker(selection: Binding(get: { searchManager.collectionSortOption }, set: { searchManager.collectionSortOption = $0 })) {
                            ForEach(ScanSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        } label: {
                            Label("Sort by", systemImage: "arrow.up.arrow.down")
                        }
                        .pickerStyle(.menu)
                    } else if activeTab == .library {
                        ControlGroup {
                            Toggle(isOn: Binding(get: { gridColumns == 1 }, set: { if $0 { gridColumns = 1 } })) {
                                Label("1x1", systemImage: "rectangle.grid.1x2")
                            }
                            Toggle(isOn: Binding(get: { gridColumns == 2 }, set: { if $0 { gridColumns = 2 } })) {
                                Label("2x2", systemImage: "square.grid.2x2")
                            }
                            Toggle(isOn: Binding(get: { gridColumns == 3 }, set: { if $0 { gridColumns = 3 } })) {
                                Label("3x3", systemImage: "square.grid.3x3")
                            }
                        }
                        Picker(selection: Binding(get: { searchManager.sortOption }, set: { searchManager.sortOption = $0 })) {
                            ForEach(ScanSortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        } label: {
                            Label("Sort by", systemImage: "arrow.up.arrow.down")
                        }
                        .pickerStyle(.menu)
                        Button(action: { searchManager.isSelectionMode = true }) { Label("Select multiple", systemImage: "checkmark.circle") }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold))
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
        }
        
        ToolbarItem(placement: .keyboard) {
            HStack {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
