import SwiftUI

struct ExploreAuthorProfileLoadingView: View {
    let showsFollowButton: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                ExploreAuthorProfileSkeletonCard()

                if showsFollowButton {
                    ExploreAuthorProfileSkeletonFollowButton()
                }

                ExploreAuthorProfileSkeletonStats()
                ExploreAuthorProfileSkeletonHeatmap()
                ExploreAuthorProfileSkeletonGrid()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityLabel("Loading profile")
    }
}

private struct ExploreAuthorProfileSkeletonCard: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GlowPulsingSkeletonView(cornerRadius: 24)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 5) {
                    GlowPulsingSkeletonView(cornerRadius: 6)
                        .frame(width: 156, height: 22)
                    GlowPulsingSkeletonView(cornerRadius: 5)
                        .frame(width: 92, height: 15)
                }

                Spacer(minLength: 0)
            }

            Divider()

            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(spacing: 4) {
                        GlowPulsingSkeletonView(cornerRadius: 5)
                            .frame(width: 38, height: 20)
                        GlowPulsingSkeletonView(cornerRadius: 4)
                            .frame(width: 64, height: 13)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if FeatureFlags.isEnabled(.fieldTrips) {
                Divider()
                EarnedFieldTripPatchCarouselSkeleton()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityHidden(true)
    }
}

private struct ExploreAuthorProfileSkeletonFollowButton: View {
    var body: some View {
        GlowPulsingSkeletonView(cornerRadius: 24)
            .frame(height: 50)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }
}

private struct ExploreAuthorProfileSkeletonStats: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    GlowPulsingSkeletonView(cornerRadius: 10)
                        .frame(width: 54, height: 54)
                    Spacer(minLength: 0)
                    GlowPulsingSkeletonView(cornerRadius: 7)
                        .frame(width: 74, height: 34)
                    GlowPulsingSkeletonView(cornerRadius: 6)
                        .frame(width: 128, height: 18)
                }
                .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ExploreAuthorProfileSkeletonHeatmap: View {
    private let columns = Array(repeating: GridItem(.fixed(11), spacing: 3), count: 18)

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                GlowPulsingSkeletonView(cornerRadius: 5)
                    .frame(width: 28, height: 28)
                GlowPulsingSkeletonView(cornerRadius: 7)
                    .frame(width: 176, height: 30)
                GlowPulsingSkeletonView(cornerRadius: 7)
                    .frame(width: 64, height: 30)
            }

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<126, id: \.self) { _ in
                    GlowPulsingSkeletonView(cornerRadius: 2, style: .raisedGrid)
                        .frame(width: 11, height: 11)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }
}

private struct ExploreAuthorProfileSkeletonGrid: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                GlowPulsingSkeletonView(cornerRadius: 6)
                    .frame(width: 150, height: 24)
                Spacer()
                GlowPulsingSkeletonView(cornerRadius: 5)
                    .frame(width: 34, height: 18)
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<6, id: \.self) { _ in
                    GlowPulsingSkeletonView(cornerRadius: 3, style: .raisedGrid)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}
