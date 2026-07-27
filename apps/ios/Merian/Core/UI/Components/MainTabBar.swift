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
        FloatingNavigationMenu {
            // 1. Map/Explore Network
            FloatingNavigationMenuButton(
                iconName: "safari.fill",
                title: "Explore",
                accessibilityIdentifier: "MainTabBar_Explore",
                action: {
                    HapticManager.shared.triggerSheetSpring()
                    isExploreOpen = true
                },
                showBadge: appSettings.hasUnseenExplorePost || hasUnreadExploreNotifications
            )

            // 2. Local Taxonomy Library
            FloatingNavigationMenuButton(
                iconName: "rectangle.stack.fill",
                title: "Scans",
                accessibilityIdentifier: "MainTabBar_Scans",
                action: {
                    HapticManager.shared.triggerSheetSpring()
                    isScansOpen = true
                },
                showBadge: appSettings.hasUnseenScan
            )

            // 3. User Identity Profile 
            FloatingNavigationMenuButton(
                iconName: "person.fill",
                title: "Profile",
                accessibilityIdentifier: "MainTabBar_Profile",
                action: { 
                    HapticManager.shared.triggerSheetSpring()
                    isUserProfileOpen = true 
                }
            )
        }
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
        async let fetchRecentPosts: [ExplorePost]? = {
            do {
                return try await MerianNetworkClient.shared.getExploreFeed(limit: 20)
            } catch {
                MerianLog.network.debug("Failed to fetch latest post for badge: \(error.localizedDescription, privacy: .private)")
                return nil
            }
        }()
        
        async let fetchUnreadCount: Int? = {
            await AppIconBadgeCoordinator.refreshExploreUnreadNotificationCount()
        }()
        
        let (recentPosts, unreadCount) = await (fetchRecentPosts, fetchUnreadCount)

        if let unreadCount {
            hasUnreadExploreNotifications = unreadCount > 0
        }

        guard let recentPosts else {
            appSettings.hasUnseenExplorePost = false
            return
        }

        appSettings.hasUnseenExplorePost = ExploreBadgePolicy.hasUnseenExternalPost(
            in: recentPosts,
            lastSeenSharedAt: appSettings.lastSeenExplorePostSharedAt
        )
    }
}
