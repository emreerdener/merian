import SwiftData
import SwiftUI

// MARK: - Capture Control Bar

/// A horizontal control bar pinned to the bottom of the camera interface.
/// It orchestrates the primary capture button along with secondary tools
/// (like the photo library, table of contents, flash toggle, and dictation)
/// based on the current capture mode.
struct CaptureControlBar: View {
    @Bindable var viewModel: CameraViewModel
    let captureMode: CaptureMode
    @Binding var observationContext: ObservationContext
    let isKeyboardVisible: Bool
    let onTableOfContentsTap: () -> Void
    let onDictationTap: () -> Void

    @Environment(CameraManager.self) private var cameraManager
    @Environment(PhotoLibraryManager.self) private var photoLibraryManager
    @Environment(SpeechManager.self) private var speechManager
    @Environment(\.modelContext) private var modelContext

    @AppStorage("isMultiCaptureEnabled") private var isMultiCaptureEnabled: Bool = false

    var body: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                ZStack(alignment: .leading) {
                    PhotoLibraryButton(
                        selectedPhotoItems: $viewModel.selectedPhotoItems,
                        latestThumbnail: photoLibraryManager.latestThumbnail,
                        maxSelectionCount: isMultiCaptureEnabled ? max(1, stagedImageCapacity - viewModel.stagedCapture.images.count) : 1
                    )
                    .opacity(captureMode == .visual ? 1 : 0)
                    .allowsHitTesting(captureMode == .visual)
                    
                    TableOfContentsButton(
                        onTap: onTableOfContentsTap
                    )
                    .opacity(captureMode == .describe ? 1 : 0)
                    .allowsHitTesting(captureMode == .describe)
                }
                .animation(.easeInOut(duration: 0.2), value: captureMode)

                Spacer()

                let willStageOnly = isMultiCaptureEnabled && (UserDefaults.standard.bool(forKey: "requiresScanConfirmation") || viewModel.stagedCapture.images.isEmpty)
                
                CaptureButton(
                    captureMode: captureMode,
                    willStageOnly: willStageOnly,
                    onAction: {
                        switch captureMode {
                        case .visual:
                            viewModel.executeCapture()
                        case .audio:
                            break
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

                Spacer()
                ZStack {
                    FlashButton(
                        isFlashEnabled: cameraManager.isFlashEnabled,
                        onToggleFlash: { cameraManager.toggleFlash() }
                    )
                    .opacity(captureMode == .visual ? 1 : 0)
                    .allowsHitTesting(captureMode == .visual)

                    DictationButton(
                        isRecording: speechManager.isRecording,
                        onToggleDictation: onDictationTap
                    )
                    .opacity(captureMode == .describe ? 1 : 0)
                    .allowsHitTesting(captureMode == .describe)
                }
                .animation(.easeInOut(duration: 0.2), value: captureMode)
            }
            .disabled(viewModel.isStagingRefinement)
            .padding(.bottom, 140)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.stagedCapture.images.count)
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
    let onAction: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .stroke(captureMode == .visual ? Color.white : Color.primary, lineWidth: 1)
                .frame(width: 80, height: 80)

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
