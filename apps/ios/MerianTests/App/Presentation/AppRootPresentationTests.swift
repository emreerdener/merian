@testable import Merian
import Testing

@Suite("App root presentation")
struct AppRootPresentationTests {
    @Test func exploreLaunchRequiresOnboardingAndOptIn() {
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

    @Test func rootWaitsForRequiredConsentRestoration() {
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

    @Test func configurationWarningPreservesStoreRecoveryNotice() throws {
        let notice = StartupRecoveryNotice(
            title: "Library Repaired",
            message: "Recovered safely.",
            diagnosticText: "diagnostic"
        )

        let combined = try #require(StartupRecoveryNoticePolicy.combined(
            storeNotice: notice,
            configurationIssues: [.missingValue("SUPABASE_URL")]
        ))

        #expect(combined.title == "Library Repaired")
        #expect(combined.message ==
            "Recovered safely.\n\nConfiguration warnings: SUPABASE_URL is missing or empty.")
        #expect(combined.diagnosticText == "diagnostic")
    }

    @Test func configurationWarningCanStandAlone() throws {
        let combined = try #require(StartupRecoveryNoticePolicy.combined(
            storeNotice: nil,
            configurationIssues: [.missingValue("SUPABASE_URL")]
        ))

        #expect(combined.title == "Configuration Warning")
        #expect(combined.message ==
            "Configuration warnings: SUPABASE_URL is missing or empty.")
        #expect(combined.diagnosticText == nil)
    }
}
