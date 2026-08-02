import SwiftData
import SwiftUI

struct ActiveFieldTripProfileItem: Identifiable, Equatable {
    let userFieldTripId: String
    let template: FieldTripTemplate
    let startedAt: String
    let currentLevelNumber: Int
    let completedCount: Int
    let targetCount: Int

    var id: String { userFieldTripId }

    var currentLevelItems: [FieldTripChecklistItem] {
        template.levels
            .first(where: { $0.levelNumber == currentLevelNumber })?
            .items ?? []
    }
}

enum ActiveFieldTripProfilePresentation {
    static let previewLimit = 1

    static func items(templates: [FieldTripTemplate]) -> [ActiveFieldTripProfileItem] {
        let items = templates.compactMap { template -> ActiveFieldTripProfileItem? in
            guard template.viewerHasAccess,
                  let progress = template.activeProgress,
                  !progress.isComplete else {
                return nil
            }

            return ActiveFieldTripProfileItem(
                userFieldTripId: progress.userFieldTripId,
                template: template,
                startedAt: progress.startedAt,
                currentLevelNumber: progress.currentLevelNumber,
                completedCount: progress.completedCount,
                targetCount: progress.targetCount
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt < rhs.startedAt
            }
            return lhs.template.templateId < rhs.template.templateId
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

struct EarnedFieldTripPatch: Identifiable, Equatable {
    let id: String
    let templateId: String
    let imageName: String
    let templateTitle: String
    let levelTitle: String

    var title: String {
        "\(templateTitle) · \(levelTitle)"
    }

    var galleryItem: FieldTripLevelArtworkGalleryItem {
        FieldTripLevelArtworkGalleryItem(
            id: id,
            imageName: imageName,
            title: title
        )
    }
}

enum EarnedFieldTripPatchPresentation {
    static func items(templates: [FieldTripTemplate]) -> [EarnedFieldTripPatch] {
        templates.flatMap { template -> [EarnedFieldTripPatch] in
            guard let progress = template.viewerProgress else { return [] }

            let earnedThroughLevel = progress.currentLevelNumber - (progress.isComplete ? 0 : 1)
            guard earnedThroughLevel > 0 else { return [] }

            return template.levels
                .filter { $0.levelNumber <= earnedThroughLevel }
                .sorted { $0.levelNumber < $1.levelNumber }
                .compactMap { level in
                    guard let imageName = FieldTripLevelArtwork.imageName(
                        templateSlug: template.slug,
                        levelNumber: level.levelNumber
                    ) else {
                        return nil
                    }

                    return EarnedFieldTripPatch(
                        id: "\(template.templateId):\(level.levelId)",
                        templateId: template.templateId,
                        imageName: imageName,
                        templateTitle: FieldTripTemplatePresentation.title(
                            template.title,
                            slug: template.slug
                        ),
                        levelTitle: level.title
                    )
                }
        }
    }

    static func items(profileSummaries: [FieldTripProfileActiveSummary]) -> [EarnedFieldTripPatch] {
        profileSummaries.flatMap { summary -> [EarnedFieldTripPatch] in
            let earnedThroughLevel = summary.currentLevelNumber - (summary.isComplete ? 0 : 1)
            guard earnedThroughLevel > 0 else { return [] }

            return (1...earnedThroughLevel).compactMap { levelNumber in
                guard let imageName = FieldTripLevelArtwork.imageName(
                    templateSlug: summary.slug,
                    levelNumber: levelNumber
                ) else {
                    return nil
                }

                return EarnedFieldTripPatch(
                    id: "\(summary.userFieldTripId):\(levelNumber)",
                    templateId: summary.templateId,
                    imageName: imageName,
                    templateTitle: FieldTripTemplatePresentation.title(
                        summary.title,
                        slug: summary.slug
                    ),
                    levelTitle: "Level \(levelNumber)"
                )
            }
        }
    }
}

struct EarnedFieldTripPatchCarousel: View {
    let patches: [EarnedFieldTripPatch]
    let onOpenFieldTrip: (String) -> Void

    @State private var selectedPatch: EarnedFieldTripPatch?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(patches) { patch in
                    Button {
                        HapticManager.shared.triggerSelectionPulse()
                        selectedPatch = patch
                    } label: {
                        FieldTripPatchArtwork(imageName: patch.imageName)
                            .frame(width: 64, height: 64)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(patch.title) patch")
                    .accessibilityHint("Opens the patch gallery at this patch")
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, -12)
        .fullScreenCover(item: $selectedPatch) { patch in
            FieldTripLevelArtworkExpandedView(
                items: patches.map(\.galleryItem),
                initialItemID: patch.id,
                onOpenFieldTrip: { item in
                    guard let selectedPatch = patches.first(where: { $0.id == item.id }) else {
                        return
                    }
                    onOpenFieldTrip(selectedPatch.templateId)
                }
            )
        }
    }
}

/// A square canvas that preserves the silhouette supplied by each patch asset.
/// Patch artwork is intentionally not clipped to a circle so future shapes render as designed.
private struct FieldTripPatchArtwork: View {
    let imageName: String

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
            }
    }
}

struct EarnedFieldTripPatchCarouselSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    GlowPulsingSkeletonView(cornerRadius: 32)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.horizontal, -12)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

enum FieldTripProfilePresentation {
    static func visibleChallengeBadges(
        in summaries: FieldTripProfileSummaries,
        eventsEnabled: Bool
    ) -> [FieldTripChallengeBadge] {
        eventsEnabled ? summaries.challengeBadges : []
    }

    static func itemCount(
        in summaries: FieldTripProfileSummaries,
        eventsEnabled: Bool
    ) -> Int {
        summaries.active.count
            + summaries.pinned.count
            + summaries.published.count
            + visibleChallengeBadges(in: summaries, eventsEnabled: eventsEnabled).count
    }

    static func hasContent(
        _ summaries: FieldTripProfileSummaries,
        eventsEnabled: Bool
    ) -> Bool {
        itemCount(in: summaries, eventsEnabled: eventsEnabled) > 0
    }
}

struct ActiveFieldTripsProfilePreview: View {
    let onOpenTemplate: (String) -> Void
    let onOpenCompletedScan: (String) -> Void
    let onViewAll: () -> Void
    let onEarnedPatchesChange: ([EarnedFieldTripPatch]) -> Void
    let onEarnedPatchesLoadingChange: (Bool) -> Void

    @Environment(SupabaseManager.self) private var supabase
    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var localScans: [LocalScanRecord]

    @State private var items: [ActiveFieldTripProfileItem] = []
    // Start in a rendered state so SwiftUI mounts the task that performs the first load.
    // An initial EmptyView does not reliably receive lifecycle modifiers.
    @State private var isLoading = true
    @State private var isLoadInFlight = false
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
        VStack(alignment: .leading, spacing: 16) {
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
            onEarnedPatchesChange([])
            onEarnedPatchesLoadingChange(false)
            hasLoaded = true
            isLoading = false
            return
        }
        guard !isLoadInFlight else { return }

        isLoadInFlight = true
        isLoading = true
        onEarnedPatchesLoadingChange(true)
        defer {
            isLoadInFlight = false
            isLoading = false
            hasLoaded = true
            onEarnedPatchesLoadingChange(false)
        }

        do {
            let templates = try await MerianNetworkClient.shared.getFieldTrips(limit: 80)
            let loadedItems = ActiveFieldTripProfilePresentation.items(
                templates: templates
            )
            let loadedPatches = EarnedFieldTripPatchPresentation.items(
                templates: templates
            )
            guard !Task.isCancelled else { return }
            items = loadedItems
            onEarnedPatchesChange(loadedPatches)
            MerianLog.network.debug(
                "Loaded \(loadedItems.count, privacy: .public) active Profile Field trips and \(loadedPatches.count, privacy: .public) earned patches."
            )
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
                HStack(spacing: 8) {
                    Text(FieldTripTemplatePresentation.title(item.template.title, slug: item.template.slug))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            FieldTripScanPreviewStrip(
                targetCount: item.targetCount,
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
                        completedCount: item.completedCount,
                        targetCount: item.targetCount
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
        VStack(alignment: .leading, spacing: 16) {
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
    let onOpenTemplate: (String) -> Void
    let onOpenPublication: (String) -> Void
    var onTogglePinned: ((FieldTripProfilePublishedSummary) -> Void)?

    private var eventsEnabled: Bool {
        FieldTripEventsAvailability.isEnabled
    }

    private var visibleChallengeBadges: [FieldTripChallengeBadge] {
        FieldTripProfilePresentation.visibleChallengeBadges(
            in: summaries,
            eventsEnabled: eventsEnabled
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Field trips")
                    .font(.title3.weight(.bold))

                Spacer()

                let count = FieldTripProfilePresentation.itemCount(
                    in: summaries,
                    eventsEnabled: eventsEnabled
                )
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
                    .font(.subheadline.weight(.bold))
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
                labelFontSize: 11,
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

private struct FieldTripActiveProfilePatch: View {
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
