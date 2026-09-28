import Foundation
import Testing

@testable import Merian

@Suite("What's New launch")
struct WhatsNewLaunchTests {
    @Test func existingInstallShowsUntilAcknowledgedThenWaitsForNewHighlights() throws {
        try withStore { store in
            #expect(prepare(store))
            #expect(prepare(store)) // Launching alone never consumes the announcement.
            store.acknowledge()
            #expect(!prepare(store))
            let nextRelease = WhatsNewLaunchStore(
                defaults: store.defaults,
                releaseID: "next-highlights"
            )
            #expect(prepare(nextRelease))
        }
    }

    @Test func freshInstallSkipsCurrentHighlightsAfterOnboarding() throws {
        try withStore { store in
            #expect(!store.prepareLaunch(
                hasCompletedOnboarding: false,
                isRunningTests: false,
                hasStartupInterruption: false
            ))
            #expect(!prepare(store))
        }
    }

    @Test func recoveryDefersWithoutAcknowledging() throws {
        try withStore { store in
            #expect(!store.prepareLaunch(
                hasCompletedOnboarding: true,
                isRunningTests: false,
                hasStartupInterruption: true
            ))
            #expect(prepare(store))
        }
    }

    @Test func testProcessesDoNotReadOrConsumeLiveAnnouncementState() throws {
        try withStore { store in
            #expect(!store.prepareLaunch(
                hasCompletedOnboarding: false,
                isRunningTests: true,
                hasStartupInterruption: false
            ))
            #expect(store.defaults.string(
                forKey: UserDefaultsKeys.lastSeenWhatsNewRelease
            ) == nil)
            #expect(prepare(store))
        }
    }

    @Test func onboardingAndConsentRemainAheadOfAnnouncement() {
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: false,
            hasCurrentRequiredConsent: true,
            isRestoringRequiredConsent: false
        ) == .onboarding)
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: true,
            hasCurrentRequiredConsent: false,
            isRestoringRequiredConsent: true
        ) == .restoringConsent)
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: true,
            hasCurrentRequiredConsent: false,
            isRestoringRequiredConsent: false
        ) == .onboarding)
        #expect(AppRootPresentationPolicy.presentation(
            hasCompletedOnboarding: true,
            hasCurrentRequiredConsent: true,
            isRestoringRequiredConsent: false
        ) == .workspace)
    }

    private func prepare(_ store: WhatsNewLaunchStore) -> Bool {
        store.prepareLaunch(
            hasCompletedOnboarding: true,
            isRunningTests: false,
            hasStartupInterruption: false
        )
    }

    private func withStore(_ body: (WhatsNewLaunchStore) -> Void) throws {
        let suiteName = "WhatsNewLaunchTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(WhatsNewLaunchStore(defaults: defaults))
    }
}
