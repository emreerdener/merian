import Foundation
@testable import Merian
import XCTest

@MainActor
final class AccountDeletionTransitionPolicyTests: XCTestCase {
    func testAccountDeletionTreatsOtherHTTPFailuresAsAmbiguous() {
        let unauthorized = MerianError.httpError(
            statusCode: 401,
            message: #"{"code":"invalid_session"}"#
        )
        let unrelatedConflict = MerianError.httpError(
            statusCode: 409,
            message: #"{"code":"account_deletion_conflict"}"#
        )
        let serverFailure = MerianError.httpError(
            statusCode: 503,
            message: #"{"code":"temporarily_unavailable"}"#
        )

        XCTAssertFalse(
            AccountDeletionTransitionPolicy
                .isDefinitiveIntakeRejection(unauthorized)
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy
                .isDefinitiveIntakeRejection(unrelatedConflict)
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy
                .isDefinitiveIntakeRejection(serverFailure)
        )
    }

    func testOnlyMatchedExpiredRecoveryProvesDeletionWasAccepted() {
        let matchedExpiry = MerianError.httpError(
            statusCode: 410,
            message: #"{"code":"account_deletion_recovery_expired"}"#
        )
        let wrongStatus = MerianError.httpError(
            statusCode: 404,
            message: #"{"code":"account_deletion_recovery_expired"}"#
        )
        let unknownProof = MerianError.httpError(
            statusCode: 404,
            message: #"{"code":"account_deletion_recovery_invalid"}"#
        )
        let expiredPreparation = MerianError.httpError(
            statusCode: 410,
            message: #"{"code":"account_deletion_recovery_preparation_expired"}"#
        )

        XCTAssertTrue(
            AccountDeletionTransitionPolicy
                .isAcceptedExpiredRecovery(matchedExpiry)
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy
                .isAcceptedExpiredRecovery(wrongStatus)
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy
                .isAcceptedExpiredRecovery(unknownProof)
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy
                .isAcceptedExpiredRecovery(expiredPreparation)
        )
    }

    func testOnlyExactUnknownRecoveryIsClassified() {
        let unknownProof = MerianError.httpError(
            statusCode: 404,
            message: #"{"code":"account_deletion_recovery_invalid"}"#
        )
        let wrongStatus = MerianError.httpError(
            statusCode: 410,
            message: #"{"code":"account_deletion_recovery_invalid"}"#
        )
        let wrongCode = MerianError.httpError(
            statusCode: 404,
            message: #"{"code":"account_deletion_recovery_expired"}"#
        )

        XCTAssertTrue(
            AccountDeletionTransitionPolicy.isUnknownRecovery(unknownProof)
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy.isUnknownRecovery(wrongStatus)
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy.isUnknownRecovery(wrongCode)
        )
    }

    func testDeletionBarrierRestoresOnlyTheExactCachedSourceSession() {
        let sourceUserID = UUID()
        let otherUserID = UUID()
        let source = AuthTransitionSession(
            userID: sourceUserID,
            isAnonymous: false
        )

        XCTAssertTrue(
            AccountDeletionTransitionPolicy.canRestoreDeferredBarrierSession(
                markerIsPending: true,
                sourceSession: source,
                cachedUserID: sourceUserID,
                cachedUserIsAnonymous: false,
                cachedSessionIsExpired: false
            )
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy.canRestoreDeferredBarrierSession(
                markerIsPending: false,
                sourceSession: source,
                cachedUserID: sourceUserID,
                cachedUserIsAnonymous: false,
                cachedSessionIsExpired: false
            )
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy.canRestoreDeferredBarrierSession(
                markerIsPending: true,
                sourceSession: source,
                cachedUserID: otherUserID,
                cachedUserIsAnonymous: false,
                cachedSessionIsExpired: false
            )
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy.canRestoreDeferredBarrierSession(
                markerIsPending: true,
                sourceSession: source,
                cachedUserID: sourceUserID,
                cachedUserIsAnonymous: true,
                cachedSessionIsExpired: false
            )
        )
        XCTAssertFalse(
            AccountDeletionTransitionPolicy.canRestoreDeferredBarrierSession(
                markerIsPending: true,
                sourceSession: source,
                cachedUserID: sourceUserID,
                cachedUserIsAnonymous: false,
                cachedSessionIsExpired: true
            )
        )
    }
}
