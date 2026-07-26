import SwiftUI

struct NotificationRowView: View {
    let notification: ExploreNotification
    let isRecentlyRead: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                iconBadge

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(primaryText)
                            .font(.subheadline)
                            .fontWeight(isRecentlyRead ? .semibold : .medium)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            if isRecentlyRead {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 7, height: 7)
                            }

                            Text(relativeTimestamp)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let secondaryText, !secondaryText.isEmpty {
                        Text(secondaryText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                }

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.top, 2)
                } else if notification.postId != nil || notification.communityRequestId != nil || notification.fieldTripPublicationId != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(iconBackgroundColor)
                .frame(width: 42, height: 42)

            Image(systemName: iconName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(iconForegroundColor)
        }
    }

    private var iconName: String {
        switch notification.type {
        case .likeAggregated:
            return "heart.fill"
        case .comment:
            return "bubble.left.fill"
        case .commentReply:
            return "arrowshape.turn.up.left.fill"
        case .commentMention:
            return "at"
        case .commentReaction:
            return "face.smiling.fill"
        case .follow:
            return "person.crop.circle.badge.plus"
        case .communityIdentificationAdded:
            return "person.2.wave.2.fill"
        case .communityRequestResolved:
            return "checkmark.seal.fill"
        case .communityIdentificationHelped:
            return "sparkles"
        case .mediaMissing:
            return "exclamationmark.triangle.fill"
        case .mediaRestored:
            return "checkmark.icloud.fill"
        case .fieldTripComment:
            return "map.fill"
        case .fieldTripReply:
            return "arrowshape.turn.up.left.fill"
        case .fieldTripFollowedPublication:
            return "map.circle.fill"
        }
    }

    private var iconForegroundColor: Color {
        switch notification.type {
        case .likeAggregated:
            return .red
        case .comment:
            return .blue
        case .commentReply:
            return .purple
        case .commentMention:
            return .mint
        case .commentReaction:
            return .orange
        case .follow:
            return .green
        case .communityIdentificationAdded:
            return .teal
        case .communityRequestResolved:
            return .green
        case .communityIdentificationHelped:
            return .indigo
        case .mediaMissing:
            return .orange
        case .mediaRestored:
            return .green
        case .fieldTripComment:
            return .blue
        case .fieldTripReply:
            return .purple
        case .fieldTripFollowedPublication:
            return .green
        }
    }

    private var iconBackgroundColor: Color {
        switch notification.type {
        case .likeAggregated:
            return Color.red.opacity(0.12)
        case .comment:
            return Color.blue.opacity(0.12)
        case .commentReply:
            return Color.purple.opacity(0.12)
        case .commentMention:
            return Color.mint.opacity(0.14)
        case .commentReaction:
            return Color.orange.opacity(0.14)
        case .follow:
            return Color.green.opacity(0.12)
        case .communityIdentificationAdded:
            return Color.teal.opacity(0.14)
        case .communityRequestResolved:
            return Color.green.opacity(0.12)
        case .communityIdentificationHelped:
            return Color.indigo.opacity(0.12)
        case .mediaMissing:
            return Color.orange.opacity(0.14)
        case .mediaRestored:
            return Color.green.opacity(0.12)
        case .fieldTripComment:
            return Color.blue.opacity(0.12)
        case .fieldTripReply:
            return Color.purple.opacity(0.12)
        case .fieldTripFollowedPublication:
            return Color.green.opacity(0.12)
        }
    }

    private var backgroundFill: some ShapeStyle {
        if isRecentlyRead {
            return AnyShapeStyle(Color.accentColor.opacity(0.08))
        }
        return AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
    }

    private var borderColor: Color {
        if isRecentlyRead {
            return Color.accentColor.opacity(0.18)
        }
        return Color.primary.opacity(0.06)
    }

    private var primaryText: String {
        switch notification.type {
        case .comment:
            let actorName = trimmed(notification.triggeringUserName) ?? "Someone"
            return "\(actorName) commented on your post."
        case .commentReply:
            let actorName = trimmed(notification.triggeringUserName) ?? "Someone"
            if notification.isReplyToViewerComment == true {
                return "\(actorName) replied to your comment."
            }
            return "\(actorName) replied on your post."
        case .commentMention:
            let actorName = trimmed(notification.triggeringUserName) ?? "Someone"
            return "\(actorName) mentioned you in a comment."
        case .likeAggregated:
            return likeSummaryText()
        case .commentReaction:
            return commentReactionSummaryText()
        case .follow:
            let actorName = trimmed(notification.triggeringUserName) ?? "Someone"
            return "\(actorName) followed you."
        case .communityIdentificationAdded:
            return communityIdentificationSummaryText()
        case .communityRequestResolved:
            return "Your Community request was identified."
        case .communityIdentificationHelped:
            return "Your ID helped resolve a request."
        case .mediaMissing:
            return "Media is unavailable on one of your Explore posts."
        case .mediaRestored:
            return "Your Explore post is back."
        case .fieldTripComment:
            let actorName = trimmed(notification.triggeringUserName) ?? "Someone"
            return "\(actorName) commented on your outing."
        case .fieldTripReply:
            let actorName = trimmed(notification.triggeringUserName) ?? "Someone"
            if notification.isReplyToViewerComment == true {
                return "\(actorName) replied to your outing comment."
            }
            return "\(actorName) replied on an outing."
        case .fieldTripFollowedPublication:
            let actorName = trimmed(notification.triggeringUserName) ?? "Someone"
            return "\(actorName) published an outing."
        }
    }

    private var secondaryText: String? {
        switch notification.type {
        case .comment, .commentReply, .commentMention:
            return trimmed(notification.commentBody)
        case .likeAggregated:
            return nil
        case .commentReaction:
            return trimmed(notification.commentBody)
        case .follow:
            return nil
        case .communityIdentificationAdded, .communityRequestResolved, .communityIdentificationHelped:
            return communityDisplayName()
        case .mediaMissing:
            return "The post and engagement are safe while we try to restore its media."
        case .mediaRestored:
            return "Its media was restored automatically."
        case .fieldTripComment, .fieldTripReply:
            return trimmed(notification.commentBody)
        case .fieldTripFollowedPublication:
            return "From someone you follow."
        }
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        if let updatedAtDate = notification.updatedAtDate {
            return formatter.localizedString(for: updatedAtDate, relativeTo: Date())
        }
        if let createdAtDate = notification.createdAtDate {
            return formatter.localizedString(for: createdAtDate, relativeTo: Date())
        }
        return ""
    }

    private func likeSummaryText() -> String {
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

    private func commentReactionSummaryText() -> String {
        let actorNames = notification.recentActorNames.compactMap(trimmed)
        let othersCount = max(notification.actionCount - actorNames.count, 0)
        let emoji = trimmed(notification.reactionEmoji)
        let reactionText = emoji.map { "reacted \($0) to your comment." } ?? "reacted to your comment."

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

    private func communityIdentificationSummaryText() -> String {
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

    private func communityDisplayName() -> String? {
        trimmed(notification.communityRequestDisplayName)
            ?? trimmed(notification.communityTaxonCommonName)
            ?? trimmed(notification.communityTaxonScientificName)
    }

    private func trimmed(_ rawText: String?) -> String? {
        guard let trimmedText = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedText.isEmpty else {
            return nil
        }
        return trimmedText
    }
}
