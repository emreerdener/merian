import SwiftUI
import SwiftData
import SafariServices



// MARK: - Insight Sheet View
struct InsightSheetView: View {
    @EnvironmentObject var inferenceEngine: InferenceEngine
    @Environment(\.dismiss) var dismiss

    @Binding var isPresented: Bool
    
    @EnvironmentObject var hardwareOrchestrator: HardwareOrchestrator
    
    @State private var isSafariPresented = false
    @State private var selectedWikiURL: URL?
    @State private var isFlagIssuePresented = false
    @State private var showCelebration = false
    @State private var showCollectionPicker = false
    @State private var showDeleteConfirmation = false
    @State private var isSavingPhotos = false
    @State private var showSaveSuccessAlert = false
    @Environment(\.modelContext) private var modelContext
    
    // Safety Bounds
    private var isPoisonous: Bool {
        inferenceEngine.speciesData?.insightData.isPoisonous ?? false
    }
    
    private var commonName: String {
        inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..."
    }
    
    private var scientificName: String {
        inferenceEngine.speciesData?.scientificName ?? "Awaiting taxonomy"
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // 0. The Image Carousel
                        InsightCarouselView()
                        
                        // 1. The Toxicity Banner (Safety Critical)
                        InsightToxicityBanner()
                            .padding(.horizontal)
                        
                        // 2. Core Taxonomy Block
                        InsightTaxonomyHeader()
                        
                        // 3. Ecological Descriptive Insight
                        InsightDescriptionSection(isSafariPresented: $isSafariPresented, selectedWikiURL: $selectedWikiURL)
                        
                        // 3.5 Taxonomy Tree
                        InsightTaxonomyTree()
                    
                    // 4. Fallback Validation Block
                    if let score = inferenceEngine.speciesData?.confidenceScore, score < 0.85, let diagnosticData = inferenceEngine.speciesData?.diagnosticComparison {
                        DiagnosticComparisonView(diagnosticData: diagnosticData)
                            .padding(.horizontal)
                            .padding(.top, 16)
                    }
                    
                    // 5. Flag Issue Action
                    Divider()
                        .padding(.vertical, 8)
                    
                    Button(action: {
                        isFlagIssuePresented = true
                    }) {
                        HStack {
                            Image(systemName: "flag.fill")
                            Text("Report incorrect ID")
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    }
                    
                    Spacer(minLength: 40)
                    }
                    .padding(.top, 24)
                }
                .textSelection(.enabled)
                .sheet(isPresented: $isSafariPresented) {
                    if let safeUrl = selectedWikiURL {
                        SafariView(url: safeUrl)
                            .ignoresSafeArea()
                    }
                }
                .sheet(isPresented: $isFlagIssuePresented) {
                    if let scanId = inferenceEngine.speciesData?.scanId {
                        FlagIssueView(scanId: scanId)
                    }
                }
                .navigationTitle(commonName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: {
                            dismiss()
                        }) {
                           Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.secondary)
                        }
                    }
                    
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let shareUrl = URL(string: "https://merian.app") {
                                ShareLink(
                                    item: shareUrl,
                                    subject: Text("I found a \(commonName)!"),
                                    message: Text("Check out this \(commonName) (\(scientificName)) I discovered using Merian!")
                                ) {
                                    Label("Share discovery", systemImage: "square.and.arrow.up")
                                }
                            }
                            
                            Button(action: { showCollectionPicker = true }) {
                                Label("Add to collection", systemImage: "folder.badge.plus")
                            }
                            
                            Button(action: { saveUserPhotos() }) {
                                Label("Save my photos", systemImage: "arrow.down.circle")
                            }
                            .disabled(isSavingPhotos)
                            
                            Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                                Label("Delete scan", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
                .sheet(isPresented: $showCollectionPicker) {
                    if let scanId = inferenceEngine.speciesData?.scanId {
                        SaveToCollectionSheetView(scanId: scanId)
                    }
                }
                .confirmationDialog(
                    "Delete scan",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete scan permanently", role: .destructive) {
                        eradicateCurrentScan()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Are you sure you want to delete this scan? This will permanently remove the photo and data from your device and the global biological archive.")
                }
                .alert("Photos Saved", isPresented: $showSaveSuccessAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Your photos have been securely saved to your Camera Roll.")
                }
                
                if showCelebration {
                    NewDiscoveryCelebrationView(
                        commonName: commonName,
                        onDismiss: {
                            withAnimation(.easeOut(duration: 0.5)) {
                                showCelebration = false
                            }
                        }
                    )
                    .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.95)))
                    .zIndex(100)
                }
            } // NavigationStack
        } // ZStack
        // Force solid background fill above the underlying camera UI
        .presentationBackground(Color(uiColor: .systemBackground))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        // Ensure VoiceOver properly sequences the primary components autonomously upon render
        .onAppear {
            if UIAccessibility.isVoiceOverRunning {
                let announcement = isPoisonous ? "\(commonName). Warning: This subject is poisonous." : commonName
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
            if inferenceEngine.speciesData?.isNewDiscovery == true {
                showCelebration = true
            }
        }
        .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
            if !isStillProcessing {
                if inferenceEngine.speciesData?.isNewDiscovery != true {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        }
    }
    
    private func saveUserPhotos() {
        guard !isSavingPhotos else { return }
        isSavingPhotos = true
        
        Task {
            var photosSaved = 0
            
            // 1. Live photo payload
            if let liveData = inferenceEngine.activeImageData {
                let success = await PhotoLibraryManager.shared.saveImageManual(imageData: liveData)
                if success { photosSaved += 1 }
            }
            
            // 2. Local historical images securely cached on disk
            for path in inferenceEngine.validHistoricImagePaths {
                let url = URL(fileURLWithPath: path)
                if let data = try? Data(contentsOf: url) {
                    let success = await PhotoLibraryManager.shared.saveImageManual(imageData: data)
                    if success { photosSaved += 1 }
                }
            }
            
            // 3. Remote user uploads explicitly filtering out GBIF/Wiki bounds
            let refUrls: [String] = inferenceEngine.speciesData?.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
            for urlStr in refUrls {
                if urlStr.contains("merian.app"), let url = URL(string: urlStr) {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let success = await PhotoLibraryManager.shared.saveImageManual(imageData: data)
                        if success { photosSaved += 1 }
                    } catch {
                        print("Failed to map R2 cloud payload for UI download: \(error)")
                    }
                }
            }
            
            await MainActor.run {
                isSavingPhotos = false
                if photosSaved > 0 {
                    HapticManager.shared.triggerSuccessPulse()
                    showSaveSuccessAlert = true
                }
            }
        }
    }
    
    private func eradicateCurrentScan() {
        guard let targetId = inferenceEngine.speciesData?.scanId else { return }
        
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == targetId })
        let records = (try? modelContext.fetch(descriptor)) ?? []
        
        if let record = records.first {
            HapticManager.shared.triggerErrorThump()
            ScanRepository.shared.eradicateScan(record: record, modelContext: modelContext)
            dismiss()
        }
    }
}
