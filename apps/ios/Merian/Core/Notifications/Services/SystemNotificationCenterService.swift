import Foundation
import os
import UIKit
import UserNotifications

struct PushNotificationAuthorizationResult {
    let granted: Bool
    let error: (any Error)?
}

@MainActor
final class SystemNotificationCenterService {
    struct Dependencies {
        let installDelegate:
            @MainActor (_ delegate: any UNUserNotificationCenterDelegate) -> Void
        let setCategories:
            @MainActor (_ categories: Set<UNNotificationCategory>) -> Void
        let authorizationStatus:
            @MainActor () async -> UNAuthorizationStatus
        let requestAuthorization:
            @MainActor () async -> PushNotificationAuthorizationResult
        let registerForRemoteNotifications: @MainActor () -> Void
        let scheduleRequest:
            @MainActor (
                _ request: UNNotificationRequest,
                _ completion: @escaping @MainActor @Sendable (
                    (any Error)?
                ) -> Void
            ) -> Void
        let setBadgeCount:
            @MainActor (
                _ count: Int,
                _ completion: @escaping @MainActor @Sendable (
                    (any Error)?
                ) -> Void
            ) -> Void

        static var live: Self {
            let center = UNUserNotificationCenter.current()
            return Self(
                installDelegate: { center.delegate = $0 },
                setCategories: { center.setNotificationCategories($0) },
                authorizationStatus: {
                    await withCheckedContinuation { continuation in
                        center.getNotificationSettings { settings in
                            continuation.resume(
                                returning: settings.authorizationStatus
                            )
                        }
                    }
                },
                requestAuthorization: {
                    await withCheckedContinuation { continuation in
                        center.requestAuthorization(
                            options: [.alert, .sound, .badge]
                        ) { granted, error in
                            continuation.resume(
                                returning: PushNotificationAuthorizationResult(
                                    granted: granted,
                                    error: error
                                )
                            )
                        }
                    }
                },
                registerForRemoteNotifications: {
                    UIApplication.shared.registerForRemoteNotifications()
                },
                scheduleRequest: { request, completion in
                    center.add(request) { error in
                        Task { @MainActor in completion(error) }
                    }
                },
                setBadgeCount: { count, completion in
                    if #available(iOS 16.0, *) {
                        center.setBadgeCount(count) { error in
                            Task { @MainActor in completion(error) }
                        }
                    } else {
                        UIApplication.shared.applicationIconBadgeNumber = count
                        completion(nil)
                    }
                }
            )
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    nonisolated static func isAuthorized(
        _ status: UNAuthorizationStatus
    ) -> Bool {
        status == .authorized || status == .provisional
    }

    func setup(delegate: any UNUserNotificationCenterDelegate) {
        dependencies.installDelegate(delegate)

        let viewAction = UNNotificationAction(
            identifier: PushNotificationIdentifiers.viewAction,
            title: "View Details",
            options: [.foreground]
        )
        let shareAction = UNNotificationAction(
            identifier: PushNotificationIdentifiers.shareAction,
            title: "Share Discovery",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: PushNotificationIdentifiers.inferenceCategory,
            actions: [viewAction, shareAction],
            intentIdentifiers: [],
            options: []
        )
        dependencies.setCategories([category])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await dependencies.authorizationStatus()
    }

    func requestAuthorization() async -> PushNotificationAuthorizationResult {
        await dependencies.requestAuthorization()
    }

    func registerForRemoteNotifications() {
        dependencies.registerForRemoteNotifications()
    }

    func schedule(
        _ descriptor: LocalNotificationDescriptor,
        completion: @escaping @MainActor @Sendable ((any Error)?) -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = descriptor.title
        content.body = descriptor.body
        content.sound = .default
        content.userInfo = descriptor.userInfo
        if let categoryIdentifier = descriptor.categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }
        if let threadIdentifier = descriptor.threadIdentifier {
            content.threadIdentifier = threadIdentifier
        }
        if descriptor.isTimeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        if let attachmentURL = descriptor.attachmentURL {
            do {
                content.attachments = [
                    try UNNotificationAttachment(
                        identifier: "image",
                        url: attachmentURL,
                        options: nil
                    )
                ]
            } catch {
                MerianLog.notifications.debug(
                    "Failed to create notification attachment: \(error, privacy: .private)"
                )
            }
        }

        let request = UNNotificationRequest(
            identifier: descriptor.identifier,
            content: content,
            trigger: nil
        )
        dependencies.scheduleRequest(request, completion)
    }

    func setBadgeCount(_ count: Int) {
        dependencies.setBadgeCount(count) { error in
            if let error {
                MerianLog.notifications.debug(
                    "Failed to set badge count: \(error, privacy: .private)"
                )
            }
        }
    }
}
