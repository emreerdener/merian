import CoreGraphics

/// Review geometry only. The upright source rectangle stays stable while the
/// viewport changes; admission must separately bind it to the prepared bytes.
struct CapturePhotoSelectionGeometry: Sendable {
    let sourceSize: CGSize
    let viewportSize: CGFloat
    let scale: CGFloat
    let offset: CGSize
    let quarterTurns: Int
    var fitsFullAspect: Bool = false

    enum Corner: CaseIterable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    var isValid: Bool {
        [sourceSize.width, sourceSize.height, viewportSize, scale, offset.width, offset.height].allSatisfy(\.isFinite)
            && sourceSize.width > 0 && sourceSize.height > 0 && viewportSize > 0 && scale >= 1
            && imageSize.width.isFinite && imageSize.height.isFinite
            && imageSize.width > 0 && imageSize.height > 0
            && (!fitsFullAspect || (turns == 0 && scale == 1 && offset == .zero))
    }

    private var turns: Int { (quarterTurns % 4 + 4) % 4 }
    private var imageSize: CGSize {
        let rotated = turns % 2 == 0 ? sourceSize : CGSize(width: sourceSize.height, height: sourceSize.width)
        let edge = fitsFullAspect ? max(rotated.width, rotated.height) : min(rotated.width, rotated.height)
        let factor = viewportSize * scale / edge
        return CGSize(width: rotated.width * factor, height: rotated.height * factor)
    }

    var selectableRect: CGRect {
        let size = imageSize
        return CGRect(x: (viewportSize - size.width) / 2 + offset.width,
                      y: (viewportSize - size.height) / 2 + offset.height,
                      width: size.width, height: size.height)
            .intersection(CGRect(x: 0, y: 0, width: viewportSize, height: viewportSize))
    }

    /// A source selection may extend beyond the viewport during a gesture.
    /// Call finalCropRect at gesture end to decide whether it remains selected.
    func viewportRect(for sourceRect: CGRect) -> CGRect? {
        guard isValid, Self.isUnitRect(sourceRect) else { return nil }
        let rotated = Self.rotated(sourceRect, turns: turns)
        let size = imageSize
        return CGRect(x: (viewportSize - size.width) / 2 + offset.width + rotated.minX * size.width,
                      y: (viewportSize - size.height) / 2 + offset.height + rotated.minY * size.height,
                      width: rotated.width * size.width, height: rotated.height * size.height)
    }

    func sourceRect(for viewportRect: CGRect) -> CGRect? {
        guard isValid, Self.isFinitePositive(viewportRect) else { return nil }
        let size = imageSize
        let rotated = CGRect(x: (viewportRect.minX - (viewportSize - size.width) / 2 - offset.width) / size.width,
                             y: (viewportRect.minY - (viewportSize - size.height) / 2 - offset.height) / size.height,
                             width: viewportRect.width / size.width, height: viewportRect.height / size.height)
        let source = Self.rotated(rotated, turns: (4 - turns) % 4)
        guard Self.isUnitRect(source, tolerance: 0.000001) else { return nil }
        return source.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Top-left normalized review crop coordinates. Pixel-rounded preparation
    /// performs its final mapping against the actual committed crop recipe.
    func finalCropRect(for sourceRect: CGRect) -> CGRect? {
        guard let rect = viewportRect(for: sourceRect) else { return nil }
        if fitsFullAspect { return sourceRect }
        let normalized = CGRect(x: rect.minX / viewportSize, y: rect.minY / viewportSize,
                                width: rect.width / viewportSize, height: rect.height / viewportSize)
        guard Self.isUnitRect(normalized, tolerance: 0.000001) else { return nil }
        return normalized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Candidates use upright source coordinates and are supplied only by the
    /// matching source/revision owner. No asynchronous detection is needed here.
    func selection(at point: CGPoint, existing: CGRect?, candidates: [CGRect]) -> CGRect? {
        guard isValid, point.x.isFinite, point.y.isFinite,
              selectableRect.contains(point) else { return nil }
        let bounds = selectableRect
        let minimum = min(64, min(bounds.width, bounds.height))
        let candidate = candidates.compactMap { source -> CGRect? in
            guard finalCropRect(for: source) != nil, let rect = viewportRect(for: source),
                  rect.contains(point), rect.width >= minimum, rect.height >= minimum else { return nil }
            return rect
        }.min { $0.width * $0.height < $1.width * $1.height }
        if let candidate { return sourceRect(for: candidate) }
        let previous = existing.flatMap { viewportRect(for: $0) }
        let width = min(bounds.width, max(minimum, previous?.width ?? bounds.width * 0.4))
        let height = min(bounds.height, max(minimum, previous?.height ?? bounds.height * 0.4))
        let rect = CGRect(x: min(max(bounds.minX, point.x - width / 2), bounds.maxX - width),
                          y: min(max(bounds.minY, point.y - height / 2), bounds.maxY - height), width: width, height: height)
        return sourceRect(for: rect)
    }

    /// The opposite corner is fixed. Crossing is clamped before conversion to
    /// the immutable source coordinate system.
    func resized(_ sourceRect: CGRect, corner: Corner, to point: CGPoint) -> CGRect? {
        guard let rect = viewportRect(for: sourceRect), finalCropRect(for: sourceRect) != nil,
              point.x.isFinite, point.y.isFinite else { return nil }
        let bounds = selectableRect
        let minimum = min(64, min(bounds.width, bounds.height))
        let left = corner == .topLeft || corner == .bottomLeft
        let top = corner == .topLeft || corner == .topRight
        // A viewport resize can make a previously valid box smaller than the
        // interactive minimum. Keep its opposite corner fixed and use all the
        // available space when 64 points no longer fit on that side.
        let minWidth = min(minimum, left ? rect.maxX - bounds.minX : bounds.maxX - rect.minX)
        let minHeight = min(minimum, top ? rect.maxY - bounds.minY : bounds.maxY - rect.minY)
        let x = left ? min(max(bounds.minX, point.x), rect.maxX - minWidth) : max(min(bounds.maxX, point.x), rect.minX + minWidth)
        let y = top ? min(max(bounds.minY, point.y), rect.maxY - minHeight) : max(min(bounds.maxY, point.y), rect.minY + minHeight)
        let resized = CGRect(x: left ? x : rect.minX, y: top ? y : rect.minY,
                             width: left ? rect.maxX - x : x - rect.minX,
                             height: top ? rect.maxY - y : y - rect.minY)
        return self.sourceRect(for: resized)
    }

    private static func rotated(_ rect: CGRect, turns: Int) -> CGRect {
        switch turns {
        case 1: return CGRect(x: 1 - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        case 2: return CGRect(x: 1 - rect.maxX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
        case 3: return CGRect(x: rect.minY, y: 1 - rect.maxX, width: rect.height, height: rect.width)
        default: return rect
        }
    }

    private static func isFinitePositive(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }

    private static func isUnitRect(_ rect: CGRect, tolerance: CGFloat = 0) -> Bool {
        isFinitePositive(rect) && rect.minX >= -tolerance && rect.minY >= -tolerance
            && rect.maxX <= 1 + tolerance && rect.maxY <= 1 + tolerance
    }
}
