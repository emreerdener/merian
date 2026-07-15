import CoreGraphics
import Foundation

enum ImageFocusRegionSource: String, Codable, Sendable {
    case visionObjectness = "vision_objectness"
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

    var jsonObject: [String: Any] {
        [
            "x": Double(x),
            "y": Double(y),
            "width": Double(width),
            "height": Double(height),
            "source": source.rawValue
        ]
    }
}
