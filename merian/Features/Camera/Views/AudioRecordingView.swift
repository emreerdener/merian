import SwiftUI

/// Placeholder content for the audio recording mode.
/// All persistent controls (MediaModeToggle, capture button, tab bar) are rendered
/// in CameraRootView's fixed overlay so they remain visible across both pages.
struct AudioRecordingView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.2))

                Text("Audio recording coming soon")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}
