import SwiftUI

/// Shared rainbow glow and occasional border sweep for glass capsule controls.
private struct RainbowCapsuleAccentModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = -1.0
    let width: CGFloat?
    let height: CGFloat?

    func body(content: Content) -> some View {
        content
            .background {
                RainbowCapsuleGlow()
                    .frame(width: width, height: height)
            }
            .overlay {
                RainbowCapsuleBorderShimmer(phase: shimmerPhase)
                    .frame(width: width, height: height)
                    .opacity(reduceMotion ? 0 : 1)
            }
            .task(id: reduceMotion) {
                guard !reduceMotion else {
                    shimmerPhase = -1.0
                    return
                }
                while !Task.isCancelled {
                    let pause = Double.random(in: 5.5...8.5)
                    do {
                        try await Task.sleep(for: .seconds(pause))
                        shimmerPhase = -1.0
                        try await Task.sleep(for: .milliseconds(50))
                        try Task.checkCancellation()
                    } catch {
                        return
                    }
                    withAnimation(.easeOut(duration: 1.8)) {
                        shimmerPhase = 2.5
                    }
                }
            }
    }
}

extension View {
    func rainbowCapsuleAccent(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        modifier(RainbowCapsuleAccentModifier(width: width, height: height))
    }
}

private struct RainbowCapsuleBorderShimmer: View {
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

private struct RainbowCapsuleGlow: View {
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
