import SwiftData
import SwiftUI

extension InsightSheetView {
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

}
