import SwiftData
import SwiftUI
import UIKit

struct InsightFieldTripContributionLoadKey: Equatable {
    let scanId: String?
    let isAuthenticated: Bool
    let accountId: String?
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
    @State private var queuedCompletionHandoffInFlight = false
    @State private var presentedScanId: String?
    @State private var selectedFieldTripOverviewDestination: InsightFieldTripOverviewDestination?
    @State private var selectedFieldTripPublicationRoute: FieldTripPublicationRoute?
    @State private var selectedFieldTripChallengeEntryRoute: FieldTripChallengeEntryRoute?
    @State private var selectedFieldTripAuthorRoute: ExploreAuthorProfileRoute?

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
    @Query(filter: #Predicate<ScanCollection> { !$0.isDeleted }, sort: \ScanCollection.createdAt, order: .reverse) var collections: [ScanCollection]

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
        .onChange(of: isPresented) { _, isNowPresented in
            guard isNowPresented else { return }
            presentedScanId = initialScanId
            selectedFieldTripOverviewDestination = nil
            selectedFieldTripPublicationRoute = nil
            selectedFieldTripChallengeEntryRoute = nil
            selectedFieldTripAuthorRoute = nil
        }
        
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
        .sheet(item: $selectedFieldTripAuthorRoute) { route in
            ExploreAuthorProfileSheet(
                viewModel: fieldTripExploreViewModel,
                route: route
            )
        }
        .sheet(isPresented: $viewModel.state.isInsightChatSheetPresented) {
            if let speciesData = inferenceEngine.speciesData,
               let scanId = speciesData.scanId {
	                InsightChatSheet(
	                    viewModel: chatViewModel,
	                    scanId: scanId,
	                    speciesData: speciesData,
	                    displayName: viewModel.resolvedHeaderTitle,
	                    timestamp: viewModel.activeRecordTimestamp,
	                    onToast: { message in
	                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
	                            viewModel.state.toastMessage = message
	                        }
	                    },
	                    onAppendToFieldNotes: { text, kind in
	                        appendInsightChatTextToFieldNotes(text, kind: kind)
	                    },
                        onReviewAlternatives: viewModel.canReviewIdentificationConcernCandidates ? {
                            openIdentificationConcernCandidatesFromChat()
                        } : nil,
                        onReanalyzeSpecies: viewModel.canReanalyze ? {
                            startReanalysisFromInsightChat()
                        } : nil,
	                    onClose: {
	                        viewModel.state.isInsightChatSheetPresented = false
	                    }
	                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
	                .onChange(of: chatViewModel.errorMessage) { _, errorMessage in
	                    if errorMessage == "Naturebook Pro is required." {
	                        viewModel.state.isInsightChatSheetPresented = false
	                        viewModel.state.showPaywall = true
	                        chatViewModel.errorMessage = nil
	                    }
	                }
                .onChange(of: chatViewModel.unavailableScanId) { _, unavailableScanId in
                    guard unavailableScanId == scanId else { return }
                    viewModel.state.isInsightChatSheetPresented = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        viewModel.state.toastMessage = chatViewModel.errorMessage
                            ?? "Field chat isn't available for this scan."
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
            viewModel.state.explorePresentationTarget = .automatic
        }) {
            ExploreView(
                initialPostId: exploreSheetInitialPostId,
                initialCommunityRequestId: exploreSheetInitialCommunityRequestId,
                allowsInsightPresentation: false,
                onOpenOwnedPostInsight: { scanId in
                    let didBind = viewModel.bindPresentedScan(
                        scanId: scanId,
                        modelContext: modelContext,
                        inferenceEngine: inferenceEngine
                    )
                    if didBind {
                        presentedScanId = scanId
                    }
                    return didBind
                }
            )
        }
    }
}

private extension InsightSheetView {
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
        kind _: InsightChatFieldNotesAppendKind
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let title = "Field chat summary"

        let dateText = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .medium,
            timeStyle: .short
        )
        let section = "\(title) - \(dateText)\n\(trimmed)"
        let existing = viewModel.fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = existing.isEmpty ? section : "\(existing)\n\n\(section)"

        viewModel.updateFieldNotes(combined, modelContext: modelContext)
        viewModel.state.dismissedFieldNotesCardScanId = nil
    }

    func openIdentificationConcernCandidatesFromChat() {
        viewModel.state.isInsightChatSheetPresented = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard viewModel.canReviewIdentificationConcernCandidates else { return }
            viewModel.presentCandidateSwipe(source: .identificationConcern)
        }
    }

    func startReanalysisFromInsightChat() {
        guard RevenueCatManager.shared.isProActive else {
            viewModel.state.isInsightChatSheetPresented = false
            viewModel.state.showPaywall = true
            return
        }

        guard let scanId = viewModel.activeLocalRecord?.id ?? viewModel.activeLocalRecordId else { return }
        viewModel.state.isInsightChatSheetPresented = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            HapticManager.shared.triggerSelectionPulse()
            AppEventPublisher.shared.send(.triggerRefinement(
                scanId: scanId,
                initialDescription: viewModel.shareableFieldNotes
            ))
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
                    if FieldTripEventsAvailability.isEnabled {
                        FieldTripChallengeEntryDetailView(
                            entryId: selectedFieldTripChallengeEntryRoute.entryId
                        )
                    } else {
                        fieldTripEventsUnavailableView
                    }
                }
            }
            .onAppear {
                // Reset stale @State properties from previous presentations natively.
                viewModel.reset()

                // Seed both references immediately so viewModel computed properties
                // resolve on the first frame rather than waiting for InsightContentView's onAppear.
                viewModel.bindSettings(appSettings)
                viewModel.inferenceEngine = inferenceEngine
                viewModel.queuedContext = queuedScan
                if let presentedScanId {
                    viewModel.bindPresentedScan(
                        scanId: presentedScanId,
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
            .task(id: fieldTripContributionLoadKey) {
                await viewModel.loadFieldTripScanContributions(scanId: viewModel.persistentScanId)
            }
            .onReceive(AppEventPublisher.shared.publisher) { event in
                guard case .fieldTripScanContributionsInvalidated(let scanId) = event,
                      scanId == viewModel.persistentScanId else { return }
                Task {
                    await viewModel.loadFieldTripScanContributions(scanId: scanId)
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
        InsightContentView(
            viewModel: viewModel,
            queuedScan: queuedScan,
            onOpenFieldTripOverview: openFieldTripOverview
        )
            .merianSystemFeedback(
                toastMessage: $viewModel.state.toastMessage,
                toastActionTitle: $viewModel.toastActionTitle,
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
            if FieldTripEventsAvailability.isEnabled {
                FieldTripChallengeDetailView(
                    challengeId: challengeId,
                    onOpenEntry: { entryId in
                        selectedFieldTripChallengeEntryRoute = FieldTripChallengeEntryRoute(
                            entryId: entryId
                        )
                    },
                    onOpenAuthorProfile: openFieldTripChallengeAuthorProfile
                )
            } else {
                fieldTripEventsUnavailableView
            }
        }
    }

    private var fieldTripEventsUnavailableView: some View {
        ContentUnavailableView(
            "Events aren’t available yet",
            systemImage: "calendar.badge.clock",
            description: Text("Field trip Events are still in preview.")
        )
    }

    private func openFieldTripCompletedScan(_ scanId: String) {
        guard viewModel.bindPresentedScan(
            scanId: scanId,
            modelContext: modelContext,
            inferenceEngine: inferenceEngine
        ) else {
            HapticManager.shared.triggerErrorThump()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                viewModel.state.toastMessage = "This scan is not available on this device."
            }
            return
        }

        HapticManager.shared.triggerSelectionPulse()
        presentedScanId = scanId
        selectedFieldTripOverviewDestination = nil
    }

    private func openFieldTripAuthorProfile(_ publication: FieldTripRecentPublication) {
        HapticManager.shared.triggerSelectionPulse()
        selectedFieldTripAuthorRoute = ExploreAuthorProfileRoute(
            authorUserId: publication.authorUserId,
            authorName: publication.authorName,
            authorUsername: publication.authorUsername,
            authorAvatarUrl: publication.authorAvatarUrl
        )
    }

    private func openFieldTripChallengeAuthorProfile(_ entry: FieldTripChallengeEntry) {
        HapticManager.shared.triggerSelectionPulse()
        selectedFieldTripAuthorRoute = ExploreAuthorProfileRoute(
            authorUserId: entry.authorUserId,
            authorName: entry.authorName,
            authorUsername: entry.authorUsername,
            authorAvatarUrl: entry.authorAvatarUrl
        )
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
