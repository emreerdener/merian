import SwiftData
import SwiftUI

struct InsightContentView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(\.modelContext) var modelContext

    @Bindable var viewModel: InsightSheetViewModel
    
    // MARK: - Layout Constants
    private let overlapRadius: CGFloat = 32
    private let imageSize: CGFloat = UIScreen.main.bounds.width
    
    // MARK: - View
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                
                // 1. DYNAMIC STRETCHY CAROUSEL HEADER
                // Embeds firmly inside the native ScrollView to bypass NavigationStack safe area clipping perfectly.
                GeometryReader { proxy in
                    let scrollY = proxy.frame(in: .named("InsightScrollSpace")).minY
                    // MASSIVE FIX: The 'bleedBuffer' forces the image to natively render 50px taller and shifted 50px upward out of viewport.
                    // This creates a physical pixel bridge seamlessly masking `TabView` vertical pan-gesture framework synchronization tearing.
                    let bleedBuffer: CGFloat = 50 
                    
                    let persistentScanId = viewModel.activeLocalRecord?.id ?? inferenceEngine.speciesData?.scanId
                    
                    ImagesCarousel(
                        scanId: persistentScanId,
                        refUrls: viewModel.refUrls,
                        validHistoricImagePaths: viewModel.validHistoricImagePaths,
                        hasLive: viewModel.hasLive,
                        liveCount: viewModel.liveCount,
                        totalImages: viewModel.totalImages
                    )
                        .frame(width: imageSize, height: scrollY > 0 ? imageSize + scrollY + bleedBuffer : imageSize + bleedBuffer)
                        .offset(y: scrollY > 0 ? -(scrollY + bleedBuffer) : -bleedBuffer)
                        .ignoresSafeArea(.all, edges: .top) // CRUESCIAL: Kills the 16pt sheet native dragging padding!
                }
                .frame(height: imageSize)
                .ignoresSafeArea(.all, edges: .top) // Ensure the entire geometry wrapper bypasses top safe area
                .zIndex(0)
                
                // 2. OVERLAPPING BOTTOM SHEET CONTENT
                contentCards
                    .padding(.top, overlapRadius)
                    .frame(maxWidth: .infinity)
                    .background(contentSheetBackground)
                    .offset(y: -overlapRadius)
                    .padding(.bottom, -overlapRadius)
                    .zIndex(1)
            }
            .frame(width: imageSize) // CLAMP: Physically guarantees the content bounds can never expand left/right even if child views attempt to breach safe area X bounds.
        }
        .coordinateSpace(name: "InsightScrollSpace")
        // Forces native underlap of the translucent NavigationBar completely!
        .ignoresSafeArea(.container, edges: .top)
        .contentMargins(.top, 0, for: .scrollContent) // CRITICAL: Eradicates hidden iOS 17 interior scroll canvas offsets!
        .textSelection(.enabled)
        
        // Data Mapping Override
        .onAppear {
            viewModel.inferenceEngine = inferenceEngine
        }
        
        // Modal Routings
        .sheet(isPresented: $viewModel.isSafariPresented) {
            if let safeUrl = viewModel.selectedWikiURL {
                SafariView(url: safeUrl)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $viewModel.isFlagIssuePresented) {
            if let scanId = inferenceEngine.speciesData?.scanId {
                ReportInsightView(scanId: scanId) {
                    withAnimation { viewModel.toastMessage = "Report submitted. Thanks!" }
                }
            }
        }
        .sheet(isPresented: $viewModel.isIdentificationFlagPresented) {
            if let scanId = inferenceEngine.speciesData?.scanId {
                FlagIdentificationModal(scanId: scanId) {
                    withAnimation { viewModel.toastMessage = "Report submitted. Thanks!" }
                }
                .presentationDetents([.height(400)])
            }
        }
        .sheet(isPresented: $viewModel.isCandidateSwipePresented) {
            if let speciesData = inferenceEngine.speciesData {
                CandidateSwipeModal(
                    isPresented: $viewModel.isCandidateSwipePresented,
                    candidates: speciesData.candidates ?? [],
                    aiScientificName: speciesData.scientificName,
                    confirmButtonTitle: {
                        let cName = speciesData.commonName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let aiSciName = speciesData.scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let isCommonNameValid = !cName.isEmpty && cName.lowercased() != "unknown subject"
                        let isScientificNameValid = !aiSciName.isEmpty && aiSciName.lowercased() != "unknown subject"
                        if isCommonNameValid { return "Confirm \(cName.capitalized)" }
                        if isScientificNameValid { return "Confirm \(aiSciName)" }
                        return "Confirm initial match"
                    }(),
                    onConfirmOriginal: { Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) } },
                    onFlagIssue: { viewModel.isIdentificationFlagPresented = true },
                    onRefineScan: {
                        guard let scanIdStr = speciesData.scanId else { return }
                        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanIdStr })
                        if let record = try? modelContext.fetch(descriptor).first {
                            HapticManager.shared.triggerSelectionPulse()
                            AppEventPublisher.shared.send(.triggerRefinement(record: record))
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Subcomponents
private extension InsightContentView {
    
    /// The conditional routing layout parsing Insight structural parameters dynamically.
    @ViewBuilder
    var contentCards: some View {
        VStack(alignment: .leading, spacing: 16) {

            ZStack(alignment: .top) {
                if inferenceEngine.isProcessing {
                    AnalyzingContentView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color(uiColor: .systemBackground))
                        .transition(.opacity)
                } else if let speciesData = inferenceEngine.speciesData,
                   !speciesData.isBiological || speciesData.commonName.lowercased() == "not applicable" {
                    
                    NonBiologicalView(
                        species: speciesData,
                        commonName: speciesData.commonName.capitalized,
                        timestamp: viewModel.activeLocalRecord?.captureDate ?? viewModel.activeLocalRecord?.timestamp
                    )
                    .transition(.opacity)
                } else {
                    
                    BiologicalView(
                        viewModel: viewModel,
                        isSafariPresented: $viewModel.isSafariPresented, 
                        selectedWikiURL: $viewModel.selectedWikiURL,
                        timestamp: viewModel.activeLocalRecord?.captureDate ?? viewModel.activeLocalRecord?.timestamp
                    )
                    .transition(.opacity)
                }
            }
            
            Spacer(minLength: 40)
        }
        .animation(.easeInOut(duration: 0.35), value: inferenceEngine.isProcessing)
    }

    /// The rounded white background encapsulating the structural content cards smoothly.
    @ViewBuilder
    var contentSheetBackground: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: overlapRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: overlapRadius
        )
        .fill(Color(uiColor: .systemBackground))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
        // OVERSCROLL PROTECTION: Physically expands the drawn background infinitely downwards without affecting structural layout height, sealing any visual gaps when the user pulls up past the bottom natively!
        .padding(.bottom, -1000)
    }
}
