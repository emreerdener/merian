import SwiftUI
import SwiftData
import SafariServices

// MARK: - Insight Sheet View
struct InsightSheetView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var isPresented: Bool
    
    // MARK: Component State
    @State var isSafariPresented = false
    @State var selectedWikiURL: URL?
    @State var isFlagIssuePresented = false
    @State var showCelebration = false
    @Query(sort: \ScanCollection.createdAt, order: .reverse) var collections: [ScanCollection]
    @State var activeLocalRecord: LocalScanRecord? = nil
    @State var showNewCollectionAlert = false
    @State var newCollectionName = ""
    
    @State var showDeleteConfirmation = false
    @State var isSavingPhotos = false
    @State var showSaveSuccessAlert = false
    @State var toastMessage: String? = nil
    @State private var showBottomBarTools = false
    @State private var isCommonNameScrolledPast = false
    
    // MARK: Diagnostic Bounds
    var isPoisonous: Bool { inferenceEngine.speciesData?.insightData.isPoisonous ?? false }
    var commonName: String { inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..." }
    var scientificName: String { inferenceEngine.speciesData?.scientificName ?? "Awaiting taxonomy" }
    
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
    
    // MARK: - Decoupled UI Sub-Components
    
    @ViewBuilder
    var mainContent: some View {
        Group {
            ZStack(alignment: .top) {
                scrollableCanvas
                toastOverlay
                celebrationOverlay
            }
            .ignoresSafeArea(edges: .top)
        }
        .onAppear { 
            evaluateVoiceOverAndCelebration()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeIn(duration: 0.2)) {
                    showBottomBarTools = true
                }
            }
        }
        .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
            evaluateProcessingCompletion(isStillProcessing: isStillProcessing)
        }
        .onPreferenceChange(CommonNameScrollOffsetKey.self) { minY in
            // Fallback safely dropping `.infinity` out of the matrix
            guard minY != .infinity else { return }
            
            // The image is exactly 1.0 aspect ratio (screen width).
            // Scientific + Common Name blocks aggressively occupy approx ~80pts horizontally underneath.
            // Ergo, when the global scroll minY dives past the negative offset threshold -> toggle headers!
            let threshold = -(UIScreen.main.bounds.width + 80)
            let isPast = minY < threshold
            
            if isCommonNameScrolledPast != isPast {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCommonNameScrolledPast = isPast
                    }
                }
            }
        }
        .task(id: inferenceEngine.speciesData?.scanId) {
            if let scanId = inferenceEngine.speciesData?.scanId {
                fetchLocalRecord(for: scanId)
            }
        }
        .task(id: toastMessage) {
            if toastMessage != nil {
                do {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toastMessage = nil
                    }
                } catch {
                    // Elegantly absorb the CancellationError natively.
                    // This explicitly ensures the task properly aborts upon overlap without 
                    // inadvertently firing the internal `withAnimation` block (which `try?` fatally causes).
                }
            }
        }
    }
    
    private func fetchLocalRecord(for scanId: String) {
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
        activeLocalRecord = (try? modelContext.fetch(descriptor))?.first
    }
    
    
    
    @ToolbarContentBuilder
    var sheetToolbarContent: some ToolbarContent {
        InsightSheetHeader(
            commonName: commonName,
            confidenceScore: inferenceEngine.speciesData?.confidenceScore,
            isCommonNameScrolledPast: isCommonNameScrolledPast,
            isFlagIssuePresented: $isFlagIssuePresented,
            isSavingPhotos: $isSavingPhotos,
            showDeleteConfirmation: $showDeleteConfirmation,
            onSavePhotos: saveUserPhotos
        )
        
        if showBottomBarTools, let speciesData = inferenceEngine.speciesData, speciesData.isBiological && speciesData.commonName.lowercased() != "not applicable" {
            ToolbarItemGroup(placement: .bottomBar) {
                addCollectionButton
                Spacer()
                shareActionButton
            }
        }
    }
    
    // MARK: - Toast Overlay
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
