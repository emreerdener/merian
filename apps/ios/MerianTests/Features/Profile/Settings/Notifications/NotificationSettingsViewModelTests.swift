import UserNotifications
import XCTest

@testable import Merian

@MainActor
final class NotificationSettingsViewModelTests: XCTestCase {
    func testUndeterminedAuthorizationDefersEnableUntilPromptCompletion() async {
        let viewModel = NotificationSettingsViewModel(
            dependencies: makeDependencies(status: .notDetermined)
        )
        await viewModel.refreshAuthorizationStatus()

        let resolved = viewModel.resolvedValue(
            for: true,
            preference: .exploreCommentMentions
        )

        XCTAssertNil(resolved)
        XCTAssertTrue(viewModel.showPermissionPrompt)
        XCTAssertEqual(
            viewModel.pendingPreference,
            .exploreCommentMentions
        )
        XCTAssertEqual(
            viewModel.completePermissionPrompt(granted: true),
            .exploreCommentMentions
        )
        XCTAssertNil(viewModel.pendingPreference)
    }

    func testDeniedAuthorizationOpensSettingsWithoutMutatingValue() async {
        var openSettingsCount = 0
        let viewModel = NotificationSettingsViewModel(
            dependencies: makeDependencies(
                status: .denied,
                openSystemSettings: { openSettingsCount += 1 }
            )
        )
        await viewModel.refreshAuthorizationStatus()

        XCTAssertNil(
            viewModel.resolvedValue(for: true, preference: .discovery)
        )
        XCTAssertEqual(openSettingsCount, 1)
        XCTAssertFalse(viewModel.showPermissionPrompt)
    }

    func testAuthorizedToggleResolvesImmediatelyAndDisableAlwaysWorks() async {
        let viewModel = NotificationSettingsViewModel(
            dependencies: makeDependencies(status: .authorized)
        )
        await viewModel.refreshAuthorizationStatus()

        XCTAssertEqual(
            viewModel.resolvedValue(for: true, preference: .achievements),
            true
        )
        XCTAssertEqual(
            viewModel.resolvedValue(for: false, preference: .achievements),
            false
        )
    }

    func testRemoteRegistrationUsesStableReasons() async {
        var reasons: [String] = []
        let viewModel = NotificationSettingsViewModel(
            dependencies: makeDependencies(
                status: .authorized,
                syncRemoteRegistration: { reasons.append($0) }
            )
        )

        await viewModel.syncPreferenceChange(.explore)
        await viewModel.syncEnabledAfterAuthorization(
            .communityIdentifications
        )
        await viewModel.syncAllDisabledIfNeeded(false)
        await viewModel.syncAllDisabledIfNeeded(true)

        XCTAssertEqual(
            reasons,
            [
                "explore_setting_changed",
                "community_identifications_setting_enabled_after_authorization",
                "all_notification_settings_disabled"
            ]
        )
    }

    func testOlderAuthorizationRefreshCannotOverwriteNewerStatus() async {
        var pendingRefreshes: [
            CheckedContinuation<UNAuthorizationStatus, Never>
        ] = []
        let viewModel = NotificationSettingsViewModel(
            dependencies: NotificationSettingsDependencies(
                fetchAuthorizationStatus: {
                    await withCheckedContinuation {
                        pendingRefreshes.append($0)
                    }
                },
                openSystemSettings: {},
                syncRemoteRegistration: { _ in }
            )
        )

        let olderTask = Task {
            await viewModel.refreshAuthorizationStatus()
        }
        while pendingRefreshes.count < 1 {
            await Task.yield()
        }

        let newerTask = Task {
            await viewModel.refreshAuthorizationStatus()
        }
        while pendingRefreshes.count < 2 {
            await Task.yield()
        }

        pendingRefreshes[1].resume(returning: .authorized)
        await newerTask.value
        XCTAssertEqual(viewModel.authorizationStatus, .authorized)

        pendingRefreshes[0].resume(returning: .denied)
        await olderTask.value
        XCTAssertEqual(viewModel.authorizationStatus, .authorized)
    }

    private func makeDependencies(
        status: UNAuthorizationStatus,
        openSystemSettings: @escaping @MainActor () -> Void = {},
        syncRemoteRegistration: @escaping @MainActor (
            String
        ) async -> Void = { _ in }
    ) -> NotificationSettingsDependencies {
        NotificationSettingsDependencies(
            fetchAuthorizationStatus: { status },
            openSystemSettings: openSystemSettings,
            syncRemoteRegistration: syncRemoteRegistration
        )
    }
}
