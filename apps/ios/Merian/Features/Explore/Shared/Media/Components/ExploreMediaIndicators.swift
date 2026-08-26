import SwiftUI

struct ExploreMediaPlayIndicator: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(.black.opacity(0.42), in: Circle())
            .accessibilityLabel("Video")
    }
}

struct ExploreMediaTypeIndicator: View {
    let kind: ExploreMediaKind

    var body: some View {
        Image(systemName: kind == .video ? "play.fill" : "waveform")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(.black.opacity(0.62), in: Circle())
            .accessibilityLabel(kind == .video ? "Video" : "Audio recording")
    }
}
