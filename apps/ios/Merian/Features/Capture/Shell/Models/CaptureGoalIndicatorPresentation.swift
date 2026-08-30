import CoreGraphics

enum ActiveCaptureGoalSwipeDirection: Equatable {
    case next
    case previous

    static func resolve(horizontal: CGFloat, vertical: CGFloat) -> Self? {
        guard abs(horizontal) > 36,
              abs(horizontal) > abs(vertical) * 1.25 else {
            return nil
        }
        return horizontal < 0 ? .next : .previous
    }
}

enum CaptureGoalIndicatorExpansionState: Equatable {
    case collapsed
    case expanded

    var isExpanded: Bool {
        self == .expanded
    }

    var toggled: Self {
        isExpanded ? .collapsed : .expanded
    }

    func preservingOnly(in captureMode: CaptureMode) -> Self {
        captureMode == .visual ? self : .collapsed
    }

    func preservingOnly(whenVisible isVisible: Bool) -> Self {
        isVisible ? self : .collapsed
    }
}

enum CaptureGoalIndicatorLayoutPolicy {
    static let expandedHorizontalMargin: CGFloat = 32
    static let compactSize: CGFloat = 50
    static let expandedSize: CGFloat = 56
    static let compactArtworkSize: CGFloat = 42
    static let expandedArtworkSize: CGFloat = 36
    static let rowSpacing: CGFloat = 12
    static let minimumInlineGap: CGFloat = 8

    static func surfaceSize(isExpanded: Bool) -> CGFloat {
        isExpanded ? expandedSize : compactSize
    }

    static func artworkSize(isExpanded: Bool) -> CGFloat {
        isExpanded ? expandedArtworkSize : compactArtworkSize
    }

    static func compactTrailingMargin(containerWidth: CGFloat) -> CGFloat {
        guard containerWidth.isFinite, containerWidth > 0 else {
            return expandedHorizontalMargin
        }
        let availableSideSpace =
            (containerWidth - CaptureModeSelectorStyle.controlWidth) / 2
        return min(
            expandedHorizontalMargin,
            max(
                0,
                availableSideSpace - compactSize - minimumInlineGap
            )
        )
    }

    static func verticalOffset(isExpanded: Bool) -> CGFloat {
        guard !isExpanded else { return 0 }
        let centerlineAdjustment =
            (CaptureModeSelectorStyle.controlHeight - compactSize) / 2
        return -(CaptureModeSelectorStyle.controlHeight + rowSpacing)
            + centerlineAdjustment
    }
}

enum CaptureGoalArtworkRotation {
    static func artwork(
        at index: Int,
        in artworks: [CaptureGoalArtwork]
    ) -> CaptureGoalArtwork {
        guard !artworks.isEmpty else {
            return .systemSymbol(name: "binoculars.fill")
        }
        return artworks[normalizedIndex(index, count: artworks.count)]
    }

    static func nextIndex(after index: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let currentIndex = normalizedIndex(index, count: count)
        return currentIndex == count - 1 ? 0 : currentIndex + 1
    }

    private static func normalizedIndex(_ index: Int, count: Int) -> Int {
        let remainder = index % count
        return remainder >= 0 ? remainder : remainder + count
    }
}

enum ActiveCaptureGoalPresentationPolicy {
    static func shouldShow(
        goalsEnabled: Bool,
        isUserVisible: Bool,
        isVisualMode: Bool,
        hasPresentation: Bool,
        stagedCaptureIsEmpty: Bool,
        isRefining: Bool,
        isVideoRecording: Bool
    ) -> Bool {
        goalsEnabled
            && isUserVisible
            && isVisualMode
            && hasPresentation
            && stagedCaptureIsEmpty
            && !isRefining
            && !isVideoRecording
    }
}

enum CaptureGoalPreferencePolicy {
    static func preferredGoal(
        goalsEnabled: Bool,
        isUserVisible: Bool,
        isVisualMode: Bool,
        isRefining: Bool,
        selectedGoal: CaptureGoal?
    ) -> FieldTripPreferredGoal? {
        guard goalsEnabled,
              isUserVisible,
              isVisualMode,
              !isRefining,
              let selectedGoal,
              case .fieldTrip(_, let checklistItemId) = selectedGoal.destination else {
            return nil
        }

        return FieldTripPreferredGoal(
            userFieldTripId: selectedGoal.source.id,
            itemId: checklistItemId
        )
    }
}

enum ActiveCaptureGoalIndicatorCopy {
    static func instruction(for prompt: String) -> String {
        "Goal: \(prompt)"
    }

    static func accessibilityLabel(for prompt: String) -> String {
        "Outing goal. \(prompt)."
    }
}

enum CaptureGoalIndicatorAccessibilityCopy {
    static let goalCollapseLabel = "Collapse outing goal details"
    static let goalCollapseHint = "Hides the goal and outing details."
    static let goalExpandHint =
        "Expands goal details. Swipe up or down to change target."
    static let goalOpenHint =
        "Opens outing details for this target. Swipe up or down to change target."
    static let introductionCollapseLabel = "Collapse outing invitation"
    static let introductionCollapseHint = "Hides the outing details."
    static let introductionExpandHint = "Expands the outing details."

    static func progressValue(
        sourceTitle: String,
        completedCount: Int,
        targetCount: Int
    ) -> String {
        "\(sourceTitle), \(completedCount) of \(targetCount) complete"
    }
}
