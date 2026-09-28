import SwiftUI

/// Full-screen presentation for idle, recording, and review audio states.
/// Capture lifecycle actions remain owned by the Capture shell controls.
struct AudioRecordingView: View {
    @Environment(\.captureChromeLayout) private var chromeLayout
    let presentation: AudioRecordingPresentation
    let showsIdlePrompt: Bool

    @Environment(\.composingCenter) private var composingCenter
    @State private var viewModel: AudioRecordingViewModel

    init(
        presentation: AudioRecordingPresentation,
        showsIdlePrompt: Bool,
        dependencies: AudioRecordingViewModel.Dependencies
    ) {
        self.presentation = presentation
        self.showsIdlePrompt = showsIdlePrompt
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
            chromeLayout.fullScreenOverlayClearance
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
            if !presentation.showsSpectrogram && showsIdlePrompt {
                AudioRecordingIdlePrompt()
                    .padding(
                        .bottom,
                        chromeLayout.fullScreenOverlayClearance + 16
                    )
            } else if presentation.isReviewing {
                Text("Recording couldn’t be added. Free a media slot, then tap + to retry.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .padding(.bottom, chromeLayout.fullScreenOverlayClearance + 16)
            } else if presentation.isRecording {
                AudioSNRGuidanceView(
                    snrLevel: presentation.snrLevel,
                    audioHintsEnabled: presentation.audioHintsEnabled
                )
                .padding(
                    .bottom,
                    chromeLayout.fullScreenOverlayClearance + 16
                )
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
