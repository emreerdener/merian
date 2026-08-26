import SwiftUI

struct FieldTripProfilePreview: View {
    let summaries: FieldTripProfileSummaries
    var allowsPinManagement = false
    var isUpdatingPins = false
    let onOpenTemplate: (String) -> Void
    let onOpenPublication: (String) -> Void
    var onTogglePinned: ((FieldTripProfilePublishedSummary) -> Void)?

    private var visibleChallengeBadges: [FieldTripChallengeBadge] {
        FieldTripProfilePresentation.visibleChallengeBadges(in: summaries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Field trips")
                    .font(.title3.weight(.bold))

                Spacer()

                let count = FieldTripProfilePresentation.itemCount(in: summaries)
                Text(count.formatted(.number.notation(.compactName)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !visibleChallengeBadges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Badges")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(visibleChallengeBadges.prefix(3)) { badge in
                        FieldTripChallengeBadgeProfileRow(badge: badge)
                    }
                }
            }

            if !summaries.pinned.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pinned")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(summaries.pinned.prefix(3)) { trip in
                        publishedRow(trip)
                    }
                }
            }

            if !summaries.active.isEmpty {
                VStack(spacing: 8) {
                    ForEach(summaries.active.prefix(3)) { trip in
                        Button {
                            HapticManager.shared.triggerSelectionPulse()
                            onOpenTemplate(trip.templateId)
                        } label: {
                            FieldTripActiveProfileRow(trip: trip)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this Field trip")
                    }
                }
            }

            if !summaries.published.isEmpty {
                VStack(spacing: 8) {
                    ForEach(summaries.published.prefix(3)) { trip in
                        publishedRow(trip)
                    }
                }
            }
        }
    }

    private func publishedRow(_ trip: FieldTripProfilePublishedSummary) -> some View {
        HStack(spacing: 8) {
            Button {
                onOpenPublication(trip.publicationId)
            } label: {
                FieldTripPublishedProfileRow(trip: trip)
            }
            .buttonStyle(.plain)

            if allowsPinManagement, let onTogglePinned {
                Button {
                    onTogglePinned(trip)
                } label: {
                    Image(systemName: trip.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(trip.isPinned ? Color.accentColor : Color.secondary)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingPins)
                .accessibilityLabel(trip.isPinned ? "Unpin outing" : "Pin outing")
            }
        }
    }
}

struct FieldTripChallengeBadgeProfileRow: View {
    let badge: FieldTripChallengeBadge

    var body: some View {
        HStack(spacing: 12) {
            FieldTripProfileCover(urlString: badge.coverImageUrl)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "rosette")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    Text(badge.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(badge.challengeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                FieldTripBadgeTagRow(tags: Array((badge.regionTags + badge.seasonTags + badge.habitatTags).prefix(3)))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct FieldTripBadgeTagRow: View {
    let tags: [String]

    private var displayTags: [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    var body: some View {
        if !displayTags.isEmpty {
            HStack(spacing: 6) {
                ForEach(displayTags, id: \.self) { tag in
                    Text(tag.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct FieldTripActiveProfileRow: View {
    let trip: FieldTripProfileActiveSummary

    private var patchImageName: String? {
        FieldTripLevelArtwork.imageName(
            templateSlug: trip.slug,
            levelNumber: trip.currentLevelNumber
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            FieldTripActiveProfilePatch(imageName: patchImageName)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(FieldTripTemplatePresentation.title(trip.title, slug: trip.slug))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Level \(trip.currentLevelNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GoalProgressRing(
                completedCount: trip.completedCount,
                targetCount: trip.targetCount,
                lineWidth: 4.5,
                labelFontSize: 14,
                tint: .accentColor
            )
            .frame(width: 52, height: 52)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Field trip progress")
            .accessibilityValue(
                "\(trip.completedCount) of \(trip.targetCount) goals complete"
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct FieldTripActiveProfilePatch: View {
    let imageName: String?

    var body: some View {
        if let imageName {
            FieldTripPatchArtwork(imageName: imageName)
        } else {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))

                Image(systemName: "rosette")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }
}

struct FieldTripPublishedProfileRow: View {
    let trip: FieldTripProfilePublishedSummary

    var body: some View {
        HStack(spacing: 12) {
            FieldTripProfileCover(
                urlString: trip.coverImageUrl,
                templateSlug: trip.slug
            )
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(FieldTripTemplatePresentation.title(trip.title, slug: trip.slug))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(trip.itemCount) species")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label(trip.likeCount.formatted(), systemImage: "heart")
                    Label(trip.commentCount.formatted(), systemImage: "bubble.left")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct FieldTripProfileCover: View {
    let urlString: String?
    let templateSlug: String?

    init(urlString: String?, templateSlug: String? = nil) {
        self.urlString = urlString
        self.templateSlug = templateSlug
    }

    var body: some View {
        FieldTripCoverImage(
            urlString: urlString,
            templateSlug: templateSlug,
            placeholderFontSize: 20
        )
    }
}
