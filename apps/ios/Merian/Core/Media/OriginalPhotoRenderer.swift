import Foundation
import UIKit

/// Pure preparation from an original whose lifetime and integrity the caller
/// already owns. It allocates no files, storage identities or submission rights.
enum OriginalPhotoRenderer {
    enum Source: Sendable {
        case file(URL)
        case bytes(Data)

        func downsample(_ maximum: CGFloat) -> CGImage? {
            switch self {
            case let .file(url): return ImageDownsampler.downsample(url: url, maxSize: maximum)
            case let .bytes(data): return ImageDownsampler.downsample(data: data, maxSize: maximum)
            }
        }

        func image() -> UIImage? {
            switch self {
            case let .file(url): return UIImage(contentsOfFile: url.path)
            case let .bytes(data): return UIImage(data: data)
            }
        }
    }

    struct Output: Sendable {
        let inference: Data
        let display: Data
        let manualFocus: NormalizedImageFocusRegion?
    }

    /// Runs off the main actor. Interactive previews never substitute for source
    /// pixels; geometry and manual focus share ImageCropProcessor's pixel map.
    static func render(_ source: Source, recipe: SharedMediaNativePreparationRecipe) async throws -> Output {
        try recipe.validate(); try Task.checkCancellation()
        let inferenceMaximum = ImagePreparationPolicy.inferenceMaxDimension(isProActive: recipe.isPro)
        let inference: Data, display: Data
        var manualFocus: NormalizedImageFocusRegion?
        if recipe.format == .cameraStill {
            guard let center = recipe.cameraVerticalCenter else { throw SharedMediaStorageFailure.invalid }
            inference = try raster(source, maximum: inferenceMaximum, center: center)
            try Task.checkCancellation()
            display = try raster(source, maximum: ImagePreparationPolicy.displayMaxDimension, center: center)
        } else if let size = recipe.cropDisplaySize {
            guard let image = source.image() else { throw MediaPreparationError.unreadableImage }
            if let selection = recipe.sourceSelection {
                guard let mapping = ImageCropProcessor.cropMapping(image: image, displaySize: size,
                    scale: recipe.scale, offset: .init(width: recipe.offsetX, height: recipe.offsetY),
                    quarterTurns: recipe.quarterTurns),
                    let focus = mapping.focus(fromSourceSelection: selection.rect) else {
                    throw SharedMediaStorageFailure.invalid
                }
                manualFocus = focus
            }
            inference = await crop(image, recipe: recipe, size: size, maximum: inferenceMaximum)
            try Task.checkCancellation()
            display = await crop(image, recipe: recipe, size: size, maximum: ImagePreparationPolicy.displayMaxDimension)
        } else {
            // Identity geometry preserves the upright full-aspect coordinate
            // basis through downsampling and encoding; no square crop applies.
            manualFocus = recipe.sourceSelection
            inference = try raster(source, maximum: inferenceMaximum)
            try Task.checkCancellation()
            display = try raster(source, maximum: ImagePreparationPolicy.displayMaxDimension)
        }
        try Task.checkCancellation()
        guard !inference.isEmpty, !display.isEmpty,
              inference.count <= ScanMediaPayloadPolicy.maxStagedImageBytes,
              display.count <= ScanMediaPayloadPolicy.maxStagedImageBytes else { throw MediaPreparationError.encodingFailed }
        return .init(inference: inference, display: display, manualFocus: manualFocus)
    }

    private static func crop(_ image: UIImage, recipe: SharedMediaNativePreparationRecipe,
                             size: Double, maximum: CGFloat) async -> Data {
        await ImageCropProcessor.generateCrop(image: image, displaySize: size, scale: recipe.scale,
            currentScale: 1, offset: .init(width: recipe.offsetX, height: recipe.offsetY), currentOffset: .zero,
            quarterTurns: recipe.quarterTurns, maxPixelSize: Int(maximum), encoding: .jpeg)
    }

    private static func raster(_ source: Source, maximum: CGFloat, center: Double? = nil) throws -> Data {
        try Task.checkCancellation()
        return try autoreleasepool {
            guard let image = source.downsample(maximum) else { throw MediaPreparationError.unreadableImage }
            let raster: CGImage
            if let center {
                guard let cropped = ImageCropProcessor.squareCrop(image, verticalCenterFraction: center) else {
                    throw MediaPreparationError.unreadableImage
                }
                raster = cropped
            } else { raster = image }
            guard let bytes = ImageCropProcessor.encode(raster, encoding: .jpeg), !bytes.isEmpty else {
                throw MediaPreparationError.encodingFailed
            }
            return bytes
        }
    }
}
