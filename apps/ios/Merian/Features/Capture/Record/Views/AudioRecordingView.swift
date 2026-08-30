import SwiftUI

/// Full-screen presentation for idle, recording, and review audio states.
/// Capture lifecycle actions remain owned by the Capture shell controls.
struct AudioRecordingView: View {
    let presentation: AudioRecordingPresentation

    @Environment(\.composingCenter) private var composingCenter
    @State private var viewModel: AudioRecordingViewModel

    init(
        presentation: AudioRecordingPresentation,
        dependencies: AudioRecordingViewModel.Dependencies
    ) {
        self.presentation = presentation
        _viewModel = State(
            initialValue: AudioRecordingViewModel(
                dependencies: dependencies
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(UIColor.systemBackground).ignoresSafeArea()

                if presentation.showsSpectrogram {
                    recordingOrReviewContent(in: proxy)
                } else {
                    AudioRecordingIdleContent(viewModel: viewModel)
                        .position(
                            x: proxy.size.width / 2,
                            y: proxy.size.height * composingCenter
                        )
                }

                bottomGuidance
            }
        }
        .animation(
            .easeInOut(duration: 0.25),
            value: presentation.isRecording
        )
        .animation(
            .easeInOut(duration: 0.25),
            value: presentation.isReviewing
        )
    }

    private func recordingOrReviewContent(
        in proxy: GeometryProxy
    ) -> some View {
        let bottomClearance =
            CaptureControlBarLayout.fullScreenOverlayClearance
        let spectrogramHeight = AudioRecordingLayoutPolicy.spectrogramHeight(
            viewportHeight: Double(proxy.size.height),
            composingCenter: Double(composingCenter),
            bottomClearance: Double(bottomClearance)
        )

        return VStack(spacing: 16) {
            RecordingCountdownBadge(
                progress: presentation.countdownProgress,
                duration: presentation.maximumDuration,
                accessibilityPrefix:
                    presentation.countdownAccessibilityPrefix
            )
            AudioRecordingSpectrogramContent(
                presentation: presentation,
                height: CGFloat(spectrogramHeight),
                viewModel: viewModel
            )
            .frame(width: proxy.size.width)
        }
        .position(
            x: proxy.size.width / 2,
            y: proxy.size.height * composingCenter
        )
    }

    private var bottomGuidance: some View {
        VStack {
            Spacer()
            if !presentation.showsSpectrogram {
                AudioRecordingIdlePrompt()
                    .padding(
                        .bottom,
                        CaptureControlBarLayout.fullScreenOverlayClearance + 16
                    )
            } else if presentation.isRecording {
                AudioSNRGuidanceView(
                    snrLevel: presentation.snrLevel,
                    audioHintsEnabled: presentation.audioHintsEnabled
                )
                .padding(
                    .bottom,
                    CaptureControlBarLayout.fullScreenOverlayClearance + 16
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
