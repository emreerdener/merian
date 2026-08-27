import Foundation

struct ExploreNotificationRowPresentation: Equatable {
    enum Accent: Equatable {
        case red
        case blue
        case purple
        case mint
        case orange
        case green
        case teal
        case indigo
    }

    let systemImage: String
    let accent: Accent
    let primaryText: String
    let secondaryText: String?
    let showsDisclosureIndicator: Bool

    init(notification: ExploreNotification) {
        systemImage = Self.systemImage(for: notification.type)
        accent = Self.accent(for: notification.type)
        primaryText = Self.primaryText(for: notification)
        secondaryText = Self.secondaryText(for: notification)
        showsDisclosureIndicator = notification.postId != nil ||
            notification.communityRequestId != nil ||
            notification.fieldTripPublicationId != nil
    }

    private static func systemImage(for type: ExploreNotificationType) -> String {
        switch type {
        case .likeAggregated:
            "heart.fill"
        case .comment:
            "bubble.left.fill"
        case .commentReply:
            "arrowshape.turn.up.left.fill"
        case .commentMention:
            "at"
        case .commentReaction:
            "face.smiling.fill"
        case .follow:
            "person.crop.circle.badge.plus"
        case .communityIdentificationAdded:
            "person.2.wave.2.fill"
        case .communityRequestResolved:
            "checkmark.seal.fill"
        case .communityIdentificationHelped:
            "sparkles"
        case .mediaMissing:
            "exclamationmark.triangle.fill"
        case .mediaRestored:
            "checkmark.icloud.fill"
        case .fieldTripComment:
            "map.fill"
        case .fieldTripReply:
            "arrowshape.turn.up.left.fill"
        case .fieldTripFollowedPublication:
            "map.circle.fill"
        }
    }

    private static func accent(for type: ExploreNotificationType) -> Accent {
        switch type {
        case .likeAggregated:
            .red
        case .comment, .fieldTripComment:
            .blue
        case .commentReply, .fieldTripReply:
            .purple
        case .commentMention:
            .mint
        case .commentReaction, .mediaMissing:
            .orange
        case .follow, .communityRequestResolved, .mediaRestored,
             .fieldTripFollowedPublication:
            .green
        case .communityIdentificationAdded:
            .teal
        case .communityIdentificationHelped:
            .indigo
        }
    }

    private static func primaryText(for notification: ExploreNotification) -> String {
        switch notification.type {
        case .comment:
            return "\(actorName(in: notification)) commented on your post."
        case .commentReply:
            let actorName = actorName(in: notification)
            if notification.isReplyToViewerComment == true {
                return "\(actorName) replied to your comment."
            }
            return "\(actorName) replied on your post."
        case .commentMention:
            return "\(actorName(in: notification)) mentioned you in a comment."
        case .likeAggregated:
            return likeSummaryText(notification)
        case .commentReaction:
            return commentReactionSummaryText(notification)
        case .follow:
            return "\(actorName(in: notification)) followed you."
        case .communityIdentificationAdded:
            return communityIdentificationSummaryText(notification)
        case .communityRequestResolved:
            return "Your Community request was identified."
        case .communityIdentificationHelped:
            return "Your ID helped resolve a request."
        case .mediaMissing:
            return "Media is unavailable on one of your Explore posts."
        case .mediaRestored:
            return "Your Explore post is back."
        case .fieldTripComment:
            return "\(actorName(in: notification)) commented on your outing."
        case .fieldTripReply:
            let actorName = actorName(in: notification)
            if notification.isReplyToViewerComment == true {
                return "\(actorName) replied to your outing comment."
            }
            return "\(actorName) replied on an outing."
        case .fieldTripFollowedPublication:
            return "\(actorName(in: notification)) published an outing."
        }
    }

    private static func secondaryText(for notification: ExploreNotification) -> String? {
        switch notification.type {
        case .comment, .commentReply, .commentMention, .commentReaction,
             .fieldTripComment, .fieldTripReply:
            return trimmed(notification.commentBody)
        case .likeAggregated, .follow:
            return nil
        case .communityIdentificationAdded, .communityRequestResolved,
             .communityIdentificationHelped:
            return trimmed(notification.communityRequestDisplayName)
                ?? trimmed(notification.communityTaxonCommonName)
                ?? trimmed(notification.communityTaxonScientificName)
        case .mediaMissing:
            return "The post and engagement are safe while we try to restore its media."
        case .mediaRestored:
            return "Its media was restored automatically."
        case .fieldTripFollowedPublication:
            return "From someone you follow."
        }
    }

    private static func likeSummaryText(_ notification: ExploreNotification) -> String {
        let actorNames = notification.recentActorNames.compactMap(trimmed)
        let othersCount = max(notification.actionCount - actorNames.count, 0)

        switch actorNames.count {
        case 0:
            if notification.actionCount == 1 {
                return "Someone liked your post."
            }
            return "\(notification.actionCount) people liked your post."
        case 1:
            if othersCount == 0 {
                return "\(actorNames[0]) liked your post."
            }
            return "\(actorNames[0]) and \(othersCount) \(othersCount == 1 ? "other" : "others") liked your post."
        case 2:
            if othersCount == 0 {
                return "\(actorNames[0]) and \(actorNames[1]) liked your post."
            }
            return "\(actorNames[0]), \(actorNames[1]), and \(othersCount) \(othersCount == 1 ? "other" : "others") liked your post."
        default:
            if othersCount == 0 {
                return "\(actorNames[0]), \(actorNames[1]), and \(actorNames[2]) liked your post."
            }
            return "\(actorNames[0]), \(actorNames[1]), \(actorNames[2]), and \(othersCount) \(othersCount == 1 ? "other" : "others") liked your post."
        }
    }

    private static func commentReactionSummaryText(
        _ notification: ExploreNotification
    ) -> String {
        let actorNames = notification.recentActorNames.compactMap(trimmed)
        let othersCount = max(notification.actionCount - actorNames.count, 0)
        let reactionText = trimmed(notification.reactionEmoji)
            .map { "reacted \($0) to your comment." }
            ?? "reacted to your comment."

        switch actorNames.count {
        case 0:
            if notification.actionCount == 1 {
                return "Someone \(reactionText)"
            }
            return "\(notification.actionCount) people \(reactionText)"
        case 1:
            if othersCount == 0 {
                return "\(actorNames[0]) \(reactionText)"
            }
            return "\(actorNames[0]) and \(othersCount) \(othersCount == 1 ? "other" : "others") \(reactionText)"
        case 2:
            if othersCount == 0 {
                return "\(actorNames[0]) and \(actorNames[1]) \(reactionText)"
            }
            return "\(actorNames[0]), \(actorNames[1]), and \(othersCount) \(othersCount == 1 ? "other" : "others") \(reactionText)"
        default:
            if othersCount == 0 {
                return "\(actorNames[0]), \(actorNames[1]), and \(actorNames[2]) \(reactionText)"
            }
            return "\(actorNames[0]), \(actorNames[1]), \(actorNames[2]), and \(othersCount) \(othersCount == 1 ? "other" : "others") \(reactionText)"
        }
    }

    private static func communityIdentificationSummaryText(
        _ notification: ExploreNotification
    ) -> String {
        let actorNames = notification.recentActorNames.compactMap(trimmed)
        let othersCount = max(notification.actionCount - actorNames.count, 0)

        switch actorNames.count {
        case 0:
            if notification.actionCount == 1 {
                return "Someone suggested an ID for your request."
            }
            return "\(notification.actionCount) people suggested IDs for your request."
        case 1:
            if othersCount == 0 {
                return "\(actorNames[0]) suggested an ID for your request."
            }
            return """
            \(actorNames[0]) and \(othersCount) \
            \(othersCount == 1 ? "other" : "others") suggested IDs for your request.
            """
        case 2:
            if othersCount == 0 {
                return "\(actorNames[0]) and \(actorNames[1]) suggested IDs for your request."
            }
            return """
            \(actorNames[0]), \(actorNames[1]), and \(othersCount) \
            \(othersCount == 1 ? "other" : "others") suggested IDs for your request.
            """
        default:
            if othersCount == 0 {
                return "\(actorNames[0]), \(actorNames[1]), and \(actorNames[2]) suggested IDs for your request."
            }
            return """
            \(actorNames[0]), \(actorNames[1]), \(actorNames[2]), and \(othersCount) \
            \(othersCount == 1 ? "other" : "others") suggested IDs for your request.
            """
        }
    }

    private static func actorName(in notification: ExploreNotification) -> String {
        trimmed(notification.triggeringUserName) ?? "Someone"
    }

    private static func trimmed(_ rawText: String?) -> String? {
        guard let trimmedText = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedText.isEmpty else {
            return nil
        }
        return trimmedText
    }
}
