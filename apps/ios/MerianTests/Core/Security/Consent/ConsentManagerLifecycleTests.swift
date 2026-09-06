import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentManagerLifecycleTests: ConsentManagerTestCase {
    func testGeminiWithdrawalIsPersistedAndClosesConsentGate() throws {
        try consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: false
        )
        try consentManager.withdrawGeminiPermission()

        XCTAssertTrue(consentManager.hasConfirmedCurrentAdultEligibility)
        XCTAssertTrue(consentManager.hasAcceptedCurrentTerms)
        XCTAssertFalse(consentManager.hasGrantedCurrentGeminiProcessing)
        XCTAssertFalse(consentManager.hasCurrentRequiredConsent)
        XCTAssertEqual(consentManager.pendingCloudRecordCount, 4)

        let restoredManager = ConsentManager(userDefaults: userDefaults)
        XCTAssertFalse(restoredManager.hasCurrentRequiredConsent)
        XCTAssertEqual(restoredManager.pendingCloudRecordCount, 4)
    }

    func testAccountSwitchNeverInheritsPriorAccountConsent() throws {
        let firstUserId = UUID()
        let secondUserId = UUID()
        consentManager.observeSession(userId: firstUserId)
        try consentManager.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
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
