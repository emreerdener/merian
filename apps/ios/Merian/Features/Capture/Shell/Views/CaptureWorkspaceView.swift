import AVFoundation
import AVKit
import PhotosUI
import SwiftData
import SwiftUI

enum ActiveCaptureGoalSwipeDirection: Equatable {
    case next
    case previous

    static func resolve(horizontal: CGFloat, vertical: CGFloat) -> Self? {
        guard abs(horizontal) > 36,
              abs(horizontal) > abs(vertical) * 1.25 else {
            return nil
        }
        return horizontal < 0 ? .next : .previous
    }
}

enum ActiveCaptureGoalPresentationPolicy {
    static func shouldShow(
        goalsEnabled: Bool,
        isUserVisible: Bool,
        isVisualMode: Bool,
        hasPresentation: Bool,
        stagedCaptureIsEmpty: Bool,
        isRefining: Bool,
        isVideoRecording: Bool
    ) -> Bool {
        goalsEnabled
            && isUserVisible
            && isVisualMode
            && hasPresentation
            && stagedCaptureIsEmpty
            && !isRefining
            && !isVideoRecording
    }
}

enum CaptureGoalPreferencePolicy {
    static func preferredGoal(
        goalsEnabled: Bool,
        isUserVisible: Bool,
        isVisualMode: Bool,
        isRefining: Bool,
        selectedGoal: CaptureGoal?
    ) -> FieldTripPreferredGoal? {
        guard goalsEnabled,
              isUserVisible,
              isVisualMode,
              !isRefining,
              let selectedGoal,
              case .fieldTrip(_, let checklistItemId) = selectedGoal.destination else {
            return nil
        }

        return FieldTripPreferredGoal(
            userFieldTripId: selectedGoal.source.id,
            itemId: checklistItemId
        )
    }
}

struct CaptureWorkspaceView: View {
    // MARK: - Environment & Dependencies
    @Environment(CameraManager.self) var cameraManager
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    @Environment(ViewfinderIntelligence.self) var vui
    @Environment(PhotoLibraryManager.self) var photoLibraryManager
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(AudioCaptureManager.self) var audioCaptureManager
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Environment(SupabaseManager.self) private var supabaseManager
    @Environment(ActiveCaptureGoalStore.self) private var activeCaptureGoalStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(
        filter: #Predicate<LocalScanRecord> { $0.isBiological == true },
        sort: \LocalScanRecord.timestamp,
        order: .reverse
    ) private var messageShareCacheRecords: [LocalScanRecord]

    // MARK: - View Model & State
    @State private var viewModel: CaptureWorkspaceViewModel

    @State private var coordinator = CaptureActionCoordinator()
    @State private var captureMode: CaptureMode
    @State private var observationContext = ObservationContext()
    @State private var describePromptManager = DescribePromptManager()
    @State private var isDescribeQuestionsSheetPresented = false
    @State private var isKeyboardVisible: Bool = false

    // MARK: - Zoom Drag Lock
    @State private var isVerticalZooming: Bool = false
    @State private var isToggleDragging: Bool = false

    // MARK: - Staged Description Sheet
    @State private var stagedDescriptionEditIndex: Int?
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

    private var messageShareCacheSignature: String {
        messageShareCacheRecords
            .prefix(MessageScanShareCacheConstants.maxRecordCount)
            .map { record in
                [
                    record.id,
                    String(record.timestamp.timeIntervalSinceReferenceDate),
                    record.commonName,
                    record.scientificName,
                    record.locationName ?? "",
                    record.coverImagePath ?? "",
                    record.capturedMediaSnapshot.imagePaths.joined(separator: ","),
                    record.fieldNotes ?? "",
                    ExploreShareStateStore.sharedPostId(for: record.id) ?? "",
                    profileViewModel.defaultGeoprivacy
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
    }

    private var currentAccountId: String? {
        supabaseManager.currentUser?.id.uuidString
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

    private var isStagedDescriptionSheetPresented: Binding<Bool> {
        Binding(
            get: { stagedDescriptionEditIndex != nil },
            set: { isPresented in
                if !isPresented {
                    stagedDescriptionEditIndex = nil
                }
            }
        )
    }

    private var offlineToastMessageBinding: Binding<String?> {
        Binding(
            get: { viewModel.offlineToastMessage },
            set: { viewModel.offlineToastMessage = $0 }
        )
    }

    private var isStagedVideoReviewPresented: Binding<Bool> {
        Binding(
            get: { stagedVideoReviewIndex != nil },
            set: { isPresented in
                if !isPresented {
                    stagedVideoReviewIndex = nil
                }
            }
        )
    }

    private var isCropSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.imageToCrop != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.imageToCrop = nil
                }
            }
        )
    }

    // MARK: - View Hierarchy
    var body: some View {
        workspaceEventContent
    }

    private var workspaceContent: some View {
        let orderedModes = CaptureMode.userOrder(from: appSettings.captureModeOrderRaw)
        let shouldHideBottomChrome = isKeyboardVisible && captureMode == .describe

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
                                        AudioRecordingView()
                                            .frame(width: proxy.size.width, height: proxy.size.height)
                                            .clipped()
                                            .id(CaptureMode.audio)

                                    case .describe:
                                        // MARK: Describe page — Text input
                                        DescribeInputView(
                                            promptFlow: viewModel.describePromptFlow,
                                            context: $observationContext,
                                            promptManager: describePromptManager
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
                            // (top overlay, 16pt padding + ~48pt height) and the capture button row.
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
                    promptManager: describePromptManager,
                    isQuestionsSheetPresented: $isDescribeQuestionsSheetPresented,
                    coordinator: coordinator
                )
                .frame(width: 0, height: 0)

                // MARK: Fixed Overlay — Mode Toggle (top)
                if viewModel.shouldShowMediaModeToggle {
                    VStack(spacing: 12) {
                        MediaModeToggle(
                            activeMode: $captureMode, 
                            isDragging: $isToggleDragging, 
                            orderedModes: orderedModes, 
                            onModeChange: {}
                        )

                        if shouldShowCaptureGoalPresentation,
                           let presentation = activeCaptureGoalPresentation {
                            CaptureGoalIndicator(
                                presentation: presentation,
                                onOpen: { viewModel.openCaptureGoal($0) },
                                onNext: { activeCaptureGoalStore.selectNext() },
                                onPrevious: { activeCaptureGoalStore.selectPrevious() }
                            )
                            .padding(.horizontal, 32)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        Spacer()
                    }
                    .padding(.top, 16)
                    .opacity(viewModel.offlineToastMessage != nil ? 0 : 1)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.shouldShowMediaModeToggle)
                }

                // MARK: Fixed Overlay — Capture Controls (bottom, independent of toolbar)
                // Pinned to a fixed absolute bottom offset so toolbar height changes
                // (MainTabBar vs ActiveScanToolbar) never shift the shutter row.
                if viewModel.hasAvailableStagedCaptureSlot {
                    CaptureControlBar(
                        viewModel: viewModel,
                        captureMode: captureMode,
                        observationContext: $observationContext,
                        isKeyboardVisible: shouldHideBottomChrome,
                        coordinator: coordinator
                    )
                }

                // MARK: Fixed Overlay — Navigation / scan toolbar (bottom, independent of capture bar)
                VStack {
                    Spacer()

                    if viewModel.stagedCapture.isEmpty && viewModel.baseRefinementContext == nil {
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
                            onThumbnailTap: { index in viewModel.presentCrop(for: index) },
                            onCancel: {
                                let isCancelingRefinement = viewModel.baseRefinementContext != nil
                                if let scanId = viewModel.baseRefinementContext?.scanId,
                                   let record = viewModel.fetchLocalScan(scanId: scanId) {
                                    viewModel.diContainer.inferenceEngine.load(from: record)
                                    viewModel.activeSheet = .insight
                                }
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
                            onVideoTap: { index in stagedVideoReviewIndex = index }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.stagedCapture.isEmpty)
                .opacity(shouldHideBottomChrome ? 0 : 1)
                .allowsHitTesting(!shouldHideBottomChrome)
        } // ZStack
    }

    private var workspacePresentedContent: some View {
        workspaceContent
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .merianSystemFeedback(
            toastMessage: offlineToastMessageBinding,
            toastAlignment: .top
        )
        .environment(\.composingCenter, viewModel.composingZoneVerticalCenter)
        .modifier(ExternalImageImportRetryModifier(
            viewModel: viewModel,
            stagedItemCount: viewModel.stagedCapture.totalItemCount,
            stagedCaptureLimit: viewModel.stagedCaptureLimit,
            canStartProScan: revenueCatManager.canStartProScan
        ))
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .task(id: messageShareCacheSignature) {
            await MessageScanShareCacheWriter.refresh(
                records: messageShareCacheRecords,
                defaultGeoprivacy: profileViewModel.defaultGeoprivacy
            )
        }
        .task(id: feedbackPromptSignature) {
            await armFeedbackSurveyPromptIfEligible()
        }
        .sheet(isPresented: isStagedDescriptionSheetPresented) {
            let selectedIndex = stagedDescriptionEditIndex ?? 0
            StagedDescriptionSheet(
                initialText: viewModel.stagedCapture.observationContexts.indices.contains(selectedIndex)
                    ? viewModel.stagedCapture.observationContexts[selectedIndex].context.freeText
                    : "",
                onSave: { newText in
                    guard viewModel.stagedCapture.observationContexts.indices.contains(selectedIndex) else { return }
                    let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        viewModel.stagedCapture.observationContexts.remove(at: selectedIndex)
                    } else {
                        var updatedContext = viewModel.stagedCapture.observationContexts[selectedIndex].context
                        updatedContext.freeText = trimmed
                        let addedAt = viewModel.stagedCapture.observationContexts[selectedIndex].addedAt
                        viewModel.stagedCapture.observationContexts[selectedIndex] = StagedObservationContext(
                            context: updatedContext,
                            addedAt: addedAt
                        )
                        stagedDescriptionEditIndex = nil
                    }
                },
                onRemove: {
                    guard viewModel.stagedCapture.observationContexts.indices.contains(selectedIndex) else { return }
                    viewModel.stagedCapture.observationContexts.remove(at: selectedIndex)
                    stagedDescriptionEditIndex = nil
                }
            )
        }
        .sheet(isPresented: $isDescribeQuestionsSheetPresented) {
            DescribeQuestionsSheet(
                promptManager: describePromptManager,
                hasInputs: !observationContext.freeText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty,
                onReset: {
                    HapticManager.shared.triggerMediumPulse()
                    observationContext.freeText = ""
                    describePromptManager.resetFunnel()
                    describePromptManager.activeQuestionIndex = 0
                    viewModel.offlineToastMessage = "Draft discarded"
                }
            )
        }
        .fullScreenCover(isPresented: isStagedVideoReviewPresented) {
            if let selectedIndex = stagedVideoReviewIndex,
               viewModel.stagedCapture.videos.indices.contains(selectedIndex) {
                StagedVideoPreviewModal(
                    video: viewModel.stagedCapture.videos[selectedIndex],
                    onRemove: {
                        viewModel.removeStagedVideo(at: selectedIndex)
                        stagedVideoReviewIndex = nil
                    }
                )
            }
        }
        .sheet(isPresented: $showFeedbackSurvey, onDismiss: handleFeedbackSurveyDismissal) {
            FeedbackSurveyView()
        }

        // MARK: - View Modifiers
        .cameraSheetRouter(viewModel: viewModel)
        .modifier(CropSheetModifier(
            isPresented: isCropSheetPresented,
            viewModel: viewModel,
            onRequiredCropReadyForSubmit: {
                viewModel.submitStagedCapture(
                    modelContext: modelContext,
                    preferredGoal: preferredFieldTripGoal
                )
                cameraManager.resetZoom()
            }
        ))
    }

    private var workspaceLifecycleContent: some View {
        workspacePresentedContent
        .onAppear {
            viewModel.updateNotificationSuppression()
            if captureMode == .visual,
               viewModel.activeSheet == nil,
               viewModel.imageToCrop == nil,
               scenePhase == .active {
                cameraManager.startSession()
            }
            photoLibraryManager.startObservingAndFetch()
            AppDIContainer.shared.environmentContextManager.validatePermissions()
            AppDIContainer.shared.environmentContextManager.startLiveLocationTracking()
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
            if viewModel.isVideoRecording {
                viewModel.stopVideoCapture()
            }
            cameraManager.stopSession()
            audioCaptureManager.reset()
            AppDIContainer.shared.environmentContextManager.stopLiveLocationTracking()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { isKeyboardVisible = false }
        }
        .onChange(of: viewModel.selectedPhotoItems) { _, newItems in
            viewModel.handlePhotoPickerSelection(newItems: newItems, modelContext: modelContext)
        }
        .onChange(of: viewModel.stagedCapture.images.count) { _, count in
            guard count == 1 else { return }
            guard viewModel.shouldAutoSubmitStagedCapture else { return }

            viewModel.submitStagedCapture(
                modelContext: modelContext,
                preferredGoal: preferredFieldTripGoal
            )
            cameraManager.resetZoom()
        }
        .onChange(of: viewModel.stagedCapture.videos.count) { _, count in
            guard count == 1 else { return }
            guard viewModel.shouldAutoSubmitStagedCapture else { return }

            viewModel.submitStagedCapture(
                modelContext: modelContext,
                preferredGoal: preferredFieldTripGoal
            )
            cameraManager.resetZoom()
        }
        .onChange(of: viewModel.imageToCrop != nil) { _, isCropPresented in
            handleCropPresentationChange(isCropPresented: isCropPresented)
        }
    }

    private var workspaceStateContent: some View {
        workspaceLifecycleContent
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

        .onChange(of: supabaseManager.currentUser?.id) { _, _ in
            activeCaptureGoalStore.activate(accountId: currentAccountId)
            guard FeatureFlags.isEnabled(.fieldTrips) else { return }
            Task {
                await activeCaptureGoalStore.refreshIfStale(
                    accountId: currentAccountId
                )
            }
        }

        .onChange(of: viewModel.activeSheet) { _, newSheet in
            viewModel.updateNotificationSuppression()

            if newSheet != nil {
                cameraManager.stopSession()
            } else if captureMode == .visual,
                      viewModel.imageToCrop == nil,
                      scenePhase == .active {
                // Strictly guard the un-pause with `scenePhase == .active`, ensuring the
                // startSession() hardware call can never fire indiscriminately during
                // backgrounding transitions when the UI naturally dismisses sheets.
                cameraManager.startSession()
            }

            if newSheet == nil {
                Task { await presentPendingFeedbackSurveyIfReady() }
            }
        }
        .onChange(of: inferenceEngine.isProcessing) { _, isStillProcessing in
            viewModel.handleInferenceProcessingChange(isStillProcessing: isStillProcessing)
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .devPreviewAnalyzing)) { _ in
            viewModel.activeSheet = .insight
        }
        #endif
    }

    private var workspaceEventContent: some View {
        workspaceStateContent
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .requestIdentifyNatureIntent, .requestOpenScanner:
                // Close the complete sheet stack and restore visual scanning.
                viewModel.activeSheet = nil
                captureMode = .visual
                if FeatureFlags.isEnabled(.fieldTrips) {
                    Task {
                        await activeCaptureGoalStore.refresh(
                            accountId: currentAccountId,
                            force: true
                        )
                    }
                }
            case .fieldTripProgressUpdated, .captureGoalContextInvalidated:
                guard FeatureFlags.isEnabled(.fieldTrips) else { break }
                Task {
                    await activeCaptureGoalStore.refresh(
                        accountId: currentAccountId,
                        force: true
                    )
                }
            case .requestRecallLastFindIntent:
                // If there's an active or historical cache for a scan, open the modal natively
                if inferenceEngine.historicHydrationTask != nil || inferenceEngine.speciesData != nil {
                    viewModel.activeSheet = .insight
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
            } else {
                viewModel.submitAudio(audioFileName: fileName, modelContext: modelContext)
            }
            audioCaptureManager.reset()
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

    private func handleCropPresentationChange(isCropPresented: Bool) {
        if isCropPresented {
            cameraManager.stopSession()
        } else if captureMode == .visual,
                  viewModel.activeSheet == nil,
                  scenePhase == .active {
            cameraManager.startSession()
        }
    }

    private func dismissCaptureKeyboardAndRestoreChrome() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        restoreBottomChrome(animated: true)
    }

    private func submitActiveStagedCapture() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        _ = viewModel.stagePendingDescribeDraftForActiveSubmission(observationContext)
        observationContext = ObservationContext()
        viewModel.submitStagedCapture(
            modelContext: modelContext,
            preferredGoal: preferredFieldTripGoal
        )
        cameraManager.resetZoom()
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
        guard isKeyboardVisible else { return }
        let update = {
            isKeyboardVisible = false
        }

        if animated {
            withAnimation(.easeOut(duration: 0.18), update)
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction, update)
        }
    }

    private func isSoftwareKeyboardVisible(from notification: Notification) -> Bool {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return true
        }
        let screenBounds = UIScreen.main.bounds
        let visibleKeyboardHeight = max(0, screenBounds.maxY - endFrame.minY)
        return visibleKeyboardHeight > 80
    }

    private func updateComposingZoneVerticalCenter(from proxy: GeometryProxy) {
        guard proxy.size.height.isFinite, proxy.size.height > 0 else { return }

        let toggleBottom = proxy.safeAreaInsets.top + 16 + 48
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

    private func armFeedbackSurveyPromptIfEligible() async {
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
        await presentPendingFeedbackSurveyIfReady()
        feedbackSurveyForegroundCompletionScanId = nil
    }

    private func presentPendingFeedbackSurveyIfReady() async {
        guard feedbackSurveyPromptPending else { return }
        guard viewModel.activeSheet == nil else { return }
        guard !showFeedbackSurvey else { return }

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled else { return }
        guard feedbackSurveyPromptPending else { return }
        guard viewModel.activeSheet == nil else { return }
        guard !showFeedbackSurvey else { return }

        feedbackSurveyPromptPending = false
        feedbackSurveyPresentedProactively = true
        showFeedbackSurvey = true
    }
}

enum ActiveCaptureGoalIndicatorCopy {
    static func instruction(for prompt: String) -> String {
        "Goal: \(prompt)"
    }

    static func accessibilityLabel(for prompt: String) -> String {
        "Outing goal. \(prompt)."
    }
}

private struct CaptureGoalIndicator: View {
    let presentation: ActiveCaptureGoalPresentation
    let onOpen: (CaptureGoalDestination) -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .goal(let goal):
            ActiveCaptureGoalIndicator(
                goal: goal,
                onOpen: { onOpen(goal.destination) },
                onNext: onNext,
                onPrevious: onPrevious
            )
        case .introduction(let introduction):
            CaptureGoalIntroductionIndicator(
                introduction: introduction,
                onOpen: { onOpen(introduction.destination) }
            )
        }
    }
}

private struct CaptureGoalIntroductionIndicator: View {
    let introduction: CaptureGoalIntroduction
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var artworkIndex = 0

    private var artworks: [CaptureGoalArtwork] {
        introduction.artworks.isEmpty
            ? [.systemSymbol(name: "binoculars.fill")]
            : introduction.artworks
    }

    var body: some View {
        Button {
            HapticManager.shared.triggerSheetSpring(source: "capture.goalIntroduction.open")
            AppTelemetry.trackCaptureGoalIndicator(
                action: .zeroStateOpened,
                source: introduction.sourceKind
            )
            onOpen()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    ForEach(Array(artworks.enumerated()), id: \.offset) { index, artwork in
                        CaptureGoalArtworkView(artwork: artwork)
                            .opacity(index == artworkIndex ? 1 : 0)
                    }
                }
                .frame(width: 40, height: 40)
                .animation(.easeInOut(duration: 0.2), value: artworkIndex)

                VStack(alignment: .center, spacing: 2) {
                    Text(introduction.headline)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)

                    Text(introduction.subheadline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

                GoalProgressRing(
                    completedCount: introduction.progress.completedCount,
                    targetCount: introduction.progress.targetCount
                )
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .modifier(ActiveCaptureGoalGlassModifier())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(introduction.accessibilityLabel)
        .accessibilityValue(introduction.accessibilityValue)
        .accessibilityHint(introduction.accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("captureGoalIntroductionIndicator")
        .task(id: introduction.id) {
            AppTelemetry.trackCaptureGoalIndicator(
                action: .zeroStateShown,
                source: introduction.sourceKind
            )
        }
        .task(id: "\(introduction.id):\(reduceMotion)") {
            artworkIndex = 0
            guard !reduceMotion, artworks.count > 1 else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
                artworkIndex = (artworkIndex + 1) % artworks.count
            }
        }
    }
}

private struct ActiveCaptureGoalIndicator: View {
    let goal: CaptureGoal
    let onOpen: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            HapticManager.shared.triggerSheetSpring(source: "capture.activeGoal.open")
            AppTelemetry.trackCaptureGoalIndicator(action: .opened, source: goal.source.kind)
            onOpen()
        } label: {
            HStack(spacing: 8) {
                CaptureGoalArtworkView(artwork: goal.artwork)
                    .frame(width: 40, height: 40)

                VStack(alignment: .center, spacing: 2) {
                    Text(
                        ActiveCaptureGoalIndicatorCopy.instruction(for: goal.prompt)
                    )
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)

                    Text(goal.source.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

                GoalProgressRing(
                    completedCount: goal.progress.completedCount,
                    targetCount: goal.progress.targetCount
                )
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .modifier(ActiveCaptureGoalGlassModifier())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard let direction = ActiveCaptureGoalSwipeDirection.resolve(
                        horizontal: value.translation.width,
                        vertical: value.translation.height
                    ) else {
                        return
                    }
                    changeSelection(next: direction == .next)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ActiveCaptureGoalIndicatorCopy.accessibilityLabel(for: goal.prompt)
        )
        .accessibilityValue(
            "\(goal.source.title), \(goal.progress.completedCount) of \(goal.progress.targetCount) complete"
        )
        .accessibilityHint(
            "Opens outing details for this target. Swipe up or down to change target."
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("activeCaptureGoalIndicator")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                changeSelection(next: true)
            case .decrement:
                changeSelection(next: false)
            @unknown default:
                break
            }
        }
        .task(id: goal.id) {
            AppTelemetry.trackCaptureGoalIndicator(action: .shown, source: goal.source.kind)
        }
    }

    private func changeSelection(next: Bool) {
        HapticManager.shared.triggerSelectionPulse(source: "capture.activeGoal")
        AppTelemetry.trackCaptureGoalIndicator(
            action: next ? .next : .previous,
            source: goal.source.kind
        )
        if reduceMotion {
            if next {
                onNext()
            } else {
                onPrevious()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                if next {
                    onNext()
                } else {
                    onPrevious()
                }
            }
        }
    }
}

private struct CaptureGoalArtworkView: View {
    let artwork: CaptureGoalArtwork

    @ViewBuilder
    var body: some View {
        switch artwork {
        case .bundledImage(let imageName):
            Image(imageName)
                .resizable()
                .scaledToFit()
                .padding(2)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        case .systemSymbol(let symbolName):
            Image(systemName: symbolName)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(.primary.opacity(0.08), in: Circle())
                .accessibilityHidden(true)
        }
    }
}

private struct ActiveCaptureGoalGlassModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }
}

private struct StagedVideoPreviewModal: View {
    private static let dismissDragThreshold: CGFloat = 120
    private static let dismissPredictionThreshold: CGFloat = 260
    private static let dismissDirectionRatio: CGFloat = 1.2

    let video: StagedVideo
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var dismissDragOffset: CGFloat = 0

    init(video: StagedVideo, onRemove: @escaping () -> Void) {
        self.video = video
        self.onRemove = onRemove
        _player = State(initialValue: AVPlayer(url: URL(fileURLWithPath: video.filePath)))
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()

            previewContent
                .offset(y: dismissDragOffset)
                .scaleEffect(previewScale)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(dismissDragGesture, including: .all)
        .onAppear {
            player.seek(to: .zero)
            player.play()
        }
        .onDisappear {
            player.pause()
        }
    }

    private var previewContent: some View {
        ZStack {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            controlsOverlay
        }
    }

    private var controlsOverlay: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close video preview")

            Spacer()

            Button(role: .destructive) {
                player.pause()
                onRemove()
                dismiss()
            } label: {
                Label("Remove", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityLabel("Remove video")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .environment(\.colorScheme, .dark)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard dismissDragOffset > 0 || isDismissDrag(value) else { return }
                dismissDragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard dismissDragOffset > 0 || isDismissDrag(value) else {
                    resetDismissDragOffset()
                    return
                }

                if shouldDismiss(for: value) {
                    player.pause()
                    dismiss()
                } else {
                    resetDismissDragOffset()
                }
            }
    }

    private var backgroundOpacity: Double {
        let progress = min(dismissDragOffset / 360, 1)
        return 1 - Double(progress) * 0.45
    }

    private var previewScale: CGFloat {
        1 - min(dismissDragOffset / 3_000, 0.04)
    }

    private func isDismissDrag(_ value: DragGesture.Value) -> Bool {
        let verticalTranslation = value.translation.height
        guard verticalTranslation > 0 else { return false }
        let horizontalTranslation = abs(value.translation.width)
        return verticalTranslation > max(24, horizontalTranslation * Self.dismissDirectionRatio)
    }

    private func shouldDismiss(for value: DragGesture.Value) -> Bool {
        value.translation.height > Self.dismissDragThreshold
            || value.predictedEndTranslation.height > Self.dismissPredictionThreshold
    }

    private func resetDismissDragOffset() {
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
            dismissDragOffset = 0
        }
    }
}

// SwiftUI has no native API for disabling pager bounce. This probe walks up the UIKit
// hierarchy from inside the ScrollView's content to find the backing UIScrollView
// and hard-disables bounce so neither edge rubber-bands.

private struct ScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { _ProbeView() }
    func updateUIView(_ uiView: UIView, context: Context) {}

    private class _ProbeView: UIView {
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            DispatchQueue.main.async { [weak self] in
                var current: UIView? = self?.superview
                while let view = current {
                    if let sv = view as? UIScrollView {
                        sv.bounces = false
                        return
                    }
                    current = view.superview
                }
            }
        }
    }
}

private struct ExternalImageImportRetryModifier: ViewModifier {
    let viewModel: CaptureWorkspaceViewModel
    let stagedItemCount: Int
    let stagedCaptureLimit: Int
    let canStartProScan: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: stagedItemCount) { oldCount, newCount in
                if newCount < oldCount {
                    viewModel.importPendingExternalImageIfPossible()
                }
            }
            .onChange(of: stagedCaptureLimit) { oldLimit, newLimit in
                if newLimit > oldLimit {
                    viewModel.importPendingExternalImageIfPossible()
                }
            }
            .onChange(of: canStartProScan) { _, _ in
                viewModel.importPendingExternalImageIfPossible()
            }
    }
}

extension EnvironmentValues {
    var composingCenter: CGFloat {
        get { self[ComposingCenterKey.self] }
        set { self[ComposingCenterKey.self] = newValue }
    }
}

private struct ComposingCenterKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0.5
}

// End of CaptureWorkspaceView.swift
