import SwiftUI
import UserNotifications

/// Abstracted detail view establishing a parent/child routing flow specifically isolating Notification configuration.
/// Ensures the primary Profile `Preferences` list does not organically expand into an unscrollable behemoth.
struct NotificationSettingsView: View {
    @AppStorage(UserDefaultsKeys.isPushNotificationsEnabled) private var isPushNotificationsEnabled: Bool = false
    @AppStorage("isAchievementNotificationsEnabled") private var isAchievementNotificationsEnabled: Bool = false
    
    @State private var showPermissionPrompt = false
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    var body: some View {
        List {
            Section {
                SettingsToggleRow(
                    title: "Discovery alerts",
                    description: "Receive a notification whenever the AI successfully identifies a species.",
                    isOn: binding(for: $isPushNotificationsEnabled)
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
                    isOn: binding(for: $isAchievementNotificationsEnabled)
                )
            } header: {
                Text("Gamification")
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPermissionPrompt) {
            PostIdentificationNotificationSheetView {
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
    
    private func binding(for appStorage: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { appStorage.wrappedValue },
            set: { newValue in
                if newValue {
                    if authorizationStatus == .notDetermined {
                        showPermissionPrompt = true
                    } else if authorizationStatus == .denied || authorizationStatus == .provisional {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        appStorage.wrappedValue = true
                        AppDIContainer.shared.pushNotificationManager.requestAuthorization()
                    }
                } else {
                    appStorage.wrappedValue = false
                }
            }
        )
    }
}
