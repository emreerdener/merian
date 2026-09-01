import SwiftUI

struct SpeciesDictionaryDetailLoadingSkeleton: View {
    var body: some View {
        GeometryReader { proxy in
            let pageWidth = max(proxy.size.width, 1)
            let contentWidth = max(pageWidth - 32, 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero(width: pageWidth)

                    VStack(alignment: .leading, spacing: 24) {
                        header(width: contentWidth)

                        VStack(alignment: .leading, spacing: 32) {
                            SpeciesDictionaryDetailSkeletonCard(
                                width: contentWidth,
                                titleWidthRatio: 0.34,
                                rowWidthRatios: [0.64, 0.46],
                                showsBadge: true
                            )

                            SpeciesDictionaryDetailSkeletonCard(
                                width: contentWidth,
                                titleWidthRatio: 0.3,
                                rowWidthRatios: [0.9, 0.82, 0.58]
                            )

                            taxonomyCard(width: contentWidth)
                            observationChart(width: contentWidth)
                            similarSpecies(width: contentWidth)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                    .modifier(DictionaryHeroContentSheetModifier())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(uiColor: .systemBackground))
            .ignoresSafeArea(.container, edges: .top)
            .contentMargins(.top, 0, for: .scrollContent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading species details")
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func hero(width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            SpeciesDictionaryDetailSkeletonBlock(
                width: width,
                height: width,
                cornerRadius: 0
            )

            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            Color.white.opacity(index == 0 ? 0.7 : 0.35)
                        )
                        .frame(width: 7, height: 7)
                        .shadow(
                            color: .black.opacity(0.16),
                            radius: 2,
                            y: 1
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Color.black.opacity(0.12),
                in: Capsule(style: .continuous)
            )
            .padding(
                .bottom,
                SpeciesDictionaryHeroLayout.overlayBottomInset
            )
            .allowsHitTesting(false)
        }
        .frame(width: width, height: width)
        .clipped()
    }

    private func header(width: CGFloat) -> some View {
        VStack(alignment: .center, spacing: 8) {
            SpeciesDictionaryDetailSkeletonBlock(
                width: min(width * 0.52, 220),
                height: 18
            )

            SpeciesDictionaryDetailSkeletonBlock(
                width: min(width * 0.72, 280),
                height: 36,
                cornerRadius: 9
            )

            SpeciesDictionaryDetailSkeletonBlock(
                width: min(width * 0.56, 220),
                height: 14
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func taxonomyCard(width: CGFloat) -> some View {
        let innerWidth = max(width - 40, 1)
        let rowWidthRatios: [CGFloat] = [0.76, 0.62, 0.7, 0.48]

        return VStack(alignment: .leading, spacing: 16) {
            skeletonHeader(width: innerWidth * 0.34)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(rowWidthRatios, id: \.self) { ratio in
                    HStack(spacing: 12) {
                        SpeciesDictionaryDetailSkeletonBlock(
                            width: 74,
                            height: 12,
                            cornerRadius: 5
                        )
                        SpeciesDictionaryDetailSkeletonBlock(
                            width: innerWidth * ratio - 86,
                            height: 14
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func observationChart(width: CGFloat) -> some View {
        let innerWidth = max(width - 40, 1)
        let barWidth = max((innerWidth - 48) / 7, 10)
        let barHeights: [CGFloat] = [48, 74, 58, 96, 68, 42, 84]

        return VStack(alignment: .leading, spacing: 16) {
            skeletonHeader(width: innerWidth * 0.5)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(barHeights.indices, id: \.self) { index in
                    SpeciesDictionaryDetailSkeletonBlock(
                        width: barWidth,
                        height: barHeights[index],
                        cornerRadius: 5
                    )
                }
            }
            .frame(height: 112, alignment: .bottom)

            SpeciesDictionaryDetailSkeletonBlock(
                width: innerWidth * 0.58,
                height: 12
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func similarSpecies(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            skeletonHeader(width: min(width * 0.46, 180))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(0..<3, id: \.self) { _ in
                        SpeciesDetailSimilarCardSkeleton()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, -16)
            .disabled(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skeletonHeader(width: CGFloat) -> some View {
        HStack(spacing: 10) {
            SpeciesDictionaryDetailSkeletonBlock(
                width: 24,
                height: 24,
                cornerRadius: 12
            )
            SpeciesDictionaryDetailSkeletonBlock(width: width, height: 18)
        }
    }
}

private struct SpeciesDictionaryDetailSkeletonCard: View {
    let width: CGFloat
    let titleWidthRatio: CGFloat
    let rowWidthRatios: [CGFloat]
    var showsBadge = false

    var body: some View {
        let innerWidth = max(width - 40, 1)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                SpeciesDictionaryDetailSkeletonBlock(
                    width: 24,
                    height: 24,
                    cornerRadius: 12
                )
                SpeciesDictionaryDetailSkeletonBlock(
                    width: innerWidth * titleWidthRatio,
                    height: 18
                )
            }

            if showsBadge {
                SpeciesDictionaryDetailSkeletonBlock(
                    width: 106,
                    height: 28,
                    cornerRadius: 14
                )
            }

            VStack(alignment: .leading, spacing: 9) {
                ForEach(rowWidthRatios, id: \.self) { ratio in
                    SpeciesDictionaryDetailSkeletonBlock(
                        width: innerWidth * ratio,
                        height: 13
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct SpeciesDetailSimilarCardSkeleton: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            SpeciesDictionaryDetailSkeletonBlock(
                width: 200,
                height: 260,
                cornerRadius: 16
            )

            VStack(alignment: .leading, spacing: 8) {
                SpeciesDictionaryDetailSkeletonBlock(
                    width: 112,
                    height: 16
                )
                SpeciesDictionaryDetailSkeletonBlock(
                    width: 146,
                    height: 12
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                .regularMaterial,
                in: RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
            .padding(10)
        }
        .frame(width: 200, height: 260)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
        )
    }
}

private struct SpeciesDictionaryDetailSkeletonBlock: View {
    let width: CGFloat
    let height: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        GlowPulsingSkeletonView(cornerRadius: cornerRadius)
            .frame(width: max(width, 1), height: max(height, 1))
    }
}
