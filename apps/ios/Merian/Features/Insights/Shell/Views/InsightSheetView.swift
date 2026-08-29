import SwiftData
import SwiftUI
import UIKit

struct InsightFieldTripContributionLoadKey: Equatable {
    let scanId: String?
    let isAuthenticated: Bool
    let accountId: String?
}

private enum InsightChatDismissalAction: Equatable {
    case reviewAlternatives(scanId: String, generation: UInt64)
    case reanalyze(scanId: String, generation: UInt64)
    case showPaywall(scanId: String, generation: UInt64)

    var context: (scanId: String, generation: UInt64) {
        switch self {
        case .reviewAlternatives(let scanId, let generation),
             .reanalyze(let scanId, let generation),
             .showPaywall(let scanId, let generation):
            (scanId, generation)
        }
    }
}

private enum InsightShellPresentation: Identifiable, Equatable {
    case paywall
    case fieldTripAuthor(ExploreAuthorProfileRoute)
    case chat(scanId: String, generation: UInt64)
    case exploreOnboarding(scanId: String, generation: UInt64)
    case explore(scanId: String, generation: UInt64)

    var id: String {
        switch self {
        case .paywall:
            "paywall"
        case .fieldTripAuthor(let route):
            "field-trip-author-\(route.id)"
        case .chat(let scanId, let generation):
            "chat-\(scanId)-\(generation)"
        case .exploreOnboarding(let scanId, let generation):
            "explore-onboarding-\(scanId)-\(generation)"
        case .explore(let scanId, let generation):
            "explore-\(scanId)-\(generation)"
        }
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
    private var supabase: SupabaseManager { .shared }

    @Binding var isPresented: Bool
    var queuedScan: QueuedScanContext?
    var initialScanId: String?
    var allowsExplorePresentation: Bool
    var presentationStyle: InsightPresentationStyle
    var onOpenCommunityIdentificationRequest: ((String) -> Void)?
    var onOpenFieldTripOverview: ((InsightFieldTripOverviewDestination) -> Void)?

    // MARK: - State
    @State var viewModel: InsightSheetViewModel
    @State var chatViewModel = InsightChatViewModel()
    @State private var fieldTripExploreViewModel = ExploreFeedViewModel()
    @State private var queuedCompletionHandoffScanId: String?
    @State private var queuedCompletionHandoffGeneration: UInt64 = 0
    @State var presentedScanId: String?
    @State var selectedInsightChatScanId: String?
    @State var selectedInsightChatGeneration: UInt64?
    @State private var pendingInsightChatDismissalAction: InsightChatDismissalAction?
    @State var pendingDeletionScanId: String?
    @State var pendingDeletionGeneration: UInt64?
    @State var pendingNewCollectionScanId: String?
    @State var pendingNewCollectionGeneration: UInt64?
    @State private var selectedFieldTripOverviewDestination: InsightFieldTripOverviewDestination?
    @State private var selectedFieldTripPublicationRoute: FieldTripPublicationRoute?
    @State private var selectedFieldTripChallengeEntryRoute: FieldTripChallengeEntryRoute?
    @State private var activeShellPresentation: InsightShellPresentation?
    @State private var dismissedShellPresentation: InsightShellPresentation?
    @State private var pendingShellPresentation: InsightShellPresentation?
    @State private var pendingOwnedPostInsightScanId: String?

    // Seed queued scans and persisted records at @State initialization time so the
    // first render reflects the correct content path before onAppear finishes rebinding.
    init(
        isPresented: Binding<Bool>,
        queuedScan: QueuedScanContext? = nil,
        initialScanId: String? = nil,
        inferenceEngine: InferenceEngine? = nil,
        allowsExplorePresentation: Bool = true,
        presentationStyle: InsightPresentationStyle = .sheet,
        onOpenCommunityIdentificationRequest: ((String) -> Void)? = nil,
        onOpenFieldTripOverview: ((InsightFieldTripOverviewDestination) -> Void)? = nil
    ) {
        _isPresented = isPresented
        self.queuedScan = queuedScan
        self.initialScanId = initialScanId
        self.allowsExplorePresentation = allowsExplorePresentation
        self.presentationStyle = presentationStyle
        self.onOpenCommunityIdentificationRequest = onOpenCommunityIdentificationRequest
        self.onOpenFieldTripOverview = onOpenFieldTripOverview
        _presentedScanId = State(initialValue: initialScanId)
        _viewModel = State(
            initialValue: InsightSheetViewModel(
                queuedContext: queuedScan,
                inferenceEngine: inferenceEngine
            )
        )
    }
    
    // MARK: - Data Layer
    @Query(filter: #Predicate<ScanCollection> { !$0.isPendingDeletion }, sort: \ScanCollection.createdAt, order: .reverse) var collections: [ScanCollection]

    var deleteConfirmationBinding: Binding<Bool> {
        let expectedScanId = pendingDeletionScanId
        let expectedGeneration = pendingDeletionGeneration
        return Binding(
            get: {
                guard viewModel.state.showDeleteConfirmation,
                      let expectedScanId,
                      let expectedGeneration,
                      pendingDeletionScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      pendingDeletionGeneration == expectedGeneration else {
                    return false
                }
                return viewModel.isPresentingScan(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { shouldPresent in
                guard shouldPresent else {
                    guard let expectedScanId,
                          let expectedGeneration,
                          pendingDeletionScanId?
                            .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                          pendingDeletionGeneration == expectedGeneration else {
                        return
                    }
                    viewModel.state.showDeleteConfirmation = false
                    return
                }

                let targetScanId = viewModel.queuedContext?.id ??
                    viewModel.presentedLocalRecordScanId
                guard let targetScanId else { return }
                pendingDeletionScanId = targetScanId
                pendingDeletionGeneration = viewModel.scanBoundActionGeneration
                viewModel.state.showDeleteConfirmation = true
            }
        )
    }

    var newCollectionAlertBinding: Binding<Bool> {
        let expectedScanId = pendingNewCollectionScanId
        let expectedGeneration = pendingNewCollectionGeneration
        return Binding(
            get: {
                guard viewModel.state.showNewCollectionAlert,
                      let expectedScanId,
                      let expectedGeneration,
                      pendingNewCollectionScanId?
                        .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                      pendingNewCollectionGeneration == expectedGeneration else {
                    return false
                }
                return viewModel.isPresentingLocalRecord(
                    scanId: expectedScanId,
                    generation: expectedGeneration
                )
            },
            set: { shouldPresent in
                guard shouldPresent else {
                    guard let expectedScanId,
                          let expectedGeneration,
                          pendingNewCollectionScanId?
                            .caseInsensitiveCompare(expectedScanId) == .orderedSame,
                          pendingNewCollectionGeneration == expectedGeneration else {
                        return
                    }
                    viewModel.state.showNewCollectionAlert = false
                    return
                }
                guard let scanId = viewModel.presentedLocalRecordScanId else {
                    return
                }
                pendingNewCollectionScanId = scanId
                pendingNewCollectionGeneration = viewModel.scanBoundActionGeneration
                viewModel.state.showNewCollectionAlert = true
            }
        )
    }

    private var fieldTripContributionLoadKey: InsightFieldTripContributionLoadKey {
        InsightFieldTripContributionLoadKey(
            scanId: viewModel.persistentScanId,
            isAuthenticated: supabase.isAuthenticated,
            accountId: supabase.currentUser?.id.uuidString
        )
    }
    
    // MARK: - View
    var body: some View {
        presentationRoot
        .accessibilityIdentifier("InsightSheetView")
        .onChange(of: offlineQueueManager.isOnline, initial: true) { _, isOnline in
            chatViewModel.updateConnectivity(isOnline: isOnline)
        }
        .onChange(of: isPresented) { _, isNowPresented in
            guard isNowPresented else { return }
            presentedScanId = initialScanId
            selectedInsightChatScanId = nil
            selectedInsightChatGeneration = nil
            pendingInsightChatDismissalAction = nil
            pendingDeletionScanId = nil
            pendingDeletionGeneration = nil
            pendingNewCollectionScanId = nil
            pendingNewCollectionGeneration = nil
            selectedFieldTripOverviewDestination = nil
            selectedFieldTripPublicationRoute = nil
            selectedFieldTripChallengeEntryRoute = nil
            activeShellPresentation = nil
            dismissedShellPresentation = nil
            pendingShellPresentation = nil
        }

        // Dialogs
        .alert("Delete scan?", isPresented: deleteConfirmationBinding) {
            Button(viewModel.queuedContext != nil ? "Cancel upload & delete" : "Delete scan permanently", role: .destructive) {
                guard let targetScanId = pendingDeletionScanId,
                      let targetGeneration = pendingDeletionGeneration else {
                    return
                }
                viewModel.state.showDeleteConfirmation = false
                pendingDeletionScanId = nil
                pendingDeletionGeneration = nil
                guard viewModel.isPresentingScan(
                    scanId: targetScanId,
                    generation: targetGeneration
                ) else {
                    return
                }
                if let queued = viewModel.queuedContext,
                   queued.id.caseInsensitiveCompare(targetScanId) == .orderedSame {
                    Task { await offlineQueueManager.deleteQueuedScan(scanId: queued.id) }
                    dismiss()
                } else {
                    viewModel.eradicateCurrentScan(
                        expectedScanId: targetScanId,
                        expectedGeneration: targetGeneration,
                        modelContext: modelContext,
                        inferenceEngine: inferenceEngine,
                        dismiss: dismiss
                    )
                }
            }
            Button("Cancel", role: .cancel) {
                viewModel.state.showDeleteConfirmation = false
                pendingDeletionScanId = nil
                pendingDeletionGeneration = nil
            }
        } message: {
            Text(viewModel.queuedContext != nil
                ? "Are you sure you want to cancel this upload? The scan will be permanently deleted from your device."
                : "This permanently removes the scan, photo, and cloud data. If it is published to Explore, that post, its likes, and its comments will also be permanently removed.")
        }
        .alert("Saved to Photos", isPresented: $viewModel.state.showMediaSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.state.lastMediaSaveResult.successMessage)
        }
        .newCollectionAlert(
            isPresented: newCollectionAlertBinding,
            newCollectionName: $viewModel.state.newCollectionName,
            modelContext: modelContext,
            relatedRecordId: pendingNewCollectionScanId,
            canCreate: {
                guard let targetScanId = pendingNewCollectionScanId,
                      let targetGeneration = pendingNewCollectionGeneration else {
                    return false
                }
                return viewModel.isPresentingLocalRecord(
                    scanId: targetScanId,
                    generation: targetGeneration
                )
            },
            onCreated: { collection in
                guard let targetScanId = pendingNewCollectionScanId,
                      let targetGeneration = pendingNewCollectionGeneration else {
                    return
                }
                viewModel.state.showNewCollectionAlert = false
                pendingNewCollectionScanId = nil
                pendingNewCollectionGeneration = nil
                guard viewModel.isPresentingLocalRecord(
                    scanId: targetScanId,
                    generation: targetGeneration
                ) else {
                    return
                }
                viewModel.state.toastMessage = .success(
                    "Created \(collection.name) and added scan"
                )
            }
        )
        .sheet(
            item: shellPresentationBinding,
            onDismiss: handleShellPresentationDismissed
        ) { presentation in
            shellPresentationContent(presentation)
        }
        .onChange(of: viewModel.state.showPaywall, initial: true) { _, requested in
            synchronizePaywallPresentation(isRequested: requested)
        }
        .onChange(
            of: viewModel.state.isInsightChatSheetPresented,
            initial: true
        ) { _, requested in
            synchronizeInsightChatPresentation(isRequested: requested)
        }
        .onChange(of: viewModel.state.showExploreOnboarding, initial: true) { _, requested in
            synchronizeExploreOnboardingPresentation(isRequested: requested)
        }
        .onChange(of: viewModel.state.showExploreSheet, initial: true) { _, requested in
            synchronizeExplorePresentation(isRequested: requested)
        }
    }
}

private extension InsightSheetView {
    @MainActor
    var shellPresentationBinding: Binding<InsightShellPresentation?> {
        Binding(
            get: { activeShellPresentation },
            set: { presentation in
                guard presentation == nil else { return }
                dismissActiveShellPresentation()
            }
        )
    }

    @ViewBuilder
    func shellPresentationContent(
        _ presentation: InsightShellPresentation
    ) -> some View {
        switch presentation {
        case .paywall:
            PaywallView()
        case .fieldTripAuthor(let route):
            ExploreAuthorProfileSheet(
                viewModel: fieldTripExploreViewModel,
                route: route
            )
        case .chat(let scanId, let generation):
            insightChatPresentationContent(
                scanId: scanId,
                generation: generation
            )
        case .exploreOnboarding(let scanId, let generation):
            exploreOnboardingPresentationContent(
                scanId: scanId,
                generation: generation
            )
        case .explore:
            ExploreView(
                initialPostId: exploreSheetInitialPostId,
                initialCommunityRequestId: exploreSheetInitialCommunityRequestId,
                allowsInsightPresentation: false,
                onOpenOwnedPostInsight: { scanId in
                    stageOwnedPostInsightAfterExploreDismissal(scanId: scanId)
                }
            )
        }
    }

    @ViewBuilder
    func insightChatPresentationContent(
        scanId: String,
        generation: UInt64
    ) -> some View {
        if generation == viewModel.scanBoundActionGeneration,
           let speciesData = inferenceEngine.speciesData,
           speciesData.scanId?.caseInsensitiveCompare(scanId) == .orderedSame {
            InsightChatSheet(
                viewModel: chatViewModel,
                scanId: scanId,
                speciesData: speciesData,
                displayName: viewModel.resolvedHeaderTitle,
                timestamp: viewModel.activeRecordTimestamp,
                prepareForInitialLoad: {
                    await prepareInsightChatForInitialLoad(
                        expectedScanId: scanId,
                        expectedGeneration: generation
                    )
                },
                onToast: { message in
                    guard viewModel.isPresentingLocalRecord(
                        scanId: scanId,
                        generation: generation
                    ) else {
                        return
                    }
                    viewModel.state.toastMessage = message
                },
                onAppendToFieldNotes: { text, kind in
                    appendInsightChatTextToFieldNotes(
                        text,
                        kind: kind,
                        expectedScanId: scanId,
                        expectedGeneration: generation
                    )
                },
                onReviewAlternatives: viewModel.canReviewIdentificationConcernCandidates ? {
                    openIdentificationConcernCandidatesFromChat(
                        expectedScanId: scanId,
                        expectedGeneration: generation
                    )
                } : nil,
                onReanalyzeSpecies: viewModel.canReanalyze ? {
                    startReanalysisFromInsightChat(
                        expectedScanId: scanId,
                        expectedGeneration: generation
                    )
                } : nil,
                onClose: {
                    guard viewModel.isPresentingLocalRecord(
                        scanId: scanId,
                        generation: generation
                    ) else {
                        return
                    }
                    viewModel.state.isInsightChatSheetPresented = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .onChange(of: chatViewModel.errorMessage) { _, errorMessage in
                guard viewModel.isPresentingLocalRecord(
                    scanId: scanId,
                    generation: generation
                ) else {
                    return
                }
                if errorMessage == "Naturebook Pro is required." {
                    pendingInsightChatDismissalAction = .showPaywall(
                        scanId: scanId,
                        generation: generation
                    )
                    viewModel.state.isInsightChatSheetPresented = false
                    chatViewModel.errorMessage = nil
                }
            }
            .onChange(of: chatViewModel.unavailableScanId) { _, unavailableScanId in
                guard unavailableScanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame,
                      viewModel.isPresentingLocalRecord(
                          scanId: scanId,
                          generation: generation
                      ) else {
                    return
                }
                viewModel.state.isInsightChatSheetPresented = false
                viewModel.state.toastMessage = .error(
                    chatViewModel.errorMessage
                        ?? "Field chat isn't available for this scan."
                )
            }
        }
    }

    @ViewBuilder
    func exploreOnboardingPresentationContent(
        scanId: String,
        generation: UInt64
    ) -> some View {
        if viewModel.isPresentingLocalRecord(
            scanId: scanId,
            generation: generation
        ) {
            ExploreOnboardingPrompt(
                onShare: {
                    guard viewModel.isPresentingLocalRecord(
                        scanId: scanId,
                        generation: generation
                    ),
                          viewModel.state
                            .exploreOnboardingPresentationScanId?
                            .caseInsensitiveCompare(scanId) == .orderedSame,
                          viewModel.state
                            .exploreOnboardingPresentationGeneration == generation else {
                        return
                    }
                    Task {
                        await viewModel.shareToExplore(
                            includeFieldNotes: false,
                            expectedScanId: scanId,
                            expectedGeneration: generation,
                            modelContext: modelContext
                        )
                    }
                    dismissExploreOnboarding(
                        expectedScanId: scanId,
                        expectedGeneration: generation
                    )
                },
                onDismiss: {
                    dismissExploreOnboarding(
                        expectedScanId: scanId,
                        expectedGeneration: generation
                    )
                }
            )
        }
    }

    @MainActor
    func synchronizePaywallPresentation(isRequested: Bool) {
        synchronizeShellPresentation(.paywall, isRequested: isRequested)
    }

    @MainActor
    func synchronizeInsightChatPresentation(isRequested: Bool) {
        guard isRequested else {
            cancelOrDismissShellPresentation { presentation in
                if case .chat = presentation { true } else { false }
            }
            return
        }
        guard let scanId = selectedInsightChatScanId,
              let generation = selectedInsightChatGeneration else {
            viewModel.state.isInsightChatSheetPresented = false
            return
        }
        synchronizeShellPresentation(
            .chat(scanId: scanId, generation: generation),
            isRequested: true
        )
    }

    @MainActor
    func synchronizeExploreOnboardingPresentation(isRequested: Bool) {
        guard isRequested else {
            cancelOrDismissShellPresentation { presentation in
                if case .exploreOnboarding = presentation { true } else { false }
            }
            return
        }
        guard let scanId = viewModel.state.exploreOnboardingPresentationScanId,
              let generation = viewModel.state.exploreOnboardingPresentationGeneration else {
            clearExploreOnboardingRequest()
            return
        }
        synchronizeShellPresentation(
            .exploreOnboarding(scanId: scanId, generation: generation),
            isRequested: true
        )
    }

    @MainActor
    func synchronizeExplorePresentation(isRequested: Bool) {
        guard isRequested else {
            cancelOrDismissShellPresentation { presentation in
                if case .explore = presentation { true } else { false }
            }
            return
        }
        guard let scanId = viewModel.state.explorePresentationScanId,
              let generation = viewModel.state.explorePresentationGeneration else {
            clearExploreRequestPayload()
            return
        }
        synchronizeShellPresentation(
            .explore(scanId: scanId, generation: generation),
            isRequested: true
        )
    }

    @MainActor
    func synchronizeShellPresentation(
        _ presentation: InsightShellPresentation,
        isRequested: Bool
    ) {
        guard isRequested else {
            cancelOrDismissShellPresentation { $0.id == presentation.id }
            return
        }
        guard requestShellPresentation(presentation) else {
            clearShellPresentationRequest(presentation, releasePayload: true)
            return
        }
    }

    @MainActor
    @discardableResult
    func requestShellPresentation(_ presentation: InsightShellPresentation) -> Bool {
        guard isShellPresentationValid(presentation) else { return false }
        if activeShellPresentation?.id == presentation.id ||
            pendingShellPresentation?.id == presentation.id {
            return true
        }
        if activeShellPresentation == nil, dismissedShellPresentation == nil {
            activeShellPresentation = presentation
            return true
        }
        guard pendingShellPresentation == nil else { return false }
        pendingShellPresentation = presentation
        return true
    }

    @MainActor
    func cancelOrDismissShellPresentation(
        matching predicate: (InsightShellPresentation) -> Bool
    ) {
        if let activeShellPresentation, predicate(activeShellPresentation) {
            dismissActiveShellPresentation()
        }
        if let pendingShellPresentation, predicate(pendingShellPresentation) {
            self.pendingShellPresentation = nil
            clearShellPresentationRequest(
                pendingShellPresentation,
                releasePayload: true
            )
        }
    }

    @MainActor
    func dismissActiveShellPresentation() {
        guard let presentation = activeShellPresentation else { return }
        dismissedShellPresentation = presentation
        activeShellPresentation = nil
        clearShellPresentationRequest(presentation, releasePayload: false)
    }

    @MainActor
    func handleShellPresentationDismissed() {
        guard let presentation = dismissedShellPresentation else { return }
        dismissedShellPresentation = nil

        switch presentation {
        case .chat:
            resumePendingInsightChatDismissalAction()
        case .explore:
            handleExploreSheetDismissed()
        case .paywall, .fieldTripAuthor, .exploreOnboarding:
            break
        }

        guard let pendingShellPresentation else { return }
        self.pendingShellPresentation = nil
        guard isShellPresentationValid(pendingShellPresentation) else {
            clearShellPresentationRequest(
                pendingShellPresentation,
                releasePayload: true
            )
            return
        }
        activeShellPresentation = pendingShellPresentation
    }

    @MainActor
    func isShellPresentationValid(_ presentation: InsightShellPresentation) -> Bool {
        switch presentation {
        case .paywall:
            viewModel.state.showPaywall
        case .fieldTripAuthor:
            true
        case .chat(let scanId, let generation):
            viewModel.state.isInsightChatSheetPresented &&
                selectedInsightChatScanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame &&
                selectedInsightChatGeneration == generation &&
                inferenceEngine.speciesData?.scanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame &&
                viewModel.isPresentingLocalRecord(
                    scanId: scanId,
                    generation: generation
                )
        case .exploreOnboarding(let scanId, let generation):
            viewModel.state.showExploreOnboarding &&
                viewModel.state.exploreOnboardingPresentationScanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame &&
                viewModel.state.exploreOnboardingPresentationGeneration == generation &&
                viewModel.isPresentingLocalRecord(
                    scanId: scanId,
                    generation: generation
                )
        case .explore(let scanId, let generation):
            allowsExplorePresentation &&
                viewModel.state.showExploreSheet &&
                viewModel.state.explorePresentationScanId?
                    .caseInsensitiveCompare(scanId) == .orderedSame &&
                viewModel.state.explorePresentationGeneration == generation &&
                viewModel.isPresentingLocalRecord(
                    scanId: scanId,
                    generation: generation
                )
        }
    }

    @MainActor
    func clearShellPresentationRequest(
        _ presentation: InsightShellPresentation,
        releasePayload: Bool
    ) {
        switch presentation {
        case .paywall:
            viewModel.state.showPaywall = false
        case .fieldTripAuthor:
            break
        case .chat(let scanId, let generation):
            guard selectedInsightChatScanId?
                .caseInsensitiveCompare(scanId) == .orderedSame,
                  selectedInsightChatGeneration == generation else {
                return
            }
            viewModel.state.isInsightChatSheetPresented = false
            if releasePayload {
                selectedInsightChatScanId = nil
                selectedInsightChatGeneration = nil
                pendingInsightChatDismissalAction = nil
            }
        case .exploreOnboarding(let scanId, let generation):
            guard viewModel.state.exploreOnboardingPresentationScanId?
                .caseInsensitiveCompare(scanId) == .orderedSame,
                  viewModel.state.exploreOnboardingPresentationGeneration == generation else {
                return
            }
            clearExploreOnboardingRequest()
        case .explore(let scanId, let generation):
            guard viewModel.state.explorePresentationScanId?
                .caseInsensitiveCompare(scanId) == .orderedSame,
                  viewModel.state.explorePresentationGeneration == generation else {
                return
            }
            viewModel.state.showExploreSheet = false
            if releasePayload {
                clearExploreRequestPayload()
            }
        }
    }

    @MainActor
    func clearExploreOnboardingRequest() {
        viewModel.state.showExploreOnboarding = false
        viewModel.state.exploreOnboardingPresentationScanId = nil
        viewModel.state.exploreOnboardingPresentationGeneration = nil
    }

    @MainActor
    func clearExploreRequestPayload() {
        viewModel.state.showExploreSheet = false
        viewModel.state.explorePresentationTarget = .automatic
        viewModel.state.explorePresentationScanId = nil
        viewModel.state.explorePresentationGeneration = nil
        pendingOwnedPostInsightScanId = nil
    }

    @MainActor
    func handleExploreSheetDismissed() {
        guard !viewModel.state.showExploreSheet else { return }
        if let pendingScanId = pendingOwnedPostInsightScanId {
            pendingOwnedPostInsightScanId = nil
            if viewModel.bindPresentedScan(
                scanId: pendingScanId,
                modelContext: modelContext,
                inferenceEngine: inferenceEngine
            ) {
                presentedScanId = pendingScanId
            }
            viewModel.state.explorePresentationTarget = .automatic
            viewModel.state.explorePresentationScanId = nil
            viewModel.state.explorePresentationGeneration = nil
            return
        }
        if let scanId = viewModel.state.explorePresentationScanId,
           let generation = viewModel.state.explorePresentationGeneration,
           viewModel.isPresentingLocalRecord(
               scanId: scanId,
               generation: generation
           ) {
            viewModel.refreshSharedExploreStateFromLocalCache(scanId: scanId)
            Task {
                await viewModel.refreshSharedExploreStateFromServer(
                    expectedScanId: scanId,
                    expectedGeneration: generation,
                    modelContext: modelContext
                )
            }
        }
        viewModel.state.explorePresentationTarget = .automatic
        viewModel.state.explorePresentationScanId = nil
        viewModel.state.explorePresentationGeneration = nil
    }

    func stageOwnedPostInsightAfterExploreDismissal(scanId: String) -> Bool {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard (try? modelContext.fetch(descriptor).first) != nil else { return false }
        pendingOwnedPostInsightScanId = scanId
        return true
    }

    @MainActor
    func dismissExploreOnboarding(
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        guard viewModel.state.exploreOnboardingPresentationScanId?
            .caseInsensitiveCompare(expectedScanId) == .orderedSame,
              viewModel.state.exploreOnboardingPresentationGeneration ==
                expectedGeneration else {
            return
        }
        viewModel.state.showExploreOnboarding = false
        viewModel.state.exploreOnboardingPresentationScanId = nil
        viewModel.state.exploreOnboardingPresentationGeneration = nil
    }

    @MainActor
    var exploreSheetInitialPostId: String? {
        switch viewModel.state.explorePresentationTarget {
        case .automatic, .post:
            return viewModel.state.sharedExplorePostId
        case .communityRequest:
            return nil
        }
    }

    @MainActor
    var exploreSheetInitialCommunityRequestId: String? {
        switch viewModel.state.explorePresentationTarget {
        case .automatic, .communityRequest:
            return viewModel.state.sharedCommunityIdentificationRequestId
        case .post:
            return nil
        }
    }

    func appendInsightChatTextToFieldNotes(
        _ text: String,
        kind _: InsightChatFieldNotesAppendKind,
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              viewModel.isPresentingLocalRecord(
                  scanId: expectedScanId,
                  generation: expectedGeneration
              ) else {
            return
        }

        let title = "Field chat summary"

        let dateText = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .medium,
            timeStyle: .short
        )
        let section = "\(title) - \(dateText)\n\(trimmed)"
        let existing = viewModel.fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = existing.isEmpty ? section : "\(existing)\n\n\(section)"

        viewModel.updateFieldNotes(
            combined,
            expectedScanId: expectedScanId,
            expectedGeneration: expectedGeneration,
            modelContext: modelContext
        )
        viewModel.state.dismissedFieldNotesCardScanId = nil
    }

    func openIdentificationConcernCandidatesFromChat(
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        guard viewModel.isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ) else {
            return
        }
        pendingInsightChatDismissalAction = .reviewAlternatives(
            scanId: expectedScanId,
            generation: expectedGeneration
        )
        viewModel.state.isInsightChatSheetPresented = false
    }

    func startReanalysisFromInsightChat(
        expectedScanId: String,
        expectedGeneration: UInt64
    ) {
        guard viewModel.isPresentingLocalRecord(
            scanId: expectedScanId,
            generation: expectedGeneration
        ) else {
            return
        }
        guard RevenueCatManager.shared.isProActive else {
            pendingInsightChatDismissalAction = .showPaywall(
                scanId: expectedScanId,
                generation: expectedGeneration
            )
            viewModel.state.isInsightChatSheetPresented = false
            return
        }

        pendingInsightChatDismissalAction = .reanalyze(
            scanId: expectedScanId,
            generation: expectedGeneration
        )
        viewModel.state.isInsightChatSheetPresented = false
    }

    func resumePendingInsightChatDismissalAction() {
        let action = pendingInsightChatDismissalAction
        pendingInsightChatDismissalAction = nil
        selectedInsightChatScanId = nil
        selectedInsightChatGeneration = nil

        guard let action else { return }
        let context = action.context
        guard viewModel.isPresentingLocalRecord(
            scanId: context.scanId,
            generation: context.generation
        ) else {
            return
        }

        switch action {
        case .reviewAlternatives:
            guard viewModel.canReviewIdentificationConcernCandidates else { return }
            viewModel.presentCandidateSwipe(
                source: .identificationConcern,
                expectedScanId: context.scanId,
                expectedGeneration: context.generation
            )
        case .reanalyze:
            HapticManager.shared.triggerSelectionPulse()
            AppDIContainer.shared.appRouteCoordinator.request(
                .refinement(
                    scanId: context.scanId,
                    initialDescription: viewModel.shareableFieldNotes,
                    entryPoint: .standard
                ),
                source: .internalUserAction
            )
        case .showPaywall:
            viewModel.state.showPaywall = true
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
            .background(alignment: .topLeading) {
                InsightFirstRenderProbe(
                    scanId: inferenceEngine.speciesData?.scanId,
                    onRendered: { scanId in
                        inferenceEngine.recordFirstRenderedFrame(scanId: scanId)
                    }
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
            }
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
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedFieldTripOverviewDestination != nil },
                    set: { if !$0 { selectedFieldTripOverviewDestination = nil } }
                )
            ) {
                if let selectedFieldTripOverviewDestination {
                    fieldTripOverviewDetail(for: selectedFieldTripOverviewDestination)
                }
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedFieldTripPublicationRoute != nil },
                    set: { if !$0 { selectedFieldTripPublicationRoute = nil } }
                )
            ) {
                if let selectedFieldTripPublicationRoute {
                    FieldTripPublicationDetailView(
                        publicationId: selectedFieldTripPublicationRoute.publicationId
                    )
                }
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { selectedFieldTripChallengeEntryRoute != nil },
                    set: { if !$0 { selectedFieldTripChallengeEntryRoute = nil } }
                )
            ) {
                if let selectedFieldTripChallengeEntryRoute {
                    FieldTripChallengeEntryDetailView(
                        entryId: selectedFieldTripChallengeEntryRoute.entryId
                    )
                }
            }
            .onAppear {
                // Reset stale @State properties from previous presentations natively.
                viewModel.reset()

                // Seed both references immediately so viewModel computed properties
                // resolve on the first frame rather than waiting for InsightContentView's onAppear.
                viewModel.bindSettings(appSettings)
                viewModel.inferenceEngine = inferenceEngine
                var didPromoteQueuedScan = false
                if let queuedScan {
                    didPromoteQueuedScan =
                        viewModel.bindQueuedPresentationPreferringCompletedRecord(
                            queuedScan,
                            modelContext: modelContext,
                            inferenceEngine: inferenceEngine
                        )
                } else if let scanId = inferenceEngine.queuedPresentationScanId {
                    // A transport failure can win before the sheet's first
                    // onAppear. Bind the durable row synchronously when it is
                    // already visible in this context; the keyed task below
                    // retries brief SwiftData propagation misses.
                    _ = viewModel.bindQueuedPresentationIfAvailable(
                        scanId: scanId,
                        modelContext: modelContext
                    )
                }
                queuedCompletionHandoffGeneration &+= 1
                queuedCompletionHandoffScanId = nil
                selectedInsightChatScanId = nil
                selectedInsightChatGeneration = nil
                pendingDeletionScanId = nil
                pendingDeletionGeneration = nil
                pendingNewCollectionScanId = nil
                pendingNewCollectionGeneration = nil
                if let presentedScanId {
                    viewModel.bindPresentedScan(
                        scanId: presentedScanId,
                        modelContext: modelContext,
                        inferenceEngine: inferenceEngine
                    )
                }
                if !didPromoteQueuedScan {
                    viewModel.evaluateVoiceOverAndCelebration(inferenceEngine: inferenceEngine)
                }
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
            .task(id: viewModel.resultToolbarRevealKey) {
                // A fresh analysis can finish before its LocalScanRecord reaches this
                // ModelContext. Include completed-record availability in the task key so
                // that late binding schedules the Share and Field chat reveal without a
                // close/reopen cycle. The generation also distinguishes same-ID handoffs.
                let revealKey = viewModel.resultToolbarRevealKey
                guard viewModel.queuedContext == nil,
                      let scanId = revealKey.scanId else { return }
                do {
                    try await Task.sleep(nanoseconds: 350_000_000)
                } catch {
                    return
                }
                withAnimation(.easeIn(duration: 0.2)) {
                    _ = viewModel.revealBottomBarTools(
                        expectedScanId: scanId,
                        expectedGeneration: revealKey.presentationGeneration
                    )
                }
            }
            .task(id: inferenceEngine.queuedPresentationScanId) {
                guard let scanId = inferenceEngine.queuedPresentationScanId else {
                    return
                }

                // Enqueue happens before the live request, so this normally
                // succeeds on the first pass. Keep the handoff tolerant of a
                // short cross-context propagation delay without ever binding a
                // stale scan after a newer presentation replaces it.
                for _ in 0..<8 {
                    guard !Task.isCancelled,
                          inferenceEngine.queuedPresentationScanId?
                            .caseInsensitiveCompare(scanId) == .orderedSame else {
                        return
                    }
                    if viewModel.bindQueuedPresentationIfAvailable(
                        scanId: scanId,
                        modelContext: modelContext
                    ) {
                        return
                    }
                    do {
                        try await Task.sleep(for: .milliseconds(100))
                    } catch {
                        return
                    }
                }
            }
            .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
                // Queued scan path: the engine's isProcessing reflects a different pipeline.
                // Skip celebration, haptics, and record-marking — they don't apply here.
                guard viewModel.queuedContext == nil else { return }
                viewModel.evaluateProcessingCompletion(isStillProcessing: isStillProcessing, inferenceEngine: inferenceEngine, modelContext: modelContext)
            }
            .onChange(of: inferenceEngine.speciesData?.scanId) { _, newScanId in
                guard viewModel.state.isInsightChatSheetPresented,
                      let selectedInsightChatScanId,
                      newScanId?.caseInsensitiveCompare(selectedInsightChatScanId) != .orderedSame else {
                    return
                }
                viewModel.state.isInsightChatSheetPresented = false
                self.selectedInsightChatScanId = nil
                self.selectedInsightChatGeneration = nil
            }
            .onChange(of: queuedScan) { oldScan, newScan in
                if let newScan {
                    let changedSubject =
                        oldScan?.id.caseInsensitiveCompare(newScan.id) != .orderedSame
                    viewModel.bindQueuedPresentationPreferringCompletedRecord(
                        newScan,
                        modelContext: modelContext,
                        inferenceEngine: inferenceEngine
                    )
                    guard changedSubject else { return }

                    queuedCompletionHandoffGeneration &+= 1
                    queuedCompletionHandoffScanId = nil
                    selectedInsightChatScanId = nil
                    selectedInsightChatGeneration = nil
                    pendingDeletionScanId = nil
                    pendingDeletionGeneration = nil
                    pendingNewCollectionScanId = nil
                    pendingNewCollectionGeneration = nil
                    return
                }

                // The parent LibraryView proactively loaded the InferenceEngine
                // and cleared the property to signal the handoff is complete.
                // Release the queued context to transition cleanly to the results.
                if let oldScan {
                    viewModel.releaseQueuedPresentation(expectedScanId: oldScan.id)
                }
            }
            .task(id: queuedScan?.id) {
                guard let scanId = queuedScan?.id else { return }
                await attemptQueuedCompletionHandoff(scanId: scanId)
            }
            .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
                guard case .scanLibraryChanged = event else { return }
                guard let scanId = viewModel.queuedContext?.id else { return }
                Task { await attemptQueuedCompletionHandoff(scanId: scanId) }
            }
            .task(id: viewModel.scanBoundActionGeneration) {
                // The persistent ID is unchanged by a queued-to-completed handoff.
                // Re-sync against presentation identity so the completed record's
                // Field Notes state becomes available without reopening the sheet.
                viewModel.syncFieldNotesFromCurrentScan(modelContext: modelContext)
            }
            .task(id: fieldTripContributionLoadKey) {
                let scanId = fieldTripContributionLoadKey.scanId
                let generation = viewModel.scanBoundActionGeneration
                await viewModel.loadFieldTripScanContributions(
                    scanId: scanId,
                    expectedGeneration: generation
                )
            }
            .onReceive(AppDIContainer.shared.appEventPublisher.publisher) { event in
                guard case .fieldTripScanContributionsInvalidated(let scanId) = event,
                      scanId == viewModel.persistentScanId else { return }
                let generation = viewModel.scanBoundActionGeneration
                Task {
                    await viewModel.loadFieldTripScanContributions(
                        scanId: scanId,
                        expectedGeneration: generation
                    )
                }
            }
            .task(id: viewModel.audioBoostEligibleScanId) {
                guard let scanId = viewModel.audioBoostEligibleScanId else {
                    viewModel.state.isAudioBoostEnabled = false
                    viewModel.state.audioBoostActionToken = nil
                    return
                }
                viewModel.state.isAudioBoostEnabled = InsightAudioBoostPreferenceStore().isEnabled(for: scanId)
                if viewModel.state.isAudioBoostEnabled {
                    AppTelemetry.trackInsightAudioBoost(event: "restored")
                }
            }
            .onChange(of: viewModel.state.isAudioBoostEnabled) { _, enabled in
                guard let scanId = viewModel.audioBoostEligibleScanId else { return }
                InsightAudioBoostPreferenceStore().setEnabled(enabled, for: scanId)
            }
            .task(id: inferenceEngine.speciesData?.scanId) {
                // Queued scans have no speciesData — skip the record fetch and name load.
                guard viewModel.queuedContext == nil else { return }
                if let scanId = inferenceEngine.speciesData?.scanId {
                    // Loop up to 5 times (2.5s max) to allow SwiftData background stores to propagate to the @MainActor context.
                    for _ in 0..<5 {
                        guard !Task.isCancelled,
                              inferenceEngine.speciesData?.scanId?
                                .caseInsensitiveCompare(scanId) == .orderedSame else {
                            return
                        }
                        if viewModel.fetchLocalRecord(for: scanId, modelContext: modelContext) {
                            break
                        }
                        do {
                            try await Task.sleep(nanoseconds: 500_000_000)
                        } catch {
                            return
                        }
                    }
                }
                // Load user's preferred display name for this species so resolvedHeaderTitle reflects it.
                guard !Task.isCancelled,
                      let currentScanId = inferenceEngine.speciesData?.scanId,
                      viewModel.presentedLocalRecordScanId?
                        .caseInsensitiveCompare(currentScanId) == .orderedSame else {
                    return
                }
                if let scientificName = inferenceEngine.speciesData?.scientificName {
                    viewModel.loadPreferredCommonName(for: scientificName, modelContext: modelContext)
                }
                await viewModel.refreshSharedExploreStateFromServer(modelContext: modelContext)
            }
    }

    private func dismissEmbeddedInsight() {
        isPresented = false
        dismiss()
    }
    
    @ViewBuilder
    var mainContentStack: some View {
        InsightContentView(
            viewModel: viewModel,
            queuedScan: queuedScan,
            onOpenFieldTripOverview: openFieldTripOverview
        )
            .merianSystemFeedback(
                toast: $viewModel.state.toastMessage,
                toastAction: toastActionBinding
            )
            .ignoresSafeArea(edges: .top)
    }

    private func openFieldTripOverview(_ destination: InsightFieldTripOverviewDestination) {
        if presentationStyle.isEmbedded, let onOpenFieldTripOverview {
            onOpenFieldTripOverview(destination)
            return
        }

        selectedFieldTripOverviewDestination = destination
    }

    @ViewBuilder
    private func fieldTripOverviewDetail(
        for destination: InsightFieldTripOverviewDestination
    ) -> some View {
        switch destination {
        case .standardOuting(let templateId):
            FieldTripTemplateDetailView(
                templateId: templateId,
                focusedChecklistItemId: nil,
                onOpenCompletedScan: openFieldTripCompletedScan,
                onOpenPublication: { publicationId in
                    selectedFieldTripPublicationRoute = FieldTripPublicationRoute(
                        publicationId: publicationId
                    )
                },
                onOpenAuthorProfile: openFieldTripAuthorProfile
            )
        case .event(let challengeId):
            FieldTripChallengeDetailView(
                challengeId: challengeId,
                onOpenEntry: { entryId in
                    selectedFieldTripChallengeEntryRoute = FieldTripChallengeEntryRoute(
                        entryId: entryId
                    )
                },
                onOpenAuthorProfile: openFieldTripChallengeAuthorProfile
            )
        }
    }

    private func openFieldTripCompletedScan(_ scanId: String) {
        guard viewModel.bindPresentedScan(
            scanId: scanId,
            modelContext: modelContext,
            inferenceEngine: inferenceEngine
        ) else {
            HapticManager.shared.triggerErrorThump()
            viewModel.state.toastMessage = .warning(
                "This scan is not available on this device."
            )
            return
        }

        HapticManager.shared.triggerSelectionPulse()
        presentedScanId = scanId
        selectedFieldTripOverviewDestination = nil
    }

    private func openFieldTripAuthorProfile(_ publication: FieldTripRecentPublication) {
        let route = ExploreAuthorProfileRoute(
            authorUserId: publication.authorUserId,
            authorName: publication.authorName,
            authorUsername: publication.authorUsername,
            authorAvatarUrl: publication.authorAvatarUrl
        )
        guard requestShellPresentation(.fieldTripAuthor(route)) else { return }
        HapticManager.shared.triggerSelectionPulse()
    }

    private func openFieldTripChallengeAuthorProfile(_ entry: FieldTripChallengeEntry) {
        let route = ExploreAuthorProfileRoute(
            authorUserId: entry.authorUserId,
            authorName: entry.authorName,
            authorUsername: entry.authorUsername,
            authorAvatarUrl: entry.authorAvatarUrl
        )
        guard requestShellPresentation(.fieldTripAuthor(route)) else { return }
        HapticManager.shared.triggerSelectionPulse()
    }

    @MainActor
    private var toastActionBinding: Binding<(() -> Void)?> {
        Binding(
            get: {
                guard let action = viewModel.toastAction else { return nil }
                guard !allowsExplorePresentation,
                      viewModel.state.toastMessage?.action?.id == .viewCommunityRequest,
                      let requestId = viewModel.state.sharedCommunityIdentificationRequestId,
                      let scanId = viewModel.presentedLocalRecordScanId
                else {
                    return action
                }
                let generation = viewModel.scanBoundActionGeneration

                return {
                    guard viewModel.isPresentingLocalRecord(
                        scanId: scanId,
                        generation: generation
                    ),
                          viewModel.state.sharedCommunityIdentificationRequestId?
                            .caseInsensitiveCompare(requestId) == .orderedSame else {
                        return
                    }
                    if let onOpenCommunityIdentificationRequest {
                        onOpenCommunityIdentificationRequest(requestId)
                    } else {
                        AppDIContainer.shared.appRouteCoordinator.request(
                            .communityIdentification(requestId: requestId),
                            source: .internalUserAction
                        )
                    }
                }
            },
            set: { viewModel.toastAction = $0 }
        )
    }

    @MainActor
    private func attemptQueuedCompletionHandoff(scanId: String) async {
        if queuedCompletionHandoffScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame {
            return
        }
        queuedCompletionHandoffGeneration &+= 1
        let generation = queuedCompletionHandoffGeneration
        queuedCompletionHandoffScanId = scanId
        defer {
            if queuedCompletionHandoffGeneration == generation {
                queuedCompletionHandoffScanId = nil
            }
        }

        for attempt in 0..<8 {
            let isCurrentQueuedScan = viewModel.queuedContext?.id
                .caseInsensitiveCompare(scanId) == .orderedSame
            guard queuedCompletionHandoffGeneration == generation,
                  isCurrentQueuedScan else {
                return
            }
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
            "InsightSheetView.attemptQueuedCompletionHandoff: no completed local record visible scanId=\(scanId, privacy: .private)"
        )
    }
}

private struct InsightFirstRenderProbe: UIViewRepresentable {
    let scanId: String?
    let onRendered: @MainActor (String) -> Void

    func makeUIView(context: Context) -> InsightFirstRenderProbeView {
        let view = InsightFirstRenderProbeView()
        view.configure(scanId: scanId, onRendered: onRendered)
        return view
    }

    func updateUIView(_ uiView: InsightFirstRenderProbeView, context: Context) {
        uiView.configure(scanId: scanId, onRendered: onRendered)
    }
}

private final class InsightFirstRenderProbeView: UIView {
    private var scanId: String?
    private var reportedScanId: String?
    private var onRendered: (@MainActor (String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        scanId: String?,
        onRendered: @escaping @MainActor (String) -> Void
    ) {
        self.onRendered = onRendered
        guard self.scanId != scanId else { return }
        self.scanId = scanId
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard window != nil,
              let scanId,
              reportedScanId != scanId else { return }
        reportedScanId = scanId
        onRendered?(scanId)
    }
}
