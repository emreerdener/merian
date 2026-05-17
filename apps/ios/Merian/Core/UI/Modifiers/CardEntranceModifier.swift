import SwiftUI

// MARK: - Card Entrance Modifier

/// Animates a card into view with a fade + upward slide on first appearance.
///
/// Respects two gates before applying motion:
/// - `HardwareOrchestrator.isAnimationEnabled` — false under expedition mode or serious/critical thermal state
/// - `accessibilityReduceMotion` — honours the system accessibility setting
///
/// When either gate is closed, the card renders at full opacity instantly.
private struct CardEntranceModifier: ViewModifier {
    let index: Int

    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldAnimate: Bool {
        HardwareOrchestrator.shared.isAnimationEnabled && !reduceMotion
    }

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared || !shouldAnimate ? 1 : 0)
            .offset(y: hasAppeared || !shouldAnimate ? 0 : 20)
            .onAppear {
                guard shouldAnimate, !hasAppeared else { return }
                let delay = Double(index) * 0.07
                withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(delay)) {
                    hasAppeared = true
                }
            }
    }
}

// MARK: - View Extension

extension View {
    /// Applies a staggered entrance animation gated by hardware and accessibility constraints.
    /// - Parameter index: Position in the stagger sequence. Higher index = longer delay.
    func cardEntrance(index: Int) -> some View {
        modifier(CardEntranceModifier(index: index))
    }
}
