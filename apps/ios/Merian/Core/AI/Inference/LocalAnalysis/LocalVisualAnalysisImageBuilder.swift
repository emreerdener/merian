import CoreGraphics
import Foundation

enum LocalVisualAnalysisImageBuilder {
    static let maximumPixelSize: CGFloat = 512

    static func makeImage(
        data: Data,
        focusRegion: NormalizedImageFocusRegion?
    ) async -> ImageDownsampler.SendableImage? {
        let imageTask = Task.detached(priority: .userInitiated) {
            () -> ImageDownsampler.SendableImage? in
            guard !Task.isCancelled,
                  let image = ImageDownsampler.downsampledSendableImage(
                      data: data,
                      maxSize: maximumPixelSize
                  ) else {
                return nil
            }
            guard let focusRegion,
                  let cropRect = pixelCropRect(
                      focusRegion: focusRegion,
                      pixelWidth: image.cgImage.width,
                      pixelHeight: image.cgImage.height
                  ),
                  let croppedImage = image.cgImage.cropping(to: cropRect) else {
                return image
            }
            return ImageDownsampler.SendableImage(cgImage: croppedImage)
        }
        return await withTaskCancellationHandler {
            await imageTask.value
        } onCancel: {
            imageTask.cancel()
        }
    }

    static func pixelCropRect(
        focusRegion: NormalizedImageFocusRegion,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> CGRect? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        let normalized = focusRegion.rect.intersection(
            CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        guard !normalized.isNull, !normalized.isEmpty else { return nil }

        let rawRect = CGRect(
            x: normalized.minX * CGFloat(pixelWidth),
            y: normalized.minY * CGFloat(pixelHeight),
            width: normalized.width * CGFloat(pixelWidth),
            height: normalized.height * CGFloat(pixelHeight)
        )
        let integralRect = CGRect(
            x: floor(rawRect.minX),
            y: floor(rawRect.minY),
            width: ceil(rawRect.maxX) - floor(rawRect.minX),
            height: ceil(rawRect.maxY) - floor(rawRect.minY)
        ).intersection(bounds)
        return integralRect.isEmpty ? nil : integralRect
    }
}
