import SwiftUI

struct SpeciesDictionaryFeaturedSkeletonCard: View {
    let width: CGFloat

    private var imageHeight: CGFloat {
        max(300, min(430, width * 0.96))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SpeciesDictionarySkeletonBlock(
                width: width,
                height: imageHeight,
                cornerRadius: 0
            )

            SpeciesDictionarySkeletonBlock(
                width: 104,
                height: 24,
                cornerRadius: SpeciesDictionaryCatalogStyle
                    .skeletonPillCornerRadius
            )
            .padding(14)

            VStack(alignment: .leading, spacing: 8) {
                SpeciesDictionarySkeletonBlock(
                    width: width * 0.72,
                    height: 24
                )
                SpeciesDictionarySkeletonBlock(
                    width: width * 0.46,
                    height: 16
                )
            }
            .padding(16)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottomLeading
            )
        }
        .frame(width: width)
        .clipShape(
            RoundedRectangle(
                cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
                style: .continuous
            )
        )
    }
}

struct SpeciesDictionaryMapSkeletonCard: View {
    let width: CGFloat

    private var imageHeight: CGFloat {
        SpeciesDictionaryCatalogStyle.regionMapImageHeight(for: width)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                SpeciesDictionarySkeletonBlock(
                    width: width,
                    height: imageHeight,
                    cornerRadius: 0
                )

                SpeciesDictionarySkeletonBlock(
                    width: 92,
                    height: 24,
                    cornerRadius: SpeciesDictionaryCatalogStyle
                        .skeletonPillCornerRadius
                )
                .padding(14)
            }

            VStack(alignment: .leading, spacing: 8) {
                SpeciesDictionarySkeletonBlock(
                    width: width * 0.46,
                    height: 20
                )
                SpeciesDictionarySkeletonBlock(
                    width: width * 0.28,
                    height: 14
                )
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .frame(width: width)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(
            RoundedRectangle(
                cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
                style: .continuous
            )
        )
    }
}

struct SpeciesDictionaryGroupSkeletonCard: View {
    let width: CGFloat
    let height: CGFloat

    private var graphicSize: CGFloat {
        min(width * 0.76, 138)
    }

    var body: some View {
        VStack(spacing: 8) {
            SpeciesDictionarySkeletonBlock(
                width: graphicSize,
                height: graphicSize,
                cornerRadius: SpeciesDictionaryCatalogStyle
                    .thumbnailCornerRadius
            )
            .padding(.top, 10)

            VStack(spacing: 6) {
                SpeciesDictionarySkeletonBlock(
                    width: width * 0.62,
                    height: 14
                )
                SpeciesDictionarySkeletonBlock(
                    width: width * 0.48,
                    height: 11
                )
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: width, height: height)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(
            RoundedRectangle(
                cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
                style: .continuous
            )
        )
    }
}

struct SpeciesDictionaryOverviewRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            SpeciesDictionarySkeletonBlock(
                width: 52,
                height: 52,
                cornerRadius: SpeciesDictionaryCatalogStyle
                    .thumbnailCornerRadius
            )

            VStack(alignment: .leading, spacing: 7) {
                SpeciesDictionarySkeletonBlock(width: 144, height: 16)
                SpeciesDictionarySkeletonBlock(width: 76, height: 13)
            }

            Spacer(minLength: 8)

            SpeciesDictionarySkeletonBlock(
                width: 8,
                height: 18,
                cornerRadius: SpeciesDictionaryCatalogStyle
                    .chevronSkeletonCornerRadius
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(
            RoundedRectangle(
                cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
                style: .continuous
            )
        )
    }
}

struct SpeciesDictionaryCatalogRowSkeleton: View {
    private let thumbnailSize: CGFloat = 88

    var body: some View {
        HStack(spacing: 12) {
            SpeciesDictionarySkeletonBlock(
                width: thumbnailSize,
                height: thumbnailSize,
                cornerRadius: SpeciesDictionaryCatalogStyle
                    .thumbnailCornerRadius
            )

            VStack(alignment: .leading, spacing: 8) {
                SpeciesDictionarySkeletonBlock(width: 150, height: 16)
                SpeciesDictionarySkeletonBlock(width: 122, height: 12)
                SpeciesDictionarySkeletonBlock(width: 94, height: 10)
            }

            Spacer(minLength: 8)

            SpeciesDictionarySkeletonBlock(
                width: 8,
                height: 18,
                cornerRadius: SpeciesDictionaryCatalogStyle
                    .chevronSkeletonCornerRadius
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(
                cornerRadius: SpeciesDictionaryCatalogStyle.cardCornerRadius,
                style: .continuous
            )
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

private struct SpeciesDictionarySkeletonBlock: View {
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = SpeciesDictionaryCatalogStyle
        .skeletonTextCornerRadius

    var body: some View {
        GlowPulsingSkeletonView(cornerRadius: cornerRadius)
            .frame(width: width, height: height)
    }
}
