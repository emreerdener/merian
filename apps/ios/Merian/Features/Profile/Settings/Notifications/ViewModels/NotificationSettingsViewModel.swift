import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationSettingsViewModel {
    var showPermissionPrompt = false
    private(set) var authorizationStatus: UNAuthorizationStatus =
        .notDetermined
    private(set) var pendingPreference: NotificationPreference?

    private let dependencies: NotificationSettingsDependencies
    private var authorizationRefreshGeneration = 0

    init(dependencies: NotificationSettingsDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func refreshAuthorizationStatus() async {
        authorizationRefreshGeneration &+= 1
        let generation = authorizationRefreshGeneration
        let status = await dependencies.fetchAuthorizationStatus()

        guard generation == authorizationRefreshGeneration,
              !Task.isCancelled else { return }
        authorizationStatus = status
    }

    func resolvedValue(
        for requestedValue: Bool,
        preference: NotificationPreference
    ) -> Bool? {
        guard requestedValue else { return false }

        switch authorizationStatus {
        case .notDetermined:
            pendingPreference = preference
            showPermissionPrompt = true
            return nil
        case .denied, .provisional:
            dependencies.openSystemSettings()
            return nil
        default:
            return true
        }
    }

    func completePermissionPrompt(granted: Bool) -> NotificationPreference? {
        defer { pendingPreference = nil }
        return granted ? pendingPreference : nil
    }

    func clearPendingPreference() {
        pendingPreference = nil
    }

    func syncPreferenceChange(_ preference: NotificationPreference) async {
        guard let reason = preference.remoteRegistrationReason else { return }
        await dependencies.syncRemoteRegistration(reason)
    }

    func syncEnabledAfterAuthorization(
        _ preference: NotificationPreference
    ) async {
        guard let reason = preference.enabledAfterAuthorizationReason else {
            return
        }
        await dependencies.syncRemoteRegistration(reason)
    }

    func syncAllDisabledIfNeeded(_ shouldSync: Bool) async {
        guard shouldSync else { return }
        await dependencies.syncRemoteRegistration(
            "all_notification_settings_disabled"
        )
    }
}
