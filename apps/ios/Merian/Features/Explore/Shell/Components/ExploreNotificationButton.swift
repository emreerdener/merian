import SwiftUI

struct ExploreNotificationButton: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 24, height: 24)
            }

            if unreadCount > 0 {
                Circle()
                    .fill(Color(uiColor: .systemRed))
                    .frame(width: 11, height: 11)
                    .overlay(
                        Circle()
                            .stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        unreadCount == 0
            ? "Notifications"
            : "Notifications, \(unreadCount) unread"
    }
}
