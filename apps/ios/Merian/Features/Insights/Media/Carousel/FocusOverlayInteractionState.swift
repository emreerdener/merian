import CoreGraphics
import Foundation

struct FocusInteractionIdentity: Hashable {
    let scanID: String?
    let stillImageSourceIndex: Int?

    init(scanID: String?, stillImageSourceIndex: Int?) {
        self.scanID = Self.canonicalScanID(scanID)
        self.stillImageSourceIndex = stillImageSourceIndex
    }

    static func canonicalScanID(_ scanID: String?) -> String? {
        guard let scanID else { return nil }
        let trimmed = scanID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }
}

/// Presentation-only focus geometry in the visible carousel coordinate space.
/// Keeping it normalized lets a user adjustment survive view remounts and
/// geometry changes without rewriting the detector's image-space region.
struct NormalizedFocusOverlayRect: Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init?(rect: CGRect, in containerSize: CGSize) {
        guard Self.isValid(containerSize: containerSize) else { return nil }

        let bounds = CGRect(origin: .zero, size: containerSize)
        let constrainedRect = rect.standardized.intersection(bounds)
        guard Self.isValid(rect: constrainedRect) else { return nil }

        x = constrainedRect.minX / containerSize.width
        y = constrainedRect.minY / containerSize.height
        width = constrainedRect.width / containerSize.width
        height = constrainedRect.height / containerSize.height
    }

    func rect(in containerSize: CGSize) -> CGRect {
        guard Self.isValid(containerSize: containerSize) else { return .zero }
        return CGRect(
            x: x * containerSize.width,
            y: y * containerSize.height,
            width: width * containerSize.width,
            height: height * containerSize.height
        )
    }

    private static func isValid(rect: CGRect) -> Bool {
        let values = [
            rect.minX,
            rect.minY,
            rect.width,
            rect.height,
            rect.maxX,
            rect.maxY
        ]
        return values.allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }

    private static func isValid(containerSize: CGSize) -> Bool {
        containerSize.width.isFinite &&
            containerSize.height.isFinite &&
            containerSize.width > 0 &&
            containerSize.height > 0
    }
}

struct FocusOverlayInteractionState: Equatable {
    private(set) var activeScanID: String?
    private var rectsByIdentity: [FocusInteractionIdentity: NormalizedFocusOverlayRect] = [:]

    subscript(identity: FocusInteractionIdentity) -> NormalizedFocusOverlayRect? {
        get { rectsByIdentity[identity] }
        set {
            if newValue != nil, let scanID = identity.scanID {
                retainValues(forScanID: scanID)
            }
            rectsByIdentity[identity] = newValue
        }
    }

    func resolvedScanID(for proposedScanID: String?) -> String? {
        FocusInteractionIdentity.canonicalScanID(proposedScanID) ?? activeScanID
    }

    mutating func retainValues(forScanID scanID: String?) {
        guard let canonicalScanID = FocusInteractionIdentity.canonicalScanID(scanID) else {
            return
        }
        rectsByIdentity = rectsByIdentity.filter { identity, _ in
            identity.scanID == canonicalScanID
        }
        activeScanID = canonicalScanID
    }
}
