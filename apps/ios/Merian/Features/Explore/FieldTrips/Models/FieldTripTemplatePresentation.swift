import Foundation

enum FieldTripTemplatePresentation {
    static let backyardSafariSlug = "backyard_safari"
    static let parkPollinatorsSlug = "park_pollinators"
    static let backyardSafariSubtitle = "Observe local species often found in your own backyard."

    static func title(_ title: String, slug: String) -> String {
        slug == backyardSafariSlug ? "Backyard Safari" : title
    }

    static func currentLevel(for template: FieldTripTemplate) -> FieldTripLevel? {
        if let levelNumber = template.viewerProgress?.currentLevelNumber {
            return template.levels.first(where: { $0.levelNumber == levelNumber })
        }

        return template.levels.min(by: { $0.levelNumber < $1.levelNumber })
    }

    static func previewLevel(for template: FieldTripTemplate) -> FieldTripLevel? {
        currentLevel(for: template)
            ?? template.levels.min(by: { $0.levelNumber < $1.levelNumber })
    }

    static func targetCount(for template: FieldTripTemplate) -> Int {
        if let targetCount = template.viewerProgress?.targetCount, targetCount > 0 {
            return targetCount
        }

        return previewLevel(for: template)?.items.count ?? 0
    }

    static func completedCount(for template: FieldTripTemplate) -> Int {
        max(0, template.viewerProgress?.completedCount ?? 0)
    }

    static func currentLevelTitle(for template: FieldTripTemplate) -> String {
        if let title = currentLevel(for: template)?.title
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        let levelNumber = template.viewerProgress?.currentLevelNumber
            ?? template.levels.map(\.levelNumber).min()
            ?? 1
        return "Level \(max(1, levelNumber))"
    }

    static func subtitle(for template: FieldTripTemplate) -> String? {
        guard template.slug == backyardSafariSlug else { return template.subtitle }

        let targetCount = targetCount(for: template)
        guard targetCount > 0 else { return backyardSafariSubtitle }
        return "Observe \(targetCount) local species often found in your own backyard."
    }

    static func status(for template: FieldTripTemplate) -> FieldTripTemplateStatusPresentation {
        if template.isStopped {
            return .init(kind: .stopped, title: "Stopped")
        }

        switch template.catalogState {
        case .completed:
            return .init(kind: .completed, title: "Completed")
        case .inProgress:
            return .init(kind: .active, title: "Active")
        case .incomplete:
            return .init(kind: .notStarted, title: "Not started")
        }
    }

    static func detailTags(
        for template: FieldTripTemplate,
        locationLabel: String?,
        sharingEnabled: Bool = FieldTripSharingAvailability.isEnabled
    ) -> [FieldTripTemplateTagPresentation] {
        var tags: [FieldTripTemplateTagPresentation] = []

        if sharingEnabled, let progress = template.viewerProgress {
            if progress.isPublished {
                tags.append(.init(kind: .visibility, title: "Published", systemImage: "eye.fill"))
            } else {
                tags.append(.init(kind: .visibility, title: "Private", systemImage: "eye.slash.fill"))
            }
        }

        if !template.viewerHasAccess,
           template.isProOnly || template.accessKind.lowercased() == "pro" {
            tags.append(.init(kind: .access, title: "Pro", systemImage: "lock.fill"))
        }

        tags.append(.init(kind: .difficulty, title: template.difficultyTitle))
        tags.append(.init(kind: .level, title: currentLevelTitle(for: template)))

        if let locationLabel = locationLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !locationLabel.isEmpty {
            tags.append(.init(kind: .location, title: locationLabel))
        }

        return tags
    }

    static func bundledCoverImageName(for slug: String?) -> String? {
        slug == backyardSafariSlug ? "fieldtrip-backyard-safari" : nil
    }
}

struct FieldTripTemplateStatusPresentation: Equatable {
    enum Kind: String, Equatable {
        case notStarted
        case active
        case stopped
        case completed
        case locked
    }

    let kind: Kind
    let title: String

    var catalogActionTitle: String {
        kind == .notStarted ? "Get started" : "View field trip"
    }
}

struct FieldTripTemplateTagPresentation: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case access
        case difficulty
        case level
        case visibility
        case location
    }

    let kind: Kind
    let title: String
    var systemImage: String?

    var id: String { "\(kind.rawValue):\(title)" }
}
