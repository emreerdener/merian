import SwiftUI

struct CurrentUserFieldTripProfilePreview: View {
    let onOpenPublication: (String) -> Void

    @State private var summaries: FieldTripProfileSummaries?
    @State private var isLoading = false
    @State private var isUpdatingPins = false
    @State private var toastMessage: String?

    var body: some View {
        Group {
            if let summaries, !summaries.isEmpty {
                FieldTripProfilePreview(
                    summaries: summaries,
                    allowsPinManagement: true,
                    isUpdatingPins: isUpdatingPins,
                    onOpenPublication: onOpenPublication,
                    onTogglePinned: { trip in
                        Task { await togglePin(trip) }
                    }
                )
            } else if isLoading {
                FieldTripProfilePreviewSkeleton()
            }
        }
        .task {
            await load()
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .fieldTripProgressUpdated, .fieldTripChallengeProgressUpdated:
                Task { await load() }
            default:
                break
            }
        }
        .merianSystemFeedback(
            toastMessage: Binding(
                get: { toastMessage },
                set: { toastMessage = $0 }
            ),
            toastAlignment: .top
        )
    }

    private func load() async {
        guard let authorUserId = SupabaseManager.shared.currentUser?.id.uuidString else { return }
        isLoading = true
        defer { isLoading = false }

        summaries = try? await MerianNetworkClient.shared.getFieldTripProfileSummaries(
            authorUserId: authorUserId,
            limit: 6
        )
    }

    private func togglePin(_ trip: FieldTripProfilePublishedSummary) async {
        guard let summaries, !isUpdatingPins else { return }

        var pinnedPublicationIds = summaries.pinned
            .sorted { ($0.pinPosition ?? Int.max) < ($1.pinPosition ?? Int.max) }
            .map(\.publicationId)

        if pinnedPublicationIds.contains(trip.publicationId) {
            pinnedPublicationIds.removeAll { $0 == trip.publicationId }
        } else {
            guard pinnedPublicationIds.count < 3 else {
                toastMessage = "You can pin up to 3 outings."
                HapticManager.shared.triggerErrorThump()
                return
            }
            pinnedPublicationIds.append(trip.publicationId)
        }

        isUpdatingPins = true
        defer { isUpdatingPins = false }

        do {
            self.summaries = try await MerianNetworkClient.shared.setPinnedFieldTripPublications(
                publicationIds: pinnedPublicationIds
            )
            HapticManager.shared.triggerSelectionPulse()
        } catch {
            toastMessage = ExploreErrorFormatter.message(for: error)
            HapticManager.shared.triggerErrorThump()
        }
    }
}

struct FieldTripProfilePreview: View {
    let summaries: FieldTripProfileSummaries
    var allowsPinManagement = false
    var isUpdatingPins = false
    let onOpenPublication: (String) -> Void
    var onTogglePinned: ((FieldTripProfilePublishedSummary) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Outings")
                    .font(.title3.weight(.bold))

                Spacer()

                let count = summaries.active.count + summaries.pinned.count + summaries.published.count + summaries.challengeBadges.count
                Text(count.formatted(.number.notation(.compactName)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if !summaries.challengeBadges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Badges")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    ForEach(summaries.challengeBadges.prefix(3)) { badge in
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
                        FieldTripActiveProfileRow(trip: trip)
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

private struct FieldTripChallengeBadgeProfileRow: View {
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

private struct FieldTripBadgeTagRow: View {
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

private struct FieldTripActiveProfileRow: View {
    let trip: FieldTripProfileActiveSummary

    private var fractionComplete: Double {
        guard trip.targetCount > 0 else { return 0 }
        return min(1, max(0, Double(trip.completedCount) / Double(trip.targetCount)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(FieldTripTemplatePresentation.title(trip.title, slug: trip.slug))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("Level \(trip.currentLevelNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text("\(trip.completedCount)/\(trip.targetCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(6, proxy.size.width * fractionComplete))
                }
            }
            .frame(height: 7)
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
    }
}

private struct FieldTripPublishedProfileRow: View {
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
                    .font(.subheadline.weight(.bold))
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

private struct FieldTripProfileCover: View {
    let urlString: String?
    let templateSlug: String?

    init(urlString: String?, templateSlug: String? = nil) {
        self.urlString = urlString
        self.templateSlug = templateSlug
    }

    var body: some View {
        if let imageName = FieldTripTemplatePresentation.bundledCoverImageName(for: templateSlug) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .clipped()
        } else if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder.redacted(reason: .placeholder)
                @unknown default:
                    placeholder
                }
            }
            .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemGroupedBackground)
            Image(systemName: "map")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FieldTripProfilePreviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 130, height: 20)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 82)
        }
        .redacted(reason: .placeholder)
    }
}
