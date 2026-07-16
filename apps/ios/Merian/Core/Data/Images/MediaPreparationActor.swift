import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MediaPreparationMetrics: Sendable, Equatable {
    let sourceFileByteCount: Int64?
    let inferenceByteCount: Int
    let displayByteCount: Int
    let inferencePixelWidth: Int
    let inferencePixelHeight: Int
    let displayPixelWidth: Int
    let displayPixelHeight: Int
    let inferenceMaxDimension: Int
    let displayMaxDimension: Int

    var largestInferenceDimension: Int {
        max(inferencePixelWidth, inferencePixelHeight)
    }

    var largestDisplayDimension: Int {
        max(displayPixelWidth, displayPixelHeight)
    }

    var isWithinImageBudgets: Bool {
        inferenceByteCount > 0
            && displayByteCount > 0
            && inferenceByteCount <= MerianConfig.stagedImagePayloadMaxBytes
            && displayByteCount <= MerianConfig.stagedImagePayloadMaxBytes
            && largestInferenceDimension <= inferenceMaxDimension
            && largestDisplayDimension <= displayMaxDimension
    }
}

struct PreparedStillImage: Sendable {
    let inferenceData: Data
    let displayData: Data
    let previewImage: ImageDownsampler.SendableImage
    let metrics: MediaPreparationMetrics
}

enum MediaPreparationError: LocalizedError {
    case unreadableImage
    case encodingFailed
    case budgetExceeded(MediaPreparationMetrics)

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "Naturebook could not read that image."
        case .encodingFailed:
            return "Naturebook could not prepare that image."
        case .budgetExceeded:
            return "Naturebook rejected an oversized prepared image."
        }
    }
}

/// Actor-owned boundary for converting file-backed still images into Merian's
/// bounded inference, display, and preview payloads.
actor MediaPreparationActor {
    static let shared = MediaPreparationActor()

    private init() {}

    private static let supportedDestinationTypes: Set<String> = {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return Set(identifiers)
    }()

    private static let destinationTypePreferences: [String] = {
        var types: [String] = []
        if supportedDestinationTypes.contains(UTType.webP.identifier) {
            types.append(UTType.webP.identifier)
        }
        types.append(UTType.jpeg.identifier)
        return types
    }()

    func prepareStillImage(fileURL: URL, isPro: Bool) throws -> PreparedStillImage {
        try prepareStillImage(
            fileURL: fileURL,
            inferenceMaxSize: MerianConfig.inferenceImageMaxSize(isProActive: isPro),
            displayMaxSize: MerianConfig.displayImageMaxSize
        )
    }

    func prepareStillImage(
        fileURL: URL,
        inferenceMaxSize: CGFloat,
        displayMaxSize: CGFloat
    ) throws -> PreparedStillImage {
        guard let inferenceCGImage = ImageDownsampler.downsample(
            url: fileURL,
            maxSize: inferenceMaxSize
        ) else {
            throw MediaPreparationError.unreadableImage
        }

        guard let inferenceData = Self.encode(inferenceCGImage), !inferenceData.isEmpty else {
            throw MediaPreparationError.encodingFailed
        }

        guard let displayCGImage = ImageDownsampler.downsample(
            url: fileURL,
            maxSize: displayMaxSize
        ) else {
            throw MediaPreparationError.unreadableImage
        }

        guard let displayData = Self.encode(displayCGImage), !displayData.isEmpty else {
            throw MediaPreparationError.encodingFailed
        }

        let metrics = MediaPreparationMetrics(
            sourceFileByteCount: Self.fileByteCount(at: fileURL),
            inferenceByteCount: inferenceData.count,
            displayByteCount: displayData.count,
            inferencePixelWidth: inferenceCGImage.width,
            inferencePixelHeight: inferenceCGImage.height,
            displayPixelWidth: displayCGImage.width,
            displayPixelHeight: displayCGImage.height,
            inferenceMaxDimension: Int(inferenceMaxSize.rounded(.up)),
            displayMaxDimension: Int(displayMaxSize.rounded(.up))
        )
        guard metrics.isWithinImageBudgets else {
            throw MediaPreparationError.budgetExceeded(metrics)
        }

        return PreparedStillImage(
            inferenceData: inferenceData,
            displayData: displayData,
            previewImage: ImageDownsampler.SendableImage(cgImage: inferenceCGImage),
            metrics: metrics
        )
    }

    func preparePreviewImage(fileURL: URL, maxSize: CGFloat) throws -> ImageDownsampler.SendableImage {
        guard let preview = ImageDownsampler.downsampledSendableImage(
            url: fileURL,
            maxSize: maxSize
        ) else {
            throw MediaPreparationError.unreadableImage
        }
        return preview
    }

    private static func fileByteCount(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }
        return Int64(fileSize)
    }

    private static func encode(_ cgImage: CGImage) -> Data? {
        autoreleasepool {
            let renderData = NSMutableData()
            guard let destination = makeImageDestination(renderData) else { return nil }
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: MerianConfig.imageCompressionQuality
            ]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return Data(renderData)
        }
    }

    private static func makeImageDestination(_ renderData: NSMutableData) -> CGImageDestination? {
        for type in destinationTypePreferences {
            if let destination = CGImageDestinationCreateWithData(
                renderData as CFMutableData,
                type as CFString,
                1,
                nil
            ) {
                return destination
            }
        }
        return nil
    }
}
