import SwiftUI
import UIKit

#if DEBUG
private enum ExploreMediaPreviewFixtures {
    static let landscape = makeImage(
        size: CGSize(width: 1200, height: 800),
        topColor: .systemTeal,
        bottomColor: .systemOrange
    )

    static let portrait = makeImage(
        size: CGSize(width: 800, height: 1200),
        topColor: .systemPink,
        bottomColor: .systemIndigo
    )

    static let square = makeImage(
        size: CGSize(width: 1000, height: 1000),
        topColor: .systemGreen,
        bottomColor: .systemBlue
    )

    private static func makeImage(
        size: CGSize,
        topColor: UIColor,
        bottomColor: UIColor
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let bounds = CGRect(origin: .zero, size: size)
            topColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.5))

            bottomColor.setFill()
            context.fill(CGRect(x: 0, y: bounds.height * 0.5, width: bounds.width, height: bounds.height * 0.5))
        }
    }
}

#Preview("Explore Feed Media - Landscape") {
    ExploreFeedMediaView(
        postId: "preview-landscape",
        imageUrl: "preview-landscape",
        reloadGeneration: 0,
        preloadedImage: ExploreMediaPreviewFixtures.landscape
    )
    .padding()
    .background(Color(uiColor: .secondarySystemGroupedBackground))
}

#Preview("Explore Feed Media - Portrait") {
    ExploreFeedMediaView(
        postId: "preview-portrait",
        imageUrl: "preview-portrait",
        reloadGeneration: 0,
        preloadedImage: ExploreMediaPreviewFixtures.portrait
    )
    .padding()
    .background(Color(uiColor: .secondarySystemGroupedBackground))
}

#Preview("Explore Detail Media - Square") {
    ExploreDetailMediaView(
        postId: "preview-square",
        imageUrl: "preview-square",
        reloadGeneration: 0,
        preloadedImage: ExploreMediaPreviewFixtures.square
    )
    .padding()
    .background(Color(uiColor: .secondarySystemGroupedBackground))
}
#endif
