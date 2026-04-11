import SwiftData
import SwiftUI

/// The master state orchestrator routing biological inference metadata and hardware logic 
/// safely down into the decoupled visual tree via the `InsightSheetViewModel`.
struct InsightSheetView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    @Environment(OfflineQueueManager.self) var offlineQueueManager
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var isPresented: Bool
    var queuedScan: QueuedScanContext?

    // MARK: - State
    @State private var viewModel: InsightSheetViewModel

    // Seed queuedContext at @State initialization time so contentMode resolves
    // to .queued on the very first render, before onAppear fires.
    init(isPresented: Binding<Bool>, queuedScan: QueuedScanContext? = nil) {
        _isPresented = isPresented
        self.queuedScan = queuedScan
        _viewModel = State(initialValue: InsightSheetViewModel(queuedContext: queuedScan))
    }
    
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
                    // Seed both references immediately so viewModel computed properties
                    // resolve on the first frame rather than waiting for InsightContentView's onAppear.
                    viewModel.inferenceEngine = inferenceEngine
                    viewModel.queuedContext = queuedScan
                    viewModel.evaluateVoiceOverAndCelebration(inferenceEngine: inferenceEngine)
                    // Suppress foreground inference banners while the sheet is visible —
                    // the user can already see the result. PushNotificationManager.willPresent
                    // reads this flag and delivers the notification silently instead of as a banner.
                    UserDefaults.standard.set(true, forKey: "suppressInferenceBanners")
                    // Clear the tab bar badge — the user is actively viewing a scan result.
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
                    PushNotificationManager.shared.setBadgeCount(0)
                }
                .onDisappear {
                    UserDefaults.standard.set(false, forKey: "suppressInferenceBanners")
                }
                .task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation(.easeIn(duration: 0.2)) {
                        viewModel.showBottomBarTools = true
                    }
                }
                .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
                    // Queued scan path: the engine's isProcessing reflects a different pipeline.
                    // Skip celebration, haptics, and record-marking — they don't apply here.
                    guard viewModel.queuedContext == nil else { return }
                    viewModel.evaluateProcessingCompletion(isStillProcessing: isStillProcessing, inferenceEngine: inferenceEngine, modelContext: modelContext)
                }
                .onChange(of: queuedScan) { oldScan, newScan in
                    // The parent LibraryView proactively loaded the InferenceEngine
                    // and cleared the property to signal the handoff is complete.
                    // Release the queued context to transition cleanly to the results.
                    if oldScan != nil && newScan == nil {
                        viewModel.queuedContext = nil
                    }
                }
                .task(id: inferenceEngine.speciesData?.scanId) {
                    // Queued scans have no speciesData — skip the record fetch and name load.
                    guard viewModel.queuedContext == nil else { return }
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
            Button(queuedScan != nil ? "Cancel upload & delete" : "Delete scan permanently", role: .destructive) {
                if let queued = queuedScan {
                    Task { await offlineQueueManager.deleteQueuedScan(scanId: queued.id) }
                    dismiss()
                } else {
                    viewModel.eradicateCurrentScan(modelContext: modelContext, inferenceEngine: inferenceEngine, dismiss: dismiss)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(queuedScan != nil
                ? "Are you sure you want to cancel this upload? The scan will be permanently deleted from your device."
                : "Are you sure you want to delete this scan? This will permanently remove the photo and data from your device and the global biological archive.")
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
            InsightContentView(viewModel: viewModel, queuedScan: queuedScan)

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
        // Queued scan path: the standard ellipsis menu is suppressed (isAnalyzing == true),
        // so surface a dedicated trash button for the only available destructive action.
        if queuedScan != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    viewModel.showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .bold))
                }
                .tint(.red)
            }
        }

        TopToolbar(
            commonName: viewModel.resolvedHeaderTitle,
            isCommonNameScrolledPast: viewModel.isCommonNameScrolledPast,
            isIdentificationFlagPresented: $viewModel.isIdentificationFlagPresented,
            isSavingPhotos: $viewModel.isSavingPhotos,
            showDeleteConfirmation: $viewModel.showDeleteConfirmation,
            onSavePhotos: { viewModel.saveUserPhotos(inferenceEngine: inferenceEngine) },
            onReanalyze: viewModel.canReanalyze ? {
                if let record = viewModel.activeLocalRecord {
                    HapticManager.shared.triggerSelectionPulse()
                    AppEventPublisher.shared.send(.triggerRefinement(record: record))
                }
            } : nil,
            onReviewAlternatives: viewModel.canReviewAlternatives ? {
                viewModel.isCandidateSwipePresented = true
            } : nil,
            onConfirmIdentification: viewModel.canConfirm ? {
                HapticManager.shared.triggerSuccessPulse()
                Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
            } : nil,
            isAlreadyFlagged: viewModel.isAlreadyFlagged,
            isAnalyzing: viewModel.isProcessing
        )

        InsightBottomToolbar(
            showBottomBarTools: viewModel.showBottomBarTools && !viewModel.isProcessing,
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
