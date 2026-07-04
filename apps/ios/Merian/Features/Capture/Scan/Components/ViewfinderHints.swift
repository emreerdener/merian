import SwiftUI

struct ViewfinderHints: View {
    @Environment(ViewfinderIntelligence.self) var vui
    @Environment(RevenueCatManager.self) private var revenueCatManager
    var isRefining: Bool = false
    var isVideoRecording: Bool = false
    var videoRecordingProgress: Double = 0
    @State private var showInitialPrompt: Bool = true
    /// Stays false until the initial prompt has fully faded out, preventing the VUI hint
    /// from cross-fading in while the welcome text is still visible on screen.
    @State private var vuiHintsAllowed: Bool = false
    @State private var promptTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isVideoRecording {
                RecordingCountdownBadge(
                    progress: videoRecordingProgress,
                    duration: CaptureWorkspaceViewModel.videoMaxDuration,
                    accessibilityPrefix: "Video recording time remaining"
                )
            } else if showInitialPrompt {
                Text(isRefining ? "Add another" : (revenueCatManager.isProActive ? "Hold to record video" : "Tap to identify"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .clipShape(Capsule())
                    .transition(.opacity)
            } else if vuiHintsAllowed && !vui.isOptimal {
                Text(vui.currentHint.rawValue)
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
        .animation(.easeInOut(duration: 0.3), value: showInitialPrompt)
        .animation(.easeInOut(duration: 0.3), value: isVideoRecording)
        .animation(.easeInOut(duration: 0.3), value: vui.isOptimal)
        .onAppear {
            schedulePromptDismissal()
        }
        .onChange(of: isRefining) { _, refining in
            guard refining else { return }
            // Re-surface the prompt with refinement-specific text each time the
            // user enters refinement mode (e.g. multiple sessions in one app launch).
            promptTask?.cancel()
            vuiHintsAllowed = false
            withAnimation { showInitialPrompt = true }
            schedulePromptDismissal()
        }
    }

    private func schedulePromptDismissal() {
        promptTask?.cancel()
        promptTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 s
            guard !Task.isCancelled else { return }
            withAnimation { showInitialPrompt = false }
            try? await Task.sleep(nanoseconds: 350_000_000) // 0.35 s
            guard !Task.isCancelled else { return }
            vuiHintsAllowed = true
        }
    }
}
