import SwiftUI
import UIKit

struct ExploreHeroImageView: View {
    let imageUrl: String
    let reloadGeneration: UInt64
    let maxDimension: Int
    private let preloadedImage: UIImage?
    private let dependencies: ExploreHeroImageDependencies

    @State private var loadedImage: UIImage?
    @State private var hasFailedToLoad = false

    init(
        imageUrl: String,
        reloadGeneration: UInt64,
        maxDimension: Int = Int(MerianConfig.displayImageMaxSize),
        preloadedImage: UIImage? = nil
    ) {
        self.init(
            imageUrl: imageUrl,
            reloadGeneration: reloadGeneration,
            maxDimension: maxDimension,
            preloadedImage: preloadedImage,
            dependencies: .live
        )
    }

    init(
        imageUrl: String,
        reloadGeneration: UInt64,
        maxDimension: Int = Int(MerianConfig.displayImageMaxSize),
        preloadedImage: UIImage? = nil,
        dependencies: ExploreHeroImageDependencies
    ) {
        self.imageUrl = imageUrl
        self.reloadGeneration = reloadGeneration
        self.maxDimension = maxDimension
        self.preloadedImage = preloadedImage
        self.dependencies = dependencies
        _loadedImage = State(initialValue: preloadedImage)
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let loadedImage {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFill()
                } else if hasFailedToLoad {
                    failurePlaceholder
                } else {
                    loadingPlaceholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(imageUrl)|\(reloadGeneration)") {
            guard preloadedImage == nil else {
                hasFailedToLoad = false
                return
            }

            loadedImage = nil
            hasFailedToLoad = false

            let image = await dependencies.loadImage(imageUrl, maxDimension)
            guard !Task.isCancelled else { return }

            if let image {
                loadedImage = image
            } else {
                hasFailedToLoad = true
            }
        }
    }

    private var loadingPlaceholder: some View {
        GlowPulsingSkeletonView(cornerRadius: 12)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failurePlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(uiColor: .tertiarySystemFill), Color(uiColor: .secondarySystemFill)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "photo")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
