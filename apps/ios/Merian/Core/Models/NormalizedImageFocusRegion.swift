import CoreGraphics
import Foundation

enum ImageFocusRegionSource: String, Codable, Sendable {
    case visionObjectness = "vision_objectness"
    case userSelection = "user_selection"
}

/// A transient, normalized region describing the likely primary subject in the
/// final post-crop inference image. Coordinates use a top-left origin.
struct NormalizedImageFocusRegion: Codable, Sendable, Equatable, Hashable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let source: ImageFocusRegionSource

    init(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        source: ImageFocusRegionSource = .visionObjectness
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.source = source
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// Strict evidence bounds. No clamping or saliency threshold may change an
    /// explicitly submitted selection during admission or replay.
    var isValidEvidence: Bool {
        [x, y, width, height].allSatisfy(\.isFinite)
            && x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 1 && y + height <= 1
    }

    var jsonObject: [String: Any] {
        [
            "x": Double(x),
            "y": Double(y),
            "width": Double(width),
            "height": Double(height),
            "source": source.rawValue
        ]
    }

    /// Fingerprint V2's exact binary64 fields, matching DataView/float8send.
    /// Decimal JSON spelling is not a cross-runtime canonical representation.
    var fingerprintFields: [String]? {
        guard isValidEvidence else { return nil }
        return [x, y, width, height].map { coordinate in
            let value = coordinate == 0 ? Double(0) : Double(coordinate)
            return String(format: "%016llx", value.bitPattern)
        } + [source.rawValue]
    }
}
