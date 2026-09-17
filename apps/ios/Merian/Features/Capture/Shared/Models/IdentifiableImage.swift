import CoreGraphics
import Foundation
import UIKit

/// Capture-owned source image, context, provenance, and resumable crop geometry.
struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
    var environmentContext: EnvironmentContext?
    var isFromGallery: Bool = false
    var subjectDistanceInMeters: Float?
    var lastCropQuarterTurns: Int = 0
    var lastCropScale: CGFloat = 1.0
    var lastCropOffset: CGSize = .zero
}
