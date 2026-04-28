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
                } else {
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
        }
    }

    private var iconForegroundColor: Color {
        switch notification.type {
        case .likeAggregated:
            return .red
        case .comment:
            return .blue
        }
    }

    private var iconBackgroundColor: Color {
        switch notification.type {
        case .likeAggregated:
            return Color.red.opacity(0.12)
        case .comment:
            return Color.blue.opacity(0.12)
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
        case .likeAggregated:
            return likeSummaryText()
        }
    }

    private var secondaryText: String? {
        switch notification.type {
        case .comment:
            return trimmed(notification.commentBody)
        case .likeAggregated:
            return nil
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

    private func trimmed(_ rawText: String?) -> String? {
        guard let trimmedText = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedText.isEmpty else {
            return nil
        }
        return trimmedText
    }
}
