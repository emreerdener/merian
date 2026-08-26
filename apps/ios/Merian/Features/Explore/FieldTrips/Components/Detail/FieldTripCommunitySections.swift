import SwiftUI

struct FieldTripCommunityPreviewSection: View {
    let publications: [FieldTripRecentPublication]
    let isLoading: Bool
    let onOpenPublication: (String) -> Void
    let onOpenAuthorProfile: (FieldTripRecentPublication) -> Void

    var body: some View {
        if isLoading || !publications.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Community")
                    .font(.headline.weight(.bold))

                if isLoading && publications.isEmpty {
                    ForEach(0..<2, id: \.self) { _ in
                        FieldTripRecentSkeletonCard()
                    }
                } else {
                    ForEach(publications) { publication in
                        FieldTripCommunityPublicationCard(
                            publication: publication,
                            onOpenPublication: onOpenPublication,
                            onOpenAuthorProfile: onOpenAuthorProfile
                        )
                    }
                }
            }
        }
    }
}

struct FieldTripAboutOutingSection: View {
    let template: FieldTripTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FieldTripGuideRow(
                title: "How scans count",
                systemImage: "clock.arrow.circlepath",
                bodyText: """
                Only scans made once this outing starts count toward its goals. \
                Older scans—including anything already in your library when it starts—don’t qualify.
                """
            )

            if let whereToLook = template.guideWhereToLook {
                FieldTripGuideRow(
                    title: "Where to look",
                    systemImage: "binoculars",
                    bodyText: whereToLook
                )
            }

            if let whyItMatters = template.guideWhyItMatters {
                FieldTripGuideRow(
                    title: "Why it matters",
                    systemImage: "leaf",
                    bodyText: whyItMatters
                )
            }

            if let safety = template.guideSafetyEthics {
                FieldTripGuideRow(
                    title: "Safety",
                    systemImage: "hand.raised",
                    bodyText: safety
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FieldTripSelectedGoalTipsSection: View {
    let item: FieldTripChecklistItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.prompt)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            ForEach(FieldTripGoalGuidePresentation.sections(for: item)) { section in
                FieldTripGoalGuideContentRow(section: section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tips for \(item.prompt)")
    }
}

struct FieldTripActiveLevelTipsSection: View {
    let level: FieldTripLevel
    let templateSlug: String
    @Binding var expandedItemId: String?
    let highlightedItemId: String?

    var body: some View {
        let guidedItems = Array(level.items.enumerated()).filter { $0.element.hasGuide }

        VStack(alignment: .leading, spacing: 10) {
            ForEach(guidedItems, id: \.element.id) { index, item in
                FieldTripGoalGuideCard(
                    item: item,
                    imageName: FieldTripGoalArtwork.imageName(
                        for: item.prompt,
                        templateSlug: templateSlug,
                        fallbackIndex: index
                    ),
                    isExpanded: expandedItemId == item.id,
                    isHighlighted: highlightedItemId == item.id,
                    onToggle: {
                        HapticManager.shared.triggerSelectionPulse()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedItemId = expandedItemId == item.id ? nil : item.id
                        }
                    }
                )
                .id(FieldTripGuideScrollTarget(itemId: item.id))
            }
        }
    }
}

struct FieldTripGoalGuideCard: View {
    let item: FieldTripChecklistItem
    let imageName: String
    let isExpanded: Bool
    let isHighlighted: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    FieldTripGuideArtworkContainer {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .padding(5)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.prompt)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        if let preview = item.guidePreview {
                            Text(preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(isExpanded ? 1 : 2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.prompt)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse tips." : "Expand tips.")

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    ForEach(guideSections) { section in
                        FieldTripGoalGuideContentRow(section: section)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isHighlighted ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isHighlighted ? 2 : 1
                )
        }
        .animation(.easeInOut(duration: 0.25), value: isHighlighted)
    }

    private var guideSections: [FieldTripGoalGuideContentSection] {
        FieldTripGoalGuidePresentation.sections(for: item)
    }
}

enum FieldTripGoalGuidePresentation {
    static func sections(
        for item: FieldTripChecklistItem
    ) -> [FieldTripGoalGuideContentSection] {
        if let guide = item.guide {
            let sections = [
                FieldTripGoalGuideContentSection(
                    title: "Where to look",
                    systemImage: "binoculars",
                    bodyText: guide.whereToLook
                ),
                FieldTripGoalGuideContentSection(
                    title: "Best conditions",
                    systemImage: "cloud.sun",
                    bodyText: guide.bestConditions
                ),
                FieldTripGoalGuideContentSection(
                    title: "What to notice",
                    systemImage: "eye",
                    bodyText: guide.whatToNotice
                ),
                FieldTripGoalGuideContentSection(
                    title: "Scan safely",
                    systemImage: "hand.raised",
                    bodyText: guide.scanSafely
                )
            ].compactMap { $0.nonEmpty }

            if !sections.isEmpty {
                return sections
            }
        }

        return [
            FieldTripGoalGuideContentSection(
                title: "Tip",
                systemImage: "lightbulb",
                bodyText: item.guideTip
            )
        ].compactMap { $0.nonEmpty }
    }
}

struct FieldTripGoalGuideContentSection: Identifiable {
    let title: String
    let systemImage: String
    let bodyText: String?

    var id: String { title }

    var nonEmpty: Self? {
        guard let bodyText,
              !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return self
    }
}

struct FieldTripGoalGuideContentRow: View {
    let section: FieldTripGoalGuideContentSection

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: section.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                if let bodyText = section.bodyText {
                    Text(bodyText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FieldTripGuideRow: View {
    let title: String
    let systemImage: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(bodyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

enum FieldTripGuideArtworkContainerLayout {
    static let size: CGFloat = 58
    static let cornerRadius: CGFloat = 10
}

struct FieldTripGuideArtworkContainer<Artwork: View>: View {
    let artwork: Artwork

    init(@ViewBuilder artwork: () -> Artwork) {
        self.artwork = artwork()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: FieldTripGuideArtworkContainerLayout.cornerRadius,
                style: .continuous
            )
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))

            artwork
        }
        .frame(
            width: FieldTripGuideArtworkContainerLayout.size,
            height: FieldTripGuideArtworkContainerLayout.size
        )
    }
}
