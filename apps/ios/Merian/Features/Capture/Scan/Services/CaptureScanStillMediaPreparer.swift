import Foundation

enum CaptureScanStillMediaPreparer {
    nonisolated static func prepare(
        _ request: CaptureScanStillPreparationRequest
    ) async throws -> PreparedCaptureScanStill? {
        try await DetachedWork.value(
            priority: .userInitiated,
            category: .imagePreparation
        ) {
            try Task.checkCancellation()
            let inferencePrepared: (
                data: Data,
                preview: SendableCGImage
            )? = autoreleasepool {
                let inferenceMaxSize = MerianConfig.inferenceImageMaxSize(
                    isProActive: request.isProActive
                )
                guard let safeCGImage = ImageDownsampler.downsample(
                    data: request.captureData,
                    maxSize: inferenceMaxSize
                ) else {
                    return nil
                }

                let croppedCGImage = ImageCropProcessor.squareCrop(
                    safeCGImage,
                    verticalCenterFraction: request.composingCenter
                ) ?? safeCGImage

                guard let finalSafeData = ImageCropProcessor.encode(
                    croppedCGImage
                ), !finalSafeData.isEmpty else {
                    return nil
                }

                return (
                    finalSafeData,
                    SendableCGImage(image: safeCGImage)
                )
            }
            guard let inferencePrepared else { return nil }
            try Task.checkCancellation()

            async let focusRegion = ImageFocusRegionDetector.detect(
                in: inferencePrepared.data
            )

            let displaySafeData: Data = autoreleasepool {
                guard let displayCGImage = ImageDownsampler.downsample(
                    data: request.captureData,
                    maxSize: MerianConfig.displayImageMaxSize
                ) else {
                    return inferencePrepared.data
                }
                let croppedDisplayCGImage = ImageCropProcessor.squareCrop(
                    displayCGImage,
                    verticalCenterFraction: request.composingCenter
                ) ?? displayCGImage
                return ImageCropProcessor.encode(croppedDisplayCGImage)
                    ?? inferencePrepared.data
            }
            try Task.checkCancellation()
            let resolvedFocusRegion = await focusRegion
            try Task.checkCancellation()

            return PreparedCaptureScanStill(
                inferenceData: inferencePrepared.data,
                displayData: displaySafeData,
                previewCGImage: inferencePrepared.preview,
                focusRegion: resolvedFocusRegion
            )
        }
    }
}
