import SwiftUI

struct FieldTripExpandedLevelSkeleton: View {
    let progressPlacement: FieldTripLevelProgressPlacement
    let showsSelectedGoalTips: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch progressPlacement {
            case .headerRing:
                FieldTripOutingLevelHeaderSkeleton(trailingAccessory: .progressRing)
            case .bar:
                FieldTripLevelHeaderSkeleton(
                    trailingAccessory: expandedHeaderAccessory
                )
            }

            if case .bar = progressPlacement {
                progressBar
            }

            switch progressPlacement {
            case .headerRing:
                HStack(spacing: FieldTripLevelGoalCollectionLayout.equalWidthSpacing) {
                    FieldTripGoalTileSkeleton(
                        isSelected: showsSelectedGoalTips,
                        showsInlineTitle: false
                    )
                    FieldTripGoalTileSkeleton(showsInlineTitle: false)
                }
            case .bar:
                VStack(spacing: 16) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: 16) {
                            ForEach(0..<2, id: \.self) { _ in
                                FieldTripGoalTileSkeleton()
                            }
                        }
                    }
                }
            }

            if showsSelectedGoalTips {
                FieldTripSelectedGoalTipsSkeleton()
            }
        }
        .padding(cardPadding)
        .background(
            levelCardShape.fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            levelCardShape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var expandedHeaderAccessory: FieldTripLevelHeaderSkeleton.TrailingAccessory {
        switch progressPlacement {
        case .headerRing:
            .progressRing
        case .bar:
            .balancedSpacer
        }
    }

    private var cardPadding: CGFloat {
        switch progressPlacement {
        case .headerRing:
            16
        case .bar:
            12
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 52, height: 11)

                Spacer()

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 28, height: 11)
            }

            Capsule()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 7)
        }
    }

    private var levelCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }
}

struct FieldTripGoalTileSkeleton: View {
    var isSelected = false
    var showsInlineTitle = true

    var body: some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .padding(8)
            } else if showsInlineTitle {
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: 72, height: 14)
                }
                .padding(10)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
    }
}

struct FieldTripSelectedGoalTipsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 118, height: 24)

            ForEach(0..<4, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: index.isMultiple(of: 2) ? 112 : 128, height: 13)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(maxWidth: .infinity)
                            .frame(height: 11)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(width: index.isMultiple(of: 2) ? 206 : 174, height: 11)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 4)
    }
}

struct FieldTripAboutOutingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: index == 0 ? 132 : 104, height: 14)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(maxWidth: .infinity)
                            .frame(height: 11)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                            .frame(width: index == 1 ? 184 : 224, height: 11)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
    }
}

struct FieldTripCompactLevelSkeleton: View {
    let progressPlacement: FieldTripLevelProgressPlacement

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch progressPlacement {
            case .headerRing:
                FieldTripOutingLevelHeaderSkeleton(trailingAccessory: .lockedRing)
            case .bar:
                FieldTripLevelHeaderSkeleton(
                    trailingAccessory: compactHeaderAccessory
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: FieldTripScanPreviewLayout.spacing) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(
                            cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
                            style: .continuous
                        )
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        .frame(
                            width: tileSize,
                            height: tileSize
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
                                style: .continuous
                            )
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        }
                    }
                }
                .padding(.horizontal, horizontalInset)
            }
            .scrollDisabled(true)
            .frame(height: tileSize)
            .padding(.horizontal, -horizontalInset)
        }
        .padding(cardPadding)
        .background(
            levelCardShape.fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay {
            levelCardShape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var compactHeaderAccessory: FieldTripLevelHeaderSkeleton.TrailingAccessory {
        switch progressPlacement {
        case .headerRing:
            .lockedRing
        case .bar:
            .completionLabel
        }
    }

    private var tileSize: CGFloat {
        switch progressPlacement {
        case .headerRing:
            FieldTripLevelGoalCollectionLayout.scrollTileSize
        case .bar:
            FieldTripScanPreviewLayout.tileSize
        }
    }

    private var horizontalInset: CGFloat {
        switch progressPlacement {
        case .headerRing:
            16
        case .bar:
            12
        }
    }

    private var cardPadding: CGFloat {
        switch progressPlacement {
        case .headerRing:
            16
        case .bar:
            12
        }
    }

    private var levelCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }
}
