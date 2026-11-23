import UIKit

/// Coordinates are top-left normalized upright pixels at either end. The crop
/// itself is an integral rectangle in the retained original's raw pixel grid.
struct ImageCropMapping {
    let sourcePixelSize: CGSize
    let sourceOrientation: UIImage.Orientation
    let targetOrientation: UIImage.Orientation
    let cropPixels: CGRect

    func focus(fromSourceSelection selection: CGRect) -> NormalizedImageFocusRegion? {
        guard Self.isUnitRect(selection) else { return nil }
        let raw = Self.rawRect(fromUpright: selection, orientation: sourceOrientation)
        let pixels = CGRect(x: raw.minX * sourcePixelSize.width, y: raw.minY * sourcePixelSize.height,
                            width: raw.width * sourcePixelSize.width, height: raw.height * sourcePixelSize.height)
        guard cropPixels.contains(pixels) else { return nil }
        let local = CGRect(x: (pixels.minX - cropPixels.minX) / cropPixels.width,
                           y: (pixels.minY - cropPixels.minY) / cropPixels.height,
                           width: pixels.width / cropPixels.width, height: pixels.height / cropPixels.height)
        let upright = Self.uprightRect(fromRaw: local, orientation: targetOrientation)
        let focus = NormalizedImageFocusRegion(x: upright.minX, y: upright.minY,
            width: upright.width, height: upright.height, source: .userSelection)
        return focus.isValidEvidence ? focus : nil
    }

    func sourceSelection(fromFocus focus: NormalizedImageFocusRegion) -> CGRect? {
        guard focus.source == .userSelection, focus.isValidEvidence else { return nil }
        let local = Self.rawRect(fromUpright: focus.rect, orientation: targetOrientation)
        let raw = CGRect(x: (cropPixels.minX + local.minX * cropPixels.width) / sourcePixelSize.width,
                         y: (cropPixels.minY + local.minY * cropPixels.height) / sourcePixelSize.height,
                         width: local.width * cropPixels.width / sourcePixelSize.width,
                         height: local.height * cropPixels.height / sourcePixelSize.height)
        let selection = Self.uprightRect(fromRaw: raw, orientation: sourceOrientation)
        return Self.isUnitRect(selection) ? selection : nil
    }

    static func isUnitRect(_ rect: CGRect) -> Bool {
        [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.minX >= 0 && rect.minY >= 0 && rect.width > 0 && rect.height > 0
            && rect.maxX <= 1 && rect.maxY <= 1
    }

    static func rawRect(fromUpright rect: CGRect, orientation: UIImage.Orientation) -> CGRect {
        let x = rect.minX, y = rect.minY, width = rect.width, height = rect.height
        switch orientation {
        case .up: return rect
        case .down: return CGRect(x: 1 - x - width, y: 1 - y - height, width: width, height: height)
        case .left: return CGRect(x: 1 - y - height, y: x, width: height, height: width)
        case .right: return CGRect(x: y, y: 1 - x - width, width: height, height: width)
        case .upMirrored: return CGRect(x: 1 - x - width, y: y, width: width, height: height)
        case .downMirrored: return CGRect(x: x, y: 1 - y - height, width: width, height: height)
        case .leftMirrored: return CGRect(x: y, y: x, width: height, height: width)
        case .rightMirrored: return CGRect(x: 1 - y - height, y: 1 - x - width, width: height, height: width)
        @unknown default: return rect
        }
    }

    static func uprightRect(fromRaw rect: CGRect, orientation: UIImage.Orientation) -> CGRect {
        switch orientation {
        case .left: return rawRect(fromUpright: rect, orientation: .right)
        case .right: return rawRect(fromUpright: rect, orientation: .left)
        default: return rawRect(fromUpright: rect, orientation: orientation)
        }
    }
}
