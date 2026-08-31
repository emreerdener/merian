enum InsightSharePendingAction: Equatable {
    case externalShare
    case askCommunity
    case composeExplorePost
    case publishExploreAnyway
    case editExplorePost
    case editCommunityRequest
    case viewCommunityRequest
    case viewInExplore
}

struct InsightSharePresentation: Equatable {
    let isPublished: Bool
    let recommendation: InsightShareRecommendation

    init(
        sharedExplorePostID: String?,
        recommendation: InsightShareRecommendation
    ) {
        isPublished = sharedExplorePostID != nil
        self.recommendation = recommendation
    }

    var headline: String {
        if isPublished {
            return "Published"
        }

        switch recommendation {
        case .askCommunity:
            return "Ask the community"
        case .communityPending:
            return "Identify request"
        case .communityResolvedNeedsPublish:
            return "Ready to publish"
        case .publishToExplore:
            return "Share with community"
        }
    }

    var actionTitle: String {
        if isPublished {
            return "View post"
        }

        switch recommendation {
        case .askCommunity:
            return "Ask for ID"
        case .communityPending:
            return "Edit request"
        case .communityResolvedNeedsPublish, .publishToExplore:
            return "Share discovery"
        }
    }

    var actionSystemImage: String {
        switch recommendation {
        case .askCommunity:
            return "person.crop.badge.magnifyingglass"
        case .communityPending:
            return "square.and.pencil"
        case .communityResolvedNeedsPublish, .publishToExplore:
            return "safari"
        }
    }

    var description: String {
        if isPublished {
            return "This discovery is visible to the community."
        }

        switch recommendation {
        case .askCommunity:
            return "Get help from other Naturebook explorers before adding this discovery to Explore observations."
        case .communityPending:
            return "This scan is public in Identify while the community reviews the ID."
        case .communityResolvedNeedsPublish:
            return "The community identified this request. Publish it to Explore when you are ready."
        case .publishToExplore:
            return "Publish this discovery so others can learn and explore."
        }
    }

    var publishConfirmationMessage: String {
        switch recommendation {
        case .communityPending:
            return Self.pendingCommunityPublishDisclaimer
        case .askCommunity:
            return "This ID has not been confirmed yet. Ask the community first if you want help verifying it before publishing."
        case .communityResolvedNeedsPublish, .publishToExplore:
            return "Publish this discovery so others can learn and explore."
        }
    }

    func primaryAction(
        canAskCommunity: Bool,
        canEditCommunityRequest: Bool
    ) -> InsightSharePendingAction {
        switch recommendation {
        case .askCommunity:
            return canAskCommunity ? .askCommunity : .composeExplorePost
        case .communityPending:
            return canEditCommunityRequest
                ? .editCommunityRequest
                : .viewCommunityRequest
        case .communityResolvedNeedsPublish, .publishToExplore:
            return .composeExplorePost
        }
    }

    static let pendingCommunityPublishDisclaimer =
        "The community is still reviewing this ID. Publish only if you are comfortable making it visible in Explore now."
}
