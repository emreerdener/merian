import SwiftUI

/// Shared iOS 26 scroll-edge treatment for media heroes rendered beneath a
/// transparent navigation toolbar.
struct MediaHeroTopScrollEdgeEffectModifier: ViewModifier {
    let isHidden: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(isHidden, for: .top)
        } else {
            content
        }
    }
}

enum MediaHeroTopScrollEdgeEffectPolicy {
    static func isHidden(
        heroMaxY: CGFloat,
        currentlyHidden: Bool
    ) -> Bool {
        guard heroMaxY.isFinite else { return currentlyHidden }

        let toolbarLowerBoundary: CGFloat = 44
        let returnHysteresis: CGFloat = 4
        if currentlyHidden {
            return heroMaxY > toolbarLowerBoundary
        }
        return heroMaxY >= toolbarLowerBoundary + returnHysteresis
    }
}
