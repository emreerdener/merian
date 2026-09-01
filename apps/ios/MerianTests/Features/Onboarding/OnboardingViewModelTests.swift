@testable import Merian
import Foundation
import Testing
import XCTest

@MainActor
final class OnboardingViewModelTests: ConsentManagerTestCase {
    private var viewModel: OnboardingViewModel!

    override func setUp() {
        super.setUp()
        viewModel = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: consentManager,
            resumeConsentBlockedScan: { _ in nil }
        )
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    func testInitialStateIsWelcome() {
        XCTAssertEqual(viewModel.currentStep, .welcome, "ViewModel should strictly start at the .welcome step on cold boot.")
        XCTAssertFalse(viewModel.hasCompletedOnboarding, "AppStorage bypass flag should explicitly be false initially.")
    }


    func testAdvanceStepProgression() {
        // Initial boundary is welcome
        XCTAssertEqual(viewModel.currentStep, .welcome)

        // Sequence: welcome -> camera
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .camera)

        // Sequence: camera -> location
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .location)

        // Sequence: location -> ready
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .ready)

        // Attempting to advance past .ready should securely trap without crashing Swift's Int boundary indices natively.
        viewModel.advanceStep()
        XCTAssertEqual(viewModel.currentStep, .ready, "ViewModel should actively trap progression at .ready boundary without out-of-bounds scalar execution crashes.")
    }

    func testCompleteOnboarding() throws {
        // Assume user advanced sequentially to completion
        viewModel.currentStep = .ready

        // Fire completion
        try viewModel.completeOnboarding(analyticsEnabled: false)

        // Verify AppStorage binding actually triggers the physical override
        XCTAssertTrue(viewModel.hasCompletedOnboarding, "The completeOnboarding physical action MUST explicitly flip the global teardown flag in SwiftUI memory.")
        XCTAssertTrue(userDefaults.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding), "The injected defaults mapping must confirm persistence for WindowGroup reconfiguration on next launch.")
        XCTAssertTrue(consentManager.hasConfirmedCurrentAdultEligibility)
        XCTAssertTrue(consentManager.hasAcceptedCurrentTerms)
        XCTAssertTrue(consentManager.hasGrantedCurrentGeminiProcessing)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertTrue(consentManager.hasCurrentRequiredConsent)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 3)

        let restoredManager = ConsentManager(userDefaults: userDefaults)
        XCTAssertTrue(restoredManager.hasCurrentRequiredConsent)
        XCTAssertFalse(restoredManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(restoredManager.pendingCloudRecordCount, 3)
    }

    func testOnboardingDoesNotCompleteUntilLedgerWriteIsVerified() throws {
        let store = FaultInjectingConsentLedgerStore()
        store.failLedgerWrites = true
        let manager = ConsentManager(ledgerStore: store)
        let model = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: manager
        )
        model.currentStep = .ready

        XCTAssertThrowsError(
            try model.completeOnboarding(analyticsEnabled: false)
        )
        XCTAssertFalse(model.hasCompletedOnboarding)
        XCTAssertFalse(manager.hasCurrentRequiredConsent)
        XCTAssertNil(store.ledgerData)

        store.failLedgerWrites = false
        try model.completeOnboarding(analyticsEnabled: false)

        XCTAssertTrue(model.hasCompletedOnboarding)
        XCTAssertTrue(manager.hasCurrentRequiredConsent)
        XCTAssertNotNil(store.ledgerData)
    }


    func testPriorDisclosureVersionsReturnCompletedBetaUserToReadyStep() throws {
        let now = Date()
        let priorLedger = ConsentManager.LocalLedger(
            activeUserId: nil,
            termsReceipts: [
                ConsentManager.TermsAcceptanceReceipt(
                    id: UUID(),
                    ownerUserId: nil,
                    syncedUserId: nil,
                    termsVersion: ConsentPolicy.termsVersion,
                    acceptedAt: now,
                    acceptanceText: ConsentPolicy.combinedAcceptanceText,
                    platform: "ios",
                    appVersion: "1.0.3",
                    appBuild: "275",
                    recordedAt: nil
                )
            ],
            aiConsentEvents: [
                ConsentManager.AIConsentEvent(
                    id: UUID(),
                    ownerUserId: nil,
                    syncedUserId: nil,
                    provider: ConsentPolicy.geminiProvider,
                    disclosureVersion: "2026-08-03.1",
                    eventKind: .granted,
                    occurredAt: now,
                    disclosureText: "Prior internal-test disclosure",
                    actionText: ConsentPolicy.combinedAcceptanceText,
                    platform: "ios",
                    appVersion: "1.0.3",
                    appBuild: "275",
                    recordedAt: nil
                )
            ],
            adultEligibilityReceipts: [
                ConsentManager.AdultEligibilityReceipt(
                    id: UUID(),
                    ownerUserId: nil,
                    syncedUserId: nil,
                    policyVersion: ConsentPolicy.adultEligibilityVersion,
                    confirmedAt: now,
                    confirmationMethod: .selfAttestation,
                    confirmationText: ConsentPolicy.adultConfirmationText,
                    platform: "ios",
                    appVersion: "1.0.3",
                    appBuild: "275",
                    recordedAt: nil
                )
            ],
            analyticsConsentEvents: [
                ConsentManager.AnalyticsConsentEvent(
                    id: UUID(),
                    ownerUserId: nil,
                    syncedUserId: nil,
                    provider: ConsentPolicy.analyticsProvider,
                    disclosureVersion: "2026-08-03",
                    eventKind: .granted,
                    occurredAt: now,
                    disclosureText: "Prior internal-test disclosure",
                    actionText: "Prior internal-test grant",
                    platform: "ios",
                    appVersion: "1.0.3",
                    appBuild: "275",
                    recordedAt: nil
                )
            ]
        )
        userDefaults.set(
            try JSONEncoder().encode(priorLedger),
            forKey: UserDefaultsKeys.legalConsentLedger
        )
        appSettings.hasCompletedOnboarding = true

        let restoredManager = ConsentManager(userDefaults: userDefaults)
        let restoredViewModel = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: restoredManager
        )

        XCTAssertTrue(restoredManager.hasConfirmedCurrentAdultEligibility)
        XCTAssertTrue(restoredManager.hasAcceptedCurrentTerms)
        XCTAssertFalse(restoredManager.hasGrantedCurrentGeminiProcessing)
        XCTAssertFalse(restoredManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertFalse(restoredManager.hasCurrentRequiredConsent)
        XCTAssertEqual(restoredViewModel.currentStep, .ready)
    }

    func testLegacyCompletionRoutesDirectlyToCurrentConsentStep() {
        appSettings.hasCompletedOnboarding = true

        let legacyViewModel = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: consentManager
        )

        XCTAssertEqual(legacyViewModel.currentStep, .ready)
    }

    func testOptionalAnalyticsGrantAndWithdrawalNeverCloseRequiredGate() throws {
        viewModel.currentStep = .ready
        try viewModel.completeOnboarding(analyticsEnabled: true)

        XCTAssertTrue(consentManager.hasCurrentRequiredConsent)
        XCTAssertTrue(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 4)

        try consentManager.setPostHogAnalyticsEnabled(false)

        XCTAssertTrue(consentManager.hasCurrentRequiredConsent)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 5)

        let restoredManager = ConsentManager(userDefaults: userDefaults)
        XCTAssertTrue(restoredManager.hasCurrentRequiredConsent)
        XCTAssertFalse(restoredManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(restoredManager.pendingCloudRecordCount, 5)
    }

}

@Suite("Onboarding Consent Recovery Tests", .serialized)
@MainActor
struct OnboardingConsentRecoveryTests {
    @Test func testCompleteOnboardingResumesConsentBlockedScanForCurrentAccount() throws {
        let suiteName = "merian.tests.onboarding.consent-recovery.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let appSettings = AppSettings(
            userDefaults: userDefaults,
            observeExternalChanges: false
        )
        let consentManager = ConsentManager(userDefaults: userDefaults)
        appSettings.hasCompletedOnboarding = false

        let accountId = UUID()
        consentManager.observeSession(userId: accountId)
        var resumedAccountIds: [UUID] = []
        var lifecycleGateWasOpen = false
        let model = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: consentManager,
            resumeConsentBlockedScan: { resumedAccountId in
                resumedAccountIds.append(resumedAccountId)
                lifecycleGateWasOpen = appSettings.hasCompletedOnboarding
                return "saved-scan-id"
            }
        )

        try model.completeOnboarding(analyticsEnabled: false)

        #expect(resumedAccountIds == [accountId])
        #expect(lifecycleGateWasOpen)
        #expect(model.hasCompletedOnboarding)
        #expect(consentManager.hasCurrentRequiredConsent)
    }

    @Test func testCompleteOnboardingDoesNotResumeWithoutCurrentAccount() throws {
        let suiteName = "merian.tests.onboarding.consent-recovery.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let appSettings = AppSettings(
            userDefaults: userDefaults,
            observeExternalChanges: false
        )
        let consentManager = ConsentManager(userDefaults: userDefaults)
        appSettings.hasCompletedOnboarding = false

        var resumeAttemptCount = 0
        let model = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: consentManager,
            resumeConsentBlockedScan: { _ in
                resumeAttemptCount += 1
                return "unexpected-scan-id"
            }
        )

        try model.completeOnboarding(analyticsEnabled: false)

        #expect(resumeAttemptCount == 0)
        #expect(model.hasCompletedOnboarding)
        #expect(consentManager.hasCurrentRequiredConsent)
    }
}
