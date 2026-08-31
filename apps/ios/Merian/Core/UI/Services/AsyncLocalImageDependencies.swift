import UIKit

@MainActor
struct AsyncLocalImageDependencies {
    let loadImage: @MainActor (
        _ path: String?,
        _ fallbackURL: String?,
        _ maxDimension: Int
    ) async -> UIImage?

    init(
        loadImage: @escaping @MainActor (
            _ path: String?,
            _ fallbackURL: String?,
            _ maxDimension: Int
        ) async -> UIImage?
    ) {
        self.loadImage = loadImage
    }

    static var live: Self {
        Self(
            loadImage: { path, fallbackURL, maxDimension in
                await LocalImageLoader.shared.loadImage(
                    fromPath: path,
                    fallbackUrl: fallbackURL,
                    maxDimension: maxDimension
                )
            }
        )
    }
}
