import SwiftUI

struct InsightCarouselVideoMuteControl: View {
    @Binding var isMuted: Bool
    let feedback: () -> Void

    var body: some View {
        Button {
            isMuted.toggle()
            feedback()
        } label: {
            Label(
                isMuted ? "Muted" : "Sound on",
                systemImage: isMuted
                    ? "speaker.slash.fill"
                    : "speaker.wave.2.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.28))
            }
            .background(
                .ultraThinMaterial,
                in: Capsule(style: .continuous)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? "Video muted" : "Video sound on")
        .accessibilityHint("Toggles video sound")
        .padding(.leading, 14)
        .padding(.bottom, 40)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .leading)),
            removal: .opacity
        ))
        .animation(
            .spring(response: 0.3, dampingFraction: 0.8),
            value: isMuted
        )
    }
}

struct InsightCarouselReferenceAttributionTag: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.28))
            }
            .background(
                .ultraThinMaterial,
                in: Capsule(style: .continuous)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .padding(.trailing, 14)
            .padding(.bottom, 40)
            .allowsHitTesting(false)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity
            ))
    }
}
