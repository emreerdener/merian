import Foundation
@testable import Merian
import XCTest

@MainActor
final class PurchaseIdentitySignOutWorkflowTests: XCTestCase {
    func testUserSignOutTransitionInitializesOneAnonymousSessionAfterSignOut() async {
        var steps: [String] = []
        var initializationCount = 0

        let isReady = await PurchaseIdentitySignOutWorkflow
            .performUserSignOutTransition(
                performSignOut: {
                    steps.append("signOut")
                },
                initializeAnonymousSession: {
                    steps.append("initializeAnonymousSession")
                    initializationCount += 1
                    return true
                }
            )

        XCTAssertTrue(isReady)
        XCTAssertEqual(initializationCount, 1)
        XCTAssertEqual(steps, ["signOut", "initializeAnonymousSession"])
    }

    func testUserSignOutTransitionPropagatesAnonymousSessionFailure() async {
        let isReady = await PurchaseIdentitySignOutWorkflow
            .performUserSignOutTransition(
                performSignOut: {},
                initializeAnonymousSession: { false }
            )

        XCTAssertFalse(isReady)
    }

    func testPurchaseSafeSignOutPersistsBeforeClosingAndCompletingIdentity() async {
        var steps: [String] = []

        let isReady = await PurchaseIdentitySignOutWorkflow
            .performPurchaseSafeSignOutTransition(
                prepareAndPersistHandoff: {
                    steps.append("prepareAndPersist")
                },
                performSignOut: {
                    steps.append("signOut")
                },
                initializeAnonymousSession: {
                    steps.append("initializeAnonymousSession")
                    return true
                },
                completeHandoff: {
                    steps.append("completeHandoff")
                },
                reportFailure: { error in
                    XCTFail("Unexpected sign-out failure: \(error)")
                }
            )

        XCTAssertTrue(isReady)
        XCTAssertEqual(
            steps,
            [
                "prepareAndPersist",
                "signOut",
                "initializeAnonymousSession",
                "completeHandoff"
            ]
        )
    }

    func testPurchaseSafeSignOutNeverClosesSessionWhenPreparationFails() async {
        var didSignOut = false
        var didInitialize = false
        var reportedError: Error?

        let isReady = await PurchaseIdentitySignOutWorkflow
            .performPurchaseSafeSignOutTransition(
                prepareAndPersistHandoff: {
                    throw SupabaseAuthTransitionError
                        .signOutPurchaseHandoffPersistenceFailed
                },
                performSignOut: {
                    didSignOut = true
                },
                initializeAnonymousSession: {
                    didInitialize = true
                    return true
                },
                completeHandoff: {},
                reportFailure: { reportedError = $0 }
            )

        XCTAssertFalse(isReady)
        XCTAssertFalse(didSignOut)
        XCTAssertFalse(didInitialize)
        guard let reportedError =
            reportedError as? SupabaseAuthTransitionError,
            case .signOutPurchaseHandoffPersistenceFailed = reportedError else {
            return XCTFail("Expected the preparation error to be reported")
        }
    }

    func testPurchaseSafeSignOutPropagatesDurableCompletionFailure() async {
        var didComplete = false
        var reportedError: Error?

        let isReady = await PurchaseIdentitySignOutWorkflow
            .performPurchaseSafeSignOutTransition(
                prepareAndPersistHandoff: {},
                performSignOut: {},
                initializeAnonymousSession: { true },
                completeHandoff: {
                    didComplete = true
                    throw SupabaseAuthTransitionError
                        .signOutPurchaseContinuityPending
                },
                reportFailure: { reportedError = $0 }
            )

        XCTAssertFalse(isReady)
        XCTAssertTrue(didComplete)
        guard let reportedError =
            reportedError as? SupabaseAuthTransitionError,
            case .signOutPurchaseContinuityPending = reportedError else {
            return XCTFail("Expected the completion error to be reported")
        }
    }

    func testSignOutPurchaseFinalizationClearsProofOnlyAfterEveryCheck() async throws {
        var steps: [String] = []

        try await PurchaseIdentitySignOutWorkflow
            .finalizeSignOutPurchaseHandoff(
                bindDestination: { steps.append("bind") },
                verifyBoundDestinationSession: {
                    steps.append("verifyBoundSession")
                },
                linkProviderIdentity: { steps.append("link") },
                verifyLinkedDestinationSession: {
                    steps.append("verifyLinkedSession")
                },
                synchronizeStorePurchases: {
                    steps.append("syncPurchases")
                },
                completeServerHandoff: { steps.append("complete") },
                refreshServerEntitlement: {
                    steps.append("refreshEntitlement")
                    return true
                },
                verifyFinalDestinationSession: {
                    steps.append("verifyFinalSession")
                },
                clearPendingHandoff: { steps.append("clearProof") }
            )

        XCTAssertEqual(
            steps,
            [
                "bind",
                "verifyBoundSession",
                "link",
                "verifyLinkedSession",
                "syncPurchases",
                "complete",
                "refreshEntitlement",
                "verifyFinalSession",
                "clearProof"
            ]
        )
    }

    func testSignOutPurchaseFinalizationRetainsProofAfterSyncFailure() async {
        var steps: [String] = []

        do {
            try await PurchaseIdentitySignOutWorkflow
                .finalizeSignOutPurchaseHandoff(
                    bindDestination: { steps.append("bind") },
                    verifyBoundDestinationSession: {
                        steps.append("verifyBoundSession")
                    },
                    linkProviderIdentity: { steps.append("link") },
                    verifyLinkedDestinationSession: {
                        steps.append("verifyLinkedSession")
                    },
                    synchronizeStorePurchases: {
                        steps.append("syncPurchases")
                        throw URLError(.networkConnectionLost)
                    },
                    completeServerHandoff: { steps.append("complete") },
                    refreshServerEntitlement: {
                        steps.append("refreshEntitlement")
                        return true
                    },
                    verifyFinalDestinationSession: {
                        steps.append("verifyFinalSession")
                    },
                    clearPendingHandoff: { steps.append("clearProof") }
                )
            XCTFail("Expected receipt synchronization failure")
        } catch {
            XCTAssertEqual(
                (error as? URLError)?.code,
                .networkConnectionLost
            )
        }

        XCTAssertEqual(
            steps,
            [
                "bind",
                "verifyBoundSession",
                "link",
                "verifyLinkedSession",
                "syncPurchases"
            ]
        )
        XCTAssertFalse(steps.contains("clearProof"))
    }

    func testSignOutPurchaseFinalizationRetainsProofAfterCancellation() async {
        var steps: [String] = []

        let wasCancelled = await Task { @MainActor in
            do {
                try await PurchaseIdentitySignOutWorkflow
                    .finalizeSignOutPurchaseHandoff(
                        bindDestination: {
                            steps.append("bind")
                            withUnsafeCurrentTask { task in
                                task?.cancel()
                            }
                        },
                        verifyBoundDestinationSession: {
                            steps.append("verifyBoundSession")
                        },
                        linkProviderIdentity: { steps.append("link") },
                        verifyLinkedDestinationSession: {
                            steps.append("verifyLinkedSession")
                        },
                        synchronizeStorePurchases: {
                            steps.append("syncPurchases")
                        },
                        completeServerHandoff: { steps.append("complete") },
                        refreshServerEntitlement: { true },
                        verifyFinalDestinationSession: {},
                        clearPendingHandoff: { steps.append("clearProof") }
                    )
                return false
            } catch is CancellationError {
                return true
            } catch {
                XCTFail("Expected CancellationError, received \(error)")
                return false
            }
        }.value

        XCTAssertTrue(wasCancelled)
        XCTAssertEqual(steps, ["bind"])
        XCTAssertFalse(steps.contains("clearProof"))
    }

    func testSignOutPurchaseFinalizationRejectsPreflightCancellationBeforeBinding() async {
        var steps: [String] = []

        let wasCancelled = await Task { @MainActor in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            do {
                try await PurchaseIdentitySignOutWorkflow
                    .finalizeSignOutPurchaseHandoff(
                        bindDestination: { steps.append("bind") },
                        verifyBoundDestinationSession: {
                            steps.append("verifyBoundSession")
                        },
                        linkProviderIdentity: { steps.append("link") },
                        verifyLinkedDestinationSession: {
                            steps.append("verifyLinkedSession")
                        },
                        synchronizeStorePurchases: {
                            steps.append("syncPurchases")
                        },
                        completeServerHandoff: {
                            steps.append("complete")
                        },
                        refreshServerEntitlement: { true },
                        verifyFinalDestinationSession: {},
                        clearPendingHandoff: {
                            steps.append("clearProof")
                        }
                    )
                return false
            } catch is CancellationError {
                return true
            } catch {
                XCTFail("Expected CancellationError, received \(error)")
                return false
            }
        }.value

        XCTAssertTrue(wasCancelled)
        XCTAssertTrue(steps.isEmpty)
    }

    func testSignOutPurchaseFinalizationRefusesStaleSessionBeforeProviderLink() async {
        var steps: [String] = []

        do {
            try await PurchaseIdentitySignOutWorkflow
                .finalizeSignOutPurchaseHandoff(
                    bindDestination: { steps.append("bind") },
                    verifyBoundDestinationSession: {
                        steps.append("verifyBoundSession")
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    },
                    linkProviderIdentity: { steps.append("link") },
                    verifyLinkedDestinationSession: {
                        steps.append("verifyLinkedSession")
                    },
                    synchronizeStorePurchases: {
                        steps.append("syncPurchases")
                    },
                    completeServerHandoff: { steps.append("complete") },
                    refreshServerEntitlement: { true },
                    verifyFinalDestinationSession: {},
                    clearPendingHandoff: { steps.append("clearProof") }
                )
            XCTFail("Expected stale destination rejection")
        } catch {
            guard let transitionError =
                error as? SupabaseAuthTransitionError else {
                return XCTFail("Expected an auth-transition error")
            }
            guard case .signOutSessionChanged = transitionError else {
                return XCTFail("Expected stale destination rejection")
            }
        }

        XCTAssertEqual(steps, ["bind", "verifyBoundSession"])
    }
}
