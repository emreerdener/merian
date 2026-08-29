import UIKit

struct ProfilePublicScanImageDependencies {
    let loadImage: @Sendable (
        _ imagePath: String?,
        _ fallbackURL: String?,
        _ maxDimension: Int
    ) async -> UIImage?

    static let live = Self(
        loadImage: { imagePath, fallbackURL, maxDimension in
            await LocalImageLoader.shared.loadImage(
                fromPath: imagePath,
                fallbackUrl: fallbackURL,
                maxDimension: maxDimension
            )
        }
    )
}
