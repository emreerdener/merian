import CoreGraphics
import Foundation
import UIKit

/// Capture-owned source image, context, provenance, and resumable crop geometry.
struct IdentifiableImage: Identifiable {
    let id: UUID
    let image: UIImage
    var environmentContext: EnvironmentContext?
    var isFromGallery: Bool = false
    var subjectDistanceInMeters: Float?
    var initialCameraVerticalCenter: CGFloat?
    var lastCropQuarterTurns: Int = 0
    var lastCropScale: CGFloat = 1.0
    var lastCropOffset: CGSize = .zero
    /// Transient viewport basis; native recipes remain the durable authority.
    var lastCropDisplaySize: CGFloat?
    /// Canonical upright retained-source selection; final-byte focus is separate.
    /// Native drafts persist this in their versioned preparation recipe.
    var manualSourceSelection: NormalizedImageFocusRegion?
    /// False when only the accepted pixels have a known coordinate basis.
    var allowsReframing: Bool = true

    init(image: UIImage, environmentContext: EnvironmentContext? = nil, isFromGallery: Bool = false,
         subjectDistanceInMeters: Float? = nil, initialCameraVerticalCenter: CGFloat? = nil,
         lastCropQuarterTurns: Int = 0, lastCropScale: CGFloat = 1, lastCropOffset: CGSize = .zero,
         lastCropDisplaySize: CGFloat? = nil, manualSourceSelection: NormalizedImageFocusRegion? = nil,
         allowsReframing: Bool = true, id: UUID = UUID()) {
        self.id = id; self.image = image; self.environmentContext = environmentContext
        self.isFromGallery = isFromGallery; self.subjectDistanceInMeters = subjectDistanceInMeters
        self.initialCameraVerticalCenter = initialCameraVerticalCenter; self.lastCropQuarterTurns = lastCropQuarterTurns
        self.lastCropScale = lastCropScale; self.lastCropOffset = lastCropOffset
        self.lastCropDisplaySize = lastCropDisplaySize; self.manualSourceSelection = manualSourceSelection
        self.allowsReframing = allowsReframing
    }
}
