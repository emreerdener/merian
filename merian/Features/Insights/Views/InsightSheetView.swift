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
                        // 0. The universally shared Image Carousel bounds natively
                        InsightCarouselView()
                        
                        if let speciesData = inferenceEngine.speciesData, !speciesData.isBiological || speciesData.commonName.lowercased() == "not applicable" {
                            // Specialized Non-Biological UI: Strip out taxonomy, safety loops, and regional bounds entirely!
                            VStack(alignment: .leading, spacing: 16) {
                                Text(commonName)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                Text(speciesData.insightData.description)
                                    .font(.body)
                                    .foregroundColor(.primary.opacity(0.8))
                                    .lineSpacing(6)
                            }
                            .padding(.horizontal)
                            
                        } else {
                            // Core Biological Taxonomy Pipeline
                            InsightTaxonomyHeader()
                            
                            InsightDescriptionSection(isSafariPresented: $isSafariPresented, selectedWikiURL: $selectedWikiURL)
                            
                            InsightToxicityBanner()
                                .padding(.horizontal)
                                
                            InsightTaxonomyTree()
                            
                            if let score = inferenceEngine.speciesData?.confidenceScore, score < 0.85, let diagnosticData = inferenceEngine.speciesData?.diagnosticComparison {
                                DiagnosticComparisonView(diagnosticData: diagnosticData)
                                    .padding(.horizontal)
                                    .padding(.top, 16)
                            }
                        }
                        
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
                            Button(action: { shareDiscovery() }) {
                                Label("Share discovery", systemImage: "square.and.arrow.up")
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
                    VStack {
                        NewDiscoveryCelebrationView(
                            commonName: commonName,
                            onDismiss: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    showCelebration = false
                                }
                            }
                        )
                        .padding(.top, 16)
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
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
                let url = URL.documentsDirectory.appendingPathComponent(path)
                if let data = try? Data(contentsOf: url) {
                    let success = await PhotoLibraryManager.shared.saveImageManual(imageData: data)
                    if success { photosSaved += 1 }
                }
            }
            
            // 3. Remote user uploads explicitly filtering out GBIF/Wiki bounds
            let refUrls: [String] = inferenceEngine.speciesData?.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
            for urlStr in refUrls {
                let cleanStr = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanStr.contains("merian.app"), let url = URL(string: cleanStr) {
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
    
    // MARK: - Native Sharing Pipeline
    private func shareDiscovery() {
        var items: [Any] = [
            "Check out this \(commonName) (\(scientificName)) I discovered using Merian! \nhttps://merian.app"
        ]
        
        // Attempt to explicitly attach the physical photograph natively into the iOS Share Sheet payload
        if let liveData = inferenceEngine.activeImageData, let image = UIImage(data: liveData) {
            items.insert(image, at: 0)
            presentShareSheet(items: items)
            
        } else if let validPath = inferenceEngine.validHistoricImagePaths.first, 
                  let data = try? Data(contentsOf: URL.documentsDirectory.appendingPathComponent(validPath)),
                  let image = UIImage(data: data) {
            items.insert(image, at: 0)
            presentShareSheet(items: items)
            
        } else {
            // Unpack remote Cloudflare R2 string natively dropping any foreign wikipedia resources
            let refUrls: [String] = inferenceEngine.speciesData?.referenceImageUrl?.components(separatedBy: ",").filter { !$0.isEmpty } ?? []
            if let safeCloudUrl = refUrls.first(where: { $0.contains("merian.app") })?.trimmingCharacters(in: .whitespacesAndNewlines), let url = URL(string: safeCloudUrl) {
                // Execute a decoupled fast background fetch for the remote image to prevent blocking the UI thread abruptly
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) {
                        items.insert(image, at: 0)
                    }
                    await MainActor.run { presentShareSheet(items: items) }
                }
            } else {
                presentShareSheet(items: items)
            }
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
