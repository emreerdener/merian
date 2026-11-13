import SwiftUI

struct ViewfinderHints: View {
    @Environment(ViewfinderIntelligence.self) private var vui
    @Environment(RevenueCatManager.self) private var revenueCatManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isCameraVisible: Bool = false
    var hasEmptyDraft: Bool = true
    var isCapturing: Bool = false
    var claimIntroduction: @MainActor () -> Bool = { false }
    var isRefining: Bool = false
    var isVideoRecording: Bool = false
    var videoRecordingProgress: Double = 0
    @State private var presentation = ViewfinderHintPresentation()

    private var context: ViewfinderHintPresentation.Context {
        var context = ViewfinderHintPresentation.Context(
            isVisible: isCameraVisible,
            hasEmptyDraft: hasEmptyDraft,
            isRefining: isRefining,
            isCapturing: isCapturing || isVideoRecording,
            canRecordVideo: revenueCatManager.canStartProScan
        )
        #if DEBUG
        context.keepsPromptVisible = ProcessInfo.processInfo.arguments
            .contains("-keepViewfinderHintVisible")
        #endif
        return context
    }

    var body: some View {
        Group {
            if isCameraVisible {
                if isVideoRecording {
                    RecordingCountdownBadge(
                        progress: videoRecordingProgress,
                        duration: CaptureWorkspaceViewModel.videoMaxDuration,
                        accessibilityPrefix: "Video recording time remaining"
                    )
                } else if let text = presentation.phase.text {
                    hint(text)
                        .id(presentation.phase)
                } else if presentation.allowsGuidance && !vui.isOptimal && !isCapturing {
                    hint(vui.currentHint.rawValue)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: presentation.phase)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: presentation.allowsGuidance)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isVideoRecording)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: vui.isOptimal)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ViewfinderHint")
        .onChange(of: context, initial: true) { _, context in
            presentation.update(context, claimIntroduction: claimIntroduction)
        }
        .onAppear { presentation.update(context, claimIntroduction: claimIntroduction) }
        .onDisappear { presentation.hide() }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(Capsule())
            .transition(.opacity)
    }
}
