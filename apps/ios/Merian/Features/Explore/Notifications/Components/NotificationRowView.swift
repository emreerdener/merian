import SwiftUI

struct NotificationRowView: View {
    let notification: ExploreNotification
    let isRecentlyRead: Bool
    let isLoading: Bool
    let action: () -> Void

    private let presentation: ExploreNotificationRowPresentation

    init(
        notification: ExploreNotification,
        isRecentlyRead: Bool,
        isLoading: Bool,
        action: @escaping () -> Void
    ) {
        self.notification = notification
        self.isRecentlyRead = isRecentlyRead
        self.isLoading = isLoading
        self.action = action
        presentation = ExploreNotificationRowPresentation(notification: notification)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                iconBadge

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(presentation.primaryText)
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

                    if let secondaryText = presentation.secondaryText,
                       !secondaryText.isEmpty {
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
                } else if presentation.showsDisclosureIndicator {
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
                .fill(presentation.accent.color.opacity(presentation.accent.backgroundOpacity))
                .frame(width: 42, height: 42)

            Image(systemName: presentation.systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(presentation.accent.color)
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
}

private extension ExploreNotificationRowPresentation.Accent {
    var color: Color {
        switch self {
        case .red:
            .red
        case .blue:
            .blue
        case .purple:
            .purple
        case .mint:
            .mint
        case .orange:
            .orange
        case .green:
            .green
        case .teal:
            .teal
        case .indigo:
            .indigo
        }
    }

    var backgroundOpacity: Double {
        switch self {
        case .red, .blue, .purple, .green, .indigo:
            0.12
        case .mint, .orange, .teal:
            0.14
        }
    }
}
