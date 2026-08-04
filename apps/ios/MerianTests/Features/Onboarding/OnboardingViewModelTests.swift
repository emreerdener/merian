@testable import Merian
import SwiftUI
import XCTest

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    
    var viewModel: OnboardingViewModel!
    var appSettings: AppSettings!
    var consentManager: ConsentManager!
    var userDefaults: UserDefaults!
    var suiteName: String!
    
    override func setUp() {
        super.setUp()
        suiteName = "merian.tests.onboarding.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        appSettings = AppSettings(userDefaults: userDefaults, observeExternalChanges: false)
        consentManager = ConsentManager(userDefaults: userDefaults)
        appSettings.hasCompletedOnboarding = false
        viewModel = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: consentManager
        )
    }
    
    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        viewModel = nil
        appSettings = nil
        consentManager = nil
        userDefaults = nil
        suiteName = nil
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
    
    func testCompleteOnboarding() {
        // Assume user advanced sequentially to completion
        viewModel.currentStep = .ready
        
        // Fire completion
        viewModel.completeOnboarding(analyticsEnabled: false)
        
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

    func testReadyStepMatchesStoredConsentCopyAndPurposeBeforeConsent() {
        let disclosure = ReadyStepView.disclosure
        let consent = ReadyStepView.consentStatement
        let adult = ReadyStepView.adultStatement
        let analytics = ReadyStepView.analyticsStatement

        XCTAssertEqual(disclosure, ConsentPolicy.geminiDisclosureText)
        XCTAssertEqual(consent, ConsentPolicy.combinedAcceptanceText)
        XCTAssertEqual(adult, ConsentPolicy.adultConfirmationText)
        XCTAssertEqual(analytics, ConsentPolicy.analyticsDisclosureText)

        let completeSurface = [disclosure, consent, adult, analytics].joined(separator: " ")
        for requiredDisclosure in [
            "observation data",
            "terms",
            "Google Gemini",
            "AI-powered identification",
            "18 or older",
            "usage and diagnostics",
            "improve Naturebook"
        ] {
            XCTAssertTrue(
                completeSurface.contains(requiredDisclosure),
                "Ready-step disclosure must identify its recipient, data, and purpose: \(requiredDisclosure)"
            )
        }
    }

    func testEveryReadySwitchCombinationKeepsAnalyticsOptional() {
        for adultConfirmed in [false, true] {
            for geminiAllowed in [false, true] {
                for analyticsAllowed in [false, true] {
                    XCTAssertEqual(
                        ReadyStepView.canStartScanning(
                            adultConfirmed: adultConfirmed,
                            geminiAllowed: geminiAllowed,
                            analyticsAllowed: analyticsAllowed
                        ),
                        adultConfirmed && geminiAllowed
                    )
                }
            }
        }
    }

    func testReadyTermsLinkTargetsTheFullTermsOfService() throws {
        let statement = ReadyStepView.linkedConsentStatement
        let termsRange = try XCTUnwrap(statement.range(of: "terms"))

        XCTAssertEqual(statement[termsRange].link, ReadyStepView.termsURL)
        XCTAssertTrue(ReadyStepView.termsURL.absoluteString.hasSuffix("/terms"))
    }

    func testReadyRequiredConsentStatementsEndWithRedAsterisk() throws {
        let statements = [
            ReadyStepView.appendingRequiredIndicator(
                to: AttributedString(ReadyStepView.adultStatement)
            ),
            ReadyStepView.linkedConsentStatement
        ]

        for statement in statements {
            XCTAssertTrue(
                String(statement.characters).hasSuffix(ReadyStepView.requiredIndicator)
            )
            let indicatorRange = try XCTUnwrap(statement.range(of: "*"))
            XCTAssertEqual(statement[indicatorRange].foregroundColor, Color.red)
        }

        XCTAssertFalse(ReadyStepView.analyticsStatement.hasSuffix("*"))
    }

    func testLegacyCompletionRoutesDirectlyToCurrentConsentStep() {
        appSettings.hasCompletedOnboarding = true

        let legacyViewModel = OnboardingViewModel(
            appSettings: appSettings,
            consentManager: consentManager
        )

        XCTAssertEqual(legacyViewModel.currentStep, .ready)
    }

    func testGeminiWithdrawalIsPersistedAndClosesConsentGate() {
        consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: false
        )
        consentManager.withdrawGeminiPermission()

        XCTAssertTrue(consentManager.hasConfirmedCurrentAdultEligibility)
        XCTAssertTrue(consentManager.hasAcceptedCurrentTerms)
        XCTAssertFalse(consentManager.hasGrantedCurrentGeminiProcessing)
        XCTAssertFalse(consentManager.hasCurrentRequiredConsent)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 4)

        let restoredManager = ConsentManager(userDefaults: userDefaults)
        XCTAssertFalse(restoredManager.hasCurrentRequiredConsent)
        XCTAssertEqual(restoredManager.pendingCloudRecordCount, 4)
    }

    func testOptionalAnalyticsGrantAndWithdrawalNeverCloseRequiredGate() {
        viewModel.currentStep = .ready
        viewModel.completeOnboarding(analyticsEnabled: true)

        XCTAssertTrue(consentManager.hasCurrentRequiredConsent)
        XCTAssertTrue(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 4)

        consentManager.setPostHogAnalyticsEnabled(false)

        XCTAssertTrue(consentManager.hasCurrentRequiredConsent)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 5)

        let restoredManager = ConsentManager(userDefaults: userDefaults)
        XCTAssertTrue(restoredManager.hasCurrentRequiredConsent)
        XCTAssertFalse(restoredManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertEqual(restoredManager.pendingCloudRecordCount, 5)
    }

    func testAccountSwitchNeverInheritsPriorAccountConsent() {
        let firstUserId = UUID()
        let secondUserId = UUID()
        consentManager.observeSession(userId: firstUserId)
        consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: true
        )

        XCTAssertTrue(consentManager.hasCurrentRequiredConsent)
        XCTAssertTrue(consentManager.hasGrantedCurrentPostHogAnalytics)

        consentManager.observeSession(userId: secondUserId)

        XCTAssertFalse(consentManager.hasConfirmedCurrentAdultEligibility)
        XCTAssertFalse(consentManager.hasAcceptedCurrentTerms)
        XCTAssertFalse(consentManager.hasGrantedCurrentGeminiProcessing)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
        XCTAssertFalse(consentManager.hasCurrentRequiredConsent)

        consentManager.observeSession(userId: nil)
        XCTAssertFalse(consentManager.hasCurrentRequiredConsent)
        XCTAssertFalse(consentManager.hasGrantedCurrentPostHogAnalytics)
    }
}
