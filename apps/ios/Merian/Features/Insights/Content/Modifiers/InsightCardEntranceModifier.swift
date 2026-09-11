import SwiftUI

/// Animates an Insight content card into view on first appearance.
private struct InsightCardEntranceModifier: ViewModifier {
    let index: Int
    let isAnimationEnabled: Bool

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool {
        isAnimationEnabled && !reduceMotion
    }

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared || !shouldAnimate ? 1 : 0)
            .offset(y: hasAppeared || !shouldAnimate ? 0 : 20)
            .onAppear {
                guard shouldAnimate, !hasAppeared else { return }
                let delay = Double(index) * 0.07
                withAnimation(.spring(
                    response: 0.5,
                    dampingFraction: 0.78
                ).delay(delay)) {
                    hasAppeared = true
                }
            }
    }
}

extension View {
    func insightCardEntrance(
        index: Int,
        isAnimationEnabled: Bool
    ) -> some View {
        modifier(InsightCardEntranceModifier(
            index: index,
            isAnimationEnabled: isAnimationEnabled
        ))
    }
}
