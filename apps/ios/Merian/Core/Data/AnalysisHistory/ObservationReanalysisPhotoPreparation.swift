import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Normalization and hashing run on a worker, never the UI actor.
enum ObservationReanalysisPhotoPreparation {
    struct Photo: Sendable {
        let bytes: Data
        let reference: ObservationEvidenceUpload.Reference
    }

    nonisolated static func prepare(bytes: Data, mediaID: UUID, original: ObservationHistoryPhotoReference?) throws -> Photo {
        try Task.checkCancellation()
        guard !bytes.isEmpty, bytes.count <= ObservationEvidenceUpload.maximumBytes else { throw MerianError.invalidResponse }
        let output: Data
        let type: String
        if let original {
            guard bytes.count == original.byteCount, digest(bytes) == original.sha256,
                  ["image/jpeg", "image/png"].contains(original.contentType),
                  let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) == 1,
                  CGImageSourceGetType(source) as String? == (original.contentType == "image/png" ? UTType.png.identifier : UTType.jpeg.identifier) else {
                throw MerianError.invalidResponse
            }
            output = bytes; type = original.contentType
        } else {
            // Explicit new/edited evidence uses the existing bounded raster policy, but never WebP output.
            guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) == 1,
                  let image = ImageDownsampler.downsample(data: bytes, maxSize: ImagePreparationPolicy.maximumInferenceDimension) else {
                throw MerianError.invalidResponse
            }
            let encoded = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw MerianError.invalidResponse
            }
            CGImageDestinationAddImage(destination, image,
                [kCGImageDestinationLossyCompressionQuality: ImagePreparationPolicy.compressionQuality] as CFDictionary)
            guard CGImageDestinationFinalize(destination), encoded.length > 0,
                  encoded.length <= ObservationEvidenceUpload.maximumBytes else { throw MerianError.invalidResponse }
            output = encoded as Data; type = "image/jpeg"
        }
        try Task.checkCancellation()
        return Photo(bytes: output, reference: .init(mediaID: mediaID, contentType: type, byteCount: output.count, sha256: digest(output)))
    }

    nonisolated private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
