import CoreGraphics

enum SpeciesDictionaryCatalogStyle {
    static let cardCornerRadius: CGFloat = 16
    static let thumbnailCornerRadius: CGFloat = 12
    static let skeletonTextCornerRadius: CGFloat = 6
    static let skeletonPillCornerRadius: CGFloat = 10
    static let chevronSkeletonCornerRadius: CGFloat = 4

    static func regionMapImageHeight(for width: CGFloat) -> CGFloat {
        max(210, min(260, width * 0.60))
    }
}
