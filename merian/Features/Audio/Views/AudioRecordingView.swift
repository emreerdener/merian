import SwiftUI

/// Placeholder content for the audio recording mode.
/// All persistent controls (MediaModeToggle, capture button, tab bar) are rendered
/// in CameraRootView's fixed overlay so they remain visible across both pages.
struct AudioRecordingView: View {
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 12) {
                Image("bird_tree")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)

                Text("Audio recording coming soon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
} 
