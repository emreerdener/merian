import SwiftUI
import UIKit

@MainActor
struct ProfilePublicScanImageView: View {
    let imagePath: String?
    let fallbackURL: String?
    let reloadGeneration: UInt64

    private let dependencies: ProfilePublicScanImageDependencies
    @State private var loadedImage: UIImage?
    @State private var hasFailedToLoad = false

    init(
        imagePath: String?,
        fallbackURL: String?,
        reloadGeneration: UInt64,
        dependencies: ProfilePublicScanImageDependencies? = nil
    ) {
        self.imagePath = imagePath
        self.fallbackURL = fallbackURL
        self.reloadGeneration = reloadGeneration
        self.dependencies = dependencies ?? .live
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
        .task(id: loadTaskID) {
            loadedImage = nil
            hasFailedToLoad = false

            let image = await dependencies.loadImage(
                imagePath,
                fallbackURL,
                360
            )
            guard !Task.isCancelled else { return }
            loadedImage = image
            hasFailedToLoad = image == nil
        }
    }

    private var loadTaskID: ProfilePublicScanImageLoadTaskID {
        ProfilePublicScanImageLoadTaskID(
            imagePath: imagePath,
            fallbackURL: fallbackURL,
            reloadGeneration: reloadGeneration,
            maxDimension: 360
        )
    }

    private var loadingPlaceholder: some View {
        GlowPulsingSkeletonView(cornerRadius: 3, style: .raisedGrid)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failurePlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(uiColor: .tertiarySystemFill),
                    Color(uiColor: .secondarySystemFill)
                ],
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

private struct ProfilePublicScanImageLoadTaskID: Hashable {
    let imagePath: String?
    let fallbackURL: String?
    let reloadGeneration: UInt64
    let maxDimension: Int
}
