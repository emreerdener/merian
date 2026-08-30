import SwiftData
import SwiftUI
import UIKit

struct CaptureWorkspaceView: View {
    // MARK: - Environment & Dependencies
    @Environment(CameraManager.self) private var cameraManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(ActiveCaptureGoalStore.self) private var activeCaptureGoalStore
    @Environment(SpeechManager.self) private var speechManager
    @Environment(AudioCaptureManager.self) private var audioCaptureManager
    @Environment(\.modelContext) private var modelContext

    // MARK: - View Model & State
    @State private var viewModel: CaptureWorkspaceViewModel

    @State private var coordinator = CaptureActionCoordinator()
    @State private var captureMode: CaptureMode
    @State private var observationContext = ObservationContext()
    @State private var describePromptViewModel = DescribePromptViewModel()
    @State private var isDescribeQuestionsSheetPresented = false
    @State private var isKeyboardVisible: Bool = false
    @State private var captureGoalIndicatorExpansionState:
        CaptureGoalIndicatorExpansionState = .collapsed

    // MARK: - Zoom Drag Lock
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
        opensExploreOnFreshLaunch: Bool = false
    ) {
        let raw = (appSettings ?? AppSettings.shared).captureModeOrderRaw
        let mode = CaptureMode.userOrder(from: raw).first ?? .visual
        _viewModel = State(initialValue: CaptureWorkspaceViewModel(
            initialActiveSheet: opensExploreOnFreshLaunch ? .explore : nil
        ))
        _captureMode = State(initialValue: mode)
        _scrollPageMode = State(initialValue: mode)
    }

    private var describePageIdentity: String {
        if viewModel.baseRefinementContext != nil {
            return "reanalysis-\(viewModel.refinementSubjectId ?? "unknown")"
        }
        return "standard"
    }

    private var activeCaptureGoalPresentation: ActiveCaptureGoalPresentation? {
        activeCaptureGoalStore.presentation
    }

    private var shouldShowCaptureGoalPresentation: Bool {
        ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: FeatureFlags.isEnabled(.fieldTrips),
            isUserVisible: appSettings.showsCaptureGoalProgress,
            isVisualMode: captureMode == .visual,
            hasPresentation: activeCaptureGoalPresentation != nil,
            stagedCaptureIsEmpty: viewModel.stagedCapture.isEmpty,
            isRefining: viewModel.baseRefinementContext != nil,
            isVideoRecording: viewModel.isVideoRecording
        )
    }

    // MARK: - View Hierarchy
    var body: some View {
        workspaceContent
            .modifier(CaptureWorkspaceOrchestrationModifier(
                viewModel: viewModel,
                captureMode: $captureMode,
                observationContext: $observationContext,
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
                                            dependencies: .live(
                                                audioCaptureManager:
                                                    audioCaptureManager
                                            )
                                        )
                                            .frame(width: proxy.size.width, height: proxy.size.height)
                                            .clipped()
                                            .id(CaptureMode.audio)

                                    case .describe:
                                        // MARK: Describe page — Text input
                                        DescribeInputView(
                                            promptFlow: viewModel.describePromptFlow,
                                            context: $observationContext,
                                            promptViewModel: describePromptViewModel
                                        )
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .clipped()
                                        .id(describePageIdentity)
                                        .id(CaptureMode.describe)
                                    }
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                        .scrollPosition(id: $scrollPageMode)
                        .scrollDisabled(isVerticalZooming || isToggleDragging)
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
                            // Crop framing intentionally keeps a 16pt margin above the control
                            // bar's 124pt bottom inset; update this geometry if the fixed
                            // CaptureControlBarLayout dimensions change.
                            // proxy uses the full-screen frame (.ignoresSafeArea on the GeometryReader)
                            // so safe-area insets must be accounted for explicitly.
                            updateComposingZoneVerticalCenter(from: proxy)
                        }
                    }
                }
                .ignoresSafeArea()

                DescribeInputLifecycleObserver(
                    captureMode: captureMode,
                    promptFlow: viewModel.describePromptFlow,
                    context: $observationContext,
                    promptViewModel: describePromptViewModel,
                    isQuestionsSheetPresented: $isDescribeQuestionsSheetPresented,
                    coordinator: coordinator,
                    speechManager: speechManager
                )
                .frame(width: 0, height: 0)

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
                                    CaptureGoalIndicatorLayoutPolicy.expandedHorizontalMargin
                                )
                                .padding(
                                    .trailing,
                                    captureGoalIndicatorExpansionState.isExpanded
                                        ? CaptureGoalIndicatorLayoutPolicy.expandedHorizontalMargin
                                        : CaptureGoalIndicatorLayoutPolicy.compactTrailingMargin(
                                            containerWidth: overlayProxy.size.width
                                        )
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
                // Pinned to a fixed absolute bottom offset so toolbar height changes
                // (MainTabBar vs ActiveScanToolbar) never shift the shutter row.
                if viewModel.hasAvailableStagedCaptureSlot {
                    CaptureControlBar(
                        viewModel: viewModel,
                        captureMode: captureMode,
                        observationContext: $observationContext,
                        isSuppressed: shouldHideBottomChrome,
                        coordinator: coordinator
                    )
                }

                // MARK: Fixed Overlay — Navigation / scan toolbar (bottom, independent of capture bar)
                VStack {
                    Spacer()

                    if !viewModel.shouldPresentActiveScanToolbar {
                        MainTabBar(
                            isExploreOpen: $viewModel.activeSheet.mapped(to: .explore),
                            isScansOpen: $viewModel.activeSheet.mapped(to: .scans),
                            isUserProfileOpen: $viewModel.activeSheet.mapped(to: .profile)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        ActiveScanToolbar(
                            stagedCapture: viewModel.stagedCapture,
                            isRefining: viewModel.baseRefinementContext != nil,
                            stagedCaptureLimit: viewModel.stagedCaptureLimit,
                            selectedPhotoItems: $viewModel.selectedPhotoItems,
                            onRequestPhotoPickerPresentation: { selectionCount in
                                await viewModel.requestImageImportEntryAdmission(
                                    prospectiveImageCount: selectionCount
                                )
                            },
                            onThumbnailTap: { index in viewModel.presentCrop(for: index) },
                            onCancel: {
                                let isCancelingRefinement = viewModel.baseRefinementContext != nil
                                viewModel.restoreRefinementInsightAfterCancellation()
                                viewModel.clearStagedCaptureAndCropState(discardStagedMediaFiles: true)
                                viewModel.cancelRefinementStaging()
                                if isCancelingRefinement {
                                    observationContext = ObservationContext()
                                }
                            },
                            onSubmit: {
                                submitActiveStagedCapture()
                            },
                            onDescriptionTap: { index in stagedDescriptionEditIndex = index },
                            onAudioTap: { index in stagedAudioReviewIndex = index },
                            onVideoTap: { index in stagedVideoReviewIndex = index }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(
                    .spring(response: 0.35, dampingFraction: 0.8),
                    value: viewModel.shouldPresentActiveScanToolbar
                )
                .opacity(shouldHideBottomChrome ? 0 : 1)
                .allowsHitTesting(!shouldHideBottomChrome)
        } // ZStack
    }

    private func dismissCaptureKeyboardAndRestoreChrome() {
        CaptureWorkspaceKeyboardService.dismissKeyboard()
        restoreBottomChrome(animated: true)
    }

    private func submitActiveStagedCapture() {
        CaptureWorkspaceKeyboardService.dismissKeyboard()
        Task { @MainActor in
            _ = viewModel.stagePendingDescribeDraftForActiveSubmission(
                observationContext
            )
            observationContext = ObservationContext()
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
            isRefining: viewModel.baseRefinementContext != nil,
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
            - CaptureControlBarLayout.reservedHeight
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
