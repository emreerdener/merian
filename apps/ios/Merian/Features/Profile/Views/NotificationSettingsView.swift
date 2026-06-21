import SwiftUI
import UserNotifications

/// Abstracted detail view establishing a parent/child routing flow specifically isolating Notification configuration.
/// Ensures the primary Profile `Preferences` list does not organically expand into an unscrollable behemoth.
struct NotificationSettingsView: View {
    private enum PendingNotificationToggle {
        case discovery
        case achievements
        case explore
        case exploreCommentMentions
        case communityIdentifications
    }

    @Environment(AppSettings.self) private var appSettings
    
    @State private var showPermissionPrompt = false
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingPermissionToggle: PendingNotificationToggle?
    
    var body: some View {
        @Bindable var appSettings = appSettings

        List {
            Section {
                SettingsToggleRow(
                    title: "Discovery alerts",
                    description: "Receive a notification whenever the AI successfully identifies a species.",
                    isOn: binding(for: $appSettings.isPushNotificationsEnabled, target: .discovery)
                )
            } header: {
                Text("Inference events")
            } footer: {
                Text("Turning this off suppresses active OS interruptions but keeps results securely banked in your local collections natively.")
            }
            
            Section {
                SettingsToggleRow(
                    title: "Achievements & milestones",
                    description: "Get notified when you unlock new ecological awards.",
                    isOn: binding(for: $appSettings.isAchievementNotificationsEnabled, target: .achievements)
                )
            } header: {
                Text("Gamification")
            }

            Section {
                SettingsToggleRow(
                    title: "Explore activity",
                    description: "Receive a push when someone likes or comments on one of your Explore posts.",
                    isOn: binding(for: $appSettings.isExploreNotificationsEnabled, target: .explore) {
                        Task { @MainActor in
                            await AppDIContainer.shared.pushNotificationManager.syncRemotePushRegistrationIfPossible(
                                reason: "explore_setting_changed"
                            )
                        }
                    }
                )
                SettingsToggleRow(
                    title: "Comment mentions",
                    description: "Receive a push when someone mentions you in an Explore comment.",
                    isOn: binding(
                        for: $appSettings.isExploreCommentMentionNotificationsEnabled,
                        target: .exploreCommentMentions
                    ) {
                        Task { @MainActor in
                            await AppDIContainer.shared.pushNotificationManager.syncRemotePushRegistrationIfPossible(
                                reason: "explore_comment_mentions_setting_changed"
                            )
                        }
                    }
                )
                SettingsToggleRow(
                    title: "Community identifications",
                    description: """
                    Receive pushes when people identify your requests, consensus resolves, \
                    or your ID helps resolve a request.
                    """,
                    isOn: binding(
                        for: $appSettings.isCommunityIdentificationNotificationsEnabled,
                        target: .communityIdentifications
                    ) {
                        Task { @MainActor in
                            await AppDIContainer.shared.pushNotificationManager.syncRemotePushRegistrationIfPossible(
                                reason: "community_identifications_setting_changed"
                            )
                        }
                    }
                )
            } header: {
                Text("Explore")
            } footer: {
                Text("These controls affect remote Explore and Community pushes only. The in-app notifications feed remains available inside Explore.")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPermissionPrompt, onDismiss: {
            pendingPermissionToggle = nil
            fetchStatus()
        }) {
            PostIdentificationNotificationSheetView { granted in
                if granted {
                    applyPendingPermissionToggle()
                } else {
                    pendingPermissionToggle = nil
                }
                fetchStatus()
                showPermissionPrompt = false
            }
            .presentationDetents([.height(320)])
        }
        .onAppear(perform: fetchStatus)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            fetchStatus()
        }
    }
    
    private func fetchStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                authorizationStatus = settings.authorizationStatus
            }
        }
    }
    
    private func binding(
        for appStorage: Binding<Bool>,
        target: PendingNotificationToggle,
        onCommit: (() -> Void)? = nil
    ) -> Binding<Bool> {
        Binding(
            get: { appStorage.wrappedValue },
            set: { newValue in
                if newValue {
                    if authorizationStatus == .notDetermined {
                        pendingPermissionToggle = target
                        showPermissionPrompt = true
                    } else if authorizationStatus == .denied || authorizationStatus == .provisional {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        appStorage.wrappedValue = true
                        onCommit?()
                    }
                } else {
                    appStorage.wrappedValue = false
                    onCommit?()
                }
            }
        )
    }

    private func applyPendingPermissionToggle() {
        guard let pendingPermissionToggle else { return }

        switch pendingPermissionToggle {
        case .discovery:
            appSettings.isPushNotificationsEnabled = true
        case .achievements:
            appSettings.isAchievementNotificationsEnabled = true
        case .explore:
            appSettings.isExploreNotificationsEnabled = true
            Task { @MainActor in
                await AppDIContainer.shared.pushNotificationManager.syncRemotePushRegistrationIfPossible(
                    reason: "explore_setting_enabled_after_authorization"
                )
            }
        case .exploreCommentMentions:
            appSettings.isExploreCommentMentionNotificationsEnabled = true
            Task { @MainActor in
                await AppDIContainer.shared.pushNotificationManager.syncRemotePushRegistrationIfPossible(
                    reason: "explore_comment_mentions_setting_enabled_after_authorization"
                )
            }
        case .communityIdentifications:
            appSettings.isCommunityIdentificationNotificationsEnabled = true
            Task { @MainActor in
                await AppDIContainer.shared.pushNotificationManager.syncRemotePushRegistrationIfPossible(
                    reason: "community_identifications_setting_enabled_after_authorization"
                )
            }
        }

        self.pendingPermissionToggle = nil
    }
}
