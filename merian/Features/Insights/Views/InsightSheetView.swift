import SwiftUI
import SwiftData
import SafariServices

// MARK: - Insight Sheet View

/// The master state orchestrator routing biological inference metadata, navigation bounds, and hardware logic cleanly down into the decoupled `InsightLayout` tree.
struct InsightSheetView: View {
    // MARK: - Environment & Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var isPresented: Bool
    
    // MARK: - Interface State
    @State var showCelebration = false
    @State var showBottomBarTools = false
    @State var isCommonNameScrolledPast = false
    
    // MARK: - Alert & Modal Flags
    @State var isFlagIssuePresented = false
    @State var showDeleteConfirmation = false
    @State var showSaveSuccessAlert = false
    @State var showNewCollectionAlert = false
    @State var toastMessage: String? = nil
    @State var newCollectionName = ""
    
    // MARK: - Navigation State
    @State var isSafariPresented = false
    @State var selectedWikiURL: URL?
    
    // MARK: - Hardware Tasks
    @State var isSavingPhotos = false
    
    // MARK: - SwiftData Layer
    @Query(sort: \ScanCollection.createdAt, order: .reverse) var collections: [ScanCollection]
    @State var activeLocalRecord: LocalScanRecord? = nil
    
    // MARK: - Diagnostic Bounds
    var isPoisonous: Bool { inferenceEngine.speciesData?.insightData.isPoisonous ?? false }
    var commonName: String { inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..." }
    var scientificName: String { inferenceEngine.speciesData?.scientificName ?? "Awaiting taxonomy" }
    // MARK: - Root Presentation Logic
    
    /// Establishes the `NavigationStack` environment and binds native iOS dialogue popups globally. Modifiers sit strictly at this node to avoid messy `@Binding` drilling.
    var body: some View {
        NavigationStack {
            mainContent
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar { sheetToolbarContent }
                .toolbarBackground(.visible, for: .bottomBar)
                .toolbarBackground(.ultraThinMaterial, for: .bottomBar)
        }
        // Presentation Logic Hook
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        // Dialogs
        .alert("Delete scan?", isPresented: $showDeleteConfirmation) {
            Button("Delete scan permanently", role: .destructive) { eradicateCurrentScan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this scan? This will permanently remove the photo and data from your device and the global biological archive.")
        }
        .alert("Photos Saved", isPresented: $showSaveSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your photos have been securely saved to your Camera Roll.")
        }
        .alert("New Collection", isPresented: $showNewCollectionAlert) {
            TextField("Collection Name", text: $newCollectionName)
            Button("Cancel", role: .cancel) { }
            Button("Create", action: createNewCollection)
        }
    }
    
}
