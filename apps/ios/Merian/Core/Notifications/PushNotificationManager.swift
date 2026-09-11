import Foundation
import Observation
import os
import UserNotifications

/// Stable application facade for system-notification permission, APNs
/// registration, local scheduling, foreground presentation, and typed routing.
@MainActor
@Observable
final class PushNotificationManager: NSObject,
    UNUserNotificationCenterDelegate {
    struct Dependencies {
        let notificationCenter: SystemNotificationCenterService
        let preferences: PushNotificationPreferencesStore
        let registrationCoordinator: PushRegistrationCoordinator
        let registrationContext: PushRegistrationContextService
        let pushEnvironment: String
        let makeIdentifier: @MainActor () -> String

        @MainActor static var live: Self {
            #if DEBUG
            let environment = "sandbox"
            #else
            let environment = "production"
            #endif
            return Self(
                notificationCenter: SystemNotificationCenterService(),
                preferences: PushNotificationPreferencesStore(),
                registrationCoordinator: PushRegistrationCoordinator(),
                registrationContext: .live,
                pushEnvironment: environment,
                makeIdentifier: { UUID().uuidString }
            )
        }
    }

    static let shared = PushNotificationManager()

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private let requestRoute:
        @MainActor @Sendable (AppRoute, AppRouteSource) -> Void
    @ObservationIgnored private var notifiedScanIDs: Set<String> = []
    @ObservationIgnored private var pendingInferenceScanIDs: Set<String> = []
    @ObservationIgnored private var permissionStatusTask: Task<Void, Never>?
    @ObservationIgnored private var permissionStatusGeneration: UInt = 0
    @ObservationIgnored private var authorizationRequestGeneration: UInt = 0
    @ObservationIgnored private var activeAuthorizationRequestGeneration: UInt?

    private override init() {
        dependencies = .live
        requestRoute = { route, source in
            AppDIContainer.shared.appRouteCoordinator.request(
                route,
                source: source
            )
        }
        super.init()
    }

    init(
        requestRoute: @escaping @MainActor @Sendable (
            AppRoute,
            AppRouteSource
        ) -> Void
    ) {
        dependencies = .live
        self.requestRoute = requestRoute
        super.init()
    }

    init(
        dependencies: Dependencies,
        requestRoute: @escaping @MainActor @Sendable (
            AppRoute,
            AppRouteSource
        ) -> Void
    ) {
        self.dependencies = dependencies
        self.requestRoute = requestRoute
        super.init()
    }

    func setupDelegate() {
        dependencies.notificationCenter.setup(delegate: self)
    }

    func syncPermissionState() {
        guard activeAuthorizationRequestGeneration == nil else { return }

        permissionStatusGeneration &+= 1
        let generation = permissionStatusGeneration
        let notificationCenter = dependencies.notificationCenter
        permissionStatusTask?.cancel()
        permissionStatusTask = Task { @MainActor [weak self] in
            let status = await notificationCenter.authorizationStatus()
            guard let self,
                  !Task.isCancelled,
                  permissionStatusGeneration == generation,
                  activeAuthorizationRequestGeneration == nil else { return }

            let isGranted = SystemNotificationCenterService.isAuthorized(status)
            dependencies.preferences.setAuthorization(isGranted)
            if isGranted {
                dependencies.notificationCenter
                    .registerForRemoteNotifications()
            }
            await syncRemotePushRegistrationIfPossible(
                reason: "permission_state_sync"
            )
            if permissionStatusGeneration == generation {
                permissionStatusTask = nil
            }
        }
    }

    func requestAuthorization(
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        permissionStatusGeneration &+= 1
        permissionStatusTask?.cancel()
        permissionStatusTask = nil

        authorizationRequestGeneration &+= 1
        let generation = authorizationRequestGeneration
        activeAuthorizationRequestGeneration = generation
        let notificationCenter = dependencies.notificationCenter
        Task { @MainActor [weak self] in
            let result = await notificationCenter.requestAuthorization()
            guard let self else {
                completion(result.granted)
                return
            }
            guard activeAuthorizationRequestGeneration == generation else {
                completion(result.granted)
                return
            }

            if let error = result.error {
                MerianLog.notifications.debug(
                    "Failed to request push notification authorization: \(error.localizedDescription, privacy: .private)"
                )
                dependencies.preferences.setAuthorization(false)
            } else if result.granted {
                MerianLog.notifications.debug(
                    "Push notification authorization granted."
                )
                dependencies.preferences.setAuthorization(true)
                dependencies.notificationCenter
                    .registerForRemoteNotifications()
            } else {
                MerianLog.notifications.debug(
                    "Push notification authorization denied."
                )
                dependencies.preferences.setAuthorization(false)
            }

            activeAuthorizationRequestGeneration = nil
            completion(result.granted)
            await syncRemotePushRegistrationIfPossible(
                reason: "authorization_request"
            )
        }
    }

    func registerForRemoteNotificationsIfAuthorized() {
        guard dependencies.preferences.hasAuthorization else { return }
        dependencies.notificationCenter.registerForRemoteNotifications()
    }

    func handleRemoteDeviceToken(_ deviceToken: Data) {
        dependencies.preferences.storeDeviceToken(
            PushNotificationPolicy.encodedDeviceToken(deviceToken)
        )
        MerianLog.notifications.debug(
            "Received APNs device token from the system."
        )

        Task { @MainActor [weak self] in
            await self?.syncRemotePushRegistrationIfPossible(
                reason: "device_token_received"
            )
        }
    }

    func handleRemoteRegistrationFailure(_ error: any Error) {
        MerianLog.notifications.error(
            "APNs device registration failed: \(error.localizedDescription, privacy: .private)"
        )
    }

    func syncRemotePushRegistrationIfPossible(reason: String) async {
        guard let request = dependencies.preferences.registrationRequest(
            accountScopeID:
                dependencies.registrationContext.currentAccountScopeID(),
            environment: dependencies.pushEnvironment
        ) else { return }
        await dependencies.registrationCoordinator.synchronize(
            request,
            reason: reason
        )
    }

    func sendInferenceCompleteNotification(
        speciesName: String,
        scanId: String,
        imageURL: URL? = nil
    ) {
        guard !notifiedScanIDs.contains(scanId),
              !pendingInferenceScanIDs.contains(scanId) else { return }
        pendingInferenceScanIDs.insert(scanId)

        let descriptor = PushNotificationPolicy.inferenceCompleteDescriptor(
            speciesName: speciesName,
            scanID: scanId,
            imageURL: imageURL
        )
        dependencies.notificationCenter.schedule(descriptor) { [weak self] error in
            guard let self else { return }
            pendingInferenceScanIDs.remove(scanId)
            if let error {
                MerianLog.notifications.debug(
                    "Failed to schedule inference notification: \(error.localizedDescription, privacy: .private)"
                )
                return
            }
            notifiedScanIDs.insert(scanId)
            MerianLog.notifications.debug(
                "Inference notification scheduled for \(speciesName, privacy: .private)."
            )
        }
    }

    func sendUploadFailedNotification() {
        let descriptor = PushNotificationPolicy.uploadFailedDescriptor(
            identifier: dependencies.makeIdentifier()
        )
        dependencies.notificationCenter.schedule(descriptor) { error in
            if let error {
                MerianLog.notifications.debug(
                    "Failed to schedule failure notification: \(error.localizedDescription, privacy: .private)"
                )
            } else {
                MerianLog.notifications.debug(
                    "Failure notification scheduled."
                )
            }
        }
    }

    func sendAchievementUnlockedNotification(achievementTitle: String) {
        let descriptor = PushNotificationPolicy.achievementDescriptor(
            title: achievementTitle,
            identifier: dependencies.makeIdentifier()
        )
        dependencies.notificationCenter.schedule(descriptor) { error in
            if let error {
                MerianLog.notifications.debug(
                    "Failed to schedule achievement notification: \(error.localizedDescription, privacy: .private)"
                )
            } else {
                MerianLog.notifications.debug(
                    "Achievement notification scheduled for '\(achievementTitle, privacy: .public)'."
                )
            }
        }
    }

    func setBadgeCount(_ count: Int) {
        dependencies.notificationCenter.setBadgeCount(count)
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationAction(
            userInfo: response.notification.request.content.userInfo,
            actionIdentifier: response.actionIdentifier
        )
        completionHandler()
    }

    nonisolated func handleNotificationAction(
        userInfo: [AnyHashable: Any],
        actionIdentifier: String
    ) {
        guard let route = PushNotificationPolicy.route(
            userInfo: userInfo,
            isDismissAction:
                actionIdentifier == UNNotificationDismissActionIdentifier
        ) else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            logRoute(route, actionIdentifier: actionIdentifier)
            requestRoute(route, .pushNotification)
        }
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        let presentation = PushNotificationPolicy.foregroundPresentation(
            notificationType:
                notification.request.content.userInfo["type"] as? String,
            suppressesInferenceBanners:
                PushNotificationPreferencesStore.suppressesInferenceBanners()
        )
        switch presentation {
        case .silent:
            completionHandler([])
        case .bannerSoundAndList:
            completionHandler([.banner, .sound, .list])
        }
    }

    private func logRoute(_ route: AppRoute, actionIdentifier: String) {
        switch route {
        case .communityIdentification(let requestID):
            MerianLog.notifications.debug(
                "Community push notification tapped — routing to requestId \(requestID, privacy: .private)"
            )
        case .explorePost(let postID, _, _):
            MerianLog.notifications.debug(
                "Explore push notification tapped — routing to postId \(postID, privacy: .private)"
            )
        case .scan(let scanID):
            if actionIdentifier == PushNotificationIdentifiers.shareAction {
                MerianLog.notifications.debug(
                    "Share action tapped for scanId \(scanID, privacy: .private)"
                )
            } else {
                MerianLog.notifications.debug(
                    "Push notification tapped — routing to scanId \(scanID, privacy: .private)"
                )
            }
        default:
            break
        }
    }
}
