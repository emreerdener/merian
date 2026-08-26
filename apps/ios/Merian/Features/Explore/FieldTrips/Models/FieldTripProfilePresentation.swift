import Foundation

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

enum FieldTripProfilePresentation {
    static func visibleChallengeBadges(
        in summaries: FieldTripProfileSummaries
    ) -> [FieldTripChallengeBadge] {
        summaries.challengeBadges
    }

    static func itemCount(in summaries: FieldTripProfileSummaries) -> Int {
        summaries.active.count
            + summaries.pinned.count
            + summaries.published.count
            + visibleChallengeBadges(in: summaries).count
    }

    static func hasContent(_ summaries: FieldTripProfileSummaries) -> Bool {
        itemCount(in: summaries) > 0
    }
}
