import Foundation
import UIKit

/// Memory-only output assertions, not a pair publication or file capability.
/// Only the sealed native plan may admit these against its exact active attempt.
struct SharedMediaNativePreparedOutputs: Sendable {
    let attempt: SharedMediaNativePreparationAttempt
    let intent: SharedMediaNativeDerivativeIntent
    let ai: Data
    let display: Data
}

/// Called by the existing file-owning IO actor after reservation and source
/// verification. It creates no scratch file and never constructs a repository.
enum SharedMediaNativePhotoProcessor {
    static func prepare(url: URL, attempt: SharedMediaNativePreparationAttempt, focusFactory: ImageFocusWorkFactory) async throws -> SharedMediaNativePreparedOutputs {
        try attempt.validate(); try Task.checkCancellation()
        let recipe = attempt.recipe
        let ai: Data, display: Data
        if recipe.format == .cameraStill {
            guard let center = recipe.cameraVerticalCenter else { throw SharedMediaStorageFailure.invalid }
            ai = try cameraCrop(url: url, center: center,
                maximum: ImagePreparationPolicy.inferenceMaxDimension(isProActive: recipe.isPro))
            try Task.checkCancellation()
            display = try cameraCrop(url: url, center: center, maximum: ImagePreparationPolicy.displayMaxDimension)
        } else if let size = recipe.cropDisplaySize {
            guard let image = UIImage(contentsOfFile: url.path) else { throw MediaPreparationError.unreadableImage }
            ai = await ImageCropProcessor.generateCrop(image: image, displaySize: size, scale: recipe.scale,
                currentScale: 1, offset: .init(width: recipe.offsetX, height: recipe.offsetY), currentOffset: .zero,
                quarterTurns: recipe.quarterTurns, maxPixelSize: Int(ImagePreparationPolicy.inferenceMaxDimension(isProActive: recipe.isPro)), encoding: .jpeg)
            try Task.checkCancellation()
            display = await ImageCropProcessor.generateCrop(image: image, displaySize: size, scale: recipe.scale,
                currentScale: 1, offset: .init(width: recipe.offsetX, height: recipe.offsetY), currentOffset: .zero,
                quarterTurns: recipe.quarterTurns, maxPixelSize: Int(ImagePreparationPolicy.displayMaxDimension), encoding: .jpeg)
        } else {
            let prepared = try await MediaPreparationActor.shared.prepareStillImage(fileURL: url, isPro: recipe.isPro, encoding: .jpeg)
            ai = prepared.inferenceData; display = prepared.displayData
        }
        try Task.checkCancellation()
        let aiInput = try SharedMediaDerivativeWorkFiles.prepare(ai, role: .aiInput)
        let displayInput = try SharedMediaDerivativeWorkFiles.prepare(display, role: .display)
        // Unlike the interactive Capture façade, this call waits for actual
        // worker termination even when timeout/cancellation fixes a nil outcome.
        let focus = await ImageFocusEngine.detectAndDrain(in: ai, factory: focusFactory)
        try Task.checkCancellation()
        let intent = SharedMediaNativeDerivativeIntent(format: .intent, preparation: try .init(attempt: attempt),
            pairID: UUID(), nonce: UUID(), previousPairID: nil, ai: aiInput, display: displayInput, focus: focus.region)
        _ = try intent.encoded()
        return .init(attempt: attempt, intent: intent, ai: ai, display: display)
    }

    /// Runs inside the admitted file worker. Both outputs use orientation-normalized
    /// bounded decoding of the verified original, never a presentation preview.
    private static func cameraCrop(url: URL, center: Double, maximum: CGFloat) throws -> Data {
        try Task.checkCancellation()
        return try autoreleasepool {
            guard let image = ImageDownsampler.downsample(url: url, maxSize: maximum),
                  let crop = ImageCropProcessor.squareCrop(image, verticalCenterFraction: center),
                  let bytes = ImageCropProcessor.encode(crop, encoding: .jpeg), !bytes.isEmpty else {
                throw MediaPreparationError.unreadableImage
            }
            return bytes
        }
    }
}
