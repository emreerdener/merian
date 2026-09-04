import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("App Settings")
struct AppSettingsTests {
    @Test func testAppSettingsOwnsTransientUIFlags() {
        let suiteName = "merian.tests.app-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(settings.hasUnseenScan == false)
        #expect(settings.hasPromptedForNotificationsPostIdent == false)
        #expect(settings.hasSeenExploreOnboarding == false)
        #expect(settings.hasUnseenExplorePost == false)
        #expect(settings.lastSeenExplorePostSharedAt.isEmpty)
        #expect(settings.suppressInferenceBanners == false)

        settings.hasUnseenScan = true
        settings.hasPromptedForNotificationsPostIdent = true
        settings.hasSeenExploreOnboarding = true
        settings.hasUnseenExplorePost = true
        settings.lastSeenExplorePostSharedAt = "2026-05-09T12:34:56Z"
        settings.suppressInferenceBanners = true

        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenScan))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasPromptedForNotificationsPostIdent))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding))
        #expect(defaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost))
        #expect(defaults.string(forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt) == "2026-05-09T12:34:56Z")
        #expect(defaults.bool(forKey: UserDefaultsKeys.suppressInferenceBanners))

        defaults.set(false, forKey: UserDefaultsKeys.hasUnseenScan)
        defaults.set(false, forKey: UserDefaultsKeys.suppressInferenceBanners)
        settings.refreshFromDefaults()

        #expect(settings.hasUnseenScan == false)
        #expect(settings.suppressInferenceBanners == false)
    }

    @Test func testAchievementNotificationsDefaultOnAndRespectExplicitOff() {
        let suiteName = "merian.tests.achievement-notification-defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(settings.isAchievementNotificationsEnabled == true)

        defaults.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)
        settings.refreshFromDefaults()

        #expect(settings.isAchievementNotificationsEnabled == false)
    }

    @Test func testOpenExploreOnLaunchDefaultsOffPersistsAndReloads() {
        let suiteName = "merian.tests.open-explore-on-launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(settings.opensExploreOnLaunch == false)

        settings.opensExploreOnLaunch = true
        #expect(defaults.bool(forKey: UserDefaultsKeys.opensExploreOnLaunch))

        let restored = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(restored.opensExploreOnLaunch)

        defaults.set(false, forKey: UserDefaultsKeys.opensExploreOnLaunch)
        restored.refreshFromDefaults()
        #expect(restored.opensExploreOnLaunch == false)
    }

    @Test func testCaptureGoalProgressDefaultsOnAndPersistsExplicitOff() {
        let suiteName = "merian.tests.capture-goal-progress.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(settings.showsCaptureGoalProgress)

        settings.showsCaptureGoalProgress = false
        #expect(!defaults.bool(forKey: UserDefaultsKeys.showsCaptureGoalProgress))

        let restored = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        #expect(!restored.showsCaptureGoalProgress)
    }

    @Test func testExploreNotificationDefaultsStartOn() {
        let suiteName = "merian.tests.explore-notification-defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)

        #expect(settings.isExploreNotificationsEnabled == true)
        #expect(settings.isExploreCommentMentionNotificationsEnabled == true)
    }

    @Test func testGridColumnNormalizationPersistsTheClampedValue() {
        let suiteName = "merian.tests.grid-column-normalization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(2, forKey: UserDefaultsKeys.gridColumns)

        let settings = AppSettings(userDefaults: defaults, observeExternalChanges: false)
        settings.gridColumns = 9

        #expect(settings.gridColumns == 3)
        #expect(defaults.integer(forKey: UserDefaultsKeys.gridColumns) == 3)

        settings.gridColumns = 0

        #expect(settings.gridColumns == 1)
        #expect(defaults.integer(forKey: UserDefaultsKeys.gridColumns) == 1)
        #expect(
            AppSettings(
                userDefaults: defaults,
                observeExternalChanges: false
            ).gridColumns == 1
        )
    }

    @Test func testExternalDefaultsNotificationReloadsObservedState() async {
        let suiteName = "merian.tests.app-settings-external-change.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        #expect(settings.hasUnseenScan == false)

        defaults.set(true, forKey: UserDefaultsKeys.hasUnseenScan)
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: defaults
        )

        for _ in 0..<10 where !settings.hasUnseenScan {
            await Task.yield()
        }

        #expect(settings.hasUnseenScan)
    }
}
