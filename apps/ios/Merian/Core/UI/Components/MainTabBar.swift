import SwiftUI
import UIKit

struct MainTabBar: View {
    // MARK: - Navigation Dependencies
    @Binding var isExploreOpen: Bool
    @Binding var isScansOpen: Bool
    @Binding var isUserProfileOpen: Bool
    @Environment(AppSettings.self) private var appSettings
    @State private var hasUnreadExploreNotifications: Bool = false
    
    // MARK: - Visual Layout
    var body: some View {
        HStack(spacing: 48) {
            
            // 1. Map/Explore Network
            TabBarButton(
                iconName: "safari",
                title: "Explore",
                accessibilityIdentifier: "MainTabBar_Explore",
                action: {
                    HapticManager.shared.triggerSheetSpring()
                    appSettings.hasSeenExploreNewChip = true
                    isExploreOpen = true
                },
                showBadge: appSettings.hasUnseenExplorePost || hasUnreadExploreNotifications,
                chipText: appSettings.hasUnseenExplorePost || hasUnreadExploreNotifications || appSettings.hasSeenExploreNewChip ? nil : "NEW"
            )

            // 2. Local Taxonomy Library
            TabBarButton(
                iconName: "rectangle.stack",
                title: "Scans",
                accessibilityIdentifier: "MainTabBar_Scans",
                action: {
                    HapticManager.shared.triggerSheetSpring()
                    isScansOpen = true
                },
                showBadge: appSettings.hasUnseenScan
            )

            // 3. User Identity Profile 
            TabBarButton(
                iconName: "person",
                title: "Profile",
                accessibilityIdentifier: "MainTabBar_Profile",
                action: { 
                    HapticManager.shared.triggerSheetSpring()
                    isUserProfileOpen = true 
                }
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 32)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.16), radius: 15, x: 0, y: 8)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.5),
                            Color.white.opacity(0.1),
                            Color.white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
        .task {
            await refreshExploreBadge()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await refreshExploreBadge()
            }
        }
        .onChange(of: isExploreOpen) { _, newValue in
            if !newValue {
                Task {
                    await refreshExploreBadge()
                }
            }
        }
    }

    @MainActor
    private func refreshExploreBadge() async {
        async let fetchLatestPost: ExplorePost? = {
            do {
                return try await MerianNetworkClient.shared.getExploreFeed(limit: 1).first
            } catch {
                MerianLog.network.debug("Failed to fetch latest post for badge: \(error.localizedDescription, privacy: .private)")
                return nil
            }
        }()
        
        async let fetchUnreadCount: Int? = {
            do {
                return try await MerianNetworkClient.shared.getUnreadExploreNotificationCount()
            } catch {
                MerianLog.network.debug("Failed to fetch unread notification count for badge: \(error.localizedDescription, privacy: .private)")
                return nil
            }
        }()
        
        let (latestPost, unreadCount) = await (fetchLatestPost, fetchUnreadCount)

        if let unreadCount {
            hasUnreadExploreNotifications = unreadCount > 0
        }

        guard let latestPost else {
            appSettings.hasUnseenExplorePost = false
            return
        }

        guard let latestPostDate = latestPost.sharedAtDate else { return }
        guard !appSettings.lastSeenExplorePostSharedAt.isEmpty else { return }

        guard let lastSeenPostDate = DateUtilities.iso8601FractionalFormatter.date(from: appSettings.lastSeenExplorePostSharedAt)
            ?? DateUtilities.iso8601Formatter.date(from: appSettings.lastSeenExplorePostSharedAt) else {
            return
        }

        appSettings.hasUnseenExplorePost = latestPostDate > lastSeenPostDate
    }
}

// MARK: - Internal Component Layout Wrappers

private struct TabBarButton: View {
    // MARK: - Properties
    let iconName: String
    let title: String
    let accessibilityIdentifier: String
    let action: () -> Void
    var isDisabled: Bool = false
    var showBadge: Bool = false
    var chipText: String?

    // MARK: - Visual Layout
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .regular))
                    .frame(height: 24)
                    .overlay(alignment: .topTrailing) {
                        if showBadge {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 4, y: -2)
                        }

                        if let chipText {
                            Text(chipText)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.green)
                                )
                                .fixedSize()
                                .offset(x: 16, y: -10)
                        }
                    }
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.primary)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
