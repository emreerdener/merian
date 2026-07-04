import AVFoundation
import AVKit
import PhotosUI
import SwiftData
import SwiftUI

struct CaptureWorkspaceView: View {
    // MARK: - Environment & Dependencies
    @Environment(CameraManager.self) var cameraManager
    @Environment(HardwareOrchestrator.self) var hardwareOrchestrator
    @Environment(ViewfinderIntelligence.self) var vui
    @Environment(PhotoLibraryManager.self) var photoLibraryManager
    @Environment(InferenceEngine.self) var inferenceEngine
    @Environment(AudioCaptureManager.self) var audioCaptureManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(
        filter: #Predicate<LocalScanRecord> { $0.isBiological == true },
        sort: \LocalScanRecord.timestamp,
        order: .reverse
    ) private var messageShareCacheRecords: [LocalScanRecord]

    // MARK: - View Model & State
    @State private var viewModel = CaptureWorkspaceViewModel()

    @State private var coordinator = CaptureActionCoordinator()
    @State private var captureMode: CaptureMode
    @State private var observationContext = ObservationContext()
    @State private var isKeyboardVisible: Bool = false
    @State private var controlBarHeight: CGFloat = 250

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
    init(appSettings: AppSettings? = nil) {
        let raw = (appSettings ?? AppSettings.shared).captureModeOrderRaw
        let mode = CaptureMode.userOrder(from: raw).first ?? .visual
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

    // MARK: - View Hierarchy
    var body: some View {
        let orderedModes = CaptureMode.userOrder(from: appSettings.captureModeOrderRaw)
        let shouldHideBottomChrome = isKeyboardVisible && captureMode == .describe

        ZStack {
                // Paged capture mode switcher.
                // CameraPreviewView lives inside page 1 so the outer horizontal UIScrollView
                // naturally defers vertical pan gestures to the inner camera pan recognizer
                // (zoom), while claiming horizontal ones (paging).
                // GeometryReader captures the true full-screen dimensions (after the outer
                // ZStack's .ignoresSafeArea() expands it) and hands them to each page via
                // explicit .frame(), bypassing any ambiguity in containerRelativeFrame's
                // safe-area-vs-full-screen reference resolution.
                GeometryReader { proxy in
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(orderedModes, id: \.self) { mode in
                                    switch mode {
                                    case .visual:
                                        // MARK: Page 1 — Camera
                                        VisualCaptureView(
                                            viewModel: viewModel,
                                            isVerticalZooming: $isVerticalZooming
                                        )
                                        .frame(width: proxy.size.width, height: proxy.size.height)
                                        .clipped()
                                        .id(CaptureMode.visual)

                                    case .audio:
                                        // MARK: Page 2 — Audio Recording
                                        AudioRecordingView()
                                            .frame(width: proxy.size.width, height: proxy.size.height)
                                            .clipped()
                                            .id(CaptureMode.audio)

                                    case .describe:
                                        // MARK: Page 3 — Describe Input
                                        DescribeInputView(
                                            captureMode: captureMode,
                                            promptFlow: viewModel.describePromptFlow,
                                            context: $observationContext,
                                            coordinator: coordinator,
                                            showToast: { viewModel.offlineToastMessage = $0 }
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
                            // (top overlay, 16pt padding + ~48pt height) and the capture button row
                            // (bottom overlay, 140pt padding + 80pt button height).
                            // proxy uses the full-screen frame (.ignoresSafeArea on the GeometryReader)
                            // so safe-area insets must be accounted for explicitly.
                            updateComposingZoneVerticalCenter(from: proxy)
                        }
                    }
                }
                .ignoresSafeArea()

                // MARK: Fixed Overlay — Mode Toggle (top)
                if viewModel.shouldShowMediaModeToggle {
                    VStack {
                        MediaModeToggle(
                            activeMode: $captureMode, 
                            isDragging: $isToggleDragging, 
                            orderedModes: orderedModes, 
                            onModeChange: {}
                        )
                            .padding(.top, 16)
                            .opacity(viewModel.offlineToastMessage != nil ? 0 : 1)
                        Spacer()
                    }
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
                            selectedPhotoItems: $viewModel.selectedPhotoItems,
                            onThumbnailTap: { index in viewModel.presentCrop(for: index) },
                            onCancel: {
                                let isCancelingRefinement = viewModel.baseRefinementContext != nil
                                if let scanId = viewModel.baseRefinementContext?.scanId,
                                   let record = viewModel.fetchLocalScan(scanId: scanId) {
                                    viewModel.diContainer.inferenceEngine.load(from: record)
                                    viewModel.activeSheet = .insight
                                }
                                viewModel.clearStagedCaptureAndCropState()
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
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .merianSystemFeedback(
            toastMessage: Binding(
                get: { viewModel.offlineToastMessage },
                set: { viewModel.offlineToastMessage = $0 }
            ),
            toastAlignment: .top
        )
        .environment(\.controlBarHeight, controlBarHeight)
        .environment(\.composingCenter, viewModel.composingZoneVerticalCenter)
        .onPreferenceChange(CaptureBarHeightPreferenceKey.self) { newHeight in
            updateControlBarHeight(newHeight)
        }
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
        .sheet(
            isPresented: Binding(
                get: { stagedDescriptionEditIndex != nil },
                set: { if !$0 { stagedDescriptionEditIndex = nil } }
            )
        ) {
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
        .fullScreenCover(
            isPresented: Binding(
                get: { stagedVideoReviewIndex != nil },
                set: { if !$0 { stagedVideoReviewIndex = nil } }
            )
        ) {
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
        .sheet(isPresented: $showFeedbackSurvey, onDismiss: {
            guard feedbackSurveyPresentedProactively else { return }
            feedbackSurveyPresentedProactively = false
            if appSettings.feedbackSurveySubmittedCampaignId != FeedbackSurveyCampaign.currentId {
                appSettings.feedbackSurveyDismissedCampaignId = FeedbackSurveyCampaign.currentId
            }
        }) {
            FeedbackSurveyView()
        }

        // MARK: - View Modifiers
        .cameraSheetRouter(viewModel: viewModel)
        .modifier(CropSheetModifier(
            isPresented: Binding(
                get: { viewModel.imageToCrop != nil },
                set: { if !$0 { viewModel.imageToCrop = nil } }
            ),
            viewModel: viewModel,
            onRequiredCropReadyForSubmit: {
                viewModel.submitStagedCapture(modelContext: modelContext)
                cameraManager.resetZoom()
            }
        ))
        .onAppear {
            viewModel.updateNotificationSuppression()
            if captureMode == .visual {
                cameraManager.startSession()
            }
            photoLibraryManager.startObservingAndFetch()
            AppDIContainer.shared.environmentContextManager.validatePermissions()
            AppDIContainer.shared.environmentContextManager.startLiveLocationTracking()
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

            viewModel.submitStagedCapture(modelContext: modelContext)
            cameraManager.resetZoom()
        }
        .onChange(of: viewModel.stagedCapture.videos.count) { _, count in
            guard count == 1 else { return }
            guard viewModel.shouldAutoSubmitStagedCapture else { return }

            viewModel.submitStagedCapture(modelContext: modelContext)
            cameraManager.resetZoom()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(
                newPhase,
                captureMode: captureMode,
                cameraManager: cameraManager,
                audioCaptureManager: audioCaptureManager
            )
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
        }

        .onChange(of: viewModel.activeSheet) { _, newSheet in
            viewModel.updateNotificationSuppression()

            if newSheet != nil {
                cameraManager.stopSession()
            } else if captureMode == .visual && scenePhase == .active {
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
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .requestIdentifyNatureIntent:
                // Close any open modals and shift pager strictly to visual scanning
                viewModel.activeSheet = nil
                captureMode = .visual
            case .requestRecallLastFindIntent:
                // If there's an active or historical cache for a scan, open the modal natively
                if inferenceEngine.historicHydrationTask != nil || inferenceEngine.speciesData != nil {
                    viewModel.activeSheet = .insight
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
        .onChange(of: audioCaptureManager.audioFilePath) { _, fileName in
            guard let fileName else { return }
            
            let willStageOnly = viewModel.stagedCapture.hasVisualMedia
                || appSettings.isMultiCaptureEnabled
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

    private func dismissCaptureKeyboardAndRestoreChrome() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        restoreBottomChrome(animated: true)
    }

    private func submitActiveStagedCapture() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        _ = viewModel.stagePendingDescribeDraftForActiveSubmission(observationContext)
        observationContext = ObservationContext()
        viewModel.submitStagedCapture(modelContext: modelContext)
        cameraManager.resetZoom()
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

    private func updateControlBarHeight(_ newHeight: CGFloat) {
        guard newHeight.isFinite, newHeight > 0 else { return }
        guard abs(controlBarHeight - newHeight) > 0.5 else { return }

        DispatchQueue.main.async {
            guard abs(controlBarHeight - newHeight) > 0.5 else { return }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                controlBarHeight = newHeight
            }
        }
    }

    private func updateComposingZoneVerticalCenter(from proxy: GeometryProxy) {
        guard proxy.size.height.isFinite, proxy.size.height > 0 else { return }

        let toggleBottom = proxy.safeAreaInsets.top + 16 + 48
        let captureButtonTop = proxy.size.height - proxy.safeAreaInsets.bottom - 140 - 80
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
            appSettings.feedbackSurveySubmittedCampaignId
        ].joined(separator: "|")
    }

    private func armFeedbackSurveyPromptIfEligible() async {
        guard !hasEvaluatedFeedbackSurveyPrompt else { return }
        guard FeedbackSurveyPromptPolicy.shouldPrompt(
            completedScanCount: messageShareCacheRecords.count,
            hasCompletedOnboarding: appSettings.hasCompletedOnboarding,
            dismissedCampaignId: appSettings.feedbackSurveyDismissedCampaignId,
            submittedCampaignId: appSettings.feedbackSurveySubmittedCampaignId
        ) else {
            return
        }

        hasEvaluatedFeedbackSurveyPrompt = true
        feedbackSurveyPromptPending = true
        await presentPendingFeedbackSurveyIfReady()
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

private struct StagedVideoPreviewModal: View {
    let video: StagedVideo
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(video: StagedVideo, onRemove: @escaping () -> Void) {
        self.video = video
        self.onRemove = onRemove
        _player = State(initialValue: AVPlayer(url: URL(fileURLWithPath: video.filePath)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
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
        .onDisappear {
            player.pause()
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

// MARK: - Safe Area Synchronization
struct CaptureBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 250
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension EnvironmentValues {
    var controlBarHeight: CGFloat {
        get { self[ControlBarHeightKey.self] }
        set { self[ControlBarHeightKey.self] = newValue }
    }
}

private struct ControlBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 250
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
