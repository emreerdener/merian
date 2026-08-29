import UIKit

struct ScanThumbnailLoadRequest: Hashable, Sendable {
    let imagePath: String?
    let fallbackImageURL: String?
    let audioPath: String?
    let prefersReferenceForAudio: Bool
    let maxDimension: Int

    var hasVisualSource: Bool {
        imagePath != nil || fallbackImageURL != nil
    }
}

enum ScanThumbnailLoadResult {
    case loaded(UIImage)
    case noVisualSource
    case failed
}

struct ScanThumbnailLoadingDependencies: Sendable {
    let loadSpectrogram: @Sendable (
        _ audioPath: String,
        _ maxDimension: Int
    ) async -> UIImage?
    let loadVisual: @Sendable (
        _ imagePath: String?,
        _ fallbackURL: String?,
        _ maxDimension: Int
    ) async -> UIImage?

    static let live = Self(
        loadSpectrogram: { audioPath, maxDimension in
            await AudioSpectrogramThumbnailLoader.shared.loadImage(
                fromPath: audioPath,
                maxDimension: maxDimension
            )
        },
        loadVisual: { imagePath, fallbackURL, maxDimension in
            await LocalImageLoader.shared.loadImage(
                fromPath: imagePath,
                fallbackUrl: fallbackURL,
                maxDimension: maxDimension
            )
        }
    )
}

struct ScanThumbnailLoader: Sendable {
    private let dependencies: ScanThumbnailLoadingDependencies

    init(dependencies: ScanThumbnailLoadingDependencies = .live) {
        self.dependencies = dependencies
    }

    /// Returns `nil` when the caller was cancelled while a shared loader kept
    /// filling its cache. A cancelled request must never publish that result or
    /// continue into a fallback load for a reused SwiftUI tile.
    func load(_ request: ScanThumbnailLoadRequest) async
        -> ScanThumbnailLoadResult? {
        guard !Task.isCancelled else { return nil }

        if let audioPath = request.audioPath,
           !request.prefersReferenceForAudio {
            let spectrogram = await dependencies.loadSpectrogram(
                audioPath,
                request.maxDimension
            )
            guard !Task.isCancelled else { return nil }
            if let spectrogram {
                return .loaded(spectrogram)
            }
        }

        guard request.hasVisualSource else {
            return .noVisualSource
        }

        let image = await dependencies.loadVisual(
            request.imagePath,
            request.fallbackImageURL,
            request.maxDimension
        )
        guard !Task.isCancelled else { return nil }
        guard let image else { return .failed }
        return .loaded(image)
    }
}
