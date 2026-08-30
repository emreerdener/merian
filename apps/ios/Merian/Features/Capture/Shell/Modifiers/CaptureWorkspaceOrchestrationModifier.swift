import Combine
import SwiftData
import SwiftUI

struct CaptureWorkspaceOrchestrationModifier: ViewModifier {
    @Environment(CameraManager.self) private var cameraManager
    @Environment(PhotoLibraryManager.self) private var photoLibraryManager
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(AudioCaptureManager.self) private var audioCaptureManager
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(UsageManager.self) private var usageManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Environment(SupabaseManager.self) private var supabaseManager
    @Environment(ActiveCaptureGoalStore.self) private var activeCaptureGoalStore
    @Environment(AppRouteCoordinator.self) private var appRouteCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(
        filter: #Predicate<LocalScanRecord> { $0.isBiological == true },
        sort: \LocalScanRecord.timestamp,
        order: .reverse
    ) private var messageShareCacheRecords: [LocalScanRecord]

    let viewModel: CaptureWorkspaceViewModel
    @Binding var captureMode: CaptureMode
    @Binding var observationContext: ObservationContext
    let describePromptViewModel: DescribePromptViewModel
    @Binding var isDescribeQuestionsSheetPresented: Bool
    @Binding var isKeyboardVisible: Bool
    @Binding var captureGoalIndicatorExpansionState:
        CaptureGoalIndicatorExpansionState
    @Binding var stagedDescriptionEditIndex: Int?
    @Binding var stagedAudioReviewIndex: Int?
    @Binding var stagedVideoReviewIndex: Int?
    @Binding var showFeedbackSurvey: Bool
    @Binding var hasEvaluatedFeedbackSurveyPrompt: Bool
    @Binding var feedbackSurveyPromptPending: Bool
    @Binding var feedbackSurveyPresentedProactively: Bool
    @Binding var feedbackSurveyForegroundCompletionScanId: String?
    let preferredFieldTripGoal: FieldTripPreferredGoal?

    func body(content: Content) -> some View {
        eventContent(content)
    }

    private var messageShareCacheSignature: String {
        viewModel.messageShareCacheSignature(
            records: messageShareCacheRecords,
            defaultGeoprivacy: profileViewModel.defaultGeoprivacy
        )
    }

    private var currentAccountId: String? {
        viewModel.captureGoalAccountId(
            for: supabaseManager.currentUser?.id
        )
    }

    private var isFeaturePresentationOccupied: Bool {
        stagedDescriptionEditIndex != nil
            || isDescribeQuestionsSheetPresented
            || stagedAudioReviewIndex != nil
            || stagedVideoReviewIndex != nil
            || showFeedbackSurvey
            || viewModel.imageToCrop != nil
    }

    private func lifecycleContent(_ content: Content) -> some View {
        content
            .modifier(CaptureWorkspacePresentationModifier(
                viewModel: viewModel,
                messageShareCacheRecords: messageShareCacheRecords,
                defaultGeoprivacy: profileViewModel.defaultGeoprivacy,
                canStartProScan: revenueCatManager.canStartProScan,
                messageShareCacheSignature: messageShareCacheSignature,
                feedbackPromptSignature: feedbackPromptSignature,
                observationContext: $observationContext,
                describePromptViewModel: describePromptViewModel,
                isDescribeQuestionsSheetPresented:
                    $isDescribeQuestionsSheetPresented,
                stagedDescriptionEditIndex: $stagedDescriptionEditIndex,
                stagedAudioReviewIndex: $stagedAudioReviewIndex,
                stagedVideoReviewIndex: $stagedVideoReviewIndex,
                showFeedbackSurvey: $showFeedbackSurvey,
                preferredFieldTripGoal: preferredFieldTripGoal,
                onArmFeedbackSurveyPrompt: armFeedbackSurveyPromptIfEligible,
                onFeedbackSurveyDismissal: handleFeedbackSurveyDismissal,
                onFeaturePresentationDismissed:
                    handleFeaturePresentationDismissed,
                onRootPresentationDismissed: handleRootPresentationDismissed
            ))
        .onAppear {
            #if DEBUG
            UITestSeedCoordinator.prepareStagedAudioReviewIfNeeded(
                viewModel: viewModel
            )
            #endif
            viewModel.updateNotificationSuppression()
            if captureMode == .visual,
               viewModel.activeSheet == nil,
               viewModel.imageToCrop == nil,
               scenePhase == .active {
                cameraManager.startSession()
            }
            photoLibraryManager.startObservingAndFetch()
            viewModel.validateEnvironmentContextPermissions()
            viewModel.startLiveEnvironmentContextTracking()
            viewModel.importPendingExternalImageIfPossible()
            activeCaptureGoalStore.activate(accountId: currentAccountId)
            if FeatureFlags.isEnabled(.fieldTrips) {
                Task {
                    await activeCaptureGoalStore.refreshIfStale(
                        accountId: currentAccountId
                    )
                }
            }
        }
        .onDisappear {
            viewModel.handleVisualCaptureInterruption()
            cameraManager.stopSession()
            audioCaptureManager.reset()
            viewModel.stopLiveEnvironmentContextTracking()
        }
        .onReceive(
            CaptureWorkspaceKeyboardService.willShowNotifications
                .receive(on: DispatchQueue.main)
        ) { notification in
            guard captureMode == .describe else {
                restoreBottomChrome(animated: false)
                return
            }
            guard isSoftwareKeyboardVisible(from: notification) else {
                restoreBottomChrome(animated: false)
                return
            }
            withAnimation(.easeOut(duration: 0.25)) { isKeyboardVisible = true }
        }
        .onReceive(
            CaptureWorkspaceKeyboardService.willHideNotifications
                .receive(on: DispatchQueue.main)
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) { isKeyboardVisible = false }
        }
        .onChange(of: viewModel.selectedPhotoItems) { _, newItems in
            viewModel.handlePhotoPickerSelection(newItems: newItems, modelContext: modelContext)
        }
        .onChange(of: viewModel.stagedCapture.images.count) { _, count in
            guard count == 1 else { return }
            guard viewModel.isAutomaticStagedSubmissionPending else { return }

            Task { @MainActor in
                await viewModel.submitStagedCapture(
                    modelContext: modelContext,
                    preferredGoal: preferredFieldTripGoal
                )
                cameraManager.resetZoom()
            }
        }
        .onChange(of: viewModel.stagedCapture.videos.count) { _, count in
            guard count == 1 else { return }
            guard viewModel.isAutomaticStagedSubmissionPending else { return }

            Task { @MainActor in
                await viewModel.submitStagedCapture(
                    modelContext: modelContext,
                    preferredGoal: preferredFieldTripGoal
                )
                cameraManager.resetZoom()
            }
        }
        .onChange(of: viewModel.imageToCrop != nil) { _, isCropPresented in
            handleCropPresentationChange(isCropPresented: isCropPresented)
        }
    }

    private func stateContent(_ content: Content) -> some View {
        lifecycleContent(content)
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(
                newPhase,
                captureMode: captureMode,
                cameraManager: cameraManager,
                audioCaptureManager: audioCaptureManager
            )
            if newPhase == .active {
                viewModel.importPendingExternalImageIfPossible()
                if FeatureFlags.isEnabled(.fieldTrips) {
                    Task {
                        await activeCaptureGoalStore.refreshIfStale(
                            accountId: currentAccountId
                        )
                    }
                }
            }
        }
        .onChange(of: captureMode) { _, newMode in
            captureGoalIndicatorExpansionState =
                captureGoalIndicatorExpansionState.preservingOnly(in: newMode)
            if newMode != .describe {
                dismissCaptureKeyboardAndRestoreChrome()
            }
            viewModel.handleCaptureModeChange(
                newMode,
                scenePhase: scenePhase,
                cameraManager: cameraManager,
                audioCaptureManager: audioCaptureManager
            )
            if newMode == .visual, FeatureFlags.isEnabled(.fieldTrips) {
                Task {
                    await activeCaptureGoalStore.refreshIfStale(
                        accountId: currentAccountId
                    )
                }
            }
        }

        .onChange(of: supabaseManager.currentUser?.id) { oldUserId, newUserId in
            guard viewModel.captureGoalAccountId(
                for: oldUserId
            ) != viewModel.captureGoalAccountId(
                for: newUserId
            ) else {
                return
            }
            captureGoalIndicatorExpansionState = .collapsed
            activeCaptureGoalStore.activate(accountId: currentAccountId)
            guard FeatureFlags.isEnabled(.fieldTrips) else { return }
            Task {
                await activeCaptureGoalStore.refreshIfStale(
                    accountId: currentAccountId
                )
            }
        }
        .onChange(of: appSettings.showsCaptureGoalProgress) { _, isVisible in
            captureGoalIndicatorExpansionState =
                captureGoalIndicatorExpansionState.preservingOnly(
                    whenVisible: isVisible
                )
        }

        .onChange(of: viewModel.activeSheet) { _, newSheet in
            viewModel.updateNotificationSuppression()

            if newSheet != nil {
                viewModel.handleVisualCaptureInterruption()
                cameraManager.stopSession()
            } else if captureMode == .visual,
                      viewModel.imageToCrop == nil,
                      !viewModel.isRootPresentationDismissing,
                      scenePhase == .active {
                // Strictly guard the un-pause with `scenePhase == .active`, ensuring the
                // startSession() hardware call can never fire indiscriminately during
                // backgrounding transitions when the UI naturally dismisses sheets.
                cameraManager.startSession()
            }

        }
        .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
            viewModel.handleInferenceProcessingChange(isStillProcessing: isStillProcessing)
        }
        .onChange(of: usageManager.showPaywall, initial: true) { _, isRequested in
            viewModel.handlePaywallPresentationRequest(isRequested: isRequested)
        }
        .onChange(of: isFeaturePresentationOccupied) { _, isOccupied in
            if isOccupied {
                viewModel.handleVisualCaptureInterruption()
                cameraManager.stopSession()
            }
        }
    }

    private func eventContent(_ content: Content) -> some View {
        stateContent(content)
        .task(id: appRouteCoordinator.nextRequestID) {
            viewModel.consumeNextAppRoute(
                isFeaturePresentationOccupied: isFeaturePresentationOccupied
            )
        }
        .onChange(of: appRouteCoordinator.accountGeneration) { _, _ in
            viewModel.handleRouteAccountGenerationChanged()
        }
        .onReceive(viewModel.appEvents) { event in
            switch event {
            case .fieldTripProgressInvalidated, .captureGoalContextInvalidated:
                guard FeatureFlags.isEnabled(.fieldTrips) else { break }
                Task {
                    await activeCaptureGoalStore.refresh(
                        accountId: currentAccountId,
                        force: true
                    )
                }
            case .foregroundBiologicalScanCompleted(let scanId):
                if !hasEvaluatedFeedbackSurveyPrompt {
                    feedbackSurveyForegroundCompletionScanId = scanId
                }
            case .exploreShareStateChanged:
                Task {
                    await MessageScanShareCacheWriter.refresh(
                        records: messageShareCacheRecords,
                        defaultGeoprivacy: profileViewModel.defaultGeoprivacy
                    )
                }
            default: break
            }
        }
        .onChange(of: viewModel.requestedCaptureMode) { _, requested in
            guard let requested else { return }
            captureMode = requested
            viewModel.requestedCaptureMode = nil
            observationContext = ObservationContext(
                freeText: viewModel.refinementInitialDescriptionDraft ?? ""
            )
            viewModel.refinementInitialDescriptionDraft = nil
        }
        .onChange(of: audioCaptureManager.isRecording) { _, isRecording in
            guard isRecording, !viewModel.stagedCapture.hasVisualMedia else { return }
            viewModel.prepareNonVisualCaptureContext()
        }
        .onChange(of: audioCaptureManager.audioFilePath) { _, fileName in
            guard let fileName else { return }

            let willStageOnly = viewModel.stagedCapture.hasVisualMedia
                || viewModel.isMultiCaptureFunctionallyEnabled
                || appSettings.requiresScanConfirmation
                || !viewModel.stagedCapture.observationContexts.isEmpty

            if willStageOnly {
                viewModel.stagedCapture.audios.append(StagedAudio(filePath: fileName))
                audioCaptureManager.reset()
            } else {
                Task { @MainActor in
                    let didSubmit = await viewModel.submitAudio(
                        audioFileName: fileName,
                        modelContext: modelContext
                    )
                    if didSubmit {
                        audioCaptureManager.reset()
                    } else {
                        audioCaptureManager.restoreSubmissionForReview()
                    }
                }
            }
        }
        .onPhysicalCameraShutter(
            isEnabled: viewModel.activeSheet == nil &&
                       viewModel.imageToCrop == nil &&
                       !viewModel.isStagingRefinement
        ) {
            viewModel.executeCapture()
        }
    }

    private func handleFeedbackSurveyDismissal() {
        guard feedbackSurveyPresentedProactively else { return }
        feedbackSurveyPresentedProactively = false
        if appSettings.feedbackSurveySubmittedCampaignId != FeedbackSurveyCampaign.currentId {
            appSettings.feedbackSurveyDismissedCampaignId = FeedbackSurveyCampaign.currentId
        }
    }

    private func handleFeaturePresentationDismissed() {
        viewModel.handleFeaturePresentationDismissed()
        presentPendingFeedbackSurveyIfReady()
        restoreCameraAfterPresentationIfPossible()
    }

    private func handleRootPresentationDismissed() {
        presentPendingFeedbackSurveyIfReady()
        restoreCameraAfterPresentationIfPossible()
    }

    private func restoreCameraAfterPresentationIfPossible() {
        guard captureMode == .visual,
              viewModel.activeSheet == nil,
              !isFeaturePresentationOccupied,
              appRouteCoordinator.inFlightRequest == nil,
              appRouteCoordinator.nextRequestID == nil,
              scenePhase == .active else { return }
        cameraManager.startSession()
    }

    private func handleCropPresentationChange(isCropPresented: Bool) {
        if isCropPresented {
            cameraManager.stopSession()
        }
    }

    private func isSoftwareKeyboardVisible(from notification: Notification) -> Bool {
        CaptureWorkspaceKeyboardService.isSoftwareKeyboardVisible(
            from: notification
        )
    }

    private func dismissCaptureKeyboardAndRestoreChrome() {
        CaptureWorkspaceKeyboardService.dismissKeyboard()
        restoreBottomChrome(animated: true)
    }

    private func restoreBottomChrome(animated: Bool) {
        CaptureWorkspacePresentationBindings.restoreBottomChrome(
            isKeyboardVisible: $isKeyboardVisible,
            animated: animated
        )
    }

    private var feedbackPromptSignature: String {
        [
            String(messageShareCacheRecords.count),
            String(appSettings.hasCompletedOnboarding),
            appSettings.feedbackSurveyDismissedCampaignId,
            appSettings.feedbackSurveySubmittedCampaignId,
            feedbackSurveyForegroundCompletionScanId ?? "",
            String(feedbackSurveyForegroundCompletionIsReflectedInHistory)
        ].joined(separator: "|")
    }

    private var feedbackSurveyForegroundCompletionIsReflectedInHistory: Bool {
        guard let scanId = feedbackSurveyForegroundCompletionScanId else {
            return false
        }
        return messageShareCacheRecords.contains {
            $0.id.caseInsensitiveCompare(scanId) == .orderedSame
        }
    }

    private func armFeedbackSurveyPromptIfEligible() {
        guard !hasEvaluatedFeedbackSurveyPrompt else { return }
        guard feedbackSurveyForegroundCompletionIsReflectedInHistory else {
            return
        }
        let shouldPrompt = FeedbackSurveyPromptPolicy.shouldPrompt(
            completedScanCount: messageShareCacheRecords.count,
            hasCompletedOnboarding: appSettings.hasCompletedOnboarding,
            hasForegroundBiologicalScanCompletion: true,
            dismissedCampaignId: appSettings.feedbackSurveyDismissedCampaignId,
            submittedCampaignId: appSettings.feedbackSurveySubmittedCampaignId
        )

        guard shouldPrompt else {
            feedbackSurveyForegroundCompletionScanId = nil
            return
        }

        hasEvaluatedFeedbackSurveyPrompt = true
        feedbackSurveyPromptPending = true
        presentPendingFeedbackSurveyIfReady()
        feedbackSurveyForegroundCompletionScanId = nil
    }

    private func presentPendingFeedbackSurveyIfReady() {
        guard feedbackSurveyPromptPending else { return }
        guard viewModel.activeSheet == nil else { return }
        guard !showFeedbackSurvey else { return }
        guard !isFeaturePresentationOccupied else { return }
        guard appRouteCoordinator.inFlightRequest == nil,
              appRouteCoordinator.nextRequestID == nil else { return }

        feedbackSurveyPromptPending = false
        feedbackSurveyPresentedProactively = true
        showFeedbackSurvey = true
    }
}
