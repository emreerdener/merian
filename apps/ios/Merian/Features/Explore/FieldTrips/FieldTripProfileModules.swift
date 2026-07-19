import SwiftData
import SwiftUI

struct ActiveFieldTripProfileItem: Identifiable, Equatable {
    let outing: FieldTripCaptureOuting
    let template: FieldTripTemplate

    var id: String { outing.userFieldTripId }

    var currentLevelItems: [FieldTripChecklistItem] {
        template.levels
            .first(where: { $0.levelNumber == outing.levelNumber })?
            .items ?? []
    }
}

enum ActiveFieldTripProfilePresentation {
    static let previewLimit = 2

    static func items(
        outings: [FieldTripCaptureOuting],
        templates: [FieldTripTemplate]
    ) -> [ActiveFieldTripProfileItem] {
        let templatesById = Dictionary(uniqueKeysWithValues: templates.map { ($0.templateId, $0) })

        return outings.compactMap { outing in
            guard let template = templatesById[outing.templateId],
                  template.viewerHasAccess,
                  let progress = template.activeProgress,
                  progress.userFieldTripId == outing.userFieldTripId,
                  !progress.isComplete else {
                return nil
            }

            return ActiveFieldTripProfileItem(outing: outing, template: template)
        }
    }

    static func previewItems(
        from items: [ActiveFieldTripProfileItem]
    ) -> ArraySlice<ActiveFieldTripProfileItem> {
        items.prefix(previewLimit)
    }

    static func shouldShowViewAll(for items: [ActiveFieldTripProfileItem]) -> Bool {
        items.count > previewLimit
    }
}

struct ActiveFieldTripsProfilePreview: View {
    let onOpenTemplate: (String) -> Void
    let onOpenCompletedScan: (String) -> Void
    let onViewAll: () -> Void

    @Environment(SupabaseManager.self) private var supabase
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var localScans: [LocalScanRecord]

    @State private var items: [ActiveFieldTripProfileItem] = []
    @State private var isLoading = false
    @State private var hasLoaded = false

    private var currentUserId: String? {
        supabase.currentUser?.id.uuidString
    }

    private var localScansById: [String: LocalScanRecord] {
        localScans.reduce(into: [:]) { scans, scan in
            scans[scan.id] = scan
        }
    }

    var body: some View {
        Group {
            if !items.isEmpty {
                content
            } else if isLoading && !hasLoaded {
                ActiveFieldTripsProfileSkeleton()
            }
        }
        .task(id: currentUserId) {
            await load()
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            switch event {
            case .fieldTripProgressUpdated:
                Task { await load() }
            case .captureGoalContextInvalidated(let source) where source == .fieldTrip:
                Task { await load() }
            default:
                break
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Field trips")
                    .font(.title3.weight(.bold))

                Spacer()

                Text(items.count.formatted(.number.notation(.compactName)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                ForEach(ActiveFieldTripProfilePresentation.previewItems(from: items)) { item in
                    CurrentUserActiveFieldTripProfileCard(
                        item: item,
                        localScansById: localScansById,
                        onOpenTemplate: {
                            HapticManager.shared.triggerSelectionPulse()
                            onOpenTemplate(item.template.templateId)
                        },
                        onOpenCompletedScan: onOpenCompletedScan
                    )
                }
            }

            if ActiveFieldTripProfilePresentation.shouldShowViewAll(for: items) {
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    onViewAll()
                } label: {
                    HStack(spacing: 4) {
                        Text("View all field trips")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        Capsule()
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Field trips in Explore.")
            }
        }
    }

    @MainActor
    private func load() async {
        guard currentUserId != nil else {
            items = []
            hasLoaded = true
            isLoading = false
            return
        }
        guard !isLoading else { return }

        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            async let outings = MerianNetworkClient.shared.getFieldTripCaptureContext()
            async let templates = MerianNetworkClient.shared.getFieldTrips(limit: 80)
            let loadedItems = try await ActiveFieldTripProfilePresentation.items(
                outings: outings,
                templates: templates
            )
            guard !Task.isCancelled else { return }
            items = loadedItems
        } catch {
            MerianLog.network.warning("Failed to load active Profile Field trips: \(error.localizedDescription, privacy: .private)")
        }
    }
}

private struct CurrentUserActiveFieldTripProfileCard: View {
    let item: ActiveFieldTripProfileItem
    let localScansById: [String: LocalScanRecord]
    let onOpenTemplate: () -> Void
    let onOpenCompletedScan: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpenTemplate) {
                Text(FieldTripTemplatePresentation.title(item.template.title, slug: item.template.slug))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            FieldTripScanPreviewStrip(
                targetCount: item.outing.targetCount,
                templateSlug: item.template.slug,
                items: item.currentLevelItems,
                localScansById: localScansById,
                onOpenTemplate: onOpenTemplate,
                onOpenCompletedScan: onOpenCompletedScan
            )
            .padding(.bottom, 12)

            Button(action: onOpenTemplate) {
                FieldTripLevelProgressBar(
                    progress: FieldTripLevelProgressPresentation(
                        completedCount: item.outing.completedCount,
                        targetCount: item.outing.targetCount
                    )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .accessibilityElement(children: .contain)
    }
}

private struct ActiveFieldTripsProfileSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                GlowPulsingSkeletonView(cornerRadius: 5)
                    .frame(width: 110, height: 23)
                Spacer()
                GlowPulsingSkeletonView(cornerRadius: 5)
                    .frame(width: 20, height: 16)
            }

            ForEach(0..<ActiveFieldTripProfilePresentation.previewLimit, id: \.self) { _ in
                GlowPulsingSkeletonView(cornerRadius: 24)
                    .frame(height: 190)
            }
        }
        .accessibilityLabel("Loading active Field trips")
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
                Text("Field trips")
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
