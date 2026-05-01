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
    init(isPresented: Binding<Bool>, queuedScan: QueuedScanContext? = nil, inferenceEngine: InferenceEngine? = nil) {
        _isPresented = isPresented
        self.queuedScan = queuedScan
        _viewModel = State(initialValue: InsightSheetViewModel(queuedContext: queuedScan, inferenceEngine: inferenceEngine))
    }
    
    // MARK: - Data Layer
    @Query(filter: #Predicate<ScanCollection> { !$0.isDeleted }, sort: \ScanCollection.createdAt, order: .reverse) var collections: [ScanCollection]
    
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
                    // Reset stale @State properties from previous presentations natively.
                    viewModel.reset()

                    // Seed both references immediately so viewModel computed properties
                    // resolve on the first frame rather than waiting for InsightContentView's onAppear.
                    viewModel.inferenceEngine = inferenceEngine
                    viewModel.queuedContext = queuedScan
                    viewModel.evaluateVoiceOverAndCelebration(inferenceEngine: inferenceEngine)
                    // Suppress foreground inference banners while the sheet is visible —
                    // the user can already see the result. PushNotificationManager.willPresent
                    // reads this flag and delivers the notification silently instead of as a banner.
                    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.suppressInferenceBanners)
                    // Clear the tab bar badge — the user is actively viewing a scan result.
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
                    PushNotificationManager.shared.setBadgeCount(0)
                }
                .onDisappear {
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.suppressInferenceBanners)
                }
                .task {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation(.easeIn(duration: 0.2)) {
                        viewModel.state.showBottomBarTools = true
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
                    await viewModel.refreshSharedExploreStateFromServer()
                }
                .task(id: viewModel.state.toastMessage) {
                    if viewModel.state.toastMessage != nil {
                        do {
                            try await Task.sleep(nanoseconds: 2_500_000_000)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.state.toastMessage = nil
                            }
                        } catch { } // absorb CancellationError elegantly
                    }
                }
        }
        .accessibilityIdentifier("InsightSheetView")
        // Presentation Logic Hook
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        
        // Dialogs
        .alert("Delete scan?", isPresented: $viewModel.state.showDeleteConfirmation) {
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
        .alert("Photos saved", isPresented: $viewModel.state.showSaveSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your photos have been securely saved to your camera roll.")
        }
        .newCollectionAlert(
            isPresented: $viewModel.state.showNewCollectionAlert,
            newCollectionName: $viewModel.state.newCollectionName,
            modelContext: modelContext,
            relatedRecord: viewModel.activeLocalRecord,
            onCreated: { collection in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    viewModel.state.toastMessage = "Created \(collection.name) and added scan"
                }
            }
        )
        .sheet(isPresented: $viewModel.state.showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $viewModel.state.showExploreOnboarding) {
            ExploreOnboardingPrompt(
                onShare: {
                    Task { await viewModel.shareToExplore() }
                    viewModel.state.showExploreOnboarding = false
                },
                onDismiss: {
                    viewModel.state.showExploreOnboarding = false
                }
            )
        }
        .sheet(isPresented: $viewModel.state.showExploreSheet, onDismiss: {
            viewModel.refreshSharedExploreStateFromLocalCache()
        }) {
            ExploreView(initialPostId: viewModel.state.sharedExplorePostId)
        }
    }
}

// MARK: - Layout Extensions
private extension InsightSheetView {
    
    @ViewBuilder
    var mainContentStack: some View {
        InsightContentView(viewModel: viewModel, queuedScan: queuedScan)
            .merianSystemFeedback(
                toastMessage: $viewModel.state.toastMessage,
                toastActionTitle: $viewModel.toastActionTitle,
                toastAction: $viewModel.toastAction,
                showCelebration: $viewModel.state.showCelebration,
                commonNameForCelebration: inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..."
            )
            .ignoresSafeArea(edges: .top)
    }
    
    @ToolbarContentBuilder
    var sheetToolbar: some ToolbarContent {
        // Queued scan path: the standard ellipsis menu is suppressed (isAnalyzing == true),
        // so surface a dedicated trash button for the only available destructive action.
        if queuedScan != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    viewModel.state.showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .bold))
                }
                .tint(.red)
            }
        }

        TopToolbar(
            commonName: viewModel.resolvedHeaderTitle,
            isCommonNameScrolledPast: viewModel.state.isCommonNameScrolledPast,
            isIdentificationFlagPresented: $viewModel.state.isIdentificationFlagPresented,
            isSavingPhotos: $viewModel.state.isSavingPhotos,
            showDeleteConfirmation: $viewModel.state.showDeleteConfirmation,
            hasUserPhotos: viewModel.hasUserPhotos,
            onSavePhotos: { viewModel.saveUserPhotos(inferenceEngine: inferenceEngine) },
            onReanalyze: viewModel.canReanalyze ? {
                if RevenueCatManager.shared.isProActive {
                    if let record = viewModel.activeLocalRecord {
                        HapticManager.shared.triggerSelectionPulse()
                        AppEventPublisher.shared.send(.triggerRefinement(record: record))
                    }
                } else {
                    viewModel.state.showPaywall = true
                }
            } : nil,
            onReviewAlternatives: viewModel.canReviewAlternatives ? {
                viewModel.state.isCandidateSwipePresented = true
            } : nil,
            onConfirmIdentification: viewModel.canConfirm ? {
                HapticManager.shared.triggerSuccessPulse()
                Task { await inferenceEngine.confirmAIIdentification(modelContext: modelContext) }
            } : nil,
            isAlreadyFlagged: viewModel.isAlreadyFlagged,
            isAnalyzing: viewModel.isProcessing
        )

        InsightBottomToolbar(
            showBottomBarTools: viewModel.state.showBottomBarTools && !viewModel.isProcessing,
            collections: collections,
            activeLocalRecord: viewModel.activeLocalRecord,
            toggleScanInCollection: { collection in
                viewModel.toggleScanInCollection(collection, modelContext: modelContext)
            },
            showNewCollectionAlert: $viewModel.state.showNewCollectionAlert,
            shareExternally: { viewModel.shareDiscovery(inferenceEngine: inferenceEngine) },
            onShareToExplore: viewModel.canShareToExplore ? {
                Task { await viewModel.shareToExplore() }
            } : nil,
            isSharingToExplore: viewModel.state.isSharingToExplore,
            sharedExplorePostId: viewModel.state.sharedExplorePostId,
            onViewInExplore: {
                viewModel.state.showExploreSheet = true
            }
        )
    }
}
