import SwiftUI

enum FieldTripDetailSkeletonKind {
    case outing
    case event

    var isOuting: Bool {
        switch self {
        case .outing:
            true
        case .event:
            false
        }
    }

    var progressPlacement: FieldTripLevelProgressPlacement {
        switch self {
        case .outing:
            .headerRing
        case .event:
            .bar
        }
    }
}

struct FieldTripTemplateDetailSkeleton: View {
    let kind: FieldTripDetailSkeletonKind
    var showsFeaturedMediaHero = false
    var onFeaturedHeroMaxYChange: ((CGFloat) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsFeaturedMediaHero {
                FieldTripFeaturedMediaSkeleton()
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onChange(
                                    of: proxy.frame(
                                        in: .named(FieldTripFeaturedMediaLayout.scrollCoordinateSpace)
                                    ).maxY,
                                    initial: true
                                ) { _, newMaxY in
                                    onFeaturedHeroMaxYChange?(newMaxY)
                                }
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 24) {
                overview

                FieldTripExpandedLevelSkeleton(
                    progressPlacement: kind.progressPlacement,
                    showsSelectedGoalTips: kind.isOuting
                )
                FieldTripCompactLevelSkeleton(
                    progressPlacement: kind.progressPlacement
                )

                if kind.isOuting {
                    FieldTripCompactLevelSkeleton(
                        progressPlacement: kind.progressPlacement
                    )
                    FieldTripAboutOutingSkeleton()
                }
            }
            .padding(.horizontal, showsFeaturedMediaHero ? 16 : 0)
            .modifier(FieldTripHeroContentSheetModifier(
                isEnabled: showsFeaturedMediaHero
            ))
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var overview: some View {
        switch kind {
        case .outing:
            FieldTripOutingOverviewSkeleton()
        case .event:
            FieldTripEventOverviewSkeleton()
        }
    }
}

struct FieldTripOutingOverviewSkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            FieldTripDetailStatusSkeletonBadge()

            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 250, height: 34)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(maxWidth: 300)
                    .frame(height: 16)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 230, height: 16)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 8) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 76, height: 27)

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 68, height: 27)

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 82, height: 27)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            FieldTripDetailPrimaryActionSkeleton()
                .padding(.top, 12)
        }
        .padding(.vertical, 16)
    }
}

struct FieldTripEventOverviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .aspectRatio(16 / 9, contentMode: .fit)

            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(maxWidth: 220)
                    .frame(height: 30)

                Spacer(minLength: 8)

                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 58, height: 23)
            }

            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 16)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 250, height: 16)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    metadataPill(width: 132)
                    metadataPill(width: 108)
                }

                HStack(spacing: 8) {
                    metadataPill(width: 124)
                    metadataPill(width: 96)
                }
            }
        }
    }

    private func metadataPill(width: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .frame(width: width, height: 27)
    }
}

struct FieldTripFeaturedMediaSkeleton: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            GlowPulsingSkeletonView(cornerRadius: 0)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.white.opacity(0.9))
                Circle()
                    .fill(Color.white.opacity(0.4))
                Circle()
                    .fill(Color.white.opacity(0.4))
            }
            .frame(width: 34, height: 6)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, FieldTripFeaturedMediaLayout.overlayBottomInset)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}

struct FieldTripDetailStatusSkeletonBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 7, height: 7)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 54, height: 11)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FieldTripDetailPrimaryActionSkeleton: View {
    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.14))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct FieldTripHeroContentSheetModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .padding(.top, FieldTripFeaturedMediaLayout.contentTopSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: FieldTripFeaturedMediaLayout.contentOverlap,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: FieldTripFeaturedMediaLayout.contentOverlap
                    )
                    .fill(Color(uiColor: .systemGroupedBackground))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: -4)
                    .padding(.bottom, -1000)
                )
                .offset(y: -FieldTripFeaturedMediaLayout.contentOverlap)
                .padding(.bottom, -FieldTripFeaturedMediaLayout.contentOverlap)
                .zIndex(1)
        } else {
            content
        }
    }
}
