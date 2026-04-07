import SwiftData
import SwiftUI

enum ScansTab {
    case library
    case collections
}

struct ScansSheetView: View {
    // MARK: - App State Engines
    @State private var searchManager = ScansManager()

    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var rawRecords: [LocalScanRecord]
    private var allRecords: [LocalScanRecord] {
        rawRecords.filter { $0.isBiological == true && $0.commonName != "Unknown Subject" }
    }
    @Query(filter: #Predicate<ScanCollection> { !$0.isDeleted }, sort: \ScanCollection.createdAt, order: .reverse) private var collections: [ScanCollection]

    /// Manually-managed queue list, bypassing `@Query` for live updates while the sheet is open.
    ///
    /// SwiftData's `@Query` in a presented `.sheet` does not reliably re-evaluate when
    /// `ModelContext.save()` fires while the app is backgrounded — the sheet's render cycle
    /// is paused and the save notification may be dropped before the view processes it.
    /// On foreground return the pending overlay would remain stuck until the user closes and
    /// reopens the sheet.
    ///
    /// Driving this array from `OfflineQueueManager.unsyncedItemsCount` (an `@Observable`
    /// property) guarantees delivery: `@Observable` change notifications are queued and
    /// processed on the next active render pass regardless of when the mutation happened.
    @State private var queuedScans: [OfflineQueuedScan] = []

    @Environment(\.modelContext) private var modelContext
    @Environment(OfflineQueueManager.self) private var offlineQueueManager
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(\.dismiss) var dismiss
    @Binding var isInsightSheetOpen: Bool
    
    // MARK: - Navigation Control
    @State private var selectedScanForInsight: LocalScanRecord?
    @State private var activeTab: ScansTab = .library
    
    // MARK: - Component State
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    @State private var newlyCreatedCollection: ScanCollection?
    
    @State private var scanToDelete: LocalScanRecord?
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false
    @State private var showSelectionLimitAlert = false
    @State private var isSearchFocused = false
    
    // MARK: - Static Bounds
    private let filterCategories = ["All", "Plants", "Fungi", "Insects", "Birds", "Mammals", "Reptiles", "Other"]

    /// Mirrors ScansGrid's thumbnailSize formula so the prefetch cache key matches exactly.
    @AppStorage("gridColumns") private var gridColumns: Int = 3
    private var prefetchThumbnailSize: Int {
        let screenWidth = UIScreen.main.bounds.width
        let cellWidth = (screenWidth - CGFloat(2 * (gridColumns - 1))) / CGFloat(gridColumns)
        return Int(cellWidth * UIScreen.main.scale)
    }
    
    // MARK: - Core View Builder
    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    LibraryTabContent(
                        searchManager: searchManager, filterCategories: filterCategories,
                        queuedScans: queuedScans,
                        isSearchFocused: $isSearchFocused, selectedScanForInsight: $selectedScanForInsight,
                        showSelectionLimitAlert: $showSelectionLimitAlert, scanToDelete: $scanToDelete,
                        showDeleteConfirmation: $showDeleteConfirmation
                    )
                    CollectionsTabContent(
                        searchManager: searchManager, isSearchFocused: isSearchFocused,
                        sortedCollections: searchManager.sortedCollections, isInsightSheetOpen: $isInsightSheetOpen,
                        showNewCollectionAlert: $showNewCollectionAlert,
                        newlyCreatedCollection: $newlyCreatedCollection
                    )
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(get: { activeTab }, set: { if let val = $0 { activeTab = val } }))
            .modifier(ScansSheetModifiers(
                searchManager: searchManager, activeTab: $activeTab, isSearchFocused: $isSearchFocused,
                selectedScanForInsight: $selectedScanForInsight, showNewCollectionAlert: $showNewCollectionAlert,
                newCollectionName: $newCollectionName, scanToDelete: $scanToDelete,
                showDeleteConfirmation: $showDeleteConfirmation, showBatchDeleteConfirmation: $showBatchDeleteConfirmation,
                showSelectionLimitAlert: $showSelectionLimitAlert, toastMessage: $searchManager.toastMessage,
                isDownloading: $searchManager.isDownloading, dismiss: dismiss, modelContext: modelContext,
                onBatchDelete: handleBatchDelete, onCollectionCreated: { newlyCreatedCollection = $0 }
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
            syncStateLocally()
            refreshQueuedScans()
            prefetchLeadingThumbnails(from: searchManager.allScans)
        }
        .onChange(of: rawRecords) { _, _ in
            syncStateLocally()
        }
        .onChange(of: collections) { _, _ in
            searchManager.collections = collections
            searchManager.performSearch(query: searchManager.searchQuery)
        }
        .onChange(of: offlineQueueManager.unsyncedItemsCount) { _, _ in
            // `@Observable` change notifications are queued and delivered on the next active
            // render pass — reliable even when the app was backgrounded when the scan
            // completed and the @Query save notification was never processed by the sheet.
            refreshQueuedScans()
            syncStateFromStore()
        }
    }
    
    // MARK: - Data Refresh

    /// Synchronizes native SwiftData reactive arrays with the offline search manager engine.
    private func syncStateLocally() {
        searchManager.allScans = allRecords
        searchManager.collections = collections
        searchManager.performSearch(query: searchManager.searchQuery)
    }

    /// Fires 18 concurrent image loads before LazyVGrid renders, filling the first visible
    /// screen (6 rows × 3 columns on the largest supported iPhone) with no gray placeholders.
    private func prefetchLeadingThumbnails(from records: [LocalScanRecord]) {
        let slice = records.prefix(18).map {
            (imagePath: $0.localImagePath, fallbackUrl: $0.referenceImageUrl)
        }
        LocalImageLoader.shared.prefetch(records: Array(slice), maxDimension: prefetchThumbnailSize)
    }

    /// Fetches the current `OfflineQueuedScan` list directly from the model context.
    ///
    /// Called on `onAppear` and whenever `offlineQueueManager.unsyncedItemsCount` changes.
    /// By fetching directly rather than relying on `@Query` auto-refresh, this bypasses the
    /// SwiftData sheet `@Query` notification drop that occurs when saves happen while the
    /// app is backgrounded.
    private func refreshQueuedScans() {
        let nonFailedMax = ScanQueueState.failed.rawValue
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate<OfflineQueuedScan> { $0.scanStateRaw < nonFailedMax },
            sortBy: [SortDescriptor(\OfflineQueuedScan.timestamp, order: .reverse)]
        )
        queuedScans = (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Forces `searchManager` to reflect the latest `LocalScanRecord` state by fetching
    /// directly from the model context, bypassing any stale `@Query rawRecords` cache.
    ///
    /// Called alongside `refreshQueuedScans()` when `unsyncedItemsCount` changes so the
    /// completed scan tile appears at the same time the pending overlay disappears.
    private func syncStateFromStore() {
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate<LocalScanRecord> { $0.isBiological == true && $0.commonName != "Unknown Subject" },
            sortBy: [SortDescriptor(\LocalScanRecord.timestamp, order: .reverse)]
        )
        searchManager.allScans = (try? modelContext.fetch(descriptor)) ?? []
        searchManager.collections = collections
        searchManager.performSearch(query: searchManager.searchQuery)
    }

    // MARK: - Action Handlers

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
    let queuedScans: [OfflineQueuedScan]
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
            queuedScans: queuedScans,
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
    @Binding var showNewCollectionAlert: Bool
    @Binding var newlyCreatedCollection: ScanCollection?

    var body: some View {
        CollectionsView(
            searchQuery: searchManager.searchQuery,
            isSearchFocused: isSearchFocused,
            collections: sortedCollections,
            isInsightSheetOpen: $isInsightSheetOpen,
            showNewCollectionAlert: $showNewCollectionAlert,
            newlyCreatedCollection: $newlyCreatedCollection
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
