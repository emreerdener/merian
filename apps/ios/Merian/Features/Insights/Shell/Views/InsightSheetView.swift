import SwiftData
import SwiftUI

struct InsightSheetView: View {
    // MARK: - Dependencies
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    @Environment(OfflineQueueManager.self) var offlineQueueManager
    @Environment(AppSettings.self) var appSettings
    @Environment(\.modelContext) var modelContext
    @Environment(\.dismiss) var dismiss

    @Binding var isPresented: Bool
    var queuedScan: QueuedScanContext?
    var initialScanId: String?
    var allowsExplorePresentation: Bool
    var presentationStyle: InsightPresentationStyle
    var onOpenCommunityIdentificationRequest: ((String) -> Void)?
    var onOpenFieldTripOverview: ((InsightFieldTripOverviewDestination) -> Void)?
    let dependencies: InsightShellDependencies

    // MARK: - State
    @State var viewModel: InsightSheetViewModel
    @State var chatViewModel = InsightChatViewModel()
    @State var fieldTripExploreViewModel = ExploreFeedViewModel()
    @State var queuedCompletionHandoffScanId: String?
    @State var queuedCompletionHandoffGeneration: UInt64 = 0
    @State var presentedScanId: String?
    @State var selectedInsightChatScanId: String?
    @State var selectedInsightChatGeneration: UInt64?
    @State var pendingInsightChatDismissalAction: InsightChatDismissalAction?
    @State var pendingDeletionScanId: String?
    @State var pendingDeletionGeneration: UInt64?
    @State var pendingNewCollectionScanId: String?
    @State var pendingNewCollectionGeneration: UInt64?
    @State var selectedFieldTripOverviewDestination: InsightFieldTripOverviewDestination?
    @State var selectedFieldTripPublicationRoute: FieldTripPublicationRoute?
    @State var selectedFieldTripChallengeEntryRoute: FieldTripChallengeEntryRoute?
    @State var activeShellPresentation: InsightShellPresentation?
    @State var dismissedShellPresentation: InsightShellPresentation?
    @State var pendingShellPresentation: InsightShellPresentation?
    @State var pendingOwnedPostInsightScanId: String?

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
        onOpenFieldTripOverview: ((InsightFieldTripOverviewDestination) -> Void)? = nil,
        dependencies: InsightShellDependencies? = nil
    ) {
        let dependencies = dependencies ?? .live
        _isPresented = isPresented
        self.queuedScan = queuedScan
        self.initialScanId = initialScanId
        self.allowsExplorePresentation = allowsExplorePresentation
        self.presentationStyle = presentationStyle
        self.onOpenCommunityIdentificationRequest = onOpenCommunityIdentificationRequest
        self.onOpenFieldTripOverview = onOpenFieldTripOverview
        self.dependencies = dependencies
        _presentedScanId = State(initialValue: initialScanId)
        _viewModel = State(
            initialValue: InsightSheetViewModel(
                queuedContext: queuedScan,
                inferenceEngine: inferenceEngine,
                dependencies: dependencies
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

    // MARK: - View
    var body: some View {
        presentationRoot
        .accessibilityIdentifier("InsightSheetView")
        .onChange(of: offlineQueueManager.isOnline, initial: true) { _, isOnline in
            chatViewModel.updateConnectivity(isOnline: isOnline)
        }
        .onChange(of: isPresented) { _, isNowPresented in
            guard isNowPresented else {
                viewModel.endPresentationSession()
                activeShellPresentation = nil
                pendingShellPresentation = nil
                return
            }
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
                    dismissInsightPresentation()
                } else if viewModel.eradicateCurrentScan(
                    expectedScanId: targetScanId,
                    expectedGeneration: targetGeneration,
                    modelContext: modelContext,
                    inferenceEngine: inferenceEngine
                ) {
                    dismissInsightPresentation()
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
