@testable import Merian
import Foundation
import XCTest

@MainActor
final class ConsentManagerReapprovalTests: ConsentManagerTestCase {
    func testServerConsentRejectionDurablyReturnsUserToReadyAndRecordsFreshEvidence() throws {
        let ownerUserId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_786_100_000)
        let adultReceipt = makeAdultReceipt(
            ownerUserId: ownerUserId,
            recordedAt: recordedAt
        )
        let termsReceipt = makeTermsReceipt(
            ownerUserId: ownerUserId,
            recordedAt: recordedAt
        )
        let aiGrant = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            recordedAt: recordedAt,
            consentRevision: 12
        )
        let store = FaultInjectingConsentLedgerStore()
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: ownerUserId,
                termsReceipts: [termsReceipt],
                aiConsentEvents: [aiGrant],
                adultEligibilityReceipts: [adultReceipt],
                analyticsConsentEvents: []
            )
        )
        let manager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { _, _ in }
        )
        manager.observeSession(userId: ownerUserId)
        XCTAssertTrue(manager.hasCurrentRequiredConsent)

        XCTAssertTrue(
            try manager.requireCurrentConsentReapprovalAfterServerRejection()
        )

        XCTAssertFalse(manager.hasConfirmedCurrentAdultEligibility)
        XCTAssertFalse(manager.hasAcceptedCurrentTerms)
        XCTAssertFalse(manager.hasGrantedCurrentGeminiProcessing)
        XCTAssertFalse(manager.hasCurrentRequiredConsent)
        XCTAssertEqual(
            manager.requiredConsentRestorationState,
            .reconciling(userId: ownerUserId)
        )
        let fencedLedger = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: try XCTUnwrap(store.ledgerData)
        )
        XCTAssertTrue(
            fencedLedger.requiredConsentReapprovalUserIds.contains(ownerUserId)
        )

        let restarted = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { ownerUserId },
            analyticsPermissionApplier: { _, _ in }
        )
        restarted.observeSession(userId: ownerUserId)
        try restarted.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: adultReceipt,
                termsReceipt: termsReceipt,
                aiConsentEvent: aiGrant,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: aiGrant,
                analyticsConsentStreamHead: nil
            ),
            for: ownerUserId,
            generation: 1
        )
        XCTAssertFalse(restarted.hasCurrentRequiredConsent)
        XCTAssertEqual(restarted.requiredConsentRestorationState, .resolved)
        XCTAssertEqual(
            AppRootPresentationPolicy.presentation(
                hasCompletedOnboarding: true,
                hasCurrentRequiredConsent: restarted.hasCurrentRequiredConsent,
                isRestoringRequiredConsent: restarted.isRestoringRequiredConsent
            ),
            .onboarding
        )
        appSettings.hasCompletedOnboarding = true
        XCTAssertEqual(
            OnboardingViewModel(
                appSettings: appSettings,
                consentManager: restarted
            ).currentStep,
            .ready
        )

        try restarted.confirmAdultAndAcceptCurrentTermsAndGrantGemini(
            analyticsEnabled: false
        )

        XCTAssertTrue(restarted.hasCurrentRequiredConsent)
        XCTAssertEqual(restarted.pendingCloudRecordCount, 3)
        let reapprovedLedger = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: try XCTUnwrap(store.ledgerData)
        )
        XCTAssertFalse(
            reapprovedLedger.requiredConsentReapprovalUserIds.contains(ownerUserId)
        )
        XCTAssertEqual(reapprovedLedger.adultEligibilityReceipts.count, 2)
        let newAdultReceipt = try XCTUnwrap(
            reapprovedLedger.adultEligibilityReceipts.first {
                $0.id != adultReceipt.id
            }
        )
        XCTAssertNil(newAdultReceipt.syncedUserId)
        XCTAssertNil(newAdultReceipt.recordedAt)
        XCTAssertEqual(reapprovedLedger.termsReceipts.count, 2)
        let newTermsReceipt = try XCTUnwrap(
            reapprovedLedger.termsReceipts.first { $0.id != termsReceipt.id }
        )
        XCTAssertNil(newTermsReceipt.syncedUserId)
        XCTAssertNil(newTermsReceipt.recordedAt)
        XCTAssertEqual(reapprovedLedger.aiConsentEvents.count, 2)
        let newAIGrant = try XCTUnwrap(
            reapprovedLedger.aiConsentEvents.first { $0.id != aiGrant.id }
        )
        XCTAssertNil(newAIGrant.syncedUserId)
        XCTAssertNil(newAIGrant.recordedAt)
        XCTAssertNil(newAIGrant.consentRevision)
        XCTAssertEqual(newAIGrant.causalParentId, aiGrant.id)
    }

    func testServerConsentReapprovalFenceDoesNotCrossAccounts() throws {
        let rejectedUserId = UUID()
        let unaffectedUserId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_786_100_000)
        let rejectedAdultReceipt = makeAdultReceipt(
            ownerUserId: rejectedUserId,
            recordedAt: recordedAt
        )
        let rejectedTermsReceipt = makeTermsReceipt(
            ownerUserId: rejectedUserId,
            recordedAt: recordedAt
        )
        let rejectedAIGrant = makeAIConsentEvent(
            ownerUserId: rejectedUserId,
            recordedAt: recordedAt,
            consentRevision: 12
        )
        let unaffectedAdultReceipt = makeAdultReceipt(
            ownerUserId: unaffectedUserId,
            recordedAt: recordedAt
        )
        let unaffectedTermsReceipt = makeTermsReceipt(
            ownerUserId: unaffectedUserId,
            recordedAt: recordedAt
        )
        let unaffectedAIGrant = makeAIConsentEvent(
            ownerUserId: unaffectedUserId,
            recordedAt: recordedAt,
            consentRevision: 13
        )
        let store = FaultInjectingConsentLedgerStore()
        store.ledgerData = try JSONEncoder().encode(
            ConsentManager.LocalLedger(
                activeUserId: rejectedUserId,
                termsReceipts: [
                    rejectedTermsReceipt,
                    unaffectedTermsReceipt
                ],
                aiConsentEvents: [rejectedAIGrant, unaffectedAIGrant],
                adultEligibilityReceipts: [
                    rejectedAdultReceipt,
                    unaffectedAdultReceipt
                ],
                analyticsConsentEvents: []
            )
        )
        let rejectedManager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { rejectedUserId },
            analyticsPermissionApplier: { _, _ in }
        )
        rejectedManager.observeSession(userId: rejectedUserId)

        XCTAssertTrue(
            try rejectedManager
                .requireCurrentConsentReapprovalAfterServerRejection()
        )
        XCTAssertFalse(rejectedManager.hasCurrentRequiredConsent)

        let unaffectedManager = ConsentManager(
            ledgerStore: store,
            currentSDKUserIdProvider: { unaffectedUserId },
            analyticsPermissionApplier: { _, _ in }
        )
        unaffectedManager.observeSession(userId: unaffectedUserId)
        try unaffectedManager.merge(
            ConsentManager.RemoteState(
                adultEligibilityReceipt: unaffectedAdultReceipt,
                termsReceipt: unaffectedTermsReceipt,
                aiConsentEvent: unaffectedAIGrant,
                analyticsConsentEvent: nil,
                aiConsentStreamHead: unaffectedAIGrant,
                analyticsConsentStreamHead: nil
            ),
            for: unaffectedUserId,
            generation: 1
        )

        XCTAssertTrue(unaffectedManager.hasCurrentRequiredConsent)
        XCTAssertEqual(
            unaffectedManager.requiredConsentRestorationState,
            .resolved
        )
        let persistedLedger = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: try XCTUnwrap(store.ledgerData)
        )
        XCTAssertEqual(
            persistedLedger.requiredConsentReapprovalUserIds,
            [rejectedUserId]
        )
    }

    func testRequiredConsentCloudProofUsesFetchedProviderStreamHead() {
        let ownerUserId = UUID()
        let recordedAt = Date(timeIntervalSince1970: 1_786_100_000)
        let adultReceipt = makeAdultReceipt(
            ownerUserId: ownerUserId,
            recordedAt: recordedAt
        )
        let termsReceipt = makeTermsReceipt(
            ownerUserId: ownerUserId,
            recordedAt: recordedAt
        )
        let aiGrant = makeAIConsentEvent(
            ownerUserId: ownerUserId,
            recordedAt: recordedAt,
            consentRevision: 5
        )
        let completeState = ConsentManager.RemoteState(
            adultEligibilityReceipt: adultReceipt,
            termsReceipt: termsReceipt,
            aiConsentEvent: aiGrant,
            analyticsConsentEvent: nil,
            aiConsentStreamHead: aiGrant,
            analyticsConsentStreamHead: nil
        )

        XCTAssertTrue(
            ConsentManager.isAuthoritativeRequiredConsent(
                completeState,
                for: ownerUserId
            )
        )
        XCTAssertFalse(
            ConsentManager.isAuthoritativeRequiredConsent(
                completeState,
                for: UUID()
            )
        )
        XCTAssertFalse(
            ConsentManager.isAuthoritativeRequiredConsent(
                ConsentManager.RemoteState(
                    adultEligibilityReceipt: adultReceipt,
                    termsReceipt: termsReceipt,
                    aiConsentEvent: aiGrant,
                    analyticsConsentEvent: nil,
                    aiConsentStreamHead: nil,
                    analyticsConsentStreamHead: nil
                ),
                for: ownerUserId
            )
        )
    }

    func testExistingLedgerWithoutReapprovalFenceDecodesAsUnfenced() throws {
        let currentData = try JSONEncoder().encode(
            ConsentManager.LocalLedger.empty
        )
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: currentData)
                as? [String: Any]
        )
        legacyObject.removeValue(forKey: "requiredConsentReapprovalUserIds")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

        let decoded = try JSONDecoder().decode(
            ConsentManager.LocalLedger.self,
            from: legacyData
        )

        XCTAssertTrue(decoded.requiredConsentReapprovalUserIds.isEmpty)
    }

}
