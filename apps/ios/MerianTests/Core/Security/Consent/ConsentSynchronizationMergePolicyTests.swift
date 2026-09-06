import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentSynchronizationMergePolicyTests: ConsentManagerTestCase {
    func testMergeUpsertsRemoteEvidenceAndDerivesAuthoritativeState() {
        let userId = UUID()
        let otherUserId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_788_000_000)
        let adultReceipt = makeAdultReceipt(
            ownerUserId: userId,
            recordedAt: recordedAt
        )
        let termsReceipt = makeTermsReceipt(
            ownerUserId: userId,
            recordedAt: recordedAt.addingTimeInterval(1)
        )
        let aiEvent = makeAIConsentEvent(
            ownerUserId: userId,
            recordedAt: recordedAt.addingTimeInterval(2),
            consentRevision: 7
        )
        let analyticsEvent = makeAnalyticsEvent(
            ownerUserId: userId,
            eventKind: .granted,
            recordedAt: recordedAt.addingTimeInterval(3)
        )

        var staleAdultReceipt = adultReceipt
        staleAdultReceipt.syncedUserId = nil
        staleAdultReceipt.recordedAt = nil
        var staleTermsReceipt = termsReceipt
        staleTermsReceipt.syncedUserId = nil
        staleTermsReceipt.recordedAt = nil
        var staleAIEvent = aiEvent
        staleAIEvent.syncedUserId = nil
        staleAIEvent.recordedAt = nil
        staleAIEvent.consentRevision = nil
        var staleAnalyticsEvent = analyticsEvent
        staleAnalyticsEvent.syncedUserId = nil
        staleAnalyticsEvent.recordedAt = nil

        let unrelatedReceipt = makeAdultReceipt(
            ownerUserId: otherUserId,
            recordedAt: recordedAt.addingTimeInterval(-1)
        )
        let ledger = ConsentManager.LocalLedger(
            activeUserId: otherUserId,
            termsReceipts: [staleTermsReceipt],
            aiConsentEvents: [staleAIEvent],
            adultEligibilityReceipts: [
                unrelatedReceipt,
                staleAdultReceipt
            ],
            analyticsConsentEvents: [staleAnalyticsEvent]
        )
        let remoteState = ConsentManager.RemoteState(
            adultEligibilityReceipt: adultReceipt,
            termsReceipt: termsReceipt,
            aiConsentEvent: aiEvent,
            analyticsConsentEvent: analyticsEvent,
            aiConsentStreamHead: aiEvent,
            analyticsConsentStreamHead: analyticsEvent
        )

        let result = ConsentSynchronizationMergePolicy.merging(
            remoteState,
            into: ledger,
            for: userId
        )

        XCTAssertEqual(result.ledger.activeUserId, userId)
        XCTAssertEqual(
            result.ledger.adultEligibilityReceipts,
            [unrelatedReceipt, adultReceipt]
        )
        XCTAssertEqual(result.ledger.termsReceipts, [termsReceipt])
        XCTAssertEqual(result.ledger.aiConsentEvents, [aiEvent])
        XCTAssertEqual(
            result.ledger.analyticsConsentEvents,
            [analyticsEvent]
        )
        XCTAssertTrue(result.hasAuthoritativeRequiredConsent)
        XCTAssertEqual(
            result.analyticsCloudAuthorityState,
            .resolvedRemote(userId: userId, granted: true)
        )
        XCTAssertEqual(
            result.requiredConsentReapprovalAIStreamHeadId,
            aiEvent.id
        )
    }

    func testEmptyRemoteStateRetainsAuditEvidenceButClosesCloudAuthority() {
        let previousUserId = UUID()
        let currentUserId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_788_000_100)
        let priorReceipt = makeAdultReceipt(
            ownerUserId: previousUserId,
            recordedAt: recordedAt
        )
        let ledger = ConsentManager.LocalLedger(
            activeUserId: previousUserId,
            termsReceipts: [],
            aiConsentEvents: [],
            adultEligibilityReceipts: [priorReceipt],
            analyticsConsentEvents: []
        )

        let result = ConsentSynchronizationMergePolicy.merging(
            .init(
                adultEligibilityReceipt: nil,
                termsReceipt: nil,
                aiConsentEvent: nil,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: nil,
                analyticsConsentStreamHead: nil
            ),
            into: ledger,
            for: currentUserId
        )

        XCTAssertEqual(result.ledger.activeUserId, currentUserId)
        XCTAssertEqual(result.ledger.adultEligibilityReceipts, [priorReceipt])
        XCTAssertFalse(result.hasAuthoritativeRequiredConsent)
        XCTAssertEqual(
            result.analyticsCloudAuthorityState,
            .resolvedRemote(userId: currentUserId, granted: false)
        )
        XCTAssertNil(result.requiredConsentReapprovalAIStreamHeadId)
    }
}
