import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentStateProjectionPolicyTests: ConsentManagerTestCase {
    func testCurrentOwnerSelectionFencesAnObservedSignedOutSession() {
        let persistedUserId = UUID(
            uuidString: "55555555-5555-4555-8555-555555555555"
        )!
        let sessionUserId = UUID(
            uuidString: "66666666-6666-4666-8666-666666666666"
        )!

        XCTAssertEqual(
            ConsentStateProjectionPolicy.currentOwnerUserId(
                currentSessionUserId: nil,
                hasObservedSession: false,
                ledgerActiveUserId: persistedUserId
            ),
            persistedUserId
        )
        XCTAssertNil(
            ConsentStateProjectionPolicy.currentOwnerUserId(
                currentSessionUserId: nil,
                hasObservedSession: true,
                ledgerActiveUserId: persistedUserId
            )
        )
        XCTAssertEqual(
            ConsentStateProjectionPolicy.currentOwnerUserId(
                currentSessionUserId: sessionUserId,
                hasObservedSession: true,
                ledgerActiveUserId: persistedUserId
            ),
            sessionUserId
        )
    }

    func testCurrentStateSeparatesRequiredReapprovalFromAnalyticsConsent() {
        let userId = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
        let recordedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let ledger = ConsentManager.LocalLedger(
            activeUserId: userId,
            termsReceipts: [
                makeTermsReceipt(ownerUserId: userId, recordedAt: recordedAt)
            ],
            aiConsentEvents: [
                makeAIConsentEvent(
                    ownerUserId: userId,
                    recordedAt: recordedAt,
                    consentRevision: 1
                )
            ],
            adultEligibilityReceipts: [
                makeAdultReceipt(ownerUserId: userId, recordedAt: recordedAt)
            ],
            analyticsConsentEvents: [
                makeAnalyticsEvent(
                    ownerUserId: userId,
                    eventKind: .granted,
                    recordedAt: recordedAt
                )
            ]
        )

        let current = ConsentStateProjectionPolicy.currentState(
            ledger: ledger,
            ownerUserId: userId,
            inMemoryReapprovalUserIds: [],
            isLedgerStorageUncertain: false,
            isRevocationIntentStorageUncertain: false,
            isAnalyticsWithdrawalInProgress: false,
            pendingAnalyticsRevocationApplies: false
        )
        XCTAssertTrue(current.hasConfirmedAdultEligibility)
        XCTAssertTrue(current.hasAcceptedTerms)
        XCTAssertTrue(current.hasGrantedGeminiProcessing)
        XCTAssertTrue(current.hasGrantedPostHogAnalytics)

        let requiringApproval = ConsentStateProjectionPolicy.currentState(
            ledger: ledger,
            ownerUserId: userId,
            inMemoryReapprovalUserIds: [userId],
            isLedgerStorageUncertain: false,
            isRevocationIntentStorageUncertain: false,
            isAnalyticsWithdrawalInProgress: false,
            pendingAnalyticsRevocationApplies: false
        )
        XCTAssertFalse(requiringApproval.hasConfirmedAdultEligibility)
        XCTAssertFalse(requiringApproval.hasAcceptedTerms)
        XCTAssertFalse(requiringApproval.hasGrantedGeminiProcessing)
        XCTAssertTrue(requiringApproval.hasGrantedPostHogAnalytics)
    }

    func testPendingCountExcludesSyncedSupersededAndOtherAccountRecords() {
        let userId = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
        let otherUserId = UUID(
            uuidString: "99999999-9999-4999-8999-999999999999"
        )!
        let recordedAt = Date(timeIntervalSince1970: 1_760_000_000)

        var pendingAdult = makeAdultReceipt(
            ownerUserId: userId,
            recordedAt: recordedAt
        )
        pendingAdult.syncedUserId = nil
        var pendingAI = makeAIConsentEvent(
            ownerUserId: userId,
            recordedAt: recordedAt,
            consentRevision: 1
        )
        pendingAI.syncedUserId = nil
        var supersededAI = pendingAI
        supersededAI.supersededByEventId = UUID()
        var pendingAnalytics = makeAnalyticsEvent(
            ownerUserId: userId,
            eventKind: .granted,
            recordedAt: recordedAt
        )
        pendingAnalytics.syncedUserId = nil
        var otherAccountTerms = makeTermsReceipt(
            ownerUserId: otherUserId,
            recordedAt: recordedAt
        )
        otherAccountTerms.syncedUserId = nil

        let ledger = ConsentManager.LocalLedger(
            activeUserId: userId,
            termsReceipts: [
                makeTermsReceipt(
                    ownerUserId: userId,
                    recordedAt: recordedAt
                ),
                otherAccountTerms
            ],
            aiConsentEvents: [pendingAI, supersededAI],
            adultEligibilityReceipts: [pendingAdult],
            analyticsConsentEvents: [pendingAnalytics]
        )

        XCTAssertEqual(
            ConsentStateProjectionPolicy.pendingCloudRecordCount(in: ledger),
            3
        )
    }

    func testAnalyticsPermissionRequiresMatchingResolvedAuthority() {
        let userId = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let permission = ConsentStateProjectionPolicy.analyticsPermission(
            ledgerActiveUserId: userId,
            currentSessionUserId: userId,
            isSuppressedForGhostHandoff: false,
            isSuppressedForAccountTransition: false,
            cloudAuthorityState: .resolvedRemote(
                userId: userId,
                granted: true
            ),
            isLedgerStorageUncertain: false,
            isRevocationIntentStorageUncertain: false,
            isAnalyticsWithdrawalInProgress: false,
            pendingAnalyticsRevocationApplies: false,
            hasGrantedPostHogAnalytics: true
        )
        XCTAssertEqual(
            permission,
            .init(isEnabled: true, ownerUserId: userId)
        )

        let mismatched = ConsentStateProjectionPolicy.analyticsPermission(
            ledgerActiveUserId: userId,
            currentSessionUserId: UUID(),
            isSuppressedForGhostHandoff: false,
            isSuppressedForAccountTransition: false,
            cloudAuthorityState: .resolvedRemote(
                userId: userId,
                granted: true
            ),
            isLedgerStorageUncertain: false,
            isRevocationIntentStorageUncertain: false,
            isAnalyticsWithdrawalInProgress: false,
            pendingAnalyticsRevocationApplies: false,
            hasGrantedPostHogAnalytics: true
        )
        XCTAssertEqual(
            mismatched,
            .init(isEnabled: false, ownerUserId: nil)
        )
    }
}
