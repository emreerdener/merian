import SwiftUI

struct AchievementDetailHeader: View {
    let award: AwardPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(award.descriptionText)
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(award.currentCount)/\(award.targetCount)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text(award.progressStatusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(award.isCompleted ? .green : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    award.isCompleted
                                        ? Color.green.opacity(0.16)
                                        : Color(uiColor: .tertiarySystemFill)
                                )
                        )
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color(uiColor: .systemGray6))
                            .frame(height: 8)

                        Capsule()
                            .fill(
                                award.isCompleted
                                    ? Color.green.opacity(0.85)
                                    : award.tintInfo.color.opacity(0.85)
                            )
                            .frame(
                                width: max(
                                    0,
                                    geo.size.width * award.progressFraction
                                ),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)

                Text(award.detailProgressDescription)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(award.accessibilityProgressSummary)
    }
}

struct AchievementContributionRow: View {
    @Environment(ProfileViewModel.self) private var profileViewModel
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    let contribution: AchievementContribution
    let onTap: () -> Void

    var body: some View {
        ScanPreviewCard(
            onOpen: onTap,
            media: { imageButton },
            header: { details },
            actions: { EmptyView() }
        )
    }

    private var imageButton: some View {
        Button(action: onTap) {
            ScanThumbnail(
                isOnline: offlineQueueManager.isOnline,
                imagePath: contribution.imagePath,
                fallbackImageUrl: contribution.fallbackImageUrl,
                audioPath: contribution.audioPath,
                maxDimension: 1_000,
                aspectRatio: 4.0 / 3.0,
                placeholderStyle: contribution.placeholderStyle
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("AchievementContribution_\(contribution.scanID)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens this qualifying scan in the insight sheet.")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contribution.commonName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(contribution.scientificName)
                .font(.subheadline)
                .italic()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(metadataText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(contribution.reasonText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemFill))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataText: String {
        let date = contribution.timestamp.formatted(date: .abbreviated, time: .omitted)
        return [visibleLocationName, date].compactMap { $0 }.joined(separator: " • ")
    }

    private var accessibilityLabel: String {
        var components = [contribution.commonName]

        if contribution.scientificName != contribution.commonName {
            components.append(contribution.scientificName)
        }

        components.append(contribution.reasonText)
        components.append(
            contribution.timestamp.formatted(
                date: .abbreviated,
                time: .shortened
            )
        )

        if let locationName = visibleLocationName {
            components.append(locationName)
        }

        return components.joined(separator: ". ")
    }

    private var visibleLocationName: String? {
        let trimmed = contribution.locationName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }

        switch profileViewModel.defaultGeoprivacy {
        case "private":
            return nil
        case "obscured":
            return ExploreLocationPrivacy.displayLabel(from: trimmed)
        default:
            return trimmed
        }
    }
}
