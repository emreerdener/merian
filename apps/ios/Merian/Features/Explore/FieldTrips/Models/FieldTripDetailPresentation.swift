import Foundation

enum FieldTripLifecycleConfirmation: String, Identifiable {
    case stop
    case reset

    var id: String { rawValue }
}

enum FieldTripDetailLoadingPresentation {
    static func showsFeaturedMediaHero(
        isLoading: Bool,
        hasTemplate: Bool
    ) -> Bool {
        isLoading && !hasTemplate
    }
}

enum FieldTripInlineTipsPresentation {
    static func shouldShow(
        levelNumber: Int,
        currentLevelNumber: Int,
        isTripComplete: Bool,
        hasGuide: Bool
    ) -> Bool {
        hasGuide && !isTripComplete && levelNumber == currentLevelNumber
    }
}

struct FieldTripGuideScrollTarget: Hashable {
    let itemId: String
}

enum FieldTripsSection: String, CaseIterable, Identifiable {
    case fieldTrips
    case seasonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fieldTrips:
            "Outings"
        case .seasonal:
            "Events"
        }
    }
}

enum FieldTripScanPreviewLayout {
    static let tileSize: CGFloat = 96
    static let cornerRadius: CGFloat = 14
    static let spacing: CGFloat = 10
    static let horizontalInset: CGFloat = 16
}

enum FieldTripScanPreviewResolvedLayout: Equatable {
    case fixedScrollable
    case equalWidthTwoUp
}

enum FieldTripScanPreviewPresentationMode: Equatable {
    case compactScrollable
    case responsiveCatalog

    func resolvedLayout(forTargetCount targetCount: Int) -> FieldTripScanPreviewResolvedLayout {
        if self == .responsiveCatalog, max(0, targetCount) == 2 {
            return .equalWidthTwoUp
        }
        return .fixedScrollable
    }
}

enum FieldTripTemplateCardLayout {
    static let previewTileSize = FieldTripScanPreviewLayout.tileSize
    static let cornerRadius: CGFloat = 24
    static let outerHorizontalInset: CGFloat = 16
}

enum FieldTripLevelHeaderLayout {
    static let accessorySize: CGFloat = 64
    static let ringLineWidth: CGFloat = 5.5
    static let ringLabelFontSize: CGFloat = 16
    static let artworkScale: CGFloat = 1.1
}

// Bundled goal artwork. Capture surfaces intentionally use only exact
// template mappings; richer Field trip grids may use semantic fallback art.
enum FieldTripGoalArtwork {
    static let imageNames = [
        "butterfly-monarch",
        "bird-cardinal",
        "cat",
        "spider",
        "frog",
        "mushroom"
    ]

    private static let backyardSafariImageNames = [
        "butterfly": "fieldtrip-backyard-butterfly",
        "bird": "fieldtrip-backyard-cardinal",
        "cat": "fieldtrip-backyard-cat",
        "spider": "fieldtrip-backyard-spider",
        "flowering plant": "fieldtrip-backyard-flowers",
        "fungus": "fieldtrip-backyard-mushrooms",
        "dog": "fieldtrip-backyard-dog",
        "domesticated animal": "fieldtrip-backyard-dog",
        "insect": "fieldtrip-backyard-bee",
        "urban wild animal": "fieldtrip-backyard-squirrel",
        "moss or lichen": "fieldtrip-backyard-moss"
    ]

    private static let parkPollinatorsImageNames = [
        "flowering plant": "fieldtrip-park-flowering-plant",
        "butterfly or moth": "fieldtrip-park-butterfly",
        "bee or wasp": "fieldtrip-park-bee",
        "fly": "fieldtrip-park-fly",
        "beetle": "fieldtrip-park-beetle",
        "spider": "fieldtrip-park-spider",
        "spider near flowers": "fieldtrip-park-spider",
        "seed or fruiting plant": "fieldtrip-park-seedpod",
        "bird": "fieldtrip-park-hummingbird",
        "bird near flowers": "fieldtrip-park-hummingbird",
        "wild plant": "fieldtrip-park-dandelion",
        "meadow plant": "fieldtrip-park-habitat",
        "pollinator habitat": "fieldtrip-park-habitat"
    ]

    static func imageName(
        for prompt: String,
        templateSlug: String?,
        fallbackIndex: Int
    ) -> String {
        let normalizedPrompt = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let exactImageName = exactImageName(for: prompt, templateSlug: templateSlug) {
            return exactImageName
        }

        if normalizedPrompt.contains("butterfly") { return "butterfly-monarch" }
        if normalizedPrompt.contains("bird") { return "bird-cardinal" }
        if normalizedPrompt.contains("cat") { return "cat" }
        if normalizedPrompt.contains("spider") { return "spider" }
        if normalizedPrompt.contains("frog") { return "frog" }
        if normalizedPrompt.contains("fungus") || normalizedPrompt.contains("mushroom") {
            return "mushroom"
        }

        return imageNames[fallbackIndex % imageNames.count]
    }

    static func exactImageName(for prompt: String, templateSlug: String?) -> String? {
        let normalizedPrompt = prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if templateSlug == FieldTripTemplatePresentation.backyardSafariSlug {
            return backyardSafariImageNames[normalizedPrompt]
        }
        if templateSlug == FieldTripTemplatePresentation.parkPollinatorsSlug {
            return parkPollinatorsImageNames[normalizedPrompt]
        }
        return nil
    }
}

enum FieldTripLevelArtwork {
    static func imageName(templateSlug: String?, levelNumber: Int) -> String? {
        switch (templateSlug, levelNumber) {
        case (FieldTripTemplatePresentation.backyardSafariSlug, 1):
            "fieldtrip-backyard-level-1-patch"
        case (FieldTripTemplatePresentation.backyardSafariSlug, 2):
            "fieldtrip-backyard-level-2-patch"
        case (FieldTripTemplatePresentation.backyardSafariSlug, 3):
            "fieldtrip-backyard-level-3-patch"
        case (FieldTripTemplatePresentation.parkPollinatorsSlug, 1):
            "fieldtrip-park-level-1-patch"
        case (FieldTripTemplatePresentation.parkPollinatorsSlug, 2):
            "fieldtrip-park-level-2-patch"
        case (FieldTripTemplatePresentation.parkPollinatorsSlug, 3):
            "fieldtrip-park-level-3-patch"
        default:
            nil
        }
    }
}

struct FieldTripLevelArtworkGalleryItem: Identifiable, Equatable {
    let id: String
    let imageName: String
    let title: String
}

enum FieldTripLevelPresentationState: Equatable {
    case current
    case completed
    case locked

    static func resolve(
        levelNumber: Int,
        currentLevelNumber: Int,
        isTripComplete: Bool
    ) -> Self {
        if isTripComplete || levelNumber < currentLevelNumber {
            return .completed
        }
        if levelNumber == currentLevelNumber {
            return .current
        }
        return .locked
    }
}

enum FieldTripLevelStatusPresentation {
    static func status(
        for presentationState: FieldTripLevelPresentationState,
        currentStatus: FieldTripTemplateStatusPresentation
    ) -> FieldTripTemplateStatusPresentation {
        switch presentationState {
        case .current:
            currentStatus
        case .completed:
            .init(kind: .completed, title: "Completed")
        case .locked:
            .init(kind: .locked, title: "Locked")
        }
    }
}

enum FieldTripLevelGoalResolvedLayout: Equatable {
    case equalWidthGrid
    case fixedScrollable
}

enum FieldTripLevelGoalLayoutPresentation {
    static func resolvedLayout(forItemCount itemCount: Int) -> FieldTripLevelGoalResolvedLayout {
        max(0, itemCount) <= 2 ? .equalWidthGrid : .fixedScrollable
    }
}

enum FieldTripGoalTipSelection {
    static func defaultItemId(in items: [FieldTripChecklistItem]) -> String? {
        items.first(where: { !$0.isCompleted && $0.hasGuide })?.id
    }

    static func toggledSelection(
        currentItemId: String?,
        tappedItemId: String,
        hasGuide: Bool
    ) -> String? {
        guard hasGuide else { return currentItemId }
        return currentItemId == tappedItemId ? nil : tappedItemId
    }
}

struct FieldTripLevelProgressPresentation {
    let completedCount: Int
    let targetCount: Int
    let fractionComplete: Double
    let completionLabel: String?

    init(_ progress: FieldTripProgress) {
        completedCount = progress.completedCount
        targetCount = progress.targetCount
        fractionComplete = progress.fractionComplete
        completionLabel = nil
    }

    init(_ participation: FieldTripChallengeParticipation) {
        completedCount = participation.completedCount
        targetCount = participation.targetCount
        fractionComplete = participation.fractionComplete
        completionLabel = participation.isComplete ? "Badge earned" : nil
    }

    init(completedCount: Int, targetCount: Int) {
        self.completedCount = completedCount
        self.targetCount = targetCount
        if targetCount > 0 {
            fractionComplete = min(1, max(0, Double(completedCount) / Double(targetCount)))
        } else {
            fractionComplete = 0
        }
        completionLabel = nil
    }
}

enum FieldTripLevelProgressResolver {
    static func resolve(
        presentationState: FieldTripLevelPresentationState,
        currentProgress: FieldTripLevelProgressPresentation?,
        itemCount: Int,
        usesNumericRing: Bool
    ) -> FieldTripLevelProgressPresentation? {
        switch presentationState {
        case .current:
            if let currentProgress {
                return currentProgress
            }
            guard usesNumericRing else { return nil }
            return FieldTripLevelProgressPresentation(
                completedCount: 0,
                targetCount: max(0, itemCount)
            )
        case .completed:
            guard usesNumericRing else { return nil }
            let targetCount = max(0, itemCount)
            return FieldTripLevelProgressPresentation(
                completedCount: targetCount,
                targetCount: targetCount
            )
        case .locked:
            return nil
        }
    }
}

enum FieldTripLevelProgressPlacement {
    case headerRing
    case bar
}

enum FieldTripDisplayDate {
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static func shortDate(_ rawValue: String) -> String {
        guard let date = date(from: rawValue) else { return rawValue }
        return shortDateFormatter.string(from: date)
    }

    static func shortRange(start: String, end: String) -> String {
        guard let startDate = date(from: start),
              let endDate = date(from: end) else {
            return "\(start) - \(end)"
        }

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.year, .month], from: startDate)
        let endComponents = calendar.dateComponents([.year, .month], from: endDate)
        if startComponents.year == endComponents.year,
           startComponents.month == endComponents.month {
            return "\(monthDayFormatter.string(from: startDate))-\(calendar.component(.day, from: endDate))"
        }

        let startLabel = monthDayFormatter.string(from: startDate)
        let endLabel = monthDayFormatter.string(from: endDate)
        return "\(startLabel)-\(endLabel)"
    }

    private static func date(from rawValue: String) -> Date? {
        DateUtilities.iso8601FractionalFormatter.date(from: rawValue)
            ?? DateUtilities.iso8601Formatter.date(from: rawValue)
    }
}
