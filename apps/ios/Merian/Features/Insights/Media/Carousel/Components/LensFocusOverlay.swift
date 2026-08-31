import SwiftUI

private struct ImageFocusOverlayResizeInteraction: Equatable {
    let corner: ImageFocusOverlayCorner
    let translation: CGSize
}

struct LensFocusOverlay: View {
    let region: NormalizedImageFocusRegion
    let scanProgress: CGFloat
    let dependencies: InsightCarouselDependencies
    @Binding var committedFocusRect: NormalizedFocusOverlayRect?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isResolved = false
    @State private var isMoveHapticActive = false
    @State private var hapticResizeCorner: ImageFocusOverlayCorner?
    @State private var hapticResizeConstraints:
        Set<ImageFocusOverlayResizeConstraint> = []
    @GestureState private var activeMoveTranslation = CGSize.zero
    @GestureState private var activeResizeInteraction:
        ImageFocusOverlayResizeInteraction?

    private static let dragCoordinateSpaceName = "LensFocusOverlay"
    private let resizeHandleHitSize =
        ImageFocusOverlayLayout.minimumInteractiveDimension

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let detectedFocusRect = ImageFocusOverlayLayout.rect(
                for: region,
                in: geometry.size
            )
            let initialFocusRect = ImageFocusOverlayLayout.interactiveRect(
                from: detectedFocusRect,
                in: geometry.size,
                minimumDimension:
                    ImageFocusOverlayLayout.minimumInteractiveDimension
            )
            let settledFocusRect = ImageFocusOverlayLayout.interactiveRect(
                from: committedFocusRect?.rect(in: geometry.size)
                    ?? initialFocusRect,
                in: geometry.size,
                minimumDimension:
                    ImageFocusOverlayLayout.minimumInteractiveDimension
            )
            let focusRect = displayedFocusRect(
                from: settledFocusRect,
                in: geometry.size
            )
            let dragHitRect = dragHitRect(for: focusRect, in: bounds)
            let shortestSide = min(geometry.size.width, geometry.size.height)
            let bracketArm = min(30, max(18, shortestSide * 0.075))
            let strokeWidth = min(
                2.5,
                max(1, shortestSide * 0.0125 - 2.5)
            )
            let cornerRadius = min(12, max(8, shortestSide * 0.03))
            let handleHitSize = min(
                resizeHandleHitSize,
                focusRect.width,
                focusRect.height
            )

            ZStack {
                ZStack {
                    Path { path in
                        path.addRect(bounds)
                        path.addRoundedRect(
                            in: focusRect,
                            cornerSize: CGSize(
                                width: cornerRadius,
                                height: cornerRadius
                            )
                        )
                    }
                    .fill(
                        .black.opacity(0.22),
                        style: FillStyle(eoFill: true)
                    )
                    .opacity(isResolved ? 1 : 0)

                    LensFocusScanHighlight(
                        focusRect: focusRect,
                        cornerRadius: cornerRadius,
                        progress: reduceMotion ? 0.5 : scanProgress
                    )
                    .opacity(isResolved ? 1 : 0)

                    LensFocusBracketShape(
                        rect: focusRect,
                        armLength: bracketArm,
                        cornerRadius: cornerRadius
                    )
                    .stroke(
                        .white,
                        style: StrokeStyle(
                            lineWidth: strokeWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                    .scaleEffect(reduceMotion || isResolved ? 1 : 0.985)
                    .opacity(isResolved ? 1 : 0)
                }
                .allowsHitTesting(false)

                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: dragHitRect.width,
                        height: dragHitRect.height
                    )
                    .contentShape(Rectangle())
                    .position(x: dragHitRect.midX, y: dragHitRect.midY)
                    .gesture(dragGesture(
                        baseFocusRect: settledFocusRect,
                        containerSize: geometry.size
                    ))
                    .accessibilityHidden(true)

                ForEach(ImageFocusOverlayCorner.allCases, id: \.self) { corner in
                    Circle()
                        .fill(.clear)
                        .frame(width: handleHitSize, height: handleHitSize)
                        .contentShape(Circle())
                        .position(resizeHandleCenter(
                            for: corner,
                            in: focusRect
                        ))
                        .gesture(resizeGesture(
                            corner: corner,
                            baseFocusRect: settledFocusRect,
                            containerSize: geometry.size
                        ))
                        .accessibilityHidden(true)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .coordinateSpace(name: Self.dragCoordinateSpaceName)
        }
        .accessibilityHidden(true)
        .onAppear {
            if reduceMotion {
                isResolved = true
            } else {
                withAnimation(.easeOut(duration: 0.20)) {
                    isResolved = true
                }
            }
        }
    }

    private func dragHitRect(for focusRect: CGRect, in bounds: CGRect) -> CGRect {
        guard !focusRect.isEmpty, !focusRect.isNull else { return .zero }
        let horizontalExpansion = max(0, (44 - focusRect.width) / 2)
        let verticalExpansion = max(0, (44 - focusRect.height) / 2)
        return focusRect
            .insetBy(dx: -horizontalExpansion, dy: -verticalExpansion)
            .intersection(bounds)
    }

    private func dragGesture(
        baseFocusRect: CGRect,
        containerSize: CGSize
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(Self.dragCoordinateSpaceName)
        )
        .updating($activeMoveTranslation) { value, state, _ in
            state = value.translation
        }
        .onChanged { _ in
            handleMoveHapticIfNeeded()
        }
        .onEnded { value in
            let committedRect = ImageFocusOverlayLayout.draggedRect(
                from: baseFocusRect,
                committedOffset: .zero,
                activeTranslation: value.translation,
                in: containerSize
            )
            committedFocusRect = NormalizedFocusOverlayRect(
                rect: committedRect,
                in: containerSize
            )
            isMoveHapticActive = false
        }
    }

    private func resizeGesture(
        corner: ImageFocusOverlayCorner,
        baseFocusRect: CGRect,
        containerSize: CGSize
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(Self.dragCoordinateSpaceName)
        )
        .updating($activeResizeInteraction) { value, state, _ in
            state = ImageFocusOverlayResizeInteraction(
                corner: corner,
                translation: value.translation
            )
        }
        .onChanged { value in
            let result = ImageFocusOverlayLayout.resizeResult(
                from: baseFocusRect,
                corner: corner,
                translation: value.translation,
                minimumDimension:
                    ImageFocusOverlayLayout.minimumInteractiveDimension,
                in: containerSize
            )
            handleResizeHaptics(
                corner: corner,
                constraints: result.constraints
            )
        }
        .onEnded { value in
            let committedRect = ImageFocusOverlayLayout.resizedRect(
                from: baseFocusRect,
                corner: corner,
                translation: value.translation,
                minimumDimension:
                    ImageFocusOverlayLayout.minimumInteractiveDimension,
                in: containerSize
            )
            committedFocusRect = NormalizedFocusOverlayRect(
                rect: committedRect,
                in: containerSize
            )
            hapticResizeCorner = nil
            hapticResizeConstraints.removeAll()
        }
    }

    private func displayedFocusRect(
        from settledFocusRect: CGRect,
        in containerSize: CGSize
    ) -> CGRect {
        if let activeResizeInteraction {
            return ImageFocusOverlayLayout.resizedRect(
                from: settledFocusRect,
                corner: activeResizeInteraction.corner,
                translation: activeResizeInteraction.translation,
                minimumDimension:
                    ImageFocusOverlayLayout.minimumInteractiveDimension,
                in: containerSize
            )
        }

        return ImageFocusOverlayLayout.draggedRect(
            from: settledFocusRect,
            committedOffset: .zero,
            activeTranslation: activeMoveTranslation,
            in: containerSize
        )
    }

    private func resizeHandleCenter(
        for corner: ImageFocusOverlayCorner,
        in rect: CGRect
    ) -> CGPoint {
        switch corner {
        case .topLeading:
            CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomTrailing:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomLeading:
            CGPoint(x: rect.minX, y: rect.maxY)
        }
    }

    private func handleResizeHaptics(
        corner: ImageFocusOverlayCorner,
        constraints: Set<ImageFocusOverlayResizeConstraint>
    ) {
        guard hapticResizeCorner == corner else {
            hapticResizeCorner = corner
            hapticResizeConstraints = constraints
            dependencies.lightImpactFeedback(
                0.5,
                "insight.analysis.focus.resize.begin"
            )
            return
        }

        let newlyReachedConstraints = constraints.subtracting(
            hapticResizeConstraints
        )
        hapticResizeConstraints = constraints
        guard !newlyReachedConstraints.isEmpty else { return }
        dependencies.selectionFeedback(
            "insight.analysis.focus.resize.constraint"
        )
    }

    private func handleMoveHapticIfNeeded() {
        guard !isMoveHapticActive else { return }
        isMoveHapticActive = true
        dependencies.selectionFeedback(
            "insight.analysis.focus.move.begin"
        )
    }
}

private struct LensFocusScanHighlight: View {
    let focusRect: CGRect
    let cornerRadius: CGFloat
    let progress: CGFloat

    var body: some View {
        let bandHeight = VisualLaserScanBand.height
        let travelDistance = focusRect.height + bandHeight

        VisualLaserScanBand()
            .frame(width: focusRect.width, height: bandHeight)
            .offset(y: -travelDistance / 2 + travelDistance * progress)
            .frame(width: focusRect.width, height: focusRect.height)
            .clipShape(RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            ))
            .position(x: focusRect.midX, y: focusRect.midY)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

private struct LensFocusBracketShape: Shape {
    let rect: CGRect
    let armLength: CGFloat
    let cornerRadius: CGFloat

    func path(in _: CGRect) -> Path {
        let arm = min(armLength, rect.width / 2, rect.height / 2)
        let radius = min(cornerRadius, arm)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + arm))

        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))

        return path
    }
}
