import CoreGraphics

enum DictionaryHeroEdgePolicy {
    static let toolbarLowerBoundary: CGFloat = 44
    static let returnHysteresis: CGFloat = 4

    static func shouldHideEffect(
        heroMaxY: CGFloat,
        isCurrentlyHidden: Bool
    ) -> Bool? {
        guard heroMaxY.isFinite else { return nil }

        if isCurrentlyHidden {
            return heroMaxY > toolbarLowerBoundary
        }

        return heroMaxY >= toolbarLowerBoundary + returnHysteresis
    }
}
