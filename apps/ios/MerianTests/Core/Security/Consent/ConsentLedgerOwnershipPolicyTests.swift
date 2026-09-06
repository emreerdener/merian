import Foundation
@testable import Merian
import XCTest

@MainActor
final class ConsentLedgerOwnershipPolicyTests: ConsentManagerTestCase {
    func testRebindingMovesEveryGhostOwnedRecordAndReapprovalFence() {
        let ghostUserId = UUID()
        let permanentUserId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_786_200_000)
        let source = ConsentManager.LocalLedger(
            activeUserId: ghostUserId,
            termsReceipts: [makeTermsReceipt(
                ownerUserId: ghostUserId,
                recordedAt: recordedAt
            )],
            aiConsentEvents: [makeAIConsentEvent(
                ownerUserId: ghostUserId,
                recordedAt: recordedAt,
                consentRevision: 11
            )],
            adultEligibilityReceipts: [makeAdultReceipt(
                ownerUserId: ghostUserId,
                recordedAt: recordedAt
            )],
            analyticsConsentEvents: [makeAnalyticsEvent(
                ownerUserId: ghostUserId,
                eventKind: .granted,
                recordedAt: recordedAt
            )],
            requiredConsentReapprovalUserIds: [ghostUserId]
        )

        let rebound = ConsentLedgerOwnershipPolicy.rebinding(
            source,
            from: ghostUserId,
            to: permanentUserId
        )

        XCTAssertEqual(rebound.activeUserId, permanentUserId)
        XCTAssertEqual(
            rebound.adultEligibilityReceipts.map(\.ownerUserId),
            [permanentUserId]
        )
        XCTAssertEqual(
            rebound.adultEligibilityReceipts.map(\.syncedUserId),
            [permanentUserId]
        )
        XCTAssertEqual(
            rebound.termsReceipts.map(\.ownerUserId),
            [permanentUserId]
        )
        XCTAssertEqual(
            rebound.aiConsentEvents.map(\.ownerUserId),
            [permanentUserId]
        )
        XCTAssertEqual(
            rebound.analyticsConsentEvents.map(\.ownerUserId),
            [permanentUserId]
        )
        XCTAssertEqual(
            rebound.requiredConsentReapprovalUserIds,
            [permanentUserId]
        )
        XCTAssertEqual(
            ConsentManager.rebinding(
                rebound,
                from: ghostUserId,
                to: permanentUserId
            ),
            rebound
        )
    }

    func testJournalRebindingPreservesSynchronizedAndPendingState() throws {
        let ghostUserId = UUID()
        let permanentUserId = UUID()
        let unrelatedUserId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_786_200_000)
        let synchronized = makeAnalyticsEvent(
            ownerUserId: ghostUserId,
            eventKind: .revoked,
            recordedAt: recordedAt
        )
        var pending = makeAnalyticsEvent(
            ownerUserId: ghostUserId,
            eventKind: .revoked,
            recordedAt: recordedAt.addingTimeInterval(1)
        )
        pending.syncedUserId = nil
        pending.recordedAt = nil
        let unrelated = makeAnalyticsEvent(
            ownerUserId: unrelatedUserId,
            eventKind: .revoked,
            recordedAt: recordedAt
        )
        let source = ConsentManager.AnalyticsRevocationJournal(
            intents: [
                .init(event: synchronized),
                .init(event: pending),
                .init(event: unrelated)
            ]
        )

        let rebound = try XCTUnwrap(
            ConsentLedgerOwnershipPolicy.rebindingAnalyticsRevocationJournal(
                source,
                from: ghostUserId,
                to: permanentUserId
            )
        )

        XCTAssertEqual(rebound.intents[0].event.ownerUserId, permanentUserId)
        XCTAssertEqual(rebound.intents[0].event.syncedUserId, permanentUserId)
        XCTAssertEqual(rebound.intents[1].event.ownerUserId, permanentUserId)
        XCTAssertNil(rebound.intents[1].event.syncedUserId)
        XCTAssertEqual(rebound.intents[2].event, unrelated)
        XCTAssertNil(
            ConsentLedgerOwnershipPolicy
                .rebindingAnalyticsRevocationJournal(
                    source,
                    from: UUID(),
                    to: permanentUserId
                )
        )
    }
}
