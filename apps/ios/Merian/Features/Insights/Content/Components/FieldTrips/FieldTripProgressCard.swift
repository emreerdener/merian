import SwiftUI

struct FieldTripProgressCard: View {
    let contributions: [FieldTripScanContribution]
    let onOpen: (InsightFieldTripOverviewDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InsightCardHeader(systemImage: "map", title: "Field trips")

            VStack(spacing: 22) {
                ForEach(contributions) { contribution in
                    if let destination = InsightFieldTripOverviewDestination(
                        contribution: contribution
                    ) {
                        Button {
                            onOpen(destination)
                        } label: {
                            FieldTripProgressContributionRow(contribution: contribution)
                        }
                        .buttonStyle(.plain)
                    } else {
                        FieldTripProgressContributionRow(contribution: contribution)
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}

struct FieldTripProgressCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            InsightCardHeader(systemImage: "map", title: "Field trips")
            FieldTripProgressContributionRowSkeleton()
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Field trip progress")
    }
}

private struct FieldTripProgressContributionRowSkeleton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        artwork
                        labels
                    }
                    HStack {
                        Spacer()
                        progressRing
                    }
                }
            } else {
                HStack(spacing: 12) {
                    artwork
                    labels
                    Spacer(minLength: 8)
                    progressRing
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var artwork: some View {
        GlowPulsingSkeletonView(cornerRadius: 14)
            .frame(width: 68, height: 68)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 7) {
            GlowPulsingSkeletonView(cornerRadius: 4)
                .frame(width: 92, height: 10)

            GlowPulsingSkeletonView(cornerRadius: 5)
                .frame(maxWidth: 148)
                .frame(height: 18)

            GlowPulsingSkeletonView(cornerRadius: 4)
                .frame(maxWidth: 116)
                .frame(height: 13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var progressRing: some View {
        ZStack {
            GlowPulsingSkeletonView(cornerRadius: 32)
                .mask {
                    Circle().stroke(lineWidth: 5)
                }

            GlowPulsingSkeletonView(cornerRadius: 4)
                .frame(width: 28, height: 16)
        }
        .frame(width: 64, height: 64)
    }
}

private struct FieldTripProgressContributionRow: View {
    let contribution: FieldTripScanContribution
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sourceSubtitle: String {
        contribution.title
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        artwork
                        labels
                    }
                    HStack {
                        Spacer()
                        progressRing
                    }
                }
            } else {
                HStack(spacing: 12) {
                    artwork
                    labels
                    Spacer(minLength: 8)
                    progressRing
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(contribution.prompt) goal complete in \(contribution.title), "
                + "\(contribution.completedCount) of \(contribution.targetCount)"
        )
        .accessibilityHint(contribution.destination == nil ? "" : "Opens Field trip details")
        .accessibilityAddTraits(contribution.destination == nil ? [] : .isButton)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GOAL COMPLETE")
                .font(.caption2.weight(.medium))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Text(contribution.prompt)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(sourceSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var progressRing: some View {
        GoalProgressRing(
            completedCount: contribution.completedCount,
            targetCount: contribution.targetCount,
            lineWidth: 5,
            labelFontSize: 18,
            tint: .accentColor
        )
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let imageName = FieldTripGoalArtwork.exactImageName(
                    for: contribution.artworkPrompt,
                    templateSlug: contribution.artworkTemplateSlug
                ) {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                } else {
                    Image(systemName: "binoculars.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(.green, in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                }
                .offset(x: 3, y: 3)
        }
        .frame(width: 68, height: 68)
        .accessibilityHidden(true)
    }
}
