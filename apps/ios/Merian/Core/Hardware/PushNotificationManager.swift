import Foundation
import UserNotifications
#if canImport(UIKit)
import os
import UIKit
#endif

/// Manages UNUserNotificationCenter delegation for local inference completion alerts.
@MainActor
@Observable
final class PushNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()

    /// Scan IDs for which an inference notification has already been scheduled this session.
    /// Prevents duplicate notifications when both the live and background paths complete
    /// for the same scan in close succession (e.g. simulator re-attach or fast network).
    @ObservationIgnored private var notifiedScanIds: Set<String> = []
    @ObservationIgnored private var isSyncingRemotePushRegistration = false

    private var currentDeviceToken: String? {
        get { UserDefaults.standard.string(forKey: UserDefaultsKeys.remotePushDeviceToken) }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKeys.remotePushDeviceToken) }
    }

    private var effectiveExplorePushEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasPushNotificationAuthorization)
            && UserDefaults.standard.bool(forKey: UserDefaultsKeys.isExploreNotificationsEnabled)
    }

    private var exploreMentionPushEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasPushNotificationAuthorization)
            && UserDefaults.standard.bool(forKey: UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled)
    }

    private var communityIdPushEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasPushNotificationAuthorization)
            && UserDefaults.standard.bool(forKey: UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled)
    }

    private override init() {
        super.init()
    }

    func setupDelegate() {
        UNUserNotificationCenter.current().delegate = self
        setupCategories()
    }

    /// Registers custom notification categories and interactive actions for the app's push notifications.
    ///
    /// This enables rich, interactive notifications on the iOS lock screen, allowing users to
    /// trigger common actions (like viewing details or sharing a discovery) without needing to
    /// manually open the app first.
    private func setupCategories() {
        let viewAction = UNNotificationAction(identifier: "VIEW_ACTION", title: "View Details", options: [.foreground])
        let shareAction = UNNotificationAction(identifier: "SHARE_ACTION", title: "Share Discovery", options: [.foreground])
        
        let category = UNNotificationCategory(
            identifier: "INFERENCE_COMPLETE",
            actions: [viewAction, shareAction],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func syncPermissionState() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let isGranted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            Task { @MainActor in
                if UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasPushNotificationAuthorization) != isGranted {
                    UserDefaults.standard.set(isGranted, forKey: UserDefaultsKeys.hasPushNotificationAuthorization)
                }
                self.registerForRemoteNotificationsIfAuthorized()
                await self.syncRemotePushRegistrationIfPossible(reason: "permission_state_sync")
            }
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            Task { @MainActor in
                if let error = error {
                    MerianLog.hardware.debug("Failed to request push notification authorization: \(error, privacy: .private)")
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasPushNotificationAuthorization)
                } else if granted {
                    MerianLog.hardware.debug("Push notification authorization granted.")
                    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.hasPushNotificationAuthorization)
                    self.registerForRemoteNotificationsIfAuthorized()
                } else {
                    MerianLog.hardware.debug("Push notification authorization denied.")
                    UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasPushNotificationAuthorization)
                }
                await self.syncRemotePushRegistrationIfPossible(reason: "authorization_request")
                completion(granted)
            }
        }
    }

    func registerForRemoteNotificationsIfAuthorized() {
        guard UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasPushNotificationAuthorization) else {
            return
        }
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func handleRemoteDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        currentDeviceToken = token
        MerianLog.hardware.debug("Received APNs device token from the system.")

        Task {
            await syncRemotePushRegistrationIfPossible(reason: "device_token_received")
        }
    }

    func handleRemoteRegistrationFailure(_ error: Error) {
        MerianLog.hardware.error("APNs device registration failed: \(error.localizedDescription, privacy: .private)")
    }

    func syncRemotePushRegistrationIfPossible(reason: String) async {
        guard !isSyncingRemotePushRegistration else { return }
        guard let deviceToken = currentDeviceToken, !deviceToken.isEmpty else { return }

        isSyncingRemotePushRegistration = true
        defer { isSyncingRemotePushRegistration = false }

        do {
            try await MerianNetworkClient.shared.registerPushDevice(
                deviceToken: deviceToken,
                environment: currentPushEnvironment,
                exploreEnabled: effectiveExplorePushEnabled,
                commentMentionsEnabled: exploreMentionPushEnabled,
                communityIdentificationsEnabled: communityIdPushEnabled
            )
        } catch {
            MerianLog.hardware.error(
                "Remote push registration sync failed (\(reason, privacy: .public)): \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private var currentPushEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// Schedules a local notification to alert the user that the AI has finished analyzing their scan.
    ///
    /// This notification utilizes several premium UX features:
    /// - **Rich Media**: Attaches an image thumbnail if `imageURL` is provided.
    /// - **Time Sensitive**: Escalates priority to bypass focus modes (requires the Time Sensitive capability).
    /// - **Thread Grouping**: Groups all inference completion notifications neatly under a single stack.
    /// - **Interactive Actions**: Provides quick actions to view or share the discovery straight from the lock screen.
    ///
    /// - Parameters:
    ///   - speciesName: The resolved name of the discovered species.
    ///   - scanId: The unique identifier for the scan, used for internal routing when the notification is tapped.
    ///   - imageURL: An optional local file URL pointing to the scan's captured image for the lock screen thumbnail.
    func sendInferenceCompleteNotification(speciesName: String, scanId: String, imageURL: URL? = nil) {
        guard !notifiedScanIds.contains(scanId) else { return }
        notifiedScanIds.insert(scanId)

        let content = UNMutableNotificationContent()
        content.title = speciesName
        content.body = "Analysis complete. Tap to view full insights."
        content.sound = .default
        content.userInfo = ["scanId": scanId]
        content.categoryIdentifier = "INFERENCE_COMPLETE"
        content.threadIdentifier = "inference_complete_thread"
        
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        
        if let imageURL = imageURL {
            do {
                let attachment = try UNNotificationAttachment(identifier: "image", url: imageURL, options: nil)
                content.attachments = [attachment]
            } catch {
                MerianLog.hardware.debug("Failed to create notification attachment: \(error, privacy: .private)")
            }
        }

        let request = UNNotificationRequest(identifier: "inference_\(scanId)", content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                MerianLog.hardware.debug("Failed to schedule inference notification: \(error, privacy: .private)")
            } else {
                MerianLog.hardware.debug("Inference notification scheduled for \(speciesName, privacy: .private).")
            }
        }
    }

    func sendUploadFailedNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Upload failed"
        content.body = "A background scan was unable to upload and has been discarded."
        content.sound = .default
        content.userInfo = ["type": "failure"]
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                MerianLog.hardware.debug("Failed to schedule failure notification: \(error, privacy: .private)")
            } else {
                MerianLog.hardware.debug("Failure notification scheduled.")
            }
        }
    }

    func sendAchievementUnlockedNotification(achievementTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "Achievement Unlocked!"
        content.body = "You just earned: \(achievementTitle)"
        content.sound = .default
        content.userInfo = ["type": "achievement"]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                MerianLog.hardware.debug("Failed to schedule achievement notification: \(error, privacy: .private)")
            } else {
                MerianLog.hardware.debug("Achievement notification scheduled for '\(achievementTitle, privacy: .public)'.")
            }
        }
    }

    func setBadgeCount(_ count: Int) {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count) { error in
                if let error = error {
                    MerianLog.hardware.debug("Failed to set badge count: \(error, privacy: .private)")
                }
            }
        } else {
            #if canImport(UIKit)
            UIApplication.shared.applicationIconBadgeNumber = count
            #endif
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        handleNotificationAction(userInfo: userInfo, actionIdentifier: response.actionIdentifier)
        completionHandler()
    }

    /// Extracted for testability since `UNNotificationResponse` cannot be cleanly mocked in XCTest.
    nonisolated func handleNotificationAction(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        if let type = userInfo["type"] as? String, type == "explore_activity" {
            guard actionIdentifier != UNNotificationDismissActionIdentifier else { return }

            let requestId = (userInfo["communityRequestId"] as? String)
                ?? (userInfo["community_request_id"] as? String)
            if let requestId {
                Task { @MainActor in
                    MerianLog.hardware.debug(
                        "Community push notification tapped — routing to requestId \(requestId, privacy: .private)"
                    )
                    AppEventPublisher.shared.send(.openCommunityIdentificationRequest(requestId: requestId))
                }
                return
            }

            guard let postId = userInfo["postId"] as? String else { return }
            let commentId = userInfo["commentId"] as? String ?? userInfo["comment_id"] as? String
            let parentCommentId = userInfo["parentCommentId"] as? String ?? userInfo["parent_comment_id"] as? String
            Task { @MainActor in
                MerianLog.hardware.debug(
                    "Explore push notification tapped — routing to postId \(postId, privacy: .private)"
                )
                AppEventPublisher.shared.send(.appDidEnterActivePhaseWithExplorePost(
                    postId: postId,
                    targetCommentId: commentId,
                    targetReplyParentCommentId: parentCommentId
                ))
            }
            return
        }

        if let scanId = userInfo["scanId"] as? String {
            if actionIdentifier != UNNotificationDismissActionIdentifier {
                Task { @MainActor in
                    if actionIdentifier == "SHARE_ACTION" {
                        MerianLog.hardware.debug("Share action tapped for scanId \(scanId, privacy: .private)")
                    } else {
                        MerianLog.hardware.debug("Push notification tapped — routing to scanId \(scanId, privacy: .private)")
                    }
                    // For now, route to the scan regardless of which action was tapped
                    // We can handle specific share intent dynamically within the insight sheet later.
                    AppEventPublisher.shared.send(.appDidEnterActivePhaseWithScan(scanId: scanId))
                }
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let type = notification.request.content.userInfo["type"] as? String
        
        if type == "explore_activity" {
            completionHandler([.banner, .sound, .list])
        } else if type == "achievement" {
            completionHandler([])
        } else if UserDefaults.standard.bool(forKey: UserDefaultsKeys.suppressInferenceBanners) {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }
}

@MainActor
enum AppIconBadgeCoordinator {
    private static let exploreUnreadNotificationCountKey = "exploreUnreadNotificationBadgeCount"
    private static let refreshReuseInterval: TimeInterval = 10
    private static var activeExploreUnreadRefreshTask: Task<Int?, Never>?
    private static var lastExploreUnreadRefreshAt: Date?

    static var exploreUnreadNotificationCount: Int {
        max(0, UserDefaults.standard.integer(forKey: exploreUnreadNotificationCountKey))
    }

    static func setExploreUnreadNotificationCount(_ count: Int) {
        UserDefaults.standard.set(max(0, count), forKey: exploreUnreadNotificationCountKey)
        updateAppIconBadge()
    }

    static func clearExploreUnreadNotificationCount() {
        setExploreUnreadNotificationCount(0)
    }

    static func refreshExploreUnreadNotificationCount(force: Bool = false) async -> Int? {
        if let activeExploreUnreadRefreshTask {
            return await activeExploreUnreadRefreshTask.value
        }

        if !force,
           let lastExploreUnreadRefreshAt,
           Date().timeIntervalSince(lastExploreUnreadRefreshAt) < refreshReuseInterval {
            return exploreUnreadNotificationCount
        }

        let refreshTask = Task<Int?, Never> { @MainActor in
            do {
                let count = try await MerianNetworkClient.shared.getUnreadExploreNotificationCount()
                setExploreUnreadNotificationCount(count)
                return count
            } catch is CancellationError {
                return nil
            } catch let error as URLError where error.code == .cancelled {
                return nil
            } catch {
                MerianLog.network.debug(
                    "Failed to refresh Explore app icon badge count: \(error.localizedDescription, privacy: .private)"
                )
                return nil
            }
        }
        activeExploreUnreadRefreshTask = refreshTask

        let count = await refreshTask.value
        activeExploreUnreadRefreshTask = nil
        if count != nil {
            lastExploreUnreadRefreshAt = Date()
        }
        return count
    }

    static func updateAppIconBadge() {
        let unseenScanCount = AppSettings.shared.hasUnseenScan ? 1 : 0
        PushNotificationManager.shared.setBadgeCount(unseenScanCount + exploreUnreadNotificationCount)
    }
}
