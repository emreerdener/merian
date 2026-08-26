import SwiftUI

struct FieldTripLevelsSection: View {
    let template: FieldTripTemplate
    let currentLevelNumber: Int
    let isTripComplete: Bool
    let status: FieldTripTemplateStatusPresentation?
    let progress: FieldTripLevelProgressPresentation?
    let progressPlacement: FieldTripLevelProgressPlacement
    @Binding var expandedGuideItemId: String?
    let highlightedGuideItemId: String?
    let highlightedItemId: String?
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(template.levels) { level in
                FieldTripLevelSection(
                    level: level,
                    templateSlug: template.slug,
                    presentationState: .resolve(
                        levelNumber: level.levelNumber,
                        currentLevelNumber: currentLevelNumber,
                        isTripComplete: isTripComplete
                    ),
                    templateStatus: status,
                    progress: progress(for: level),
                    progressPlacement: progressPlacement,
                    showsInlineTips: FieldTripInlineTipsPresentation.shouldShow(
                        levelNumber: level.levelNumber,
                        currentLevelNumber: currentLevelNumber,
                        isTripComplete: isTripComplete,
                        hasGuide: level.items.contains(where: \.hasGuide)
                    ),
                    expandedGuideItemId: $expandedGuideItemId,
                    highlightedGuideItemId: highlightedGuideItemId,
                    highlightedItemId: highlightedItemId,
                    localScansById: localScansById,
                    onOpenCompletedScan: onOpenCompletedScan,
                    onOpenGuide: onOpenGuide
                )
            }
        }
    }

    private func progress(for level: FieldTripLevel) -> FieldTripLevelProgressPresentation? {
        let presentationState = FieldTripLevelPresentationState.resolve(
            levelNumber: level.levelNumber,
            currentLevelNumber: currentLevelNumber,
            isTripComplete: isTripComplete
        )

        return FieldTripLevelProgressResolver.resolve(
            presentationState: presentationState,
            currentProgress: progress,
            itemCount: level.items.count,
            usesNumericRing: progressPlacement == .headerRing
        )
    }
}

struct FieldTripLevelSection: View {
    let level: FieldTripLevel
    let templateSlug: String
    let presentationState: FieldTripLevelPresentationState
    let templateStatus: FieldTripTemplateStatusPresentation?
    let progress: FieldTripLevelProgressPresentation?
    let progressPlacement: FieldTripLevelProgressPlacement
    let showsInlineTips: Bool
    @Binding var expandedGuideItemId: String?
    let highlightedGuideItemId: String?
    let highlightedItemId: String?
    let localScansById: [String: LocalScanRecord]
    let onOpenCompletedScan: (String) -> Void
    let onOpenGuide: (FieldTripChecklistItem) -> Void

    @State private var isLevelArtworkExpanded = false

    private var rowStartIndices: [Int] {
        Array(stride(from: 0, to: level.items.count, by: 2))
    }

    private var levelArtworkImageName: String? {
        FieldTripLevelArtwork.imageName(
            templateSlug: templateSlug,
            levelNumber: level.levelNumber
        )
    }

    private var usesOutingPresentation: Bool {
        templateStatus != nil && progressPlacement == .headerRing
    }

    private var selectedGuideItem: FieldTripChecklistItem? {
        guard presentationState == .current,
              showsInlineTips,
              let expandedGuideItemId else {
            return nil
        }
        return level.items.first(where: { item in
            item.id == expandedGuideItemId && !item.isCompleted && item.hasGuide
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            levelHeader

            if progressPlacement == .bar, let progress {
                FieldTripLevelProgressBar(progress: progress)
            }

            if usesOutingPresentation {
                outingLevelContent
            } else {
                legacyLevelContent
            }
        }
        .padding(usesOutingPresentation ? 16 : 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var levelHeader: some View {
        if usesOutingPresentation {
            outingLevelHeader
        } else {
            legacyLevelHeader
        }
    }

    private var outingLevelHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            levelPatchAccessory(reservesSpace: true)

            Spacer(minLength: 0)

            Text(level.title)
                .font(.title.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .layoutPriority(1)

            Spacer(minLength: 0)

            switch presentationState {
            case .current, .completed:
                if let progress {
                    progressRing(progress)
                } else {
                    trailingAccessorySpacer
                }
            case .locked:
                lockedIndicator
            }
        }
    }

    private var legacyLevelHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            levelPatchAccessory(reservesSpace: false)

            VStack(alignment: .center, spacing: 8) {
                Text(level.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let description = level.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .layoutPriority(1)

            switch presentationState {
            case .current:
                if progressPlacement == .headerRing, let progress {
                    progressRing(progress)
                } else if levelArtworkImageName != nil {
                    trailingAccessorySpacer
                }
            case .completed:
                if progressPlacement == .headerRing, let progress {
                    progressRing(progress)
                } else {
                    Text("Completed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(
                            width: FieldTripLevelHeaderLayout.accessorySize,
                            height: FieldTripLevelHeaderLayout.accessorySize
                        )
                }
            case .locked:
                lockedIndicator
            }
        }
    }

    private var outingLevelContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldTripLevelGoalCollection(
                items: level.items,
                templateSlug: templateSlug,
                presentationState: presentationState,
                selectedGuideItemId: presentationState == .current
                    ? expandedGuideItemId
                    : nil,
                highlightedItemId: highlightedItemId,
                localScansById: localScansById,
                onOpenCompletedScan: onOpenCompletedScan,
                onOpenGuide: onOpenGuide
            )

            if let selectedGuideItem {
                FieldTripSelectedGoalTipsSection(item: selectedGuideItem)
                .id(FieldTripGuideScrollTarget(itemId: selectedGuideItem.id))
            }
        }
    }

    @ViewBuilder
    private var legacyLevelContent: some View {
        switch presentationState {
        case .current:
            VStack(alignment: .leading, spacing: 16) {
                ForEach(rowStartIndices, id: \.self) { startIndex in
                    FieldTripChecklistGridRow(
                        items: Array(
                            level.items[
                                startIndex..<min(startIndex + 2, level.items.count)
                            ]
                        ),
                        templateSlug: templateSlug,
                        fallbackStartIndex: startIndex,
                        highlightedItemId: highlightedItemId,
                        localScansById: localScansById,
                        onOpenCompletedScan: onOpenCompletedScan,
                        onOpenGuide: onOpenGuide
                    )
                }

                if showsInlineTips {
                    FieldTripActiveLevelTipsSection(
                        level: level,
                        templateSlug: templateSlug,
                        expandedItemId: $expandedGuideItemId,
                        highlightedItemId: highlightedGuideItemId
                    )
                }
            }
        case .completed, .locked:
            FieldTripCompactLevelStrip(
                items: level.items,
                templateSlug: templateSlug,
                presentationState: presentationState,
                localScansById: localScansById,
                onOpenCompletedScan: onOpenCompletedScan
            )
        }
    }

    @ViewBuilder
    private func levelPatchAccessory(reservesSpace: Bool) -> some View {
        if let levelArtworkImageName {
            Button {
                HapticManager.shared.triggerSelectionPulse()
                isLevelArtworkExpanded = true
            } label: {
                Image(levelArtworkImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: FieldTripLevelHeaderLayout.accessorySize,
                        height: FieldTripLevelHeaderLayout.accessorySize
                    )
                    .scaleEffect(FieldTripLevelHeaderLayout.artworkScale)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View \(level.title) patch")
            .accessibilityHint("Opens a larger, zoomable image")
            .fullScreenCover(isPresented: $isLevelArtworkExpanded) {
                FieldTripLevelArtworkExpandedView(
                    items: [
                        FieldTripLevelArtworkGalleryItem(
                            id: levelArtworkImageName,
                            imageName: levelArtworkImageName,
                            title: level.title
                        )
                    ],
                    initialItemID: levelArtworkImageName
                )
            }
        } else if reservesSpace {
            trailingAccessorySpacer
        }
    }

    private func progressRing(_ progress: FieldTripLevelProgressPresentation) -> some View {
        GoalProgressRing(
            completedCount: progress.completedCount,
            targetCount: progress.targetCount,
            lineWidth: FieldTripLevelHeaderLayout.ringLineWidth,
            labelFontSize: FieldTripLevelHeaderLayout.ringLabelFontSize,
            tint: usesOutingPresentation
                ? (progress.completedCount > 0 ? .green : .secondary)
                : .accentColor,
            showsCompletionCheckmark: !usesOutingPresentation
        )
        .frame(
            width: FieldTripLevelHeaderLayout.accessorySize,
            height: FieldTripLevelHeaderLayout.accessorySize
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level progress")
        .accessibilityValue(
            "\(progress.completedCount) of \(progress.targetCount) goals complete"
        )
    }

    private var lockedIndicator: some View {
        ZStack {
            Circle()
                .stroke(
                    .secondary.opacity(0.28),
                    lineWidth: FieldTripLevelHeaderLayout.ringLineWidth
                )

            Image(systemName: "lock")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(2)
        .frame(
            width: FieldTripLevelHeaderLayout.accessorySize,
            height: FieldTripLevelHeaderLayout.accessorySize
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Locked")
    }

    private var trailingAccessorySpacer: some View {
        Color.clear
            .frame(
                width: FieldTripLevelHeaderLayout.accessorySize,
                height: FieldTripLevelHeaderLayout.accessorySize
            )
            .accessibilityHidden(true)
    }
}
