import SwiftData
import SwiftUI
import UIKit

struct CaptureWorkspaceView: View {
    // MARK: - Environment & Dependencies
    @Environment(CameraManager.self) private var cameraManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(ActiveCaptureGoalStore.self) private var activeCaptureGoalStore
    @Environment(AudioCaptureManager.self) private var audioCaptureManager
    @Environment(\.modelContext) private var modelContext

    // MARK: - View Model & State
    private let showsWhatsNewOnFreshLaunch: Bool
    @State private var viewModel: CaptureWorkspaceViewModel
    // Observe and control the same manager used by the session's live adapter.
    private var speechManager: SpeechManager { viewModel.diContainer.speechManager }

    @State private var coordinator = CaptureActionCoordinator()
    @State private var captureMode: CaptureMode
    private var observationContext: ObservationContext {
        get { viewModel.descriptionDraft }
        nonmutating set { viewModel.updateDescriptionDraft(newValue) }
    }
    private var descriptionBinding: Binding<ObservationContext> {
        let generation = viewModel.draftSession.generation
        return Binding(get: { viewModel.descriptionDraft }, set: {
            guard viewModel.draftSession.generation == generation else { return }
            viewModel.updateDescriptionDraft($0)
        })
    }
    @State private var describePromptViewModel = DescribePromptViewModel()
    @State private var isDescribeQuestionsSheetPresented = false
    @State private var isKeyboardVisible: Bool = false
    @State private var stagedToolbarHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var chromeLayout: CaptureChromeLayout {
        CaptureChromeLayout(toolbarHeight: viewModel.shouldPresentActiveScanToolbar ? stagedToolbarHeight : 0)
    }
    @State private var captureGoalIndicatorExpansionState:
        CaptureGoalIndicatorExpansionState = .collapsed

    // MARK: - Zoom Drag Lock
    @State private var isViewfinderVisible = false
    @State private var isVerticalZooming: Bool = false
    @State private var isToggleDragging: Bool = false

    // MARK: - Staged Description Sheet
    @State private var stagedDescriptionEditIndex: Int?
    @State private var stagedAudioReviewIndex: Int?
    @State private var stagedVideoReviewIndex: Int?
    @State private var showFeedbackSurvey = false
    @State private var hasEvaluatedFeedbackSurveyPrompt = false
    @State private var feedbackSurveyPromptPending = false
    @State private var feedbackSurveyPresentedProactively = false
    @State private var feedbackSurveyForegroundCompletionScanId: String?

    /// Dedicated scroll-position state for the pager. Decoupled from captureMode so that
    /// scrollPosition(id:) never writes captureMode directly — eliminating the "onChange(of:
    /// CaptureMode) tried to update multiple times per frame" warning that occurs when the
    /// ScrollView's UIKit pan fires its binding setter multiple times per frame during a
    /// simultaneous toggle drag. Two onChange handlers keep the two variables in sync:
    ///   scrollPageMode → captureMode  (user paging, guarded by !isToggleDragging)
    ///   captureMode    → scrollProxy.scrollTo  (programmatic, e.g. toggle tap/drag end)
    @State private var scrollPageMode: CaptureMode?

    /// Instantiates the CaptureWorkspaceView by immediately checking the injected settings
    /// to retrieve the user's preferred first tab (default view).
    /// This strictly sidesteps lifecycle events like `.onAppear`, which would
    /// improperly re-snap the UI to the primary tab every time the view remounts.
    @MainActor
    init(
        appSettings: AppSettings? = nil,
        opensExploreOnFreshLaunch: Bool = false,
        showsWhatsNewOnFreshLaunch: Bool = false,
        diContainer: AppDIContainer? = nil,
        reanalysisAccess: CaptureReanalysisAccess? = nil,
        dependencies: CaptureWorkspaceDependencies? = nil
    ) {
        self.showsWhatsNewOnFreshLaunch = showsWhatsNewOnFreshLaunch
        let raw = (appSettings ?? AppSettings.shared).captureModeOrderRaw
        let mode = CaptureMode.userOrder(from: raw).first ?? .visual
        _viewModel = State(initialValue: CaptureWorkspaceViewModel(
            diContainer: diContainer,
            reanalysisAccess: reanalysisAccess,
            dependencies: dependencies,
            initialActiveSheet: showsWhatsNewOnFreshLaunch
                ? .whatsNew : (opensExploreOnFreshLaunch ? .explore : nil),
            opensExploreAfterWhatsNew: showsWhatsNewOnFreshLaunch
                && opensExploreOnFreshLaunch
        ))
        _captureMode = State(initialValue: mode)
        _scrollPageMode = State(initialValue: mode)
    }

    private var activeCaptureGoalPresentation: ActiveCaptureGoalPresentation? {
        activeCaptureGoalStore.presentation
    }

    private var shouldShowCaptureGoalPresentation: Bool {
        ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: FeatureFlags.isEnabled(.fieldTrips),
            isUserVisible: appSettings.showsCaptureGoalProgress,
            isCaptureMode: captureMode == .visual || captureMode == .audio,
            hasPresentation: activeCaptureGoalPresentation != nil,
            stagedCaptureIsEmpty: viewModel.stagedCapture.isEmpty && !viewModel.hasInitialDraftLiability
                && !audioCaptureManager.isRecording,
            isRefining: viewModel.isReanalyzing,
            isVideoRecording: viewModel.isVideoRecording
        )
    }

    // MARK: - View Hierarchy
    var body: some View {
        ZStack {
            workspaceContent
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .allowsHitTesting(!viewModel.isFieldNotesOccupied && viewModel.mediaReviewPresentationID == nil)
                .accessibilityHidden(viewModel.isFieldNotesOccupied || viewModel.mediaReviewPresentationID != nil)
            if viewModel.mediaReviewPresentationID == nil, viewModel.shouldPresentCaptureToolbarHost {
                CaptureFieldNotesOverlay(workspace: viewModel,
                                         speechManager: speechManager, onNavigation: navigateNotesToolbar,
                                         onOpenNotes: editSharedNote) {
                    activeToolbar
                }
                .opacity(viewModel.isFieldNotesOccupied || !shouldHideBottomChrome ? 1 : 0)
                .allowsHitTesting(viewModel.isFieldNotesOccupied || !shouldHideBottomChrome)
            }
        }
            .onChange(of: viewModel.draftSession.generation) { _, _ in
                if let session = viewModel.fieldNotesSession,
                   session.draftGeneration != viewModel.draftSession.generation {
                    viewModel.invalidateFieldNotes(clearProgress: true)
                }
                viewModel.resumePendingFieldNotesIfPossible()
            }
            .onChange(of: viewModel.canOpenFieldNotes) { _, ready in
                if ready { viewModel.resumePendingFieldNotesIfPossible() }
            }
            .onChange(of: viewModel.stagedCapture.physicalItemCount) { old, new in
                if old > 0, new == 0 { viewModel.clearFieldNotesAfterFinalMediaRemoval() }
            }
            .environment(\.captureChromeLayout, chromeLayout)
            .onPreferenceChange(CaptureToolbarHeightKey.self) { height in
                guard !viewModel.isFieldNotesOccupied, height.isFinite,
                      abs(stagedToolbarHeight - height) > 0.5 else { return }
                stagedToolbarHeight = height
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: chromeLayout)
            .onChange(of: showsWhatsNewOnFreshLaunch) { _, isEligible in
                if !isEligible, viewModel.activeSheet == .whatsNew {
                    viewModel.dismissActivePresentation()
                }
            }
            .modifier(CaptureWorkspaceOrchestrationModifier(
                viewModel: viewModel,
                coordinator: coordinator,
                isViewfinderVisible: $isViewfinderVisible,
                captureMode: $captureMode,
                observationContext: descriptionBinding,
                describePromptViewModel: describePromptViewModel,
                isDescribeQuestionsSheetPresented: $isDescribeQuestionsSheetPresented,
                isKeyboardVisible: $isKeyboardVisible,
                captureGoalIndicatorExpansionState: $captureGoalIndicatorExpansionState,
                stagedDescriptionEditIndex: $stagedDescriptionEditIndex,
                stagedAudioReviewIndex: $stagedAudioReviewIndex,
                stagedVideoReviewIndex: $stagedVideoReviewIndex,
                showFeedbackSurvey: $showFeedbackSurvey,
                hasEvaluatedFeedbackSurveyPrompt: $hasEvaluatedFeedbackSurveyPrompt,
                feedbackSurveyPromptPending: $feedbackSurveyPromptPending,
                feedbackSurveyPresentedProactively: $feedbackSurveyPresentedProactively,
                feedbackSurveyForegroundCompletionScanId:
                    $feedbackSurveyForegroundCompletionScanId,
                preferredFieldTripGoal: preferredFieldTripGoal
            ))
    }

    private var workspaceContent: some View {
        let orderedModes = CaptureMode.userOrder(from: appSettings.captureModeOrderRaw)
        let shouldHideBottomChrome =
            (isKeyboardVisible && captureMode == .describe)
            || viewModel.shouldSuppressCaptureChromeForCrop

        return ZStack {
                // Paged capture mode switcher.
                // CameraPreviewView lives inside the visual page so the outer horizontal UIScrollView
                // naturally defers vertical pan gestures to the inner camera pan recognizer
                // (zoom), while claiming horizontal ones (paging).
                // GeometryReader captures the true full-screen dimensions (after the outer
                // ZStack's .ignoresSafeArea() expands it) and hands them to each page via
                // explicit .frame(), bypassing any ambiguity in containerRelativeFrame's
                // safe-area-vs-full-screen reference resolution.
                GeometryReader { proxy in
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 0) {
                                ForEach(orderedModes, id: \.self) { mode in
                                    switch mode {
                                    case .visual:
                                        // MARK: Visual page — Camera
                                        VisualCaptureView(
                                            viewModel: viewModel,
                                            isCameraVisible: isViewfinderVisible,
                                            isVerticalZooming: $isVerticalZooming
                                        )
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .clipped()
                                        .id(CaptureMode.visual)

                                    case .audio:
                                        // MARK: Audio page — Recording
                                        AudioRecordingView(
                                            presentation: .live(
                                                audioCaptureManager:
                                                    audioCaptureManager,
                                                audioHintsEnabled:
                                                    appSettings.audioHintsEnabled
                                            ),
                                            showsIdlePrompt: viewModel.canUseCaptureControls(in: .audio),
                                            dependencies: .live(
                                                audioCaptureManager:
                                                    audioCaptureManager
                                            )
                                        )
                                            .frame(width: proxy.size.width, height: proxy.size.height)
                                            .clipped()
                                            .id(CaptureMode.audio)

                                    case .describe:
                                        EmptyView() // Historical value; never a selectable workspace.
                                    }
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .transparentTopToolbar()
                        .accessibilityIdentifier("CaptureWorkspacePager")
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $scrollPageMode)
                        .scrollDisabled(isVerticalZooming || isToggleDragging || viewModel.areCaptureActionsBlocked)
                        .scrollDismissesKeyboard(.interactively)
                        .background(ScrollBounceDisabler())
                        .onChange(of: appSettings.captureModeOrderRaw, initial: true) { _, raw in
                            let decoded = CaptureMode.userOrder(from: raw)
                            let healedRaw = decoded.map(\.rawValue).joined(separator: ",")
                            if raw != healedRaw {
                                appSettings.captureModeOrderRaw = healedRaw
                            }
                            // Re-anchor the ScrollView securely onto the active capture mode
                            // whenever the physical sequence changes underneath it.
                            DispatchQueue.main.async {
                                scrollProxy.scrollTo(captureMode, anchor: .center)
                            }
                        }
                        // Pager → captureMode: when the user swipes to a new page, sync
                        // captureMode. Guarded by !isToggleDragging so simultaneous toggle
                        // drag events that pan the scroll don't write captureMode mid-drag.
                        .onChange(of: scrollPageMode) { _, newPage in
                            if newPage != .describe {
                                dismissCaptureKeyboardAndRestoreChrome()
                            }
                            guard let newPage, newPage != captureMode, !isToggleDragging else { return }
                            viewModel.triggerSelectionFeedback(
                                source: "capture.modePager"
                            )
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                captureMode = newPage
                            }
                        }
                        // captureMode → pager: when the toggle commits a mode (tap or drag end),
                        // programmatically scroll the pager to match.
                        .onChange(of: captureMode) { _, newMode in
                            if newMode != .describe {
                                dismissCaptureKeyboardAndRestoreChrome()
                            }
                            guard newMode != scrollPageMode else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                scrollPageMode = newMode
                            }
                        }
                        .onAppear {
                            // Measure the composing zone: the open area between the mode toggle
                            // (top overlay, 16pt padding + 64pt height) and the capture button row.
                            // Crop framing keeps a 16pt margin above the control row,
                            // including clearance for an expanded staging tray.
                            // proxy uses the full-screen frame (.ignoresSafeArea on the GeometryReader)
                            // so safe-area insets must be accounted for explicitly.
                            updateComposingZoneVerticalCenter(from: proxy)
                        }
                        .onChange(of: chromeLayout) { _, _ in
                            updateComposingZoneVerticalCenter(from: proxy)
                        }
                        .onChange(of: proxy.size) { _, _ in
                            updateComposingZoneVerticalCenter(from: proxy)
                        }
                    }
                }
                .ignoresSafeArea()

                // MARK: Fixed Overlay — Mode Toggle / Capture Goal (top)
                if viewModel.shouldShowMediaModeToggle {
                    GeometryReader { overlayProxy in
                        VStack(spacing: CaptureGoalIndicatorLayoutPolicy.rowSpacing) {
                            MediaModeToggle(
                                activeMode: $captureMode,
                                isDragging: $isToggleDragging,
                                orderedModes: orderedModes,
                                onModeChange: {
                                    viewModel.triggerSelectionFeedback(
                                        source: "capture.modeSelector"
                                    )
                                }
                            )
                            .disabled(viewModel.areCaptureActionsBlocked)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .leading) {
                                if viewModel.shouldPresentActiveScanToolbar {
                                    CaptureStagingCancelButton { viewModel.requestDraftDiscard() }
                                        .disabled(viewModel.isDraftMutationLocked && !viewModel.canRetryHistoryWorkspace && !viewModel.canDiscardInitialDraft)
                                        .padding(.leading, 20)
                                }
                            }

                            if shouldShowCaptureGoalPresentation,
                               let presentation = activeCaptureGoalPresentation {
                                CaptureGoalIndicator(
                                    presentation: presentation,
                                    expansionState: $captureGoalIndicatorExpansionState,
                                    onOpen: { viewModel.openCaptureGoal($0) },
                                    onNext: { activeCaptureGoalStore.selectNext() },
                                    onPrevious: { activeCaptureGoalStore.selectPrevious() },
                                    onSelectionFeedback: {
                                        viewModel.triggerSelectionFeedback(
                                            source: $0
                                        )
                                    },
                                    onOpenFeedback: {
                                        viewModel.triggerSheetFeedback(source: $0)
                                    }
                                )
                                .padding(
                                    .leading,
                                    captureGoalIndicatorExpansionState.isExpanded
                                        ? CaptureGoalIndicatorLayoutPolicy.expandedHorizontalMargin
                                        : CaptureGoalIndicatorLayoutPolicy.compactTrailingMargin(
                                            containerWidth: overlayProxy.size.width
                                        )
                                )
                                .padding(
                                    .trailing,
                                    CaptureGoalIndicatorLayoutPolicy.expandedHorizontalMargin
                                )
                                .offset(
                                    y: CaptureGoalIndicatorLayoutPolicy.verticalOffset(
                                        isExpanded: captureGoalIndicatorExpansionState.isExpanded
                                    )
                                )
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 16)
                        .opacity(viewModel.offlineToastMessage != nil ? 0 : 1)
                        .animation(
                            .spring(response: 0.35, dampingFraction: 0.8),
                            value: viewModel.shouldShowMediaModeToggle
                        )
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // MARK: Fixed Overlay — Capture Controls (bottom, independent of toolbar)
                // Preserve the standard offset unless staging needs additional clearance.
                if viewModel.canUseCaptureControls(in: captureMode) {
                    CaptureControlBar(
                        viewModel: viewModel,
                        captureMode: captureMode,
                        observationContext: descriptionBinding,
                        isSuppressed: shouldHideBottomChrome,
                        coordinator: coordinator
                    )
                    .disabled(viewModel.areCaptureActionsBlocked)
                }

                // MARK: Fixed Overlay — Navigation / scan toolbar (bottom, independent of capture bar)
                VStack {
                    Spacer()

                    if !viewModel.shouldPresentActiveScanToolbar {
                        MainTabBar(
                            isExploreOpen: $viewModel.activeSheet.mapped(to: .explore),
                            isScansOpen: $viewModel.activeSheet.mapped(to: .scans),
                            isUserProfileOpen: $viewModel.activeSheet.mapped(to: .profile),
                            dependencies: viewModel.dependencies.navigation
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(
                    reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8),
                    value: viewModel.shouldPresentActiveScanToolbar
                )
                .opacity(shouldHideBottomChrome ? 0 : 1)
                .allowsHitTesting(!shouldHideBottomChrome)
        } // ZStack
        .alert(!viewModel.isReanalyzing ? "Discard observation?" : "Discard reanalysis?",
               isPresented: Binding(get: { viewModel.mediaReviewPresentationID == nil
                                        && viewModel.discardConfirmationGeneration != nil },
                                    set: { if !$0, viewModel.mediaReviewPresentationID == nil {
                                        viewModel.discardConfirmationGeneration = nil
                                    } }),
               presenting: viewModel.discardConfirmationGeneration) { generation in
            Button("Keep editing", role: .cancel) { viewModel.discardConfirmationGeneration = nil }
            Button("Discard", role: .destructive) {
                guard generation == viewModel.draftSession.generation,
                      !viewModel.isQueueingStagedCapture, !viewModel.isCheckingScanAdmission else { return }
                coordinator.isDictationRequested = false
                speechManager.stopDictation()
                audioCaptureManager.cancelRecording()
                audioCaptureManager.discardPending()
                _ = viewModel.confirmDraftDiscard(generation: generation)
            }
        } message: { _ in
            Text(viewModel.isReanalyzing
                 ? "Your added media and details will be removed. The original observation will be kept."
                 : "All added photos, recordings, and details will be removed.")
        }
    }

    private var activeToolbar: some View {
        ActiveScanToolbar(
            stagedCapture: viewModel.stagedCapture,
            isRefining: viewModel.isReanalyzing,
            stagedCaptureLimit: viewModel.stagedCaptureLimit,
            isSubmissionReady: viewModel.canSubmitDraft,
            isMutationLocked: viewModel.isDraftMutationLocked || viewModel.fieldNotesSession?.isSubmitting == true,
            isNotesPresented: viewModel.isFieldNotesOccupied,
            allowsFrozenRequestActions: viewModel.canRetryHistoryWorkspace || viewModel.canRetryInitialDraft || viewModel.canRecoverInitialDraft,
            onAddMore: viewModel.isFieldNotesOccupied ? { navigateNotesToolbar(.addMore) } : nil,
            onNoteTap: editSharedNote,
            onUpgradeTap: {
                if viewModel.isFieldNotesOccupied { navigateNotesToolbar(.addMore) } else { viewModel.presentStagedMediaUpgradePaywall() }
            },
            selectedPhotoItems: $viewModel.selectedPhotoItems,
            onRequestPhotoPickerPresentation: { selectionCount in
                await viewModel.requestPhotoPickerEntryAdmission(
                    maximumSelectionCount: selectionCount
                )
            },
            onThumbnailTap: { index in
                guard viewModel.stagedCapture.images.indices.contains(index) else { return }
                navigateNotesToolbar(.selectMedia("img_\(viewModel.stagedCapture.images[index].original.id)"))
            },
            onCancel: { viewModel.requestDraftDiscard() },
            onSubmit: {
                submitActiveStagedCapture()
            },
            onDescriptionTap: { index in
                guard viewModel.stagedCapture.observationContexts.indices.contains(index) else { return }
                navigateNotesToolbar(.historicalDescription(viewModel.stagedCapture.observationContexts[index].id))
            },
            onAudioTap: { index in
                guard viewModel.stagedCapture.audios.indices.contains(index) else { return }
                navigateNotesToolbar(.selectMedia("audio_\(viewModel.stagedCapture.audios[index].id)"))
            },
            onVideoTap: { index in
                guard viewModel.stagedCapture.videos.indices.contains(index) else { return }
                navigateNotesToolbar(.selectMedia("video_\(viewModel.stagedCapture.videos[index].id)"))
            },
            dependencies: viewModel.dependencies.stagingToolbar
        )
    }

    private func navigateNotesToolbar(_ action: CapturePhotoReviewAction) {
        if viewModel.isFieldNotesOccupied {
            viewModel.navigateFromFieldNotes(action)
            return
        }
        guard !viewModel.areCaptureActionsBlocked else { return }
        switch action {
        case .selectMedia(let nodeID): _ = viewModel.presentMediaReview(nodeID: nodeID)
        case .addMore: captureMode = .visual
        case .historicalDescription(let id):
            guard let index = viewModel.stagedCapture.observationContexts.firstIndex(where: { $0.id == id }) else { return }
            coordinator.isDictationRequested = false
            speechManager.stopDictation()
            if viewModel.isReanalyzing, !viewModel.stagedCapture.observationContexts[index].isRefinementSupplement {
                viewModel.isFeaturePresentationAwaitingDismissal = true
                stagedDescriptionEditIndex = index
            } else { editSharedNote() }
        case .fieldNotes: editSharedNote()
        case .identify: break
        }
    }

    private func editSharedNote() {
        if let session = viewModel.fieldNotesSession {
            viewModel.closeFieldNotes(sessionID: session.id)
        } else {
            guard stagedAudioReviewIndex == nil, stagedVideoReviewIndex == nil,
                  stagedDescriptionEditIndex == nil, !isDescribeQuestionsSheetPresented,
                  !showFeedbackSurvey else { return }
            _ = viewModel.openFieldNotes()
        }
    }

    private func dismissCaptureKeyboardAndRestoreChrome() {
        CaptureWorkspaceKeyboardService.dismissKeyboard()
        restoreBottomChrome(animated: true)
    }

    private func submitActiveStagedCapture() {
        CaptureWorkspaceKeyboardService.dismissKeyboard()
        let session = viewModel.fieldNotesSession
        if let session {
            guard viewModel.acceptsFieldNotesWrite(session), !session.isSubmitting else { return }
            session.isSubmitting = true
            session.errorMessage = nil
        }
        Task { @MainActor in
            defer { session?.isSubmitting = false }
            if let session {
                let finalized = await session.input.finishDictation {
                    session.isDictationRequested = false
                }
                guard viewModel.acceptsFieldNotesWrite(session) else { return }
                guard finalized else {
                    session.errorMessage = "Dictation could not finish. Your notes are kept. Review them before identifying."
                    return
                }
            }
            var draft = observationContext
            guard viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft) else { return }
            coordinator.isDictationRequested = false
            observationContext = draft
            await viewModel.submitStagedCapture(
                modelContext: modelContext,
                preferredGoal: preferredFieldTripGoal
            )
            cameraManager.resetZoom()
        }
    }

    private var preferredFieldTripGoal: FieldTripPreferredGoal? {
        CaptureGoalPreferencePolicy.preferredGoal(
            goalsEnabled: FeatureFlags.isEnabled(.fieldTrips),
            isUserVisible: appSettings.showsCaptureGoalProgress,
            isVisualMode: captureMode == .visual,
            isRefining: viewModel.isReanalyzing,
            selectedGoal: activeCaptureGoalStore.selectedGoal
        )
    }

    private func restoreBottomChrome(animated: Bool) {
        CaptureWorkspacePresentationBindings.restoreBottomChrome(
            isKeyboardVisible: $isKeyboardVisible,
            animated: animated
        )
    }

    private func updateComposingZoneVerticalCenter(from proxy: GeometryProxy) {
        guard proxy.size.height.isFinite, proxy.size.height > 0 else { return }

        let toggleBottom = proxy.safeAreaInsets.top
            + 16
            + CaptureModeSelectorStyle.controlHeight
        let captureButtonTop = proxy.size.height
            - chromeLayout.reservedHeight
            - 16
        let verticalCenter = ((toggleBottom + captureButtonTop) / 2) / proxy.size.height
        guard verticalCenter.isFinite else { return }
        guard abs(viewModel.composingZoneVerticalCenter - verticalCenter) > 0.001 else { return }

        DispatchQueue.main.async {
            guard abs(viewModel.composingZoneVerticalCenter - verticalCenter) > 0.001 else { return }
            viewModel.composingZoneVerticalCenter = verticalCenter
        }
    }

}
