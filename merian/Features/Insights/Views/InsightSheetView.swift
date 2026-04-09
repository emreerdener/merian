import SwiftData
import SwiftUI

/// The master state orchestrator routing biological inference metadata and hardware logic 
/// safely down into the decoupled visual tree via the `InsightSheetViewModel`.
struct InsightSheetView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var isPresented: Bool
    
    // MARK: - State
    @State private var viewModel = InsightSheetViewModel()
    
    // MARK: - Data Layer
    @Query(sort: \ScanCollection.createdAt, order: .reverse) var collections: [ScanCollection]
    
    // MARK: - View
    var body: some View {
        NavigationStack {
            mainContentStack
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar { sheetToolbar }
                .toolbarBackground(.visible, for: .bottomBar)
                .toolbarBackground(.ultraThinMaterial, for: .bottomBar)
                
                // MARK: Lifecycle Bindings
                .onAppear {
                    viewModel.evaluateVoiceOverAndCelebration(inferenceEngine: inferenceEngine)
                }
                .task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation(.easeIn(duration: 0.2)) {
                        viewModel.showBottomBarTools = true
                    }
                }
                .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
                    viewModel.evaluateProcessingCompletion(isStillProcessing: isStillProcessing, inferenceEngine: inferenceEngine, modelContext: modelContext)
                }
                .task(id: inferenceEngine.speciesData?.scanId) {
                    if let scanId = inferenceEngine.speciesData?.scanId {
                        // Loop up to 5 times (2.5s max) to allow SwiftData background stores to propagate to the @MainActor context.
                        for _ in 0..<5 {
                            viewModel.fetchLocalRecord(for: scanId, modelContext: modelContext)
                            if viewModel.activeLocalRecord != nil { break }
                            try? await Task.sleep(nanoseconds: 500_000_000)
                        }
                    }
                    // Load user's preferred display name for this species so resolvedHeaderTitle reflects it.
                    if let scientificName = inferenceEngine.speciesData?.scientificName {
                        viewModel.loadPreferredCommonName(for: scientificName)
                    }
                }
                .task(id: viewModel.toastMessage) {
                    if viewModel.toastMessage != nil {
                        do {
                            try await Task.sleep(nanoseconds: 2_500_000_000)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.toastMessage = nil
                            }
                        } catch { } // absorb CancellationError elegantly
                    }
                }
        }
        // Presentation Logic Hook
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        
        // Dialogs
        .alert("Delete scan?", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Delete scan permanently", role: .destructive) { 
                viewModel.eradicateCurrentScan(modelContext: modelContext, inferenceEngine: inferenceEngine, dismiss: dismiss) 
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this scan? This will permanently remove the photo and data from your device and the global biological archive.")
        }
        .alert("Photos saved", isPresented: $viewModel.showSaveSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your photos have been securely saved to your camera roll.")
        }
        .newCollectionAlert(
            isPresented: $viewModel.showNewCollectionAlert,
            newCollectionName: $viewModel.newCollectionName,
            modelContext: modelContext,
            relatedRecord: viewModel.activeLocalRecord,
            onCreated: { collection in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    viewModel.toastMessage = "Created \(collection.name) and added scan"
                }
            }
        )
    }
}

// MARK: - Layout Extensions
private extension InsightSheetView {
    
    @ViewBuilder
    var mainContentStack: some View {
        ZStack(alignment: .top) {
            InsightContentView(viewModel: viewModel)

            if let message = viewModel.toastMessage {
                ToastBanner(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.toastMessage = nil
                    }
                }) {
                    Text(message)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }

            CelebrationBanner(
                commonName: inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject...",
                showCelebration: $viewModel.showCelebration
            )
        }
        .ignoresSafeArea(edges: .top)
    }
    
    @ToolbarContentBuilder
    var sheetToolbar: some ToolbarContent {
        let isReviewLocked: Bool = {
            guard let speciesData = inferenceEngine.speciesData else { return false }
            return speciesData.userConfirmedIdentification || speciesData.userIdentificationOverride != nil
        }()
        
        let canReanalyze: Bool = {
            if isReviewLocked { return false }
            guard let record = viewModel.activeLocalRecord, !(record.localImagePath?.starts(with: "http") == true) else { return false }
            return (record.additionalImagePaths ?? []).isEmpty
        }()
        
        let canReviewAlternatives: Bool = {
            if isReviewLocked { return false }
            guard let speciesData = inferenceEngine.speciesData else { return false }
            return !(speciesData.candidates ?? []).isEmpty && !speciesData.alternativesExhausted
        }()
        
        let canConfirm: Bool = {
            guard let speciesData = inferenceEngine.speciesData else { return false }
            return !speciesData.userConfirmedIdentification && speciesData.userIdentificationOverride == nil && !speciesData.isFlagged
        }()
        
        TopToolbar(
            commonName: viewModel.resolvedHeaderTitle,
            isCommonNameScrolledPast: viewModel.isCommonNameScrolledPast,
            isIdentificationFlagPresented: $viewModel.isIdentificationFlagPresented,
            isSavingPhotos: $viewModel.isSavingPhotos,
            showDeleteConfirmation: $viewModel.showDeleteConfirmation,
            onSavePhotos: { viewModel.saveUserPhotos(inferenceEngine: inferenceEngine) },
            onReanalyze: canReanalyze ? {
                if let record = viewModel.activeLocalRecord {
                    HapticManager.shared.triggerSelectionPulse()
                    AppEventPublisher.shared.send(.triggerRefinement(record: record))
                }
            } : nil,
            onReviewAlternatives: canReviewAlternatives ? {
                viewModel.isCandidateSwipePresented = true
            } : nil,
            onConfirmIdentification: canConfirm ? {
                HapticManager.shared.triggerSuccessPulse()
                Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
            } : nil,
            isAlreadyFlagged: (inferenceEngine.speciesData?.isFlagged ?? false) || isReviewLocked,
            isAnalyzing: inferenceEngine.isProcessing
        )
        
        InsightBottomToolbar(
            showBottomBarTools: viewModel.showBottomBarTools && !inferenceEngine.isProcessing,
            collections: collections,
            activeLocalRecord: viewModel.activeLocalRecord,
            toggleScanInCollection: { collection in 
                viewModel.toggleScanInCollection(collection, modelContext: modelContext) 
            },
            showNewCollectionAlert: $viewModel.showNewCollectionAlert,
            shareDiscovery: { viewModel.shareDiscovery(inferenceEngine: inferenceEngine) }
        )
    }
}
