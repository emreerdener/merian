import SwiftUI

struct UnavailableVideoView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.title)
            Text("Video Unavailable")
                .font(.subheadline)
        }
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Video unavailable")
    }
}

struct CenterVideoPlaybackControl: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            if !isPlaying {
                Image(systemName: "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.46), in: Circle())
                    .shadow(
                        color: .black.opacity(0.26),
                        radius: 12,
                        x: 0,
                        y: 6
                    )
                    .allowsHitTesting(false)
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.96))
                    )
            }
        }
        .frame(
            width: MediaCarouselInteractionPolicy.centerPlaybackHitSize,
            height: MediaCarouselInteractionPolicy.centerPlaybackHitSize
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isPlaying ? "Pause video" : "Play video")
        .accessibilityAction {
            action()
        }
        .animation(.easeInOut(duration: 0.22), value: isPlaying)
    }
}
