import SwiftUI

struct AnalyzingMediaOverlay: View {
    let kind: CarouselMediaKind
    let focusRegion: NormalizedImageFocusRegion?
    let focusInteractionIdentity: FocusInteractionIdentity
    let animationStartedAt: Date
    let dependencies: InsightCarouselDependencies
    @Binding var committedFocusRect: NormalizedFocusOverlayRect?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let descriptionBandHeight: CGFloat = 89.2
    private let pulseDuration: TimeInterval = 1.25

    var body: some View {
        GeometryReader { geometry in
            TimelineView(
                .animation(paused: reduceMotion || scenePhase != .active)
            ) { timeline in
                let sweepProgress = AnalyzingMediaAnimationClock.sweepProgress(
                    at: timeline.date,
                    startedAt: animationStartedAt,
                    legDuration: VisualLaserScanBand.sweepDuration,
                    reduceMotion: reduceMotion
                )
                let pulseProgress = reduceMotion ? 1 :
                    AnalyzingMediaAnimationClock.sweepProgress(
                        at: timeline.date,
                        startedAt: animationStartedAt,
                        legDuration: pulseDuration,
                        reduceMotion: false
                    )

                ZStack {
                    tintLayer(pulseProgress: pulseProgress)
                        .allowsHitTesting(false)

                    switch kind {
                    case .visual:
                        switch StillImageAnalyzingMode(
                            focusRegion: focusRegion
                        ) {
                        case .isolatedFocus(let focusRegion):
                            LensFocusOverlay(
                                region: focusRegion,
                                scanProgress: sweepProgress,
                                dependencies: dependencies,
                                committedFocusRect: $committedFocusRect
                            )
                            .id(focusInteractionIdentity)
                        case .fullImageScan:
                            visualScan(
                                in: geometry.size,
                                sweepProgress: sweepProgress
                            )
                            .allowsHitTesting(false)
                        }
                    case .video:
                        visualScan(
                            in: geometry.size,
                            sweepProgress: sweepProgress
                        )
                        .allowsHitTesting(false)
                    case .audio:
                        audioSweep(
                            in: geometry.size,
                            sweepProgress: sweepProgress
                        )
                        .allowsHitTesting(false)
                    case .description:
                        descriptionReadSweep(
                            in: geometry.size,
                            sweepProgress: sweepProgress
                        )
                        .allowsHitTesting(false)
                    }
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .clipped()
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func tintLayer(pulseProgress: CGFloat) -> some View {
        switch kind {
        case .visual:
            if focusRegion == nil {
                Color.black.opacity(0.14)
            }
        case .video:
            Color.black.opacity(0.14)
        case .audio:
            Color.cyan.opacity(0.05 + 0.06 * Double(pulseProgress))
                .blendMode(.screen)
        case .description:
            Color.green.opacity(0.04 + 0.04 * Double(pulseProgress))
        }
    }

    private func visualScan(
        in size: CGSize,
        sweepProgress: CGFloat
    ) -> some View {
        VisualLaserScanBand()
            .frame(width: size.width)
            .offset(y: verticalOffset(
                in: size,
                bandHeight: VisualLaserScanBand.height,
                sweepProgress: sweepProgress
            ))
            .blendMode(.plusLighter)
    }

    private func audioSweep(
        in size: CGSize,
        sweepProgress: CGFloat
    ) -> some View {
        VisualLaserScanBand()
            .frame(width: size.height)
            .rotationEffect(.degrees(90))
            .offset(x: horizontalOffset(
                in: size,
                bandWidth: VisualLaserScanBand.height,
                sweepProgress: sweepProgress
            ))
            .blendMode(.plusLighter)
    }

    private func descriptionReadSweep(
        in size: CGSize,
        sweepProgress: CGFloat
    ) -> some View {
        let cardSize = DescriptionTextCarouselLayout.cardSize(in: size)

        return horizontalScanBand(
            color: .green,
            coreHeight: 1.2,
            glowHeight: 44
        )
        .frame(width: cardSize.width)
        .offset(y: verticalOffset(
            in: cardSize,
            bandHeight: descriptionBandHeight,
            sweepProgress: sweepProgress
        ))
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(
            RoundedRectangle(
                cornerRadius: DescriptionTextCarouselLayout.cardCornerRadius,
                style: .continuous
            )
        )
        .offset(y: DescriptionTextCarouselLayout.cardVerticalOffset)
        .blendMode(.screen)
        .opacity(0.85)
    }

    private func horizontalScanBand(
        color: Color,
        coreHeight: CGFloat,
        glowHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, color.opacity(0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: glowHeight)

            Rectangle()
                .fill(Color.white.opacity(0.95))
                .frame(height: coreHeight)
                .shadow(color: color.opacity(0.9), radius: 7)

            LinearGradient(
                colors: [color.opacity(0.36), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: glowHeight)
        }
    }

    private func verticalOffset(
        in size: CGSize,
        bandHeight: CGFloat,
        sweepProgress: CGFloat
    ) -> CGFloat {
        let startCenterY = -bandHeight / 2
        let endCenterY = size.height + bandHeight / 2
        let currentCenterY = startCenterY
            + (endCenterY - startCenterY) * sweepProgress
        return currentCenterY - size.height / 2
    }

    private func horizontalOffset(
        in size: CGSize,
        bandWidth: CGFloat,
        sweepProgress: CGFloat
    ) -> CGFloat {
        let startCenterX = -bandWidth / 2
        let endCenterX = size.width + bandWidth / 2
        let currentCenterX = startCenterX
            + (endCenterX - startCenterX) * sweepProgress
        return currentCenterX - size.width / 2
    }
}

struct VisualLaserScanBand: View {
    static let sweepDuration: TimeInterval = 2.15

    private static let coreHeight: CGFloat = 1.6
    private static let glowHeight: CGFloat = 54

    static var height: CGFloat {
        (glowHeight * 2) + coreHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, Color.cyan.opacity(0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.glowHeight)

            Rectangle()
                .fill(Color.white.opacity(0.95))
                .frame(height: Self.coreHeight)
                .shadow(color: Color.cyan.opacity(0.9), radius: 7)

            LinearGradient(
                colors: [Color.cyan.opacity(0.36), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.glowHeight)
        }
    }
}
