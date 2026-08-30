import SwiftUI

/// A focused child route for local and remote notification preferences.
struct NotificationSettingsView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.scenePhase) private var scenePhase

    @State private var viewModel = NotificationSettingsViewModel()

    var body: some View {
        @Bindable var appSettings = appSettings
        @Bindable var viewModel = viewModel

        List {
            Section {
                SettingsToggleRow(
                    title: "Discovery alerts",
                    description: "Receive a notification whenever the AI successfully identifies a species.",
                    isOn: binding(
                        for: $appSettings.isPushNotificationsEnabled,
                        preference: .discovery
                    )
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
                    isOn: binding(
                        for: $appSettings.isAchievementNotificationsEnabled,
                        preference: .achievements
                    )
                )
            } header: {
                Text("Gamification")
            }

            Section {
                SettingsToggleRow(
                    title: "Explore activity",
                    description: "Receive a push when someone likes or comments on one of your Explore posts.",
                    isOn: binding(
                        for: $appSettings.isExploreNotificationsEnabled,
                        preference: .explore
                    )
                )
                SettingsToggleRow(
                    title: "Comment mentions",
                    description: "Receive a push when someone mentions you in an Explore comment.",
                    isOn: binding(
                        for: $appSettings
                            .isExploreCommentMentionNotificationsEnabled,
                        preference: .exploreCommentMentions
                    )
                )
                SettingsToggleRow(
                    title: "Community identifications",
                    description: """
                    Receive pushes when people identify your requests, consensus resolves, \
                    or your ID helps resolve a request.
                    """,
                    isOn: binding(
                        for: $appSettings
                            .isCommunityIdentificationNotificationsEnabled,
                        preference: .communityIdentifications
                    )
                )
            } header: {
                Text("Explore")
            } footer: {
                Text("These controls affect remote Explore and Community pushes only. The in-app notifications feed remains available inside Explore.")
            }

            if hasAnyNotificationEnabled {
                Section {
                    Button(role: .destructive) {
                        turnOffAllNotifications()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                Image(systemName: "bell.slash.fill")
                                    .foregroundStyle(.red)
                                    .font(.system(size: 17, weight: .medium))
                                    .frame(width: 24)
                                Text("Turn off all notifications")
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            Text("Stop Naturebook from sending notification alerts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 36)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Your in-app activity and Explore notifications will still be available when you open Naturebook.")
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(
            isPresented: $viewModel.showPermissionPrompt,
            onDismiss: {
                viewModel.clearPendingPreference()
                Task { await viewModel.refreshAuthorizationStatus() }
            }
        ) {
            PostIdentificationNotificationSheetView { granted in
                if let preference = viewModel.completePermissionPrompt(
                    granted: granted
                ) {
                    applyEnabledPreference(preference)
                    Task {
                        await viewModel.syncEnabledAfterAuthorization(
                            preference
                        )
                    }
                }
                Task { await viewModel.refreshAuthorizationStatus() }
                viewModel.showPermissionPrompt = false
            }
            .presentationDetents([.height(320)])
        }
        .task {
            await viewModel.refreshAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.refreshAuthorizationStatus() }
        }
    }

    private var hasAnyNotificationEnabled: Bool {
        appSettings.isPushNotificationsEnabled ||
            appSettings.isAchievementNotificationsEnabled ||
            appSettings.isExploreNotificationsEnabled ||
            appSettings.isExploreCommentMentionNotificationsEnabled ||
            appSettings.isCommunityIdentificationNotificationsEnabled
    }

    private func turnOffAllNotifications() {
        let shouldSyncRemotePushRegistration =
            appSettings.isExploreNotificationsEnabled ||
            appSettings.isExploreCommentMentionNotificationsEnabled ||
            appSettings.isCommunityIdentificationNotificationsEnabled

        appSettings.isPushNotificationsEnabled = false
        appSettings.isAchievementNotificationsEnabled = false
        appSettings.isExploreNotificationsEnabled = false
        appSettings.isExploreCommentMentionNotificationsEnabled = false
        appSettings.isCommunityIdentificationNotificationsEnabled = false
        viewModel.clearPendingPreference()

        Task {
            await viewModel.syncAllDisabledIfNeeded(
                shouldSyncRemotePushRegistration
            )
        }
    }

    private func binding(
        for appStorage: Binding<Bool>,
        preference: NotificationPreference
    ) -> Binding<Bool> {
        Binding(
            get: { appStorage.wrappedValue },
            set: { newValue in
                guard let resolvedValue = viewModel.resolvedValue(
                    for: newValue,
                    preference: preference
                ) else { return }

                appStorage.wrappedValue = resolvedValue
                Task {
                    await viewModel.syncPreferenceChange(preference)
                }
            }
        )
    }

    private func applyEnabledPreference(
        _ preference: NotificationPreference
    ) {
        switch preference {
        case .discovery:
            appSettings.isPushNotificationsEnabled = true
        case .achievements:
            appSettings.isAchievementNotificationsEnabled = true
        case .explore:
            appSettings.isExploreNotificationsEnabled = true
        case .exploreCommentMentions:
            appSettings.isExploreCommentMentionNotificationsEnabled = true
        case .communityIdentifications:
            appSettings.isCommunityIdentificationNotificationsEnabled = true
        }
    }
}
