import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("App update compatibility recovery")
struct AppUpdateCoordinatorTests {
    @Test func dismissalAndRelaunchPreservePauseUntilInstalledBuildChanges() throws {
        let suite = "app-update-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = UUID()
        let original = AppUpdateCoordinator(defaults: defaults, buildIdentity: "1:10") { account }
        original.record(.history)
        original.record(.identification)
        #expect(original.showsPrompt)
        original.dismiss()
        original.refresh()
        #expect(!original.showsPrompt)
        #expect(original.requiresUpdate(.history, accountID: account))
        #expect(original.blocksRetry(errorCode: "client_update_required"))
        #expect(original.showsPrompt)

        let relaunched = AppUpdateCoordinator(defaults: defaults, buildIdentity: "1:10") { account }
        relaunched.refresh()
        #expect(relaunched.showsPrompt)
        #expect(!relaunched.shouldRetryHistoryAfterUpdate)

        let updated = AppUpdateCoordinator(defaults: defaults, buildIdentity: "1:11") { account }
        updated.refresh()
        #expect(!updated.showsPrompt)
        #expect(!updated.requiresUpdate(.history, accountID: account))
        #expect(updated.shouldRetryHistoryAfterUpdate)
        #expect(!updated.blocksRetry(errorCode: "client_update_required"))
        #expect(!updated.blocksRetry(errorCode: "server_result_local_recovery_update_required"))
        updated.historySucceeded(accountID: account)
        #expect(!updated.shouldRetryHistoryAfterUpdate)
    }

    @Test func accountSwitchAndLateProducerCannotPauseAnotherAccount() throws {
        let suite = "app-update-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID(), second = UUID()
        var current: UUID? = first
        let subject = AppUpdateCoordinator(defaults: defaults, buildIdentity: "1:10") { current }
        subject.record(.history, accountID: first)
        current = second
        subject.refresh()
        subject.record(.history, accountID: first)
        #expect(!subject.showsPrompt)
        #expect(!subject.requiresUpdate(.history, accountID: second))
        #expect(!subject.blocksRetry(errorCode: "automatic_retry_limit_reached"))
        current = nil
        subject.refresh()
        #expect(!subject.showsPrompt)
        current = first
        subject.refresh()
        #expect(subject.showsPrompt)
    }

    @Test func historyAndIdentificationPausesRemainIndependentAndCleanupPurgesThem() throws {
        let suite = "app-update-tests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = UUID()
        let subject = AppUpdateCoordinator(defaults: defaults, buildIdentity: "1:10") { account }
        subject.record(.identification)
        #expect(!subject.requiresUpdate(.history, accountID: account))
        #expect(!subject.blocksRetry(errorCode: "server_result_local_recovery_update_required"))
        subject.record(.history)
        subject.historySucceeded(accountID: account)
        #expect(subject.requiresUpdate(.history, accountID: account))
        let updated = AppUpdateCoordinator(defaults: defaults, buildIdentity: "1:11") { account }
        updated.historySucceeded(accountID: account)
        #expect(subject.requiresUpdate(.identification, accountID: account))
        #expect(!subject.requiresUpdate(.history, accountID: account))
        #expect(AccountScopedPreferences.purgeAndVerify(userDefaults: defaults))
        subject.refresh()
        #expect(!subject.showsPrompt)
    }

    @Test func rootPromptDefersForRecoveryAndOnboardingWithoutDiscardingRequest() {
        #expect(AppRootAlertPolicy.next(
            hasUsableStore: true, isAccountDeletionPending: true,
            needsAppleRevocation: true, isWorkspaceReady: true, needsAppUpdate: true
        ) == nil)
        #expect(AppRootAlertPolicy.next(
            hasUsableStore: false, isAccountDeletionPending: false,
            needsAppleRevocation: false, isWorkspaceReady: true, needsAppUpdate: true
        ) == nil)
        #expect(AppRootAlertPolicy.next(
            hasUsableStore: true, isAccountDeletionPending: false,
            needsAppleRevocation: true, isWorkspaceReady: true, needsAppUpdate: true
        ) == .manualAppleRevocation)
        #expect(AppRootAlertPolicy.next(
            hasUsableStore: true, isAccountDeletionPending: false,
            needsAppleRevocation: false, isWorkspaceReady: false, needsAppUpdate: true
        ) == nil)
        #expect(AppRootAlertPolicy.next(
            hasUsableStore: true, isAccountDeletionPending: false,
            needsAppleRevocation: false, isWorkspaceReady: true, needsAppUpdate: true
        ) == .appUpdate)
        #expect(AppUpdatePresentation.appStoreURL.scheme == "https")
        #expect(AppUpdatePresentation.appStoreURL.host == "apps.apple.com")
        #expect(AppUpdatePresentation.appStoreURL.path == "/app/id6760208440")
    }
}
