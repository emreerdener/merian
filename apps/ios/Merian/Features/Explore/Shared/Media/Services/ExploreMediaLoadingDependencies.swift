import UIKit

struct ExploreHeroImageDependencies {
    let loadImage: @Sendable (_ imageURL: String, _ maxDimension: Int) async -> UIImage?

    static let live = Self { imageURL, maxDimension in
        await LocalImageLoader.shared.loadImage(
            fromPath: nil,
            fallbackUrl: imageURL,
            maxDimension: maxDimension
        )
    }
}

struct ExploreAudioSpectrogramDependencies {
    let loadImage: @Sendable (_ audioURL: String, _ maxDimension: Int) async -> UIImage?

    static let live = Self { audioURL, maxDimension in
        await AudioSpectrogramThumbnailLoader.shared.loadImage(
            fromPath: audioURL,
            maxDimension: maxDimension
        )
    }
}
