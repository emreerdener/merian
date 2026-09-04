import Combine
import Foundation
@testable import Merian
import Testing

@MainActor
struct AppDIContainerTests {
    @Test func testSharedInstanceUnification() {
        let sharedContainerA = AppDIContainer.shared
        let sharedContainerB = AppDIContainer.shared
        
        // Because these contain critical heavy references (InferenceEngine, HardwareOrchestrator)
        // fetching shared across the app must mathematically return the exact same memory pointer structure.
        let isIdentical = sharedContainerA === sharedContainerB
        #expect(isIdentical == true, "AppDIContainer broke singleton rules. Multiple instantiations found.")
    }
    
    @Test func testMockPreviewInitialization() {
        let previewA = AppDIContainer.preview
        let previewB = AppDIContainer.preview
        
        // Mock init creates independent containers manually each time to prevent preview artifacts from permanently locking memory
        let isIdentical = previewA === previewB
        #expect(isIdentical == false, "AppDIContainer.preview shouldn't leak singletons to parallel SwiftUI macro previews")

        #expect(previewA.appEventPublisher !== previewB.appEventPublisher)
        #expect(previewA.appRouteCoordinator !== previewB.appRouteCoordinator)
        #expect(previewA.milestoneToastPresenter !== previewB.milestoneToastPresenter)
        #expect(previewA.milestoneToastHostRegistry !== previewB.milestoneToastHostRegistry)
        #expect(previewA.appRouteCoordinator !== AppDIContainer.shared.appRouteCoordinator)
        #expect(previewA.milestoneToastPresenter !== AppDIContainer.shared.milestoneToastPresenter)
        
        // Assert it constructs valid structural bindings
        #expect(previewA.hardwareOrchestrator === HardwareOrchestrator.shared)
    }

    @Test func testExploreLaunchPresentationRequiresOnboardingAndOptIn() {
        #expect(!AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: false,
            opensExploreOnLaunch: true
        ))
        #expect(!AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: true,
            opensExploreOnLaunch: false
        ))
        #expect(AppLaunchPresentationPolicy.shouldOpenExplore(
            hasCompletedOnboarding: true,
            opensExploreOnLaunch: true
        ))
    }

    @Test func testRootPresentationWaitsForRequiredConsentRestoration() {
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: false,
            hasCurrentRequiredConsent: false,
            isRestoringRequiredConsent: true
        ) == .onboarding)
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: true,
            hasCurrentRequiredConsent: false,
            isRestoringRequiredConsent: true
        ) == .restoringConsent)
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: true,
            hasCurrentRequiredConsent: true,
            isRestoringRequiredConsent: true
        ) == .workspace)
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: true,
            hasCurrentRequiredConsent: false,
            isRestoringRequiredConsent: false
        ) == .onboarding)
    }

    @Test func testManualAppleRevocationNoticePersistsUntilExplicitResolution() {
        let suiteName = "merian.tests.apple-revocation-notice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let eventPublisher = AppEventPublisher()
        var receivedNotice = false
        let cancellable = eventPublisher.publisher.sink { event in
            if case .manualAppleRevocationNoticeRequired = event {
                receivedNotice = true
            }
        }
        defer { cancellable.cancel() }

        ManualAppleRevocationNoticeStore.record(
            userDefaults: defaults,
            eventSender: eventPublisher
        )
        #expect(ManualAppleRevocationNoticeStore.isPending(userDefaults: defaults))
        #expect(receivedNotice)

        ManualAppleRevocationNoticeStore.resolve(userDefaults: defaults)
        #expect(!ManualAppleRevocationNoticeStore.isPending(userDefaults: defaults))
    }

    @Test func testAccountDeletionLocalCleanupPersistsUntilResolution() {
        let suiteName = "merian.tests.account-deletion-cleanup.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let events = AppEventPublisher()
        var recoveryInvalidations = 0
        let cancellable = events.publisher.sink { event in
            if case .accountDeletionRecoveryStateChanged = event {
                recoveryInvalidations += 1
            }
        }
        defer { cancellable.cancel() }

        #expect(!AccountDeletionLocalCleanupStore.isPending(userDefaults: defaults))
        #expect(
            AccountDeletionLocalCleanupStore.recordIntakePending(
                userDefaults: defaults,
                eventSender: events
            )
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .capabilityIntakePending
        )
        #expect(
            AccountDeletionLocalCleanupStore.recordCleanupPending(
                userDefaults: defaults,
                eventSender: events
            )
        )
        #expect(AccountDeletionLocalCleanupStore.isPending(userDefaults: defaults))
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .capabilityCleanupPending
        )
        #expect(
            AccountDeletionLocalCleanupStore
                .recordCapabilityRetirementPending(
                    userDefaults: defaults,
                    eventSender: events
                )
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .capabilityRetirementPending
        )
        #expect(
            AccountDeletionLocalCleanupStore
                .recordCapabilityRejectionRetirementPending(
                    userDefaults: defaults,
                    eventSender: events
                )
        )
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .capabilityRejectionRetirementPending
        )
        #expect(
            AccountDeletionLocalCleanupStore.resolve(
                userDefaults: defaults,
                eventSender: events
            )
        )
        #expect(!AccountDeletionLocalCleanupStore.isPending(userDefaults: defaults))
        #expect(recoveryInvalidations == 5)
    }

    @Test func testLegacyAcceptedReceiptUsesCapabilityFreeCleanupState() {
        let suiteName = "AccountDeletionCleanupStore.Compat.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(AccountDeletionLocalCleanupStore.record(userDefaults: defaults))
        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .cleanupPending
        )
    }

    @Test func testLegacyAccountDeletionBooleanMigratesAsAcceptedCleanup() throws {
        let suiteName = "AccountDeletionCleanupStore.Legacy.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            true,
            forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        )

        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .cleanupPending
        )
    }

    @Test func testUnknownAccountDeletionStateFailsClosedBeforeLocalErasure() throws {
        let suiteName = "AccountDeletionCleanupStore.Unknown.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            "future_state",
            forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        )

        #expect(
            AccountDeletionLocalCleanupStore.state(userDefaults: defaults)
                == .intakePending
        )
    }
}
