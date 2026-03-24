import SwiftUI

/// Abstracted detail view establishing a parent/child routing flow specifically isolating Notification configuration.
/// Ensures the primary Profile `Preferences` list does not organically expand into an unscrollable behemoth.
struct NotificationSettingsView: View {
    @AppStorage(UserDefaultsKeys.isPushNotificationsEnabled) private var isPushNotificationsEnabled: Bool = true
    @AppStorage("isAchievementNotificationsEnabled") private var isAchievementNotificationsEnabled: Bool = true
    
    var body: some View {
        List {
            Section {
                SettingsToggleRow(
                    title: "Discovery alerts",
                    description: "Receive a notification whenever the AI successfully identifies a species.",
                    isOn: $isPushNotificationsEnabled
                )
                .onChange(of: isPushNotificationsEnabled) { _, newValue in
                    if newValue {
                        AppDIContainer.shared.pushNotificationManager.requestAuthorization()
                    }
                }
            } header: {
                Text("Inference events")
            } footer: {
                Text("Turning this off suppresses active OS interruptions but keeps results securely banked in your local collections natively.")
            }
            
            Section {
                SettingsToggleRow(
                    title: "Achievements & milestones",
                    description: "Get notified when you unlock new ecological awards.",
                    isOn: $isAchievementNotificationsEnabled
                )
                .onChange(of: isAchievementNotificationsEnabled) { _, newValue in
                    if newValue {
                        AppDIContainer.shared.pushNotificationManager.requestAuthorization()
                    }
                }
            } header: {
                Text("Gamification")
            }
            
            // Note: As the roadmap expands, Future Notification parameters (e.g. Daily Reminders, Streak Warnings, Community Events)
            // will explicitly dynamically drop down into new Sections inside this View boundary identically mapping the UI abstraction.
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
