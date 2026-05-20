import SwiftData
import SwiftUI
import UIKit

enum InsightPresentationStyle {
    case sheet
    case embeddedInScansLibrary

    var isEmbedded: Bool {
        self == .embeddedInScansLibrary
    }
}

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
    var initialRecord: LocalScanRecord?
    var allowsExplorePresentation: Bool
    var presentationStyle: InsightPresentationStyle

    // MARK: - State
    @State private var viewModel: InsightSheetViewModel
    @State private var queuedCompletionHandoffInFlight = false

    // Seed queued scans and persisted records at @State initialization time so the
    // first render reflects the correct content path before onAppear finishes rebinding.
    init(
        isPresented: Binding<Bool>,
        queuedScan: QueuedScanContext? = nil,
        initialRecord: LocalScanRecord? = nil,
        inferenceEngine: InferenceEngine? = nil,
        allowsExplorePresentation: Bool = true,
        presentationStyle: InsightPresentationStyle = .sheet
    ) {
        _isPresented = isPresented
        self.queuedScan = queuedScan
        self.initialRecord = initialRecord
        self.allowsExplorePresentation = allowsExplorePresentation
        self.presentationStyle = presentationStyle
        _viewModel = State(
            initialValue: InsightSheetViewModel(
                queuedContext: queuedScan,
                initialRecord: initialRecord,
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
                    Task { await viewModel.shareToExplore(includeFieldNotes: false) }
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
        }) {
            ExploreView(
                initialPostId: viewModel.state.sharedExplorePostId,
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
            .navigationDestination(for: SpeciesDictionaryRoute.self) { route in
                SpeciesDictionaryPageContentView(
                    scientificName: route.scientificName,
                    speciesId: route.speciesId,
                    entryPoint: route.entryPoint,
                    showsCloseButton: false
                )
            }
            .onAppear {
                // Reset stale @State properties from previous presentations natively.
                viewModel.reset()

                // Seed both references immediately so viewModel computed properties
                // resolve on the first frame rather than waiting for InsightContentView's onAppear.
                viewModel.bindSettings(appSettings)
                viewModel.inferenceEngine = inferenceEngine
                viewModel.queuedContext = queuedScan
                if let initialRecord {
                    viewModel.bindPresentedRecord(initialRecord, modelContext: modelContext)
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
        if viewModel.queuedContext != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    viewModel.state.showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .bold))
                        .imageOverlayToolbarIconChrome(
                            isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground,
                            foregroundColor: .red
                        )
                }
                .tint(.red)
                .imageOverlayToolbarButtonChrome(isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground)
            }
        }

        TopToolbar(
            commonName: viewModel.resolvedHeaderTitle,
            isCommonNameScrolledPast: viewModel.state.isCommonNameScrolledPast,
            isIdentificationFlagPresented: $viewModel.state.isIdentificationFlagPresented,
            isSavingPhotos: $viewModel.state.isSavingPhotos,
            showDeleteConfirmation: $viewModel.state.showDeleteConfirmation,
            hasUserPhotos: viewModel.hasUserPhotos,
            leadingControl: presentationStyle.isEmbedded ? .back : .close,
            onSavePhotos: { viewModel.saveUserPhotos(inferenceEngine: inferenceEngine) },
            hasFieldNotes: viewModel.hasFieldNotes,
            onFieldNotes: {
                viewModel.state.isFieldNotesSheetPresented = true
            },
            onReanalyze: viewModel.canReanalyze ? {
                if RevenueCatManager.shared.isProActive {
                    if let record = viewModel.activeLocalRecord {
                        HapticManager.shared.triggerSelectionPulse()
                        AppEventPublisher.shared.send(.triggerRefinement(
                            record: record,
                            initialDescription: viewModel.shareableFieldNotes
                        ))
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
            onShareToExplore: viewModel.canShareToExplore ? { includeFieldNotes in
                Task { await viewModel.shareToExplore(includeFieldNotes: includeFieldNotes) }
            } : nil,
            isSharingToExplore: viewModel.state.isSharingToExplore,
            isUpdatingExploreFieldNotes: viewModel.state.isUpdatingExploreFieldNotes,
            fieldNotesPreview: viewModel.shareableFieldNotes,
            sharedExplorePostId: viewModel.state.sharedExplorePostId,
            fieldNotesArePublicOnExplore: viewModel.state.exploreFieldNotesArePublic,
            onViewInExplore: allowsExplorePresentation ? {
                viewModel.state.showExploreSheet = true
            } : nil,
            onUpdateFieldNotesVisibility: { isPublic in
                await viewModel.updateExploreFieldNotesVisibility(
                    isPublic: isPublic,
                    modelContext: modelContext
                )
            }
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

private struct EmbeddedInsightBackSwipeModifier: ViewModifier {
    let isEnabled: Bool
    let onBack: () -> Void

    @State private var didTriggerBack = false

    private let edgeActivationWidth: CGFloat = 44
    private let minimumHorizontalTranslation: CGFloat = 70
    private let minimumHorizontalVelocity: CGFloat = 420

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .simultaneousGesture(edgeSwipeGesture)
                .overlay(alignment: .leading) {
                    Color.clear
                        .frame(width: edgeActivationWidth)
                        .contentShape(Rectangle())
                        .gesture(edgeSwipeGesture)
                }
        } else {
            content
        }
    }

    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onEnded { value in
                guard shouldTriggerBack(for: value), !didTriggerBack else { return }

                didTriggerBack = true
                onBack()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    didTriggerBack = false
                }
            }
    }

    private func shouldTriggerBack(for value: DragGesture.Value) -> Bool {
        guard value.startLocation.x <= edgeActivationWidth else { return false }

        let horizontalTranslation = value.translation.width
        let verticalTranslation = abs(value.translation.height)
        let predictedHorizontalTranslation = value.predictedEndTranslation.width
        let horizontalVelocity = predictedHorizontalTranslation - horizontalTranslation

        guard horizontalTranslation > 0 else { return false }
        guard horizontalTranslation > verticalTranslation * 1.15 else { return false }

        return horizontalTranslation >= minimumHorizontalTranslation
            || horizontalVelocity >= minimumHorizontalVelocity
    }
}

private struct EmbeddedNavigationSwipeBackEnabler: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> Controller {
        Controller(coordinator: context.coordinator)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.enableSwipeBack()
    }

    final class Controller: UIViewController {
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            return nil
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableSwipeBack()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            enableSwipeBack()
        }

        func enableSwipeBack() {
            guard let navigationController else { return }
            coordinator.attach(to: navigationController)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var navigationController: UINavigationController?
        private weak var previousDelegate: UIGestureRecognizerDelegate?

        func attach(to navigationController: UINavigationController) {
            guard self.navigationController !== navigationController else {
                enableGesture()
                return
            }

            restorePreviousDelegate()
            self.navigationController = navigationController
            previousDelegate = navigationController.interactivePopGestureRecognizer?.delegate
            enableGesture()
        }

        private func enableGesture() {
            guard let gesture = navigationController?.interactivePopGestureRecognizer else {
                return
            }

            gesture.isEnabled = true
            gesture.delegate = self
        }

        private func restorePreviousDelegate() {
            guard
                let gesture = navigationController?.interactivePopGestureRecognizer,
                gesture.delegate === self
            else { return }

            gesture.delegate = previousDelegate
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard
                let navigationController,
                navigationController.viewControllers.count > 1
            else {
                return false
            }

            if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
                let translation = panGesture.translation(in: panGesture.view)
                guard translation.x > 0, abs(translation.x) > abs(translation.y) else {
                    return false
                }
            }

            return true
        }

        deinit {
            restorePreviousDelegate()
        }
    }
}
