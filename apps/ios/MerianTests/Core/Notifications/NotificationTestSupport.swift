import Foundation
import UserNotifications

@testable import Merian

typealias NotificationErrorCompletion =
    @MainActor @Sendable ((any Error)?) -> Void

enum NotificationTestError: Error {
    case expected
}

@MainActor
final class SystemNotificationCenterProbe {
    var installedDelegate: (any UNUserNotificationCenterDelegate)?
    var categories: Set<UNNotificationCategory> = []
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var authorizationResult = PushNotificationAuthorizationResult(
        granted: false,
        error: nil
    )
    var remoteRegistrationCount = 0
    var scheduledRequests: [UNNotificationRequest] = []
    var scheduleCompletions: [NotificationErrorCompletion] = []
    var badgeCounts: [Int] = []

    func makeService() -> SystemNotificationCenterService {
        SystemNotificationCenterService(
            dependencies: .init(
                installDelegate: { self.installedDelegate = $0 },
                setCategories: { self.categories = $0 },
                authorizationStatus: { self.authorizationStatus },
                requestAuthorization: { self.authorizationResult },
                registerForRemoteNotifications: {
                    self.remoteRegistrationCount += 1
                },
                scheduleRequest: { request, completion in
                    self.scheduledRequests.append(request)
                    self.scheduleCompletions.append(completion)
                },
                setBadgeCount: { count, completion in
                    self.badgeCounts.append(count)
                    completion(nil)
                }
            )
        )
    }

    func finishSchedule(
        at index: Int,
        error: (any Error)? = nil
    ) {
        scheduleCompletions[index](error)
    }
}

@MainActor
final class PushNotificationPreferencesProbe {
    var strings: [String: String] = [:]
    var booleans: [String: Bool] = [:]
    var booleanWriteKeys: [String] = []

    func makeStore() -> PushNotificationPreferencesStore {
        PushNotificationPreferencesStore(
            dependencies: .init(
                string: { self.strings[$0] },
                bool: { self.booleans[$0, default: false] },
                setString: { self.strings[$1] = $0 },
                setBool: {
                    self.booleanWriteKeys.append($1)
                    self.booleans[$1] = $0
                }
            )
        )
    }
}

@MainActor
final class NotificationAsyncGate {
    private(set) var entryCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        entryCount += 1
        await withCheckedContinuation { continuations.append($0) }
    }

    func resume() {
        let admitted = continuations
        continuations.removeAll()
        for continuation in admitted {
            continuation.resume()
        }
    }
}

@MainActor
func waitUntil(
    _ condition: @MainActor () -> Bool
) async {
    while !condition() {
        await Task.yield()
    }
}
