import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct ShareImportTelemetry: Codable, Equatable, Sendable {
    let timestamp: String?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsElevation: Double?
}

struct ShareImportPreparedImage {
    let scanId: String
    let imageData: Data
    let contentType: String
    let fileExtension: String
    let telemetry: ShareImportTelemetry
    let previewImage: UIImage?

    var stagingFileName: String {
        ShareImportImagePreparer.sanitizedFileName("\(scanId)_share_import.\(fileExtension)")
    }
}

private struct ShareImportEncodingCandidate {
    let type: UTType
    let contentType: String
    let fileExtension: String
}

private struct ShareImportEncodedImage {
    let data: Data
    let contentType: String
    let fileExtension: String
}

enum ShareImportImagePreparationError: LocalizedError {
    case unreadableImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "Merian could not read that image."
        case .encodingFailed:
            return "Merian could not prepare that image for upload."
        }
    }
}

enum ShareImportImagePreparer {
    static func prepare(fileURL: URL, scanId: String = UUID().uuidString.lowercased()) throws -> ShareImportPreparedImage {
        guard let downsampled = ImageDownsampler.downsample(
            url: fileURL,
            maxSize: ShareImportSharedConstants.imageMaxDimension
        ) else {
            throw ShareImportImagePreparationError.unreadableImage
        }

        guard let encoded = encode(downsampled) else {
            throw ShareImportImagePreparationError.encodingFailed
        }

        return ShareImportPreparedImage(
            scanId: scanId,
            imageData: encoded.data,
            contentType: encoded.contentType,
            fileExtension: encoded.fileExtension,
            telemetry: telemetry(from: fileURL),
            previewImage: UIImage(cgImage: downsampled)
        )
    }

    static func sanitizedFileName(_ rawFileName: String) -> String {
        var sanitized = ""
        sanitized.reserveCapacity(rawFileName.count)

        for scalar in rawFileName.unicodeScalars {
            switch scalar.value {
            case 45, 46, 48...57, 65...90, 95, 97...122:
                sanitized.unicodeScalars.append(scalar)
            default:
                sanitized.append("_")
            }
        }

        return sanitized.isEmpty ? "upload" : sanitized
    }

    private static func encode(_ image: CGImage) -> ShareImportEncodedImage? {
        let candidates = [
            ShareImportEncodingCandidate(type: .webP, contentType: "image/webp", fileExtension: "webp"),
            ShareImportEncodingCandidate(type: .jpeg, contentType: "image/jpeg", fileExtension: "jpg")
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
                kCGImageDestinationLossyCompressionQuality: ShareImportSharedConstants.imageCompressionQuality
            ]
            CGImageDestinationAddImage(destination, image, options as CFDictionary)
            if CGImageDestinationFinalize(destination), renderData.length > 0 {
                return ShareImportEncodedImage(
                    data: Data(renderData),
                    contentType: candidate.contentType,
                    fileExtension: candidate.fileExtension
                )
            }
        }

        return nil
    }

    private static func telemetry(from fileURL: URL) -> ShareImportTelemetry {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ShareImportTelemetry(timestamp: nil, gpsLatitude: nil, gpsLongitude: nil, gpsElevation: nil)
        }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]

        return ShareImportTelemetry(
            timestamp: captureTimestamp(from: exif),
            gpsLatitude: coordinate(
                value: gps?[kCGImagePropertyGPSLatitude],
                reference: gps?[kCGImagePropertyGPSLatitudeRef],
                negativeReferences: ["S"]
            ),
            gpsLongitude: coordinate(
                value: gps?[kCGImagePropertyGPSLongitude],
                reference: gps?[kCGImagePropertyGPSLongitudeRef],
                negativeReferences: ["W"]
            ),
            gpsElevation: number(gps?[kCGImagePropertyGPSAltitude])
        )
    }

    private static func captureTimestamp(from exif: [CFString: Any]?) -> String? {
        let raw = exif?[kCGImagePropertyExifDateTimeOriginal] as? String ??
            exif?[kCGImagePropertyExifDateTimeDigitized] as? String
        guard let raw else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

        guard let date = formatter.date(from: raw) else { return nil }
        return iso8601Formatter.string(from: date)
    }

    private static func coordinate(
        value: Any?,
        reference: Any?,
        negativeReferences: Set<String>
    ) -> Double? {
        guard var coordinate = number(value) else { return nil }
        if let reference = reference as? String,
           negativeReferences.contains(reference.uppercased()) {
            coordinate *= -1
        }
        return coordinate
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
