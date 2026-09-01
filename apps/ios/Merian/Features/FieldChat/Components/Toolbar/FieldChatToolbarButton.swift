import SwiftUI

struct FieldChatToolbarButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = -1.0

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text("Field chat")
            }
            .padding(.horizontal, 8)
            .fixedSize()
        }
        .background {
            FieldChatGlowAccent()
                .frame(width: 140, height: 42)
        }
        .overlay {
            FieldChatBorderShimmer(phase: shimmerPhase)
                .frame(width: 140, height: 42)
                .opacity(reduceMotion ? 0 : 1)
        }
        .accessibilityLabel("Open Field chat")
        .accessibilityIdentifier("FieldChatToolbarButton")
        .task(id: reduceMotion) {
            guard !reduceMotion else {
                shimmerPhase = -1.0
                return
            }

            while !Task.isCancelled {
                let pause = Double.random(in: 5.5...8.5)
                try? await Task.sleep(for: .seconds(pause))
                guard !Task.isCancelled else { break }

                shimmerPhase = -1.0
                try? await Task.sleep(nanoseconds: 50_000_000)

                withAnimation(.easeOut(duration: 1.8)) {
                    shimmerPhase = 2.5
                }
            }
        }
    }
}

private struct FieldChatBorderShimmer: View {
    let phase: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(
                                color: Color.white.opacity(0.75),
                                location: 0.46
                            ),
                            .init(
                                color: Color(
                                    red: 0.30,
                                    green: 0.95,
                                    blue: 0.65
                                ).opacity(0.7),
                                location: 0.5
                            ),
                            .init(
                                color: Color.white.opacity(0.55),
                                location: 0.54
                            ),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width)
                .offset(x: phase * width * 2)
                .blendMode(.screen)
                .mask {
                    Capsule(style: .continuous)
                        .strokeBorder(lineWidth: 1.4)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FieldChatGlowAccent: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(
                AngularGradient(
                    colors: [
                        Color(red: 0.20, green: 0.55, blue: 1.00),
                        Color(red: 0.30, green: 0.95, blue: 0.65),
                        Color(red: 1.00, green: 0.88, blue: 0.30),
                        Color(red: 1.00, green: 0.38, blue: 0.58),
                        Color(red: 0.62, green: 0.40, blue: 1.00),
                        Color(red: 0.20, green: 0.55, blue: 1.00)
                    ],
                    center: .center
                )
            )
            .blur(radius: 7)
            .opacity(0.32)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
