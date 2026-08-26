import SwiftUI

struct FieldTripChallengeCard: View {
    let challenge: FieldTripChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .aspectRatio(1.3, contentMode: .fit)
                    .overlay {
                        FieldTripCoverImage(
                            urlString: challenge.coverImageUrl,
                            templateSlug: challenge.templateSlug
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                FieldTripChallengeStatusBadge(status: challenge.status)
                    .padding(14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(challenge.title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if let subtitle = challenge.subtitle?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
                           !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Label(
                            FieldTripTemplatePresentation.title(
                                challenge.templateTitle,
                                slug: challenge.templateSlug
                            ),
                            systemImage: "map"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityHidden(true)
                }

                FieldTripTagRow(tags: Array((challenge.regionTags + challenge.seasonTags + challenge.habitatTags).prefix(4)))

                VStack(alignment: .leading, spacing: 8) {
                    Label(FieldTripDisplayDate.shortRange(start: challenge.startsAt, end: challenge.endsAt), systemImage: "calendar")

                    HStack(spacing: 16) {
                        Label("\(challenge.participantCount.formatted()) joined", systemImage: "person.2")
                        Label("\(challenge.completionCount.formatted()) completed", systemImage: "rosette")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, challenge.viewerParticipation == nil ? 16 : 12)

            if let participation = challenge.viewerParticipation {
                FieldTripChallengeProgressBar(participation: participation)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

struct FieldTripChallengeStatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status == "live" ? Color(uiColor: .systemBackground) : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(status == "live" ? Color.primary : Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }

    private var label: String {
        switch status {
        case "live":
            "Live"
        case "upcoming":
            "Upcoming"
        case "ended":
            "Ended"
        default:
            status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct FieldTripChallengeStatsRow: View {
    let challenge: FieldTripChallenge

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FieldTripMetadataPill(
                    title: FieldTripDisplayDate.shortRange(start: challenge.startsAt, end: challenge.endsAt),
                    systemImage: "calendar",
                    tint: .blue
                )
                FieldTripMetadataPill(
                    title: "\(challenge.participantCount.formatted()) joined",
                    systemImage: "person.2",
                    tint: .cyan
                )
            }

            HStack(spacing: 8) {
                FieldTripMetadataPill(
                    title: "\(challenge.completionCount.formatted()) completed",
                    systemImage: "rosette",
                    tint: .green
                )
                FieldTripMetadataPill(
                    title: "\(challenge.publishedEntryCount.formatted()) entries",
                    systemImage: "sparkles",
                    tint: .purple
                )
            }
        }
    }
}
