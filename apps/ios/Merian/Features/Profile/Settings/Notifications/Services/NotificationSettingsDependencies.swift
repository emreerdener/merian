import UIKit
import UserNotifications

@MainActor
struct NotificationSettingsDependencies {
    let fetchAuthorizationStatus: @MainActor () async
        -> UNAuthorizationStatus
    let openSystemSettings: @MainActor () -> Void
    let syncRemoteRegistration: @MainActor (_ reason: String) async -> Void

    static var live: Self {
        Self(
            fetchAuthorizationStatus: {
                await SystemNotificationCenterService()
                    .authorizationStatus()
            },
            openSystemSettings: {
                guard let url = URL(
                    string: UIApplication.openSettingsURLString
                ) else { return }
                UIApplication.shared.open(url)
            },
            syncRemoteRegistration: { reason in
                await AppDIContainer.shared.pushNotificationManager
                    .syncRemotePushRegistrationIfPossible(reason: reason)
            }
        )
    }
}
