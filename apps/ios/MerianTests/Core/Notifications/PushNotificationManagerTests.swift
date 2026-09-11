import Foundation
import Testing
import UserNotifications

@testable import Merian

@MainActor
struct PushNotificationManagerTests {
    @Test("Setup installs the delegate and inference actions")
    func setupDelegate() throws {
        let center = SystemNotificationCenterProbe()
        let manager = makeManager(center: center)

        manager.setupDelegate()

        #expect(center.installedDelegate === manager)
        let category = try #require(center.categories.first)
        #expect(
            category.identifier ==
                PushNotificationIdentifiers.inferenceCategory
        )
        #expect(
            category.actions.map(\.identifier) == [
                PushNotificationIdentifiers.viewAction,
                PushNotificationIdentifiers.shareAction
            ]
        )
    }

    @Test("Permission sync persists status and registers every boundary")
    func permissionSync() async throws {
        let center = SystemNotificationCenterProbe()
        center.authorizationStatus = .provisional
        let preferences = PushNotificationPreferencesProbe()
        preferences.booleans[
            UserDefaultsKeys.isExploreNotificationsEnabled
        ] = true
        preferences.booleans[
            UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled
        ] = true
        preferences.booleans[
            UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled
        ] = false
        preferences.strings[UserDefaultsKeys.remotePushDeviceToken] = "token"
        var registrations: [PushRegistrationRequest] = []
        let manager = makeManager(
            center: center,
            preferences: preferences,
            register: { registrations.append($0) }
        )

        manager.syncPermissionState()
        await waitUntil { !registrations.isEmpty }

        #expect(
            preferences.booleans[
                UserDefaultsKeys.hasPushNotificationAuthorization
            ] == true
        )
        #expect(center.remoteRegistrationCount == 1)
        #expect(
            preferences.booleanWriteKeys == [
                UserDefaultsKeys.hasPushNotificationAuthorization
            ]
        )
        let request = try #require(registrations.first)
        #expect(request.deviceToken == "token")
        #expect(request.exploreEnabled)
        #expect(request.commentMentionsEnabled)
        #expect(!request.communityIdentificationsEnabled)
    }

    @Test("Permission sync does not rewrite unchanged authorization")
    func unchangedPermissionDoesNotWriteDefaults() async {
        let center = SystemNotificationCenterProbe()
        center.authorizationStatus = .authorized
        let preferences = PushNotificationPreferencesProbe()
        preferences.booleans[
            UserDefaultsKeys.hasPushNotificationAuthorization
        ] = true
        let manager = makeManager(
            center: center,
            preferences: preferences
        )

        manager.syncPermissionState()
        await waitUntil { center.remoteRegistrationCount == 1 }
        await Task.yield()

        #expect(preferences.booleanWriteKeys.isEmpty)
    }

    @Test("The newest permission response wins")
    func stalePermissionResponseIsRejected() async {
        var continuations: [
            CheckedContinuation<UNAuthorizationStatus, Never>
        ] = []
        let service = SystemNotificationCenterService(
            dependencies: .init(
                installDelegate: { _ in },
                setCategories: { _ in },
                authorizationStatus: {
                    await withCheckedContinuation {
                        continuations.append($0)
                    }
                },
                requestAuthorization: {
                    PushNotificationAuthorizationResult(
                        granted: false,
                        error: nil
                    )
                },
                registerForRemoteNotifications: {},
                scheduleRequest: { _, _ in },
                setBadgeCount: { _, completion in completion(nil) }
            )
        )
        let preferences = PushNotificationPreferencesProbe()
        let manager = makeManager(
            centerService: service,
            preferences: preferences
        )

        manager.syncPermissionState()
        await waitUntil { continuations.count == 1 }
        manager.syncPermissionState()
        await waitUntil { continuations.count == 2 }

        continuations[1].resume(returning: .authorized)
        await waitUntil {
            preferences.booleans[
                UserDefaultsKeys.hasPushNotificationAuthorization
            ] == true
        }
        continuations[0].resume(returning: .denied)
        await Task.yield()

        #expect(
            preferences.booleans[
                UserDefaultsKeys.hasPushNotificationAuthorization
            ] == true
        )
    }

    @Test("Authorization prompts fence status polls until they finish")
    func authorizationPromptFencesStatusPolls() async {
        var statusRequestCount = 0
        var statusContinuations: [
            CheckedContinuation<UNAuthorizationStatus, Never>
        ] = []
        var authorizationContinuation: CheckedContinuation<
            PushNotificationAuthorizationResult,
            Never
        >?
        let service = SystemNotificationCenterService(
            dependencies: .init(
                installDelegate: { _ in },
                setCategories: { _ in },
                authorizationStatus: {
                    statusRequestCount += 1
                    if statusRequestCount == 1 {
                        return await withCheckedContinuation {
                            statusContinuations.append($0)
                        }
                    }
                    return .authorized
                },
                requestAuthorization: {
                    await withCheckedContinuation {
                        authorizationContinuation = $0
                    }
                },
                registerForRemoteNotifications: {},
                scheduleRequest: { _, _ in },
                setBadgeCount: { _, completion in completion(nil) }
            )
        )
        let preferences = PushNotificationPreferencesProbe()
        preferences.strings[UserDefaultsKeys.remotePushDeviceToken] = "token"
        let registrationGate = NotificationAsyncGate()
        var registrations: [PushRegistrationRequest] = []
        var authorizationCompletions: [Bool] = []
        let manager = makeManager(
            centerService: service,
            preferences: preferences,
            register: {
                registrations.append($0)
                await registrationGate.suspend()
            }
        )

        manager.syncPermissionState()
        await waitUntil { statusRequestCount == 1 }
        manager.requestAuthorization {
            authorizationCompletions.append($0)
            preferences.booleans[
                UserDefaultsKeys.isExploreNotificationsEnabled
            ] = $0
        }
        await waitUntil { authorizationContinuation != nil }
        manager.syncPermissionState()
        await Task.yield()

        #expect(statusRequestCount == 1)
        authorizationContinuation?.resume(
            returning: PushNotificationAuthorizationResult(
                granted: true,
                error: nil
            )
        )
        await waitUntil {
            preferences.booleans[
                UserDefaultsKeys.hasPushNotificationAuthorization
            ] == true
        }
        await waitUntil { registrationGate.entryCount == 1 }
        #expect(authorizationCompletions == [true])
        #expect(registrations.first?.exploreEnabled == true)
        manager.syncPermissionState()
        await waitUntil { statusRequestCount == 2 }

        #expect(statusRequestCount == 2)
        registrationGate.resume()
        statusContinuations[0].resume(returning: .denied)
        await Task.yield()

        #expect(
            preferences.booleans[
                UserDefaultsKeys.hasPushNotificationAuthorization
            ] == true
        )
    }

    @Test("Device token registration uses encoded token and current settings")
    func deviceTokenRegistration() async throws {
        let center = SystemNotificationCenterProbe()
        let preferences = PushNotificationPreferencesProbe()
        preferences.booleans[
            UserDefaultsKeys.hasPushNotificationAuthorization
        ] = true
        preferences.booleans[
            UserDefaultsKeys.isExploreNotificationsEnabled
        ] = true
        var registrations: [PushRegistrationRequest] = []
        let manager = makeManager(
            center: center,
            preferences: preferences,
            register: { registrations.append($0) }
        )

        manager.handleRemoteDeviceToken(Data([0x00, 0xAB, 0xFF]))
        await waitUntil { !registrations.isEmpty }

        #expect(
            preferences.strings[UserDefaultsKeys.remotePushDeviceToken] ==
                "00abff"
        )
        let request = try #require(registrations.first)
        #expect(request.deviceToken == "00abff")
        #expect(request.accountScopeID == "account-test")
        #expect(request.environment == "test")
        #expect(request.exploreEnabled)
    }

    @Test("Failed inference scheduling remains retryable and success dedupes")
    func inferenceSchedulingRetryAndDedupe() {
        let center = SystemNotificationCenterProbe()
        let manager = makeManager(center: center)

        manager.sendInferenceCompleteNotification(
            speciesName: "Monarch",
            scanId: "scan-1"
        )
        manager.sendInferenceCompleteNotification(
            speciesName: "Monarch",
            scanId: "scan-1"
        )
        #expect(center.scheduledRequests.count == 1)

        center.finishSchedule(
            at: 0,
            error: NotificationTestError.expected
        )
        manager.sendInferenceCompleteNotification(
            speciesName: "Monarch",
            scanId: "scan-1"
        )
        #expect(center.scheduledRequests.count == 2)

        center.finishSchedule(at: 1)
        manager.sendInferenceCompleteNotification(
            speciesName: "Monarch",
            scanId: "scan-1"
        )
        #expect(center.scheduledRequests.count == 2)
        #expect(
            center.scheduledRequests.last?.content.userInfo["scanId"]
                as? String == "scan-1"
        )
    }

    @Test("Typed routing remains on the application route boundary")
    func typedRouting() async {
        let center = SystemNotificationCenterProbe()
        var routes: [(AppRoute, AppRouteSource)] = []
        let manager = makeManager(
            center: center,
            requestRoute: { route, source in
                routes.append((route, source))
            }
        )

        manager.handleNotificationAction(
            userInfo: ["scanId": "scan-1"],
            actionIdentifier: UNNotificationDefaultActionIdentifier
        )
        await waitUntil { routes.count == 1 }

        #expect(routes[0].0 == .scan(scanId: "scan-1"))
        #expect(routes[0].1 == .pushNotification)
    }

    private func makeManager(
        center: SystemNotificationCenterProbe,
        preferences: PushNotificationPreferencesProbe? = nil,
        register: @escaping @MainActor (
            PushRegistrationRequest
        ) async throws -> Void = { _ in },
        requestRoute: @escaping @MainActor @Sendable (
            AppRoute,
            AppRouteSource
        ) -> Void = { _, _ in }
    ) -> PushNotificationManager {
        let preferences = preferences ?? PushNotificationPreferencesProbe()
        return makeManager(
            centerService: center.makeService(),
            preferences: preferences,
            register: register,
            requestRoute: requestRoute
        )
    }

    private func makeManager(
        centerService: SystemNotificationCenterService,
        preferences: PushNotificationPreferencesProbe,
        register: @escaping @MainActor (
            PushRegistrationRequest
        ) async throws -> Void = { _ in },
        requestRoute: @escaping @MainActor @Sendable (
            AppRoute,
            AppRouteSource
        ) -> Void = { _, _ in }
    ) -> PushNotificationManager {
        PushNotificationManager(
            dependencies: .init(
                notificationCenter: centerService,
                preferences: preferences.makeStore(),
                registrationCoordinator: PushRegistrationCoordinator(
                    dependencies: .init(
                        service: PushRegistrationService(register: register),
                        reportFailure: { _, _ in }
                    )
                ),
                registrationContext: PushRegistrationContextService(
                    currentAccountScopeID: { "account-test" }
                ),
                pushEnvironment: "test",
                makeIdentifier: { "generated-id" }
            ),
            requestRoute: requestRoute
        )
    }
}
