import SwiftUI
import SafariServices

// MARK: - Layout Subcomponents
extension InsightSheetView {
    
    // MARK: - Decoupled UI Sub-Components
    
    /// The declarative pipeline routing layout overlaps, triggering haptics on `.onChange`, firing gamification routines mathematically, and capturing scroll coordinates efficiently via `GeometryReader`.
    @ViewBuilder
    var mainContent: some View {
        Group {
            ZStack(alignment: .top) {
                scrollableCanvas
                if let message = toastMessage {
                    Toast(message: message)
                }
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
            evaluateScrollOffset(minY: minY)
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
                } catch { } // absorb CancellationError elegantly
            }
        }
    }
    
    // MARK: - Toolbar Logic
    
    /// Fully offloads rendering toolbar icons while piping the master orchestrator functions (save, trash, share) neatly as `action:` closures downstream. 
    @ToolbarContentBuilder
    var sheetToolbarContent: some ToolbarContent {
        TopToolbar(
            commonName: commonName,
            confidenceScore: inferenceEngine.speciesData?.confidenceScore,
            isCommonNameScrolledPast: isCommonNameScrolledPast,
            isFlagIssuePresented: $isFlagIssuePresented,
            isSavingPhotos: $isSavingPhotos,
            showDeleteConfirmation: $showDeleteConfirmation,
            onSavePhotos: saveUserPhotos
        )
        
        InsightBottomToolbar(
            showBottomBarTools: showBottomBarTools,
            collections: collections,
            activeLocalRecord: activeLocalRecord,
            toggleScanInCollection: { collection in toggleScanInCollection(collection) },
            showNewCollectionAlert: $showNewCollectionAlert,
            shareDiscovery: shareDiscovery
        )
    }
    
    // MARK: - Core Structural Canvas
    
    /// The master scrolling viewport mounting the ImagesCarousel at `index(0)` permanently fixed behind the dynamically padded `.systemBackground` layout bounds at `index(1)`. This enforces physical UI overlapping on edge-swiping. 
    @ViewBuilder
    var scrollableCanvas: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ImagesCarousel()
                    .aspectRatio(1.0, contentMode: .fill)
                    .zIndex(0)
                
                VStack(alignment: .leading, spacing: 16) {
                    if let speciesData = inferenceEngine.speciesData, !speciesData.isBiological || speciesData.commonName.lowercased() == "not applicable" {
                        nonBiologicalContent(for: speciesData)
                    } else {
                        biologicalContent
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.top, 32)
                .frame(maxWidth: .infinity)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 32,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 32
                    )
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                )
                .padding(.top, -32)
                .zIndex(1)
            }
            .frame(width: UIScreen.main.bounds.width)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: CommonNameScrollOffsetKey.self,
                        value: geo.frame(in: .scrollView).minY
                    )
                },
                alignment: .top
            )
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .textSelection(.enabled)
        .sheet(isPresented: $isSafariPresented) {
            if let safeUrl = selectedWikiURL {
                SafariView(url: safeUrl)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $isFlagIssuePresented) {
            if let scanId = inferenceEngine.speciesData?.scanId {
                ReportInsightView(scanId: scanId)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
    
    // MARK: - Fallback Topography States
    
    /// Dynamically routes to the purely typography-driven view array. It entirely strips Taxonomy/Toxicity badges for safe, inanimate object scanning outputs.
    @ViewBuilder
    func nonBiologicalContent(for species: SpeciesData) -> some View {
        NonBiologicalView(species: species, commonName: commonName)
    }
    
    // MARK: - Standard Biological Pipeline
    
    /// The master root injector mapping the full Taxonomy, Wiki Rationale array, and complex environmental geometry cascades recursively down the SwiftUI view engine bounds.
    @ViewBuilder
    var biologicalContent: some View {
        BiologicalView(
            isSafariPresented: $isSafariPresented, 
            selectedWikiURL: $selectedWikiURL,
            timestamp: activeLocalRecord?.timestamp
        )
    }
    
    // MARK: - Decoupled Gamification Overlays
    
    /// Orchestrates native New Discovery toast pills purely logically detached dynamically above the main Scroll bounds
    @ViewBuilder
    var celebrationOverlay: some View {
        CelebrationBanner(
            commonName: commonName,
            showCelebration: $showCelebration
        )
    }
    

}
