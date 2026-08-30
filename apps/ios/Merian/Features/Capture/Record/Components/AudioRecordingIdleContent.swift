import SwiftUI

struct AudioRecordingIdleContent: View {
    let viewModel: AudioRecordingViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(viewModel.idleArtworkName)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 24)
                .id(viewModel.idleArtworkIndex)
                .transition(.opacity)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        viewModel.advanceIdleArtworkAfterSelection()
                    }
                }
        }
        .onReceive(
            Timer.publish(every: 6, on: .main, in: .common).autoconnect()
        ) { _ in
            withAnimation(.easeInOut(duration: 0.8)) {
                viewModel.advanceIdleArtworkAfterTimer()
            }
        }
    }
}

struct AudioRecordingIdlePrompt: View {
    var body: some View {
        Text("Record nearby sounds")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(Capsule())
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityIdentifier("AudioIdlePrompt")
    }
}
