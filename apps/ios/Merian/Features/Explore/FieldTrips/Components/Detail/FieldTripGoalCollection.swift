import SwiftUI

enum FieldTripLevelGoalCollectionLayout {
    static let equalWidthSpacing: CGFloat = 16
    static let scrollSpacing = FieldTripScanPreviewLayout.spacing
    static let scrollTileSize: CGFloat = 120
}

struct FieldTripLevelGoalCollection: View {
    let items: [FieldTripChecklistItem]
    let templateSlug: String
    let presentationState: FieldTripLevelPresentationState
    let selectedGuideItemId: String?
    let highlightedItemId: String?
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    private var resolvedLayout: FieldTripLevelGoalResolvedLayout {
        FieldTripLevelGoalLayoutPresentation.resolvedLayout(forItemCount: items.count)
    }

    var body: some View {
        switch resolvedLayout {
        case .equalWidthGrid:
            HStack(alignment: .top, spacing: FieldTripLevelGoalCollectionLayout.equalWidthSpacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    goalTile(item: item, index: index)
                }

                if items.count == 1 {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityHidden(true)
                }
            }
        case .fixedScrollable:
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: FieldTripLevelGoalCollectionLayout.scrollSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        goalTile(item: item, index: index)
                            .frame(
                                width: FieldTripLevelGoalCollectionLayout.scrollTileSize,
                                height: FieldTripLevelGoalCollectionLayout.scrollTileSize
                            )
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: FieldTripLevelGoalCollectionLayout.scrollTileSize)
            .padding(.horizontal, -16)
        }
    }

    private func goalTile(
        item: FieldTripChecklistItem,
        index: Int
    ) -> some View {
        FieldTripChecklistGridTile(
            item: item,
            imageName: FieldTripGoalArtwork.imageName(
                for: item.prompt,
                templateSlug: templateSlug,
                fallbackIndex: index
            ),
            presentationState: presentationState,
            isSelected: selectedGuideItemId == item.id,
            isHighlighted: highlightedItemId == item.id,
            showsInlineTitle: false,
            completedScan: item.completedScanId.flatMap { localScansById[$0] },
            onOpenCompletedScan: onOpenCompletedScan,
            onOpenGuide: onOpenGuide
        )
        .id(item.id)
    }
}

struct FieldTripChecklistGridRow: View {
    let items: [FieldTripChecklistItem]
    let templateSlug: String
    let fallbackStartIndex: Int
    let highlightedItemId: String?
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                FieldTripChecklistGridTile(
                    item: item,
                    imageName: FieldTripGoalArtwork.imageName(
                        for: item.prompt,
                        templateSlug: templateSlug,
                        fallbackIndex: fallbackStartIndex + offset
                    ),
                    presentationState: .current,
                    isSelected: false,
                    isHighlighted: highlightedItemId == item.id,
                    showsInlineTitle: true,
                    completedScan: item.completedScanId.flatMap { localScansById[$0] },
                    onOpenCompletedScan: onOpenCompletedScan,
                    onOpenGuide: onOpenGuide
                )
                .id(item.id)
            }

            if items.count == 1 {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .accessibilityHidden(true)
            }
        }
    }
}

struct FieldTripChecklistGridTile: View {
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    let item: FieldTripChecklistItem
    let imageName: String
    let presentationState: FieldTripLevelPresentationState
    let isSelected: Bool
    let isHighlighted: Bool
    let showsInlineTitle: Bool
    let completedScan: LocalScanRecord?
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    @ViewBuilder
    var body: some View {
        if presentationState != .locked,
           let completedScanId = item.completedScanId,
           completedScan != nil {
            Button {
                onOpenCompletedScan(completedScanId)
            } label: {
                tileContent
            }
            .buttonStyle(FieldTripGoalTipButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Open this scan's insight.")
        } else if presentationState == .current, !item.isCompleted, item.hasGuide {
            Button {
                onOpenGuide(item)
            } label: {
                tileContent
            }
            .buttonStyle(FieldTripGoalTipButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isSelected ? "Hide tips for this goal." : "Show tips for this goal.")
        } else {
            tileContent
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(accessibilityHint)
        }
    }

    @ViewBuilder
    private var tileContent: some View {
        if presentationState != .locked, item.isCompleted, let completedScan {
            ZStack(alignment: .bottom) {
                ScanThumbnail(
                    record: completedScan,
                    isOnline: offlineQueueManager.isOnline,
                    maxDimension: 600,
                    mediaBadgeAlignment: .topTrailing
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsInlineTitle {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.78)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack(spacing: 2) {
                        Text(item.prompt)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)

                        if let completedName = item.completedCommonName,
                           completedName.caseInsensitiveCompare(item.prompt) != .orderedSame {
                            Text(completedName)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(tileShape.fill(Color(uiColor: .tertiarySystemGroupedBackground)))
            .clipShape(tileShape)
            .overlay {
                tileShape.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
            }
        } else {
            VStack(alignment: .center, spacing: 6) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsInlineTitle, presentationState != .locked, !isSelected {
                    Text(item.prompt)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if let completedName = item.completedCommonName {
                        Text(completedName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    tileShape.fill(Color(uiColor: .tertiarySystemGroupedBackground))
                }
            }
            .overlay {
                if isHighlighted {
                    tileShape.strokeBorder(Color.accentColor, lineWidth: 2)
                } else if isSelected {
                    tileShape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                }
            }
            .shadow(color: highlightShadowColor, radius: 8)
        }
    }

    private var usesHighlight: Bool {
        (isHighlighted || isSelected) && !item.isCompleted
    }

    private var highlightShadowColor: Color {
        isHighlighted && usesHighlight ? Color.accentColor.opacity(0.28) : .clear
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var accessibilityLabel: String {
        if presentationState == .locked {
            return "Locked goal"
        }
        if let completedName = item.completedCommonName {
            return "\(item.prompt), \(completedName)"
        }
        return item.prompt
    }

    private var accessibilityValue: String {
        if presentationState == .locked { return "Locked" }
        let completion = item.isCompleted ? "Completed" : "Not completed"
        return isSelected ? "\(completion), tips shown" : completion
    }

    private var accessibilityHint: String {
        presentationState == .locked
            ? "Complete the current level to unlock."
            : ""
    }
}

struct FieldTripCompactLevelStrip: View {
    @Environment(OfflineQueueManager.self) private var offlineQueueManager

    let items: [FieldTripChecklistItem]
    let templateSlug: String
    let presentationState: FieldTripLevelPresentationState
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: FieldTripScanPreviewLayout.spacing) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    compactTile(item: item, index: index)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: FieldTripScanPreviewLayout.tileSize)
        .padding(.horizontal, -12)
    }

    @ViewBuilder
    private func compactTile(item: FieldTripChecklistItem, index: Int) -> some View {
        if presentationState == .completed,
           let completedScanId = item.completedScanId,
           localScansById[completedScanId] != nil {
            Button {
                onOpenCompletedScan(completedScanId)
            } label: {
                compactTileContent(item: item, index: index)
            }
            .buttonStyle(FieldTripGoalTipButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: item))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Open this scan's insight.")
        } else {
            compactTileContent(item: item, index: index)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: item))
                .accessibilityValue(accessibilityValue)
                .accessibilityHint(accessibilityHint)
        }
    }

    @ViewBuilder
    private func compactTileContent(item: FieldTripChecklistItem, index: Int) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
            style: .continuous
        )

        if presentationState == .completed,
           let completedScanId = item.completedScanId,
           let completedScan = localScansById[completedScanId] {
            ZStack {
                Color(uiColor: .tertiarySystemGroupedBackground)

                ScanThumbnail(
                    record: completedScan,
                    isOnline: offlineQueueManager.isOnline,
                    maxDimension: 300,
                    mediaBadgeAlignment: .topTrailing
                )
            }
            .frame(
                width: FieldTripScanPreviewLayout.tileSize,
                height: FieldTripScanPreviewLayout.tileSize
            )
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        } else {
            Image(
                FieldTripGoalArtwork.imageName(
                    for: item.prompt,
                    templateSlug: templateSlug,
                    fallbackIndex: index
                )
            )
                .resizable()
                .scaledToFit()
                .frame(
                    width: FieldTripScanPreviewLayout.tileSize,
                    height: FieldTripScanPreviewLayout.tileSize
                )
        }
    }

    private func accessibilityLabel(for item: FieldTripChecklistItem) -> String {
        if presentationState == .locked {
            return "Locked goal"
        }
        if let completedName = item.completedCommonName {
            return "\(item.prompt), \(completedName)"
        }
        return item.prompt
    }

    private var accessibilityValue: String {
        presentationState == .locked ? "Locked" : "Completed"
    }

    private var accessibilityHint: String {
        presentationState == .locked
            ? "Complete the current level to unlock."
            : ""
    }
}
