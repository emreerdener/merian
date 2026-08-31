import SwiftUI

struct InsightChatEmptyAccentGradient: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hueRotationDegrees = 0.0

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.28, green: 0.68, blue: 1.0).opacity(0.28), location: 0),
                .init(color: Color(red: 0.44, green: 0.78, blue: 1.0).opacity(0.16), location: 0.24),
                .init(color: Color(red: 0.64, green: 0.48, blue: 1.0).opacity(0.07), location: 0.5),
                .init(color: Color(red: 0.28, green: 0.68, blue: 1.0).opacity(0), location: 0.74)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .hueRotation(.degrees(reduceMotion ? 0 : hueRotationDegrees))
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }

            withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                hueRotationDegrees = 360
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                hueRotationDegrees = 0
            } else {
                withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                    hueRotationDegrees = 360
                }
            }
        }
    }
}
