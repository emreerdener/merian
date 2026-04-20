import SwiftData
import SwiftUI

// MARK: - Capture Control Bar

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
    @Environment(\.modelContext) private var modelContext

    @AppStorage("isMultiCaptureEnabled") private var isMultiCaptureEnabled: Bool = false

    private var isRefining: Bool { viewModel.baseRefinementRecord != nil }
    private var imageCount: Int { viewModel.stagedCapture.images.count }
    private var isAudioReview: Bool { captureMode == .audio && audioCaptureManager.pendingPlaybackPath != nil }
    // Mirror the ActiveScanToolbar capacity logic — includes isRefining so reanalysis
    // flows get the same two-slot limit as multi-capture without enabling multi-capture.
    private var capacityLimit: Int { (isMultiCaptureEnabled || isRefining) ? stagedImageCapacity : 1 }

    var body: some View {
        VStack {
            Spacer()

            // MARK: Capacity Evaluation
            // capacityLimit and imageCount come from struct-level computed properties
            // so they stay consistent between body and the photosPicker modifier below.
            let totalStagedItems = imageCount + (viewModel.stagedCapture.observationContext != nil ? 1 : 0)
            let isAtCapacity = totalStagedItems >= capacityLimit

            HStack(alignment: .bottom) {
                ZStack(alignment: .leading) {
                    PhotoLibraryButton(
                        selectedPhotoItems: $viewModel.selectedPhotoItems,
                        latestThumbnail: photoLibraryManager.latestThumbnail,
                        maxSelectionCount: isMultiCaptureEnabled ? max(1, capacityLimit - totalStagedItems) : 1
                    )
                    .opacity(captureMode == .visual ? (isAtCapacity ? 0.5 : 1) : 0)
                    .allowsHitTesting(captureMode == .visual && !isAtCapacity)
                    
                    TableOfContentsButton(
                        onTap: { coordinator.tocRequestID = UUID() }
                    )
                    .opacity(captureMode == .describe ? 1 : 0)
                    .allowsHitTesting(captureMode == .describe)
                }
                .animation(.easeInOut(duration: 0.2), value: captureMode)

                Spacer()

                // Show "+" whenever the FAB stages rather than immediately submits:
                //   • images already staged (description joins them in the toolbar)
                //   • multi-capture mode (description is always staged, user submits via Identify)
                //   • confirm-before-submit ON (every input must be staged first)
                // Show "↑" only for immediate solo-describe when none of the above apply.
                let willStageOnly = !viewModel.stagedCapture.images.isEmpty
                    || isMultiCaptureEnabled
                    || UserDefaults.standard.bool(forKey: "requiresScanConfirmation")
                // All modes disabled when staging area is full — no new input can be added.
                // Describe also disabled while a refinement image is still loading.
                let isSubmitDisabled: Bool = isAtCapacity
                    || (captureMode == .describe && viewModel.isStagingRefinement)
                    || (captureMode == .audio && audioCaptureManager.pendingPlaybackPath != nil)

                CaptureButton(
                    captureMode: captureMode,
                    willStageOnly: willStageOnly,
                    onAction: {
                        switch captureMode {
                        case .visual:
                            viewModel.executeCapture()
                        case .audio:
                            if audioCaptureManager.isRecording {
                                if audioCaptureManager.isPaused {
                                    audioCaptureManager.resumeRecording()
                                } else {
                                    audioCaptureManager.pauseRecording()
                                }
                            } else {
                                Task {
                                    do {
                                        try await audioCaptureManager.startRecording()
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
                }
                .animation(.easeInOut(duration: 0.2), value: captureMode)
            }
            .padding(.bottom, 140)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: CaptureBarHeightPreferenceKey.self, value: proxy.size.height)
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.stagedCapture.images.count)
        .opacity((isKeyboardVisible || isAudioReview) ? 0 : 1)
        .allowsHitTesting(!isKeyboardVisible && !isAudioReview)
        .animation(.easeInOut(duration: 0.2), value: isAudioReview)
    }
}

// MARK: - Capture Button

/// Single button that transitions between the white shutter style (Visual),
/// the red record style (Audio), and the submit/stage style (Describe)
/// in place, with no position change.
private struct CaptureButton: View {
    let captureMode: CaptureMode
    let willStageOnly: Bool
    let onAction: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(AudioCaptureManager.self) private var audioCaptureManager

    private var outerRingColor: Color {
        switch captureMode {
        case .visual:   return .white
        case .audio:    return colorScheme == .dark ? .white : Color(UIColor.label)
        case .describe: return Color(UIColor.label)
        }
    }

    private var isRecording: Bool { captureMode == .audio && audioCaptureManager.isRecording }
    private var isPaused: Bool { captureMode == .audio && audioCaptureManager.isPaused }

    var body: some View {
        ZStack {
            // Track ring — dims and thickens when recording to make room for the progress arc.
            Circle()
                .stroke(outerRingColor.opacity(isRecording ? 0.25 : 1), lineWidth: isRecording ? 3 : 1)
                .frame(width: 80, height: 80)
                .animation(.easeInOut(duration: 0.2), value: isRecording)

            // Progress arc — sweeps red clockwise for the duration of the recording.
            Circle()
                .trim(from: 0, to: isRecording ? audioCaptureManager.recordingProgress : 0)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 80, height: 80)
                .animation(.linear(duration: 0.12), value: audioCaptureManager.recordingProgress)

            ZStack {
                Circle()
                    .fill(captureMode == .audio ? Color.red : (captureMode == .describe ? Color.primary : Color.white))
                    .frame(width: 72, height: 72)
                    .animation(.easeInOut(duration: 0.25), value: captureMode)

                if captureMode == .describe {
                    Image(systemName: willStageOnly ? "plus" : "arrow.up")
                        .font(.system(size: 32))
                        .foregroundStyle(Color(UIColor.systemBackground))
                        .transition(.scale.combined(with: .opacity))
                } else if isRecording {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .contentShape(Circle())
        .accessibilityIdentifier("CaptureShutter")
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            HapticManager.shared.triggerFocusSnap()
            onAction()
        }
    }
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
            HapticManager.shared.triggerMediumPulse()
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
    }
}

// MARK: - Table of Contents Button

/// A button that presents the full table of contents for Describe-mode
/// prompts, allowing users to jump between predefined questions.
private struct TableOfContentsButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.shared.triggerMediumPulse()
            onTap()
        }) {
            Image(systemName: "list.bullet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
        .padding(.leading, 32)
    }
}
