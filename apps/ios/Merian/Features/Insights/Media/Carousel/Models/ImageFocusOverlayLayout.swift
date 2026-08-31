import CoreGraphics

enum ImageFocusOverlayCorner: CaseIterable, Hashable {
    case topLeading
    case topTrailing
    case bottomTrailing
    case bottomLeading
}

enum ImageFocusOverlayResizeConstraint: Hashable {
    case leadingEdge
    case trailingEdge
    case topEdge
    case bottomEdge
    case minimumWidth
    case minimumHeight
}

struct ImageFocusOverlayResizeResult: Equatable {
    let rect: CGRect
    let constraints: Set<ImageFocusOverlayResizeConstraint>
}

enum ImageFocusOverlayLayout {
    static let minimumInteractiveDimension: CGFloat = 64

    static func rect(
        for region: NormalizedImageFocusRegion,
        in containerSize: CGSize,
        imageAspectRatio: CGFloat = 1
    ) -> CGRect {
        guard containerSize.width > 0,
              containerSize.height > 0,
              imageAspectRatio.isFinite,
              imageAspectRatio > 0 else { return .zero }

        let containerAspectRatio = containerSize.width / containerSize.height
        let renderedSize: CGSize
        if imageAspectRatio > containerAspectRatio {
            renderedSize = CGSize(
                width: containerSize.height * imageAspectRatio,
                height: containerSize.height
            )
        } else {
            renderedSize = CGSize(
                width: containerSize.width,
                height: containerSize.width / imageAspectRatio
            )
        }
        let origin = CGPoint(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2
        )
        return CGRect(
            x: origin.x + region.x * renderedSize.width,
            y: origin.y + region.y * renderedSize.height,
            width: region.width * renderedSize.width,
            height: region.height * renderedSize.height
        )
    }

    static func draggedRect(
        from baseRect: CGRect,
        committedOffset: CGSize,
        activeTranslation: CGSize,
        in containerSize: CGSize
    ) -> CGRect {
        guard let clampedOffset = clampedOffset(
            for: baseRect,
            proposedOffset: CGSize(
                width: committedOffset.width + activeTranslation.width,
                height: committedOffset.height + activeTranslation.height
            ),
            in: containerSize
        ) else {
            return .zero
        }
        return baseRect.offsetBy(
            dx: clampedOffset.width,
            dy: clampedOffset.height
        )
    }

    static func interactiveRect(
        from sourceRect: CGRect,
        in containerSize: CGSize,
        minimumDimension: CGFloat
    ) -> CGRect {
        guard isValid(rect: sourceRect),
              isValid(containerSize: containerSize),
              minimumDimension.isFinite,
              minimumDimension > 0 else {
            return .zero
        }

        let minimumWidth = min(minimumDimension, containerSize.width)
        let minimumHeight = min(minimumDimension, containerSize.height)
        let width = min(
            max(sourceRect.width, minimumWidth),
            containerSize.width
        )
        let height = min(
            max(sourceRect.height, minimumHeight),
            containerSize.height
        )
        let originX = min(
            max(sourceRect.midX - width / 2, 0),
            containerSize.width - width
        )
        let originY = min(
            max(sourceRect.midY - height / 2, 0),
            containerSize.height - height
        )

        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    static func resizedRect(
        from baseRect: CGRect,
        corner: ImageFocusOverlayCorner,
        translation: CGSize,
        minimumDimension: CGFloat,
        in containerSize: CGSize
    ) -> CGRect {
        resizeResult(
            from: baseRect,
            corner: corner,
            translation: translation,
            minimumDimension: minimumDimension,
            in: containerSize
        ).rect
    }

    static func resizeResult(
        from baseRect: CGRect,
        corner: ImageFocusOverlayCorner,
        translation: CGSize,
        minimumDimension: CGFloat,
        in containerSize: CGSize
    ) -> ImageFocusOverlayResizeResult {
        guard isValid(rect: baseRect),
              isValid(containerSize: containerSize),
              translation.width.isFinite,
              translation.height.isFinite,
              minimumDimension.isFinite,
              minimumDimension > 0 else {
            return ImageFocusOverlayResizeResult(rect: .zero, constraints: [])
        }

        let rect = interactiveRect(
            from: baseRect,
            in: containerSize,
            minimumDimension: minimumDimension
        )
        let minimumWidth = min(minimumDimension, containerSize.width)
        let minimumHeight = min(minimumDimension, containerSize.height)
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY
        var constraints: Set<ImageFocusOverlayResizeConstraint> = []

        switch corner {
        case .topLeading:
            minX = clampedResizeEdge(
                rect.minX + translation.width,
                lowerBound: 0,
                upperBound: rect.maxX - minimumWidth,
                lowerConstraint: .leadingEdge,
                upperConstraint: .minimumWidth,
                constraints: &constraints
            )
            minY = clampedResizeEdge(
                rect.minY + translation.height,
                lowerBound: 0,
                upperBound: rect.maxY - minimumHeight,
                lowerConstraint: .topEdge,
                upperConstraint: .minimumHeight,
                constraints: &constraints
            )
        case .topTrailing:
            maxX = clampedResizeEdge(
                rect.maxX + translation.width,
                lowerBound: rect.minX + minimumWidth,
                upperBound: containerSize.width,
                lowerConstraint: .minimumWidth,
                upperConstraint: .trailingEdge,
                constraints: &constraints
            )
            minY = clampedResizeEdge(
                rect.minY + translation.height,
                lowerBound: 0,
                upperBound: rect.maxY - minimumHeight,
                lowerConstraint: .topEdge,
                upperConstraint: .minimumHeight,
                constraints: &constraints
            )
        case .bottomTrailing:
            maxX = clampedResizeEdge(
                rect.maxX + translation.width,
                lowerBound: rect.minX + minimumWidth,
                upperBound: containerSize.width,
                lowerConstraint: .minimumWidth,
                upperConstraint: .trailingEdge,
                constraints: &constraints
            )
            maxY = clampedResizeEdge(
                rect.maxY + translation.height,
                lowerBound: rect.minY + minimumHeight,
                upperBound: containerSize.height,
                lowerConstraint: .minimumHeight,
                upperConstraint: .bottomEdge,
                constraints: &constraints
            )
        case .bottomLeading:
            minX = clampedResizeEdge(
                rect.minX + translation.width,
                lowerBound: 0,
                upperBound: rect.maxX - minimumWidth,
                lowerConstraint: .leadingEdge,
                upperConstraint: .minimumWidth,
                constraints: &constraints
            )
            maxY = clampedResizeEdge(
                rect.maxY + translation.height,
                lowerBound: rect.minY + minimumHeight,
                upperBound: containerSize.height,
                lowerConstraint: .minimumHeight,
                upperConstraint: .bottomEdge,
                constraints: &constraints
            )
        }

        return ImageFocusOverlayResizeResult(
            rect: CGRect(
                x: minX,
                y: minY,
                width: maxX - minX,
                height: maxY - minY
            ),
            constraints: constraints
        )
    }

    static func clampedOffset(
        for baseRect: CGRect,
        proposedOffset: CGSize,
        in containerSize: CGSize
    ) -> CGSize? {
        guard isValid(rect: baseRect),
              isValid(containerSize: containerSize),
              proposedOffset.width.isFinite,
              proposedOffset.height.isFinite else {
            return nil
        }

        return CGSize(
            width: clampedAxisOffset(
                rectMinimum: baseRect.minX,
                rectMaximum: baseRect.maxX,
                rectMidpoint: baseRect.midX,
                containerLength: containerSize.width,
                proposedOffset: proposedOffset.width
            ),
            height: clampedAxisOffset(
                rectMinimum: baseRect.minY,
                rectMaximum: baseRect.maxY,
                rectMidpoint: baseRect.midY,
                containerLength: containerSize.height,
                proposedOffset: proposedOffset.height
            )
        )
    }

    private static func clampedAxisOffset(
        rectMinimum: CGFloat,
        rectMaximum: CGFloat,
        rectMidpoint: CGFloat,
        containerLength: CGFloat,
        proposedOffset: CGFloat
    ) -> CGFloat {
        let rectLength = rectMaximum - rectMinimum
        guard rectLength < containerLength else {
            return containerLength / 2 - rectMidpoint
        }

        let minimumOffset = -rectMinimum
        let maximumOffset = containerLength - rectMaximum
        return min(max(proposedOffset, minimumOffset), maximumOffset)
    }

    private static func clampedResizeEdge(
        _ proposedValue: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat,
        lowerConstraint: ImageFocusOverlayResizeConstraint,
        upperConstraint: ImageFocusOverlayResizeConstraint,
        constraints: inout Set<ImageFocusOverlayResizeConstraint>
    ) -> CGFloat {
        if proposedValue <= lowerBound {
            constraints.insert(lowerConstraint)
        }
        if proposedValue >= upperBound {
            constraints.insert(upperConstraint)
        }
        return min(max(proposedValue, lowerBound), upperBound)
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
        return values.allSatisfy(\.isFinite)
            && rect.width > 0
            && rect.height > 0
    }

    private static func isValid(containerSize: CGSize) -> Bool {
        containerSize.width.isFinite
            && containerSize.height.isFinite
            && containerSize.width > 0
            && containerSize.height > 0
    }
}
