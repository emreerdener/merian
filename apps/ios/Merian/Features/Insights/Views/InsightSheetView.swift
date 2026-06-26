import SwiftData
import SwiftUI
import UIKit

/// The master state orchestrator routing biological inference metadata and hardware logic 
/// safely down into the decoupled visual tree via the `InsightSheetViewModel`.
struct InsightSheetView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    @Environment(OfflineQueueManager.self) var offlineQueueManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var isPresented: Bool
    var queuedScan: QueuedScanContext?
    var initialScanId: String?
    var allowsExplorePresentation: Bool
    var presentationStyle: InsightPresentationStyle
    var onOpenCommunityIdentificationRequest: ((String) -> Void)?

    // MARK: - State
    @State var viewModel: InsightSheetViewModel
    @State var chatViewModel = InsightChatViewModel()
    @State private var queuedCompletionHandoffInFlight = false

    // Seed queued scans and persisted records at @State initialization time so the
    // first render reflects the correct content path before onAppear finishes rebinding.
    init(
        isPresented: Binding<Bool>,
        queuedScan: QueuedScanContext? = nil,
        initialScanId: String? = nil,
        inferenceEngine: InferenceEngine? = nil,
        allowsExplorePresentation: Bool = true,
        presentationStyle: InsightPresentationStyle = .sheet,
        onOpenCommunityIdentificationRequest: ((String) -> Void)? = nil
    ) {
        _isPresented = isPresented
        self.queuedScan = queuedScan
        self.initialScanId = initialScanId
        self.allowsExplorePresentation = allowsExplorePresentation
        self.presentationStyle = presentationStyle
        self.onOpenCommunityIdentificationRequest = onOpenCommunityIdentificationRequest
        _viewModel = State(
            initialValue: InsightSheetViewModel(
                queuedContext: queuedScan,
                inferenceEngine: inferenceEngine
            )
        )
    }
    
    // MARK: - Data Layer
    @Query(filter: #Predicate<ScanCollection> { !$0.isDeleted }, sort: \ScanCollection.createdAt, order: .reverse) var collections: [ScanCollection]
    
    // MARK: - View
    var body: some View {
        presentationRoot
        .accessibilityIdentifier("InsightSheetView")
        
        // Dialogs
        .alert("Delete scan?", isPresented: $viewModel.state.showDeleteConfirmation) {
            Button(viewModel.queuedContext != nil ? "Cancel upload & delete" : "Delete scan permanently", role: .destructive) {
                if let queued = viewModel.queuedContext {
                    Task { await offlineQueueManager.deleteQueuedScan(scanId: queued.id) }
                    dismiss()
                } else {
                    viewModel.eradicateCurrentScan(modelContext: modelContext, inferenceEngine: inferenceEngine, dismiss: dismiss)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.queuedContext != nil
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
            relatedRecordId: viewModel.activeLocalRecordId,
            onCreated: { collection in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    viewModel.state.toastMessage = "Created \(collection.name) and added scan"
                }
            }
        )
        .sheet(isPresented: $viewModel.state.showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $viewModel.state.isInsightChatSheetPresented) {
            if let speciesData = inferenceEngine.speciesData,
               let scanId = speciesData.scanId {
                InsightChatSheet(
                    viewModel: chatViewModel,
                    scanId: scanId,
                    speciesData: speciesData,
                    timestamp: viewModel.activeRecordTimestamp,
                    onClose: {
                        viewModel.state.isInsightChatSheetPresented = false
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .onChange(of: chatViewModel.isUnavailable(for: scanId)) { _, isUnavailable in
                    if isUnavailable {
                        viewModel.state.isInsightChatSheetPresented = false
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.state.showExploreOnboarding) {
            ExploreOnboardingPrompt(
                onShare: {
                    Task {
                        await viewModel.shareToExplore(
                            includeFieldNotes: false,
                            modelContext: modelContext
                        )
                    }
                    viewModel.state.showExploreOnboarding = false
                },
                onDismiss: {
                    viewModel.state.showExploreOnboarding = false
                }
            )
        }
        .sheet(isPresented: Binding(
            get: { allowsExplorePresentation && viewModel.state.showExploreSheet },
            set: { viewModel.state.showExploreSheet = $0 }
        ), onDismiss: {
            viewModel.refreshSharedExploreStateFromLocalCache()
            Task {
                await viewModel.refreshSharedExploreStateFromServer(modelContext: modelContext)
            }
        }) {
            ExploreView(
                initialPostId: viewModel.state.sharedExplorePostId,
                initialCommunityRequestId: viewModel.state.sharedCommunityIdentificationRequestId,
                allowsInsightPresentation: false
            )
        }
    }
}

// MARK: - Layout Extensions
private extension InsightSheetView {

    @ViewBuilder
    var presentationRoot: some View {
        switch presentationStyle {
        case .sheet:
            NavigationStack {
                configuredContent
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        case .embeddedInScansLibrary:
            configuredContent
        }
    }

    var configuredContent: some View {
        mainContentStack
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { sheetToolbar }
            .toolbarBackground(.visible, for: .bottomBar)
            .toolbarBackground(.ultraThinMaterial, for: .bottomBar)
            .navigationBarBackButtonHidden(presentationStyle.isEmbedded)
            .modifier(EmbeddedInsightBackSwipeModifier(
                isEnabled: presentationStyle.isEmbedded,
                onBack: dismissEmbeddedInsight
            ))
            .background {
                if presentationStyle.isEmbedded {
                    EmbeddedNavigationSwipeBackEnabler()
                        .frame(width: 0, height: 0)
                }
            }
            .modifier(SpeciesDictionaryDestinationModifier(isEnabled: !presentationStyle.isEmbedded))
            .onAppear {
                // Reset stale @State properties from previous presentations natively.
                viewModel.reset()

                // Seed both references immediately so viewModel computed properties
                // resolve on the first frame rather than waiting for InsightContentView's onAppear.
                viewModel.bindSettings(appSettings)
                viewModel.inferenceEngine = inferenceEngine
                viewModel.queuedContext = queuedScan
                if let initialScanId {
                    viewModel.bindPresentedScan(
                        scanId: initialScanId,
                        modelContext: modelContext,
                        inferenceEngine: inferenceEngine
                    )
                }
                viewModel.evaluateVoiceOverAndCelebration(inferenceEngine: inferenceEngine)
                // Suppress foreground inference banners while the insight is visible —
                // the user can already see the result. PushNotificationManager.willPresent
                // reads this flag and delivers the notification silently instead of as a banner.
                appSettings.suppressInferenceBanners = true
                // Clear the tab bar badge — the user is actively viewing a scan result.
                appSettings.hasUnseenScan = false
                AppIconBadgeCoordinator.updateAppIconBadge()
            }
            .onDisappear {
                appSettings.suppressInferenceBanners = false
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
            .task(id: queuedScan?.id) {
                guard let scanId = queuedScan?.id else { return }
                await attemptQueuedCompletionHandoff(scanId: scanId)
            }
            .onReceive(ScanLibraryEvents.libraryDidUpdatePublisher()) { _ in
                guard let scanId = queuedScan?.id else { return }
                Task { await attemptQueuedCompletionHandoff(scanId: scanId) }
            }
            .task(id: viewModel.persistentScanId) {
                viewModel.syncFieldNotesFromCurrentScan(modelContext: modelContext)
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
                    viewModel.loadPreferredCommonName(for: scientificName, modelContext: modelContext)
                }
                await viewModel.refreshSharedExploreStateFromServer(modelContext: modelContext)
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

    private func dismissEmbeddedInsight() {
        isPresented = false
        dismiss()
    }
    
    @ViewBuilder
    var mainContentStack: some View {
        InsightContentView(viewModel: viewModel, queuedScan: queuedScan)
            .merianSystemFeedback(
                toastMessage: $viewModel.state.toastMessage,
                toastActionTitle: $viewModel.toastActionTitle,
                toastAction: toastActionBinding,
                showCelebration: $viewModel.state.showCelebration,
                commonNameForCelebration: inferenceEngine.speciesData?.commonName.capitalized ?? "Scanning subject..."
            )
            .ignoresSafeArea(edges: .top)
    }

    @MainActor
    private var toastActionBinding: Binding<(() -> Void)?> {
        Binding(
            get: {
                guard let action = viewModel.toastAction else { return nil }
                guard !allowsExplorePresentation,
                      viewModel.state.toastMessage == "Asked the community",
                      viewModel.toastActionTitle == "View",
                      let requestId = viewModel.state.sharedCommunityIdentificationRequestId
                else {
                    return action
                }

                return {
                    if let onOpenCommunityIdentificationRequest {
                        onOpenCommunityIdentificationRequest(requestId)
                    } else {
                        AppEventPublisher.shared.send(.openCommunityIdentificationRequest(requestId: requestId))
                    }
                }
            },
            set: { viewModel.toastAction = $0 }
        )
    }

    @MainActor
    private func attemptQueuedCompletionHandoff(scanId: String) async {
        guard !queuedCompletionHandoffInFlight else { return }
        queuedCompletionHandoffInFlight = true
        defer { queuedCompletionHandoffInFlight = false }

        for attempt in 0..<8 {
            guard queuedScan?.id == scanId || viewModel.queuedContext?.id == scanId else { return }
            if viewModel.promoteQueuedScanIfLocalRecordExists(
                scanId: scanId,
                modelContext: modelContext,
                inferenceEngine: inferenceEngine
            ) {
                appSettings.hasUnseenScan = false
                AppIconBadgeCoordinator.updateAppIconBadge()
                return
            }

            if attempt < 7 {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }

        MerianLog.data.debug(
            "InsightSheetView.attemptQueuedCompletionHandoff: no completed local record visible scanId=\(scanId, privacy: .public)"
        )
    }
}
