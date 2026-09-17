import Testing

@testable import Merian

@MainActor
struct BackgroundScanNotificationServiceTests {
    @Test("Background completion preserves opt-out and foreground presentation policy",
          arguments: [false, true], [false, true])
    func completionEffects(enabled: Bool, suppressesBanners: Bool) {
        var unseenCount = 0
        var notifications: [String] = []
        let service = BackgroundScanNotificationService(
            suppressesInferenceBanners: { suppressesBanners },
            markUnseenScan: { unseenCount += 1 },
            notificationsEnabled: { enabled },
            sendNotification: { notifications.append("\($0)|\($1)") }
        )

        service.notify(speciesName: "Monarch", scanId: "scan-test")

        #expect(unseenCount == (suppressesBanners ? 0 : 1))
        #expect(notifications == (enabled ? ["Monarch|scan-test"] : []))
    }

    @Test("Direct and recovered completions share scheduler deduplication and retry")
    func duplicateCompletionAndSchedulingFailure() throws {
        let center = SystemNotificationCenterProbe()
        let manager = PushNotificationManager(
            dependencies: .init(
                notificationCenter: center.makeService(),
                preferences: PushNotificationPreferencesProbe().makeStore(),
                registrationCoordinator: PushRegistrationCoordinator(
                    dependencies: .init(
                        service: PushRegistrationService(register: { _ in }),
                        reportFailure: { _, _ in }
                    )
                ),
                registrationContext: .init(currentAccountScopeID: { nil }),
                pushEnvironment: "test",
                makeIdentifier: { "test" }
            ),
            requestRoute: { _, _ in }
        )
        let service = BackgroundScanNotificationService(
            suppressesInferenceBanners: { false },
            markUnseenScan: {},
            notificationsEnabled: { true },
            sendNotification: { name, scanId in
                manager.sendInferenceCompleteNotification(speciesName: name, scanId: scanId)
            }
        )

        service.notify(speciesName: "Monarch", scanId: "scan-test")
        service.notify(speciesName: "Monarch", scanId: "scan-test")
        #expect(center.scheduledRequests.count == 1)
        center.finishSchedule(at: 0, error: NotificationTestError.expected)
        service.notify(speciesName: "Monarch", scanId: "scan-test")
        #expect(center.scheduledRequests.count == 2)
        center.finishSchedule(at: 1)
        service.notify(speciesName: "Monarch", scanId: "scan-test")
        #expect(center.scheduledRequests.count == 2)

        let request = try #require(center.scheduledRequests.last)
        #expect(request.identifier == "inference_scan-test")
        #expect(request.content.title == "Monarch")
        #expect(request.content.userInfo["scanId"] as? String == "scan-test")
    }
}
