import SwiftUI

/// The primary Capture action that retains press and long-press timing locally.
struct CapturePrimaryActionButton: View {
    let presentation: CapturePrimaryActionPresentation
    let isInteractionEnabled: Bool
    let onAction: () -> Void
    let onVisualLongPress: () -> Void
    let onHapticFeedback: (CaptureButtonHapticFeedback) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var pressState = PressState.idle
    @State private var videoLongPressTask: Task<Void, Never>?

    private let videoHoldStartDelayNanoseconds: UInt64 = 180_000_000

    private var outerRingColor: Color {
        switch presentation.captureMode {
        case .visual:
            return .white
        case .audio:
            return colorScheme == .dark ? .white : Color(UIColor.label)
        case .describe:
            return Color(UIColor.label)
        }
    }

    private var innerFill: Color {
        switch presentation.captureMode {
        case .visual:
            return presentation.isVideoRecording ? .red : .white
        case .describe:
            return presentation.isInputActive ? Color.primary : Color.clear
        case .audio:
            if presentation.isAudioReview {
                return Color.primary
            }
            if presentation.isAudioRecording,
               !presentation.isAudioPaused {
                return Color.primary
            }
            return Color.red
        }
    }

    private var iconColor: Color {
        switch presentation.captureMode {
        case .describe:
            return presentation.isInputActive
                ? Color(UIColor.systemBackground)
                : Color.primary
        default:
            return Color(UIColor.systemBackground)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    outerRingColor.opacity(
                        presentation.shouldShowRecordingChrome ? 0.25 : 1
                    ),
                    lineWidth: 1
                )
                .frame(
                    width: CaptureControlBarLayout.primaryControlSize,
                    height: CaptureControlBarLayout.primaryControlSize
                )
                .animation(
                    .easeInOut(duration: 0.2),
                    value: presentation.shouldShowRecordingChrome
                )

            if !presentation.isAudioReview {
                Circle()
                    .trim(
                        from: 0,
                        to: presentation.shouldShowRecordingChrome
                            ? presentation.recordingProgress
                            : 0
                    )
                    .stroke(
                        Color.red,
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(
                        width: CaptureControlBarLayout.primaryControlSize,
                        height: CaptureControlBarLayout.primaryControlSize
                    )
                    .animation(
                        .linear(duration: 0.12),
                        value: presentation.recordingProgress
                    )
            }

            ZStack {
                Circle()
                    .fill(innerFill)
                    .frame(width: 72, height: 72)
                    .animation(
                        .easeInOut(duration: 0.25),
                        value: presentation.isAudioReview
                    )
                    .animation(
                        .easeInOut(duration: 0.2),
                        value: presentation.isInputActive
                    )
                    .animation(
                        .easeInOut(duration: 0.2),
                        value: presentation.isAudioRecording
                            && !presentation.isAudioPaused
                    )

                actionIcon
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
        .onChange(of: presentation.captureMode) {
            invalidatePendingPress(awaitingRelease: true)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                cancelPendingPress()
            }
        }
        .onChange(of: isInteractionEnabled) { _, isEnabled in
            if !isEnabled {
                cancelPendingPress()
            }
        }
        .onDisappear {
            cancelPendingPress()
        }
    }

    @ViewBuilder
    private var actionIcon: some View {
        if presentation.captureMode == .visual,
           presentation.isVideoRecording {
            Image(systemName: "stop.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.white)
                .transition(.scale.combined(with: .opacity))
        } else if presentation.captureMode == .describe
            || presentation.isAudioReview {
            Image(
                systemName: presentation.willStageOnly ? "plus" : "arrow.up"
            )
            .font(.system(size: 32))
            .foregroundStyle(iconColor)
            .transition(.scale.combined(with: .opacity))
            .animation(
                .easeInOut(duration: 0.2),
                value: presentation.isInputActive
            )
        } else if presentation.isAudioRecording,
                  !presentation.isAudioPaused {
            Image(systemName: "pause.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color(UIColor.systemBackground))
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func handlePressBegan() {
        guard pressState == .idle,
              isInteractionEnabled,
              scenePhase == .active else { return }
        pressState = .pressed
        onHapticFeedback(.prepareHeavyImpact)

        guard presentation.captureMode == .visual,
              !presentation.isVideoRecording else {
            return
        }

        videoLongPressTask?.cancel()
        videoLongPressTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: videoHoldStartDelayNanoseconds
            )
            guard !Task.isCancelled,
                  pressState == .pressed else { return }
            pressState = .visualHoldTriggered
            onVisualLongPress()
        }
    }

    private func handlePressEnded() {
        guard pressState != .idle else { return }
        let completedPressState = pressState
        videoLongPressTask?.cancel()
        videoLongPressTask = nil
        pressState = .idle

        guard completedPressState != .cancelled else { return }

        if presentation.captureMode == .visual,
           completedPressState == .visualHoldTriggered {
            return
        }

        if presentation.captureMode == .visual,
           presentation.isVideoRecording {
            onAction()
            return
        }

        onHapticFeedback(presentation.releaseHapticFeedback)
        onAction()
    }

    private func cancelPendingPress() {
        invalidatePendingPress(awaitingRelease: false)
    }

    private func invalidatePendingPress(awaitingRelease: Bool) {
        videoLongPressTask?.cancel()
        videoLongPressTask = nil
        if awaitingRelease, pressState != .idle {
            pressState = .cancelled
        } else {
            pressState = .idle
        }
    }

    private enum PressState {
        case idle
        case pressed
        case visualHoldTriggered
        case cancelled
    }
}
