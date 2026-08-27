import UIKit

struct ExplorePostComposerImageDependencies {
    let loadImage: @MainActor (
        _ path: String,
        _ maxDimension: Int
    ) async -> UIImage?
}

extension ExplorePostComposerImageDependencies {
    static let live = Self(
        loadImage: { path, maxDimension in
            await LocalImageLoader.shared.loadImage(
                fromPath: path,
                fallbackUrl: nil,
                maxDimension: maxDimension
            )
        }
    )
}
