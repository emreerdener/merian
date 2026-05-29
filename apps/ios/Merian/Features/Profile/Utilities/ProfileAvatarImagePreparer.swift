import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct PreparedProfileAvatar: Sendable {
    let data: Data
    let contentType: String
    let fileExtension: String
}

private struct ProfileAvatarEncodingCandidate {
    let type: UTType
    let contentType: String
    let fileExtension: String
}

enum ProfileAvatarImagePreparationError: LocalizedError {
    case unreadableImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "Merian could not read that image."
        case .encodingFailed:
            return "Merian could not prepare that image."
        }
    }
}

enum ProfileAvatarImagePreparer {
    private static let maxAvatarDimension: CGFloat = 512
    private static let compressionQuality = 0.86

    static func prepare(fileURL: URL) throws -> PreparedProfileAvatar {
        guard let downsampled = ImageDownsampler.downsample(
            url: fileURL,
            maxSize: maxAvatarDimension
        ) else {
            throw ProfileAvatarImagePreparationError.unreadableImage
        }

        let squareImage = ImageCropProcessor.squareCrop(
            downsampled,
            verticalCenterFraction: 0.5
        ) ?? downsampled

        guard let encoded = encode(squareImage) else {
            throw ProfileAvatarImagePreparationError.encodingFailed
        }

        return encoded
    }

    private static func encode(_ image: CGImage) -> PreparedProfileAvatar? {
        let candidates = [
            ProfileAvatarEncodingCandidate(type: .webP, contentType: "image/webp", fileExtension: "webp"),
            ProfileAvatarEncodingCandidate(type: .jpeg, contentType: "image/jpeg", fileExtension: "jpg")
        ]

        for candidate in candidates {
            let renderData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                renderData as CFMutableData,
                candidate.type.identifier as CFString,
                1,
                nil
            ) else {
                continue
            }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: compressionQuality
            ]
            CGImageDestinationAddImage(destination, image, options as CFDictionary)
            if CGImageDestinationFinalize(destination), renderData.length > 0 {
                return PreparedProfileAvatar(
                    data: Data(renderData),
                    contentType: candidate.contentType,
                    fileExtension: candidate.fileExtension
                )
            }
        }

        return nil
    }
}
