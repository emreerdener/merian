import SwiftUI

struct MainTabBar: View {
    // MARK: - Navigation Dependencies

    @Binding var isExploreOpen: Bool
    @Binding var isScansOpen: Bool
    @Binding var isUserProfileOpen: Bool

    @Environment(AppSettings.self) private var appSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigationViewModel: CaptureNavigationViewModel
    @State private var badgeRefreshID = UUID()

    init(
        isExploreOpen: Binding<Bool>,
        isScansOpen: Binding<Bool>,
        isUserProfileOpen: Binding<Bool>,
        dependencies: CaptureNavigationDependencies
    ) {
        self._isExploreOpen = isExploreOpen
        self._isScansOpen = isScansOpen
        self._isUserProfileOpen = isUserProfileOpen
        self._navigationViewModel = State(
            initialValue: CaptureNavigationViewModel(
                dependencies: dependencies
            )
        )
    }

    // MARK: - Visual Layout

    var body: some View {
        FloatingNavigationMenu {
            FloatingNavigationMenuButton(
                iconName: "safari.fill",
                title: "Explore",
                accessibilityIdentifier: "MainTabBar_Explore",
                action: {
                    navigationViewModel.performRouteFeedback()
                    isExploreOpen = true
                },
                showBadge: appSettings.hasUnseenExplorePost
                    || navigationViewModel.hasUnreadExploreNotifications
            )

            FloatingNavigationMenuButton(
                iconName: "rectangle.stack.fill",
                title: "Scans",
                accessibilityIdentifier: "MainTabBar_Scans",
                action: {
                    navigationViewModel.performRouteFeedback()
                    isScansOpen = true
                },
                showBadge: appSettings.hasUnseenScan
            )

            FloatingNavigationMenuButton(
                iconName: "person.fill",
                title: "Profile",
                accessibilityIdentifier: "MainTabBar_Profile",
                action: {
                    navigationViewModel.performRouteFeedback()
                    isUserProfileOpen = true
                }
            )
        }
        .task(id: badgeRefreshID) {
            await navigationViewModel.refreshBadges(
                lastSeenSharedAt: appSettings.lastSeenExplorePostSharedAt
            )
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            badgeRefreshID = UUID()
        }
        .onChange(of: isExploreOpen) { _, isOpen in
            guard !isOpen else { return }
            badgeRefreshID = UUID()
        }
        .onDisappear {
            navigationViewModel.invalidateRefresh()
        }
    }
}
