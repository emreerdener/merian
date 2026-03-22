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
    @State private var toastMessage: String? = nil
    @State private var isDownloading = false
    
    // MARK: - Static Bounds
    private let maxBatchSelectionLimit = 20
    private let filterCategories = ["All", "Plants", "Fungi", "Insects", "Birds", "Mammals", "Reptiles", "Other"]
    
    // MARK: - Core View Builder
    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
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
                
                CollectionsView(
                    searchQuery: searchManager.searchQuery,
                    isSearchFocused: isSearchFocused,
                    collections: collections.sorted { c1, c2 in
                        switch searchManager.collectionSortOption {
                        case .newest: return c1.createdAt > c2.createdAt
                        case .oldest: return c1.createdAt < c2.createdAt
                        case .aToZ: return c1.name.localizedCaseInsensitiveCompare(c2.name) == .orderedAscending
                        case .zToA: return c1.name.localizedCaseInsensitiveCompare(c2.name) == .orderedDescending
                        }
                    },
                    isInsightSheetOpen: $isInsightSheetOpen
                )
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(get: { activeTab }, set: { if let val = $0 { activeTab = val } }))
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: activeTab) { _, newValue in
                if !searchManager.searchQuery.isEmpty {
                    searchManager.searchQuery = ""
                    isSearchFocused = false
                    if newValue == .library {
                        searchManager.performSearch(query: "")
                    }
                }
            }
            
            // MARK: - View Modifiers
            .sheet(item: $selectedScanForInsight) { scan in
                InsightSheetView(isPresented: Binding(
                    get: { selectedScanForInsight != nil },
                    set: { if !$0 { selectedScanForInsight = nil } }
                ))
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchManager.searchQuery, isPresented: $isSearchFocused, placement: .toolbar, prompt: activeTab == .library ? "Search keywords, habitats, colors..." : "Search collections...")
            //.searchDictationBehavior(.inline(activation: .onSelect))
            .onChange(of: searchManager.searchQuery) { _, newValue in
                if activeTab == .library {
                    searchManager.performSearch(query: newValue)
                }
            }
            .scansToolbar(
                searchManager: searchManager,
                activeTab: $activeTab,
                showNewCollectionAlert: $showNewCollectionAlert,
                dismiss: dismiss,
                onShare: {
                    let selectedItems = searchManager.getSelectedLocalRecords()
                    InsightMediaExportManager.shared.batchShareDiscovery(records: selectedItems) { items in
                        ShareSheetUtility.present(items: items)
                    }
                },
                onDownload: {
                    let selectedItems = searchManager.getSelectedLocalRecords()
                    
                    withAnimation { isDownloading = true }
                    InsightMediaExportManager.shared.batchSaveUserPhotos(records: selectedItems) { savedCount in
                        withAnimation { isDownloading = false }
                        searchManager.exitSelectionMode()
                        HapticManager.shared.triggerSuccessPulse()
                        showToast(message: "Saved \(savedCount) photo\(savedCount == 1 ? "" : "s") to your Camera Roll")
                    }
                },
                onDelete: {
                    showBatchDeleteConfirmation = true
                }
            )
            .newCollectionAlert(
                isPresented: $showNewCollectionAlert,
                newCollectionName: $newCollectionName,
                modelContext: modelContext
            )
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
        .alert(
            "Delete \(searchManager.selectedScans.count) selected scans?",
            isPresented: $showBatchDeleteConfirmation
        ) {
            Button("Delete permanently", role: .destructive) {
                let itemsToDelete = searchManager.getSelectedLocalRecords()
                for item in itemsToDelete {
                    AppDIContainer.shared.scanRepository.eradicateScan(record: item, modelContext: modelContext)
                }
                searchManager.exitSelectionMode()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove these discoveries and all associated visuals from your history.")
        }
        .alert(
            "Selection limit reached",
            isPresented: $showSelectionLimitAlert
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can only select up to 20 items at a time to ensure optimal system performance during export and deletion workloads.")
        }
        .overlay(toastOverlay)
        .overlay {
            if isDownloading {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView("Downloading...")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    
    // MARK: - Action Handlers & Logic Blocks
    
// Removed presentShareSheet as this logic was extracted into ShareSheetUtility
    
    private func showToast(message: String) {
        withAnimation(.spring()) { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut) { if toastMessage == message { toastMessage = nil } }
        }
    }
    
    // MARK: - Declarative Subcomponents
    
    @ViewBuilder
    var toastOverlay: some View {
        if let message = toastMessage {
            VStack {
                Spacer()
                Text(message)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .colorScheme(.dark)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }
}
