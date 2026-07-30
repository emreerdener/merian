import SwiftData
import SwiftUI

// MARK: - Capture Control Bar

enum CaptureControlBarLayout {
    static let primaryControlSize: CGFloat = 80
    static let bottomInset: CGFloat = 124
    static let reservedHeight = primaryControlSize + bottomInset
    /// Preserves the full-screen overlay position used before capture-bar
    /// measurement was removed. Full-screen pager geometry reports a zero
    /// bottom safe-area inset, so this value must not be derived from that proxy.
    static let fullScreenOverlayClearance: CGFloat = 250
    /// Keeps the Describe editor above the fixed control row. Matching the
    /// row's actual reserved height lets the flexible editor fill the available
    /// space; its own 24 pt bottom padding provides the visual separation.
    static let describeContentBottomClearance = reservedHeight
}

/// A horizontal control bar pinned to the bottom of the camera interface.
/// It orchestrates the primary capture button along with secondary tools
/// (like the photo library, table of contents, flash toggle, and dictation)
/// based on the current capture mode.
struct CaptureControlBar: View {
    @Bindable var viewModel: CaptureWorkspaceViewModel
    let captureMode: CaptureMode
    @Binding var observationContext: ObservationContext
    let isKeyboardVisible: Bool
    let coordinator: CaptureActionCoordinator

    @Environment(CameraManager.self) private var cameraManager
    @Environment(PhotoLibraryManager.self) private var photoLibraryManager
    @Environment(SpeechManager.self) private var speechManager
    @Environment(AudioCaptureManager.self) private var audioCaptureManager
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var audioRecordingStartTask: Task<Void, Never>?

    private var isRefining: Bool { viewModel.baseRefinementContext != nil }
    // Mirror the ActiveScanToolbar capacity logic — includes isRefining so reanalysis
    // flows get the same two-slot limit as multi-capture without enabling multi-capture.
    private var capacityLimit: Int { (appSettings.isMultiCaptureEnabled || isRefining) ? stagedCaptureCapacity : 1 }

    var body: some View {
        VStack {
            Spacer()

            // MARK: Capacity Evaluation
            // capacityLimit and imageCount come from struct-level computed properties
            // so they stay consistent between body and the photosPicker modifier below.
            let totalStagedItems = viewModel.stagedCapture.totalItemCount
            let isAtCapacity = totalStagedItems >= capacityLimit

            HStack(alignment: .center) {
                ZStack(alignment: .leading) {
                    PhotoLibraryButton(
                        selectedPhotoItems: $viewModel.selectedPhotoItems,
                        latestThumbnail: photoLibraryManager.latestThumbnail,
                        maxSelectionCount: appSettings.isMultiCaptureEnabled ? max(1, viewModel.stagedCapture.availableSlots(limit: capacityLimit)) : 1
                    )
                    .opacity(captureMode == .visual && !viewModel.isVideoRecording ? (isAtCapacity ? 0.5 : 1) : 0)
                    .allowsHitTesting(captureMode == .visual && !isAtCapacity && !viewModel.isVideoRecording)

                    VideoCancelButton(onTap: { viewModel.cancelVideoCapture() })
                        .opacity(captureMode == .visual && viewModel.isVideoRecording ? 1 : 0)
                        .allowsHitTesting(captureMode == .visual && viewModel.isVideoRecording)

                    TableOfContentsButton(
                        onTap: { coordinator.tocRequestID = UUID() }
                    )
                    .opacity(captureMode == .describe && !isRefining ? 1 : 0)
                    .allowsHitTesting(captureMode == .describe && !isRefining)

                    AudioDeleteButton(
                        isRecording: audioCaptureManager.isRecording,
                        onTap: {
                            if audioCaptureManager.isRecording {
                                audioCaptureManager.cancelRecording()
                            } else {
                                audioCaptureManager.discardPending()
                            }
                        }
                    )
                    .opacity(captureMode == .audio && (audioCaptureManager.isRecording || audioCaptureManager.pendingPlaybackPath != nil) ? 1 : 0)
                    .allowsHitTesting(captureMode == .audio && (audioCaptureManager.isRecording || audioCaptureManager.pendingPlaybackPath != nil))
                }
                .animation(.easeInOut(duration: 0.2), value: captureMode)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isVideoRecording)
                .animation(.easeInOut(duration: 0.2), value: audioCaptureManager.isRecording)
                .animation(.easeInOut(duration: 0.2), value: audioCaptureManager.pendingPlaybackPath == nil)

                Spacer()

                // Show "+" whenever the FAB stages rather than immediately submits:
                //   • images already staged (description joins them in the toolbar)
                //   • multi-capture mode (description is always staged, user submits via Identify)
                //   • confirm-before-submit ON (every input must be staged first)
                // Show "↑" only for immediate solo-describe when none of the above apply.
                let willStageOnly = viewModel.stagedCapture.hasVisualMedia
                    || !viewModel.stagedCapture.audios.isEmpty
                    || !viewModel.stagedCapture.observationContexts.isEmpty
                    || viewModel.baseRefinementContext != nil
                    || appSettings.isMultiCaptureEnabled
                    || appSettings.requiresScanConfirmation
                // All modes disabled when staging area is full — no new input can be added.
                // Describe also disabled while a refinement image is still loading.
                let isSubmitDisabled: Bool = isAtCapacity
                    || (captureMode == .describe && viewModel.isStagingRefinement)
                let isInputActive = captureMode != .describe || !observationContext.isEmpty

                CaptureButton(
                    captureMode: captureMode,
                    willStageOnly: willStageOnly,
                    isInputActive: isInputActive,
                    isVisualCaptureAllowed: viewModel.diContainer.usageManager.canPerformScan(
                        isProActive: viewModel.diContainer.revenueCatManager.isProActive
                    ),
                    isProVideoAvailable: viewModel.diContainer.revenueCatManager.isProActive,
                    isVideoRecording: viewModel.isVideoRecording,
                    videoRecordingProgress: viewModel.videoRecordingProgress,
                    onAction: {
                        switch captureMode {
                        case .visual:
                            if viewModel.isVideoRecording {
                                HapticManager.shared.triggerMediumPulse(source: CaptureButtonHapticSource.videoStop.rawValue)
                                viewModel.stopVideoCapture()
                            } else {
                                viewModel.executeCapture(emitHaptic: false)
                            }
                        case .audio:
                            if audioCaptureManager.pendingPlaybackPath != nil {
                                audioCaptureManager.confirmAndSubmit()
                            } else if audioCaptureManager.isRecording {
                                if audioCaptureManager.isPaused {
                                    audioCaptureManager.resumeRecording()
                                } else {
                                    audioCaptureManager.pauseRecording()
                                }
                            } else {
                                guard audioRecordingStartTask == nil else { return }
                                audioRecordingStartTask = Task {
                                    defer { audioRecordingStartTask = nil }
                                    do {
                                        // Ask immediately while the red-button action is still
                                        // visible and before camera shutdown can introduce delay.
                                        guard scenePhase == .active else { return }
                                        try await audioCaptureManager.requestMicrophonePermissionForRecording()
                                        try Task.checkCancellation()

                                        // Mode changes request camera shutdown asynchronously. Await
                                        // the hardware handoff here so a fast tap cannot start the
                                        // audio engine while AVCaptureSession is still releasing it.
                                        await cameraManager.stopSessionAndWait()
                                        try Task.checkCancellation()
                                        guard scenePhase == .active else { return }
                                        try await audioCaptureManager.startRecording(
                                            autoSubmitOnMaxDuration: !appSettings.requiresScanConfirmation
                                        )
                                    } catch is CancellationError {
                                        // Expected when the user leaves audio mode during startup.
                                    } catch {
                                        await MainActor.run {
                                            viewModel.offlineToastMessage = error.localizedDescription
                                        }
                                    }
                                }
                            }
                        case .describe:
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            let didSubmit = viewModel.submitDescribe(
                                observationContext: observationContext,
                                modelContext: modelContext
                            )
                            if didSubmit {
                                observationContext = ObservationContext()
                            }
                        }
                    },
                    onVisualLongPressStart: {
                        viewModel.startVideoCapture()
                    }
                )
                .animation(.easeInOut(duration: 0.2), value: captureMode)
                .opacity(isSubmitDisabled ? 0.5 : 1.0)
                .disabled(isSubmitDisabled)

                Spacer()
                ZStack {
                    FlashButton(
                        isFlashEnabled: cameraManager.isFlashEnabled,
                        onToggleFlash: { cameraManager.toggleFlash() }
                    )
                    .opacity(captureMode == .visual ? (isAtCapacity ? 0.5 : 1) : 0)
                    .allowsHitTesting(captureMode == .visual && !isAtCapacity)

                    DictationButton(
                        isRecording: coordinator.isDictationRequested,
                        onToggleDictation: { coordinator.isDictationRequested.toggle() }
                    )
                    .opacity(captureMode == .describe ? 1 : 0)
                    .allowsHitTesting(captureMode == .describe)

                    AudioDoneButton(onTap: { audioCaptureManager.stopRecordingEarly() })
                        .opacity(captureMode == .audio && audioCaptureManager.isRecording ? 1 : 0)
                        .allowsHitTesting(captureMode == .audio && audioCaptureManager.isRecording)

                    AudioReviewPlayButton()
                        .opacity(captureMode == .audio && audioCaptureManager.pendingPlaybackPath != nil ? 1 : 0)
                        .allowsHitTesting(captureMode == .audio && audioCaptureManager.pendingPlaybackPath != nil)
                }
                .animation(.easeInOut(duration: 0.2), value: captureMode)
                .animation(.easeInOut(duration: 0.2), value: audioCaptureManager.isRecording)
                .animation(.easeInOut(duration: 0.2), value: audioCaptureManager.pendingPlaybackPath == nil)
            }
            .padding(.bottom, CaptureControlBarLayout.bottomInset)
        }
        .onChange(of: captureMode) { _, newMode in
            if newMode != .audio {
                audioRecordingStartTask?.cancel()
            }
        }
        .onDisappear {
            audioRecordingStartTask?.cancel()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.stagedCapture.images.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.stagedCapture.videos.count)
        .opacity(isKeyboardVisible ? 0 : 1)
        .allowsHitTesting(!isKeyboardVisible)
    }
}

// MARK: - Capture Button

/// Single button that transitions between the white shutter style (Visual),
/// the red record style (Audio), and the submit/stage style (Describe)
/// in place, with no position change.
private struct CaptureButton: View {
    let captureMode: CaptureMode
    let willStageOnly: Bool
    let isInputActive: Bool
    let isVisualCaptureAllowed: Bool
    let isProVideoAvailable: Bool
    let isVideoRecording: Bool
    let videoRecordingProgress: Double
    let onAction: () -> Void
    let onVisualLongPressStart: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AudioCaptureManager.self) private var audioCaptureManager
    @State private var isPressActive = false
    @State private var didTriggerVideoLongPress = false
    @State private var videoLongPressTask: Task<Void, Never>?

    private let videoHoldStartDelayNanoseconds: UInt64 = 180_000_000

    private var outerRingColor: Color {
        switch captureMode {
        case .visual:   return .white
        case .audio:    return colorScheme == .dark ? .white : Color(UIColor.label)
        case .describe: return Color(UIColor.label)
        }
    }

    private var isRecording: Bool { captureMode == .audio && audioCaptureManager.isRecording }
    private var isPaused: Bool { captureMode == .audio && audioCaptureManager.isPaused }
    private var isAudioReview: Bool { captureMode == .audio && audioCaptureManager.pendingPlaybackPath != nil }
    private var shouldShowRecordingChrome: Bool { isRecording || (captureMode == .visual && isVideoRecording) }
    private var recordingProgress: Double {
        captureMode == .visual && isVideoRecording
            ? videoRecordingProgress
            : audioCaptureManager.recordingProgress
    }

    private var innerFill: Color {
        switch captureMode {
        case .visual:   return isVideoRecording ? .red : .white
        case .describe: return isInputActive ? Color.primary : Color.clear
        case .audio:
            // Red = "recording action available" (idle or paused → tap to record/resume).
            // Neutral = "currently recording, tap to pause".
            if isAudioReview { return Color.primary }
            if isRecording && !isPaused { return Color.primary }
            return Color.red
        }
    }

    private var iconColor: Color {
        switch captureMode {
        case .describe:
            isInputActive ? Color(UIColor.systemBackground) : Color.primary
        default:
            Color(UIColor.systemBackground)
        }
    }

    private var releaseHapticFeedback: CaptureButtonHapticFeedback {
        CaptureButtonHapticFeedback.releaseFeedback(
            captureMode: captureMode,
            isVideoRecording: isVideoRecording,
            isVisualCaptureAllowed: isVisualCaptureAllowed,
            audioState: audioHapticState,
            isDescribeInputActive: isInputActive,
            willStageDescribeOnly: willStageOnly
        )
    }

    private var audioHapticState: CaptureButtonAudioState {
        if isAudioReview { return .review }
        if isRecording { return isPaused ? .paused : .recording }
        return .idle
    }

    var body: some View {
        ZStack {
            // Track ring — dims when recording to show the progress arc.
            Circle()
                .stroke(outerRingColor.opacity(shouldShowRecordingChrome ? 0.25 : 1), lineWidth: 1)
                .frame(
                    width: CaptureControlBarLayout.primaryControlSize,
                    height: CaptureControlBarLayout.primaryControlSize
                )
                .animation(.easeInOut(duration: 0.2), value: shouldShowRecordingChrome)

            // Progress arc — sweeps red clockwise for the duration of the recording.
            // Hidden during review so the ring resets to a clean submit-button appearance.
            if !isAudioReview {
                Circle()
                    .trim(from: 0, to: shouldShowRecordingChrome ? recordingProgress : 0)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(
                        width: CaptureControlBarLayout.primaryControlSize,
                        height: CaptureControlBarLayout.primaryControlSize
                    )
                    .animation(.linear(duration: 0.12), value: recordingProgress)
            }

            ZStack {
                Circle()
                    .fill(innerFill)
                    .frame(width: 72, height: 72)
                    .animation(.easeInOut(duration: 0.25), value: isAudioReview)
                    .animation(.easeInOut(duration: 0.2), value: isInputActive)
                    .animation(.easeInOut(duration: 0.2), value: isRecording && !isPaused)

                if captureMode == .visual && isVideoRecording {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .transition(.scale.combined(with: .opacity))
                } else if captureMode == .describe || isAudioReview {
                    Image(systemName: willStageOnly ? "plus" : "arrow.up")
                        .font(.system(size: 32))
                        .foregroundStyle(iconColor)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.2), value: isInputActive)
                } else if isRecording && !isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color(UIColor.systemBackground))
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .contentShape(Circle())
        .accessibilityIdentifier("CaptureShutter")
        .accessibilityAddTraits(.isButton)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in handlePressBegan() }
                .onEnded { _ in handlePressEnded() }
        )
        .onDisappear {
            videoLongPressTask?.cancel()
            videoLongPressTask = nil
        }
    }

    private func handlePressBegan() {
        guard !isPressActive else { return }
        isPressActive = true
        didTriggerVideoLongPress = false
        HapticManager.shared.prepareHeavyImpact()

        guard captureMode == .visual,
              isProVideoAvailable,
              !isVideoRecording else { return }

        videoLongPressTask?.cancel()
        videoLongPressTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: videoHoldStartDelayNanoseconds)
            guard !Task.isCancelled else { return }
            didTriggerVideoLongPress = true
            onVisualLongPressStart()
        }
    }

    private func handlePressEnded() {
        videoLongPressTask?.cancel()
        videoLongPressTask = nil
        defer {
            isPressActive = false
            didTriggerVideoLongPress = false
        }

        if captureMode == .visual, didTriggerVideoLongPress {
            return
        }

        if captureMode == .visual, isVideoRecording {
            onAction()
            return
        }

        releaseHapticFeedback.trigger()
        onAction()
    }
}

enum CaptureButtonHapticFeedback: Equatable {
    case none
    case heavyImpact(CaptureButtonHapticSource)
    case mediumPulse(CaptureButtonHapticSource)

    static func releaseFeedback(
        captureMode: CaptureMode,
        isVideoRecording: Bool,
        isVisualCaptureAllowed: Bool,
        audioState: CaptureButtonAudioState,
        isDescribeInputActive: Bool,
        willStageDescribeOnly: Bool
    ) -> CaptureButtonHapticFeedback {
        switch captureMode {
        case .visual:
            return !isVideoRecording && isVisualCaptureAllowed ? .heavyImpact(.visualPhoto) : .none
        case .audio:
            switch audioState {
            case .idle:
                return .mediumPulse(.audioStart)
            case .recording:
                return .mediumPulse(.audioPause)
            case .paused:
                return .mediumPulse(.audioResume)
            case .review:
                return .mediumPulse(.audioConfirm)
            }
        case .describe:
            guard isDescribeInputActive else { return .none }
            return .mediumPulse(willStageDescribeOnly ? .describeAdd : .describeSubmit)
        }
    }

    @MainActor
    func trigger() {
        switch self {
        case .none:
            break
        case .heavyImpact(let source):
            HapticManager.shared.triggerHeavyImpact(intensity: 1.0, source: source.rawValue)
        case .mediumPulse(let source):
            HapticManager.shared.triggerMediumPulse(source: source.rawValue)
        }
    }
}

enum CaptureButtonHapticSource: String, Equatable {
    case visualPhoto = "capture.photo"
    case videoStart = "capture.video.start"
    case videoStop = "capture.video.stop"
    case videoCancel = "capture.video.cancel"
    case audioStart = "capture.audio.start"
    case audioPause = "capture.audio.pause"
    case audioResume = "capture.audio.resume"
    case audioConfirm = "capture.audio.confirm"
    case audioCancel = "capture.audio.cancel"
    case audioDone = "capture.audio.done"
    case describeAdd = "capture.describe.add"
    case describeSubmit = "capture.describe.submit"
    case describeDictation = "capture.describe.dictation"
    case describeTableOfContents = "capture.describe.tableOfContents"
}

enum CaptureButtonAudioState: Equatable {
    case idle
    case recording
    case paused
    case review
}

// MARK: - Dictation Button

/// An animated toggle button used to start and stop voice dictation
/// during Describe mode. Emits a reactive, level-based reverberation
/// effect when actively recording.
private struct DictationButton: View {
    let isRecording: Bool
    let onToggleDictation: () -> Void
    @Environment(SpeechManager.self) private var speechManager

    var body: some View {
        Button(action: {
            HapticManager.shared.triggerMediumPulse(source: CaptureButtonHapticSource.describeDictation.rawValue)
            onToggleDictation()
        }) {
            ZStack {
                // Reactive reverberation border (pulses outward)
                if isRecording {
                    Circle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: 50, height: 50)
                        .scaleEffect(1.0 + (speechManager.audioLevel * 0.4))
                        .opacity(1.0 - (Double(speechManager.audioLevel) * 0.5))
                        .animation(.easeOut(duration: 0.15), value: speechManager.audioLevel)
                }

                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(isRecording ? Color.red : Color.clear)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .environment(\.colorScheme, .dark)
                    .animation(.easeInOut(duration: 0.2), value: isRecording)
            }
            .frame(width: 50, height: 50) // Fix bounds so animation bleeding doesn't bounce the toolbar layout
        }
        .buttonStyle(.plain)
        .padding(.trailing, 32)
        .accessibilityLabel(isRecording ? "Stop dictation" : "Start dictation")
        .accessibilityIdentifier("DescribeDictation")
    }
}

// MARK: - Video Cancel Button

/// Cancels the active video recording without staging the clip.
private struct VideoCancelButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.triggerMediumPulse(source: CaptureButtonHapticSource.videoCancel.rawValue)
            onTap()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.red)
                .circularMaterialControl(colorScheme: .dark)
        }
        .buttonStyle(.plain)
        .padding(.leading, 32)
    }
}

// MARK: - Table of Contents Button

/// A button that presents the full table of contents for Describe-mode
/// prompts, allowing users to jump between predefined questions.
private struct TableOfContentsButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.triggerMediumPulse(source: CaptureButtonHapticSource.describeTableOfContents.rawValue)
            onTap()
        }) {
            Image(systemName: "list.bullet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .circularMaterialControl(colorScheme: .dark)
        }
        .buttonStyle(.plain)
        .padding(.leading, 32)
        .accessibilityLabel("Show prompts")
        .accessibilityIdentifier("DescribePrompts")
    }
}

// MARK: - Audio Delete Button

/// Discards the current recording and returns to idle state.
private struct AudioDeleteButton: View {
    let isRecording: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.triggerMediumPulse(source: CaptureButtonHapticSource.audioCancel.rawValue)
            onTap()
        }) {
            Image(systemName: isRecording ? "xmark" : "trash")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.red)
                .circularMaterialControl(colorScheme: .dark)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .padding(.leading, 32)
    }
}

// MARK: - Audio Done Button

/// Accepts the recording early and routes to review state.
private struct AudioDoneButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.triggerFocusSnap(source: CaptureButtonHapticSource.audioDone.rawValue)
            onTap()
        }) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .circularMaterialControl(colorScheme: .dark)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 32)
    }
}

// MARK: - Audio Review Play Button

/// Plays or pauses the pending recording during the review state.
private struct AudioReviewPlayButton: View {
    @Environment(AudioCaptureManager.self) private var audioCaptureManager

    var body: some View {
        Button(action: {
            if audioCaptureManager.isPlaying {
                HapticManager.shared.triggerLightImpact(
                    intensity: 0.55,
                    source: "media.capture.audio.pause"
                )
                audioCaptureManager.stopPlayback()
            } else {
                HapticManager.shared.triggerMediumPulse(source: "media.capture.audio.play")
                audioCaptureManager.playPendingRecording()
            }
        }) {
            Image(systemName: audioCaptureManager.isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .circularMaterialControl(colorScheme: .dark)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 32)
    }
}
