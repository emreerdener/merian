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
    
    @State private var isSelectionMode = false
    @State private var selectedScans: Set<String> = []
    
    @State private var scanToDelete: LocalScanRecord? = nil
    @State private var showDeleteConfirmation = false
    @State private var showBatchDeleteConfirmation = false
    @State private var showSelectionLimitAlert = false
    @State private var isSearchFocused = false
    
// Struct bounds maintained safely
    
    private let maxBatchSelectionLimit = 20
    private let filterCategories = ["All", "Plants", "Fungi", "Insects", "Birds", "Mammals", "Reptiles"]
    
    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                ScansLibraryGridView(
                    searchManager: searchManager,
                    filterCategories: filterCategories,
                    isSearchFocused: isSearchFocused,
                    isSelectionMode: isSelectionMode,
                    isSelected: { scan in selectedScans.contains(scan.id) },
                    onSelect: { scan in
                        if isSelectionMode {
                            if selectedScans.contains(scan.id) {
                                selectedScans.remove(scan.id)
                            } else {
                                if selectedScans.count >= maxBatchSelectionLimit {
                                    HapticManager.shared.triggerErrorThump()
                                    showSelectionLimitAlert = true
                                } else {
                                    selectedScans.insert(scan.id)
                                }
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
                isSelectionMode: $isSelectionMode,
                selectedScans: $selectedScans,
                dismiss: dismiss,
                onShare: {
                    let selectedItems = searchManager.filteredScans.filter { selectedScans.contains($0.id) }
                    InsightMediaExportManager.shared.batchShareDiscovery(records: selectedItems) { items in
                        presentShareSheet(items: items)
                    }
                },
                onDownload: {
                    let selectedItems = searchManager.filteredScans.filter { selectedScans.contains($0.id) }
                    InsightMediaExportManager.shared.batchSaveUserPhotos(records: selectedItems) { savedCount in
                        isSelectionMode = false
                        selectedScans.removeAll()
                        HapticManager.shared.triggerSuccessPulse()
                    }
                },
                onDelete: {
                    showBatchDeleteConfirmation = true
                }
            )
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
        .alert(
            "Delete \(selectedScans.count) selected scans?",
            isPresented: $showBatchDeleteConfirmation
        ) {
            Button("Delete permanently", role: .destructive) {
                let itemsToDelete = searchManager.filteredScans.filter { selectedScans.contains($0.id) }
                for item in itemsToDelete {
                    AppDIContainer.shared.scanRepository.eradicateScan(record: item, modelContext: modelContext)
                }
                selectedScans.removeAll()
                isSelectionMode = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove these discoveries and all associated visuals from your history.")
        }
        .alert(
            "Selection Limit Reached",
            isPresented: $showSelectionLimitAlert
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You can only select up to 20 items at a time to ensure optimal system performance during export and deletion workloads.")
        }
    }
    
    private func presentShareSheet(items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootVC = window.rootViewController else { return }
        
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Traverse safely up the stack to avoid overlapping presentation bounds
        var topController = rootVC
        while let presented = topController.presentedViewController {
            topController = presented
        }
        
        // Gracefully support iPad rendering anchors cleanly
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topController.view
            popover.sourceRect = CGRect(x: topController.view.bounds.midX, y: topController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        topController.present(activityVC, animated: true)
    }
}
