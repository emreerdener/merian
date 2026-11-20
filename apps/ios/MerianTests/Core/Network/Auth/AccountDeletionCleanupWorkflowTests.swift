@testable import Merian
import XCTest

@MainActor
final class AccountDeletionCleanupWorkflowTests: XCTestCase {
    func testLostContextBeforeCleanupNeverStartsSignOut() async {
        var events: [String] = []
        let signOut: @MainActor () async -> Bool = { events.append("sign-out"); return true }
        let purge: @MainActor () async -> Bool = { events.append("purge"); return true }
        let retire: @MainActor () -> Bool = { events.append("retire"); return true }
        let resolve: @MainActor () -> Bool = { events.append("resolve"); return true }
        let accepted = await AccountDeletionWorkflow.performAcceptedCleanup(
            validateContext: { false },
            receipt: AccountDeletionReceipt(success: true, status: .pending, manualProviderRevocationRequired: false),
            recordCleanupPending: { events.append("record"); return true },
            recordManualProviderRevocation: {}, performLocalSignOut: signOut, purgeLocalData: purge,
            acknowledgeRecovery: { events.append("acknowledge"); return true },
            recordRecoveryRetirementPending: retire, retireRecoveryCapability: retire, resolveCleanup: resolve
        )
        let retirement = await AccountDeletionWorkflow.performRecoveryRetirement(
            validateContext: { false }, performLocalSignOut: signOut, purgeLocalData: purge,
            retireRecoveryCapability: retire, resolveCleanup: resolve
        )
        let legacy = await AccountDeletionWorkflow.performPendingLocalCleanup(
            validateContext: { false }, performLocalSignOut: signOut, purgeLocalData: purge, resolveCleanup: resolve
        )
        XCTAssertFalse(accepted)
        XCTAssertFalse(retirement)
        XCTAssertFalse(legacy)
        XCTAssertEqual(events, ["record"])
    }

    func testCleanupRejectsReceiptsThatDoNotProveAcceptedDeletion() async {
        let invalidReceipts = [
            AccountDeletionReceipt(
                success: false,
                status: .pending,
                manualProviderRevocationRequired: false
            ),
            AccountDeletionReceipt(
                success: true,
                status: .prepared,
                manualProviderRevocationRequired: false
            ),
            AccountDeletionReceipt(
                success: true,
                status: .notCommitted,
                manualProviderRevocationRequired: false,
                protocolVersion: 2
            )
        ]

        for receipt in invalidReceipts {
            var events: [String] = []
            let result = await AccountDeletionWorkflow.performAcceptedCleanup(
                validateContext: { true },
                receipt: receipt,
                recordCleanupPending: {
                    events.append("record")
                    return true
                },
                recordManualProviderRevocation: {
                    events.append("manual")
                },
                performLocalSignOut: {
                    events.append("signout")
                    return true
                },
                purgeLocalData: {
                    events.append("purge")
                    return true
                },
                acknowledgeRecovery: {
                    events.append("acknowledge")
                    return true
                },
                recordRecoveryRetirementPending: {
                    events.append("record-retirement")
                    return true
                },
                retireRecoveryCapability: {
                    events.append("retire-capability")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )

            XCTAssertFalse(result)
            XCTAssertTrue(events.isEmpty)
        }
    }

    func testAcceptedAccountDeletionPersistsRecoveryBeforeSignOutAndClearsLast() async {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .pending,
            manualProviderRevocationRequired: true
        )

        let result = await AccountDeletionWorkflow.performAcceptedCleanup(
            validateContext: { true },
            receipt: receipt,
            recordCleanupPending: {
                events.append("record")
                return true
            },
            recordManualProviderRevocation: { events.append("manual") },
            performLocalSignOut: {
                events.append("signout")
                return true
            },
            purgeLocalData: {
                events.append("purge")
                return true
            },
            acknowledgeRecovery: {
                events.append("acknowledge")
                return true
            },
            recordRecoveryRetirementPending: {
                events.append("record-retirement")
                return true
            },
            retireRecoveryCapability: {
                events.append("retire-capability")
                return true
            },
            resolveCleanup: {
                events.append("resolve")
                return true
            }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(
            events,
            [
                "record",
                "manual",
                "signout",
                "purge",
                "acknowledge",
                "record-retirement",
                "retire-capability",
                "resolve"
            ]
        )
    }

    func testAccountDeletionAcknowledgementFailureRetainsProofAndMarker() async {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .completed,
            manualProviderRevocationRequired: false
        )

        let result = await AccountDeletionWorkflow.performAcceptedCleanup(
            validateContext: { true },
            receipt: receipt,
            recordCleanupPending: {
                events.append("record")
                return true
            },
            recordManualProviderRevocation: { events.append("manual") },
            performLocalSignOut: {
                events.append("signout")
                return true
            },
            purgeLocalData: {
                events.append("purge")
                return true
            },
            acknowledgeRecovery: {
                events.append("acknowledge")
                return false
            },
            recordRecoveryRetirementPending: {
                events.append("record-retirement")
                return true
            },
            retireRecoveryCapability: {
                events.append("retire-capability")
                return true
            },
            resolveCleanup: {
                events.append("resolve")
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(
            events,
            ["record", "signout", "purge", "acknowledge"]
        )
    }

    func testAccountDeletionRetirementReverifiesCleanupAndClearsProofBeforeMarker() async {
        var events: [String] = []
        let completedRetirement = await AccountDeletionWorkflow
            .performRecoveryRetirement(
                validateContext: { true },
                performLocalSignOut: {
                    events.append("signout")
                    return true
                },
                purgeLocalData: {
                    events.append("purge")
                    return true
                },
                retireRecoveryCapability: {
                    events.append("retire-capability")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )
        XCTAssertTrue(completedRetirement)
        XCTAssertEqual(
            events,
            ["signout", "purge", "retire-capability", "resolve"]
        )

        events.removeAll()
        let incompleteRetirement = await AccountDeletionWorkflow
            .performRecoveryRetirement(
                validateContext: { true },
                performLocalSignOut: { true },
                purgeLocalData: { true },
                retireRecoveryCapability: {
                    events.append("retire-capability")
                    return false
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )
        XCTAssertFalse(incompleteRetirement)
        XCTAssertEqual(events, ["retire-capability"])
    }

    func testRejectedAccountDeletionRetiresOnlyProof() {
        var events: [String] = []

        XCTAssertTrue(
            AccountDeletionWorkflow.retireRejectedRecoveryProof {
                events.append("retire-capability")
                return true
            }
        )
        XCTAssertEqual(events, ["retire-capability"])

        events.removeAll()
        XCTAssertFalse(
            AccountDeletionWorkflow.retireRejectedRecoveryProof {
                events.append("retire-capability")
                return false
            }
        )
        XCTAssertEqual(events, ["retire-capability"])
    }

    func testDefinitiveDeletionRejectionPersistsRetirementBeforeProofRemoval() {
        var events: [String] = []

        XCTAssertTrue(
            AccountDeletionWorkflow
                .performDefinitiveIntakeRejectionRetirement(
                    recordRejectionRetirementPending: {
                        events.append("record-rejection-retirement")
                        return true
                    },
                    retireRecoveryCapability: {
                        events.append("retire-capability")
                        return true
                    },
                    resolveCleanup: {
                        events.append("resolve")
                        return true
                    }
                )
        )
        XCTAssertEqual(
            events,
            [
                "record-rejection-retirement",
                "retire-capability",
                "resolve"
            ]
        )

        events.removeAll()
        XCTAssertFalse(
            AccountDeletionWorkflow
                .performDefinitiveIntakeRejectionRetirement(
                    recordRejectionRetirementPending: {
                        events.append("record-rejection-retirement")
                        return false
                    },
                    retireRecoveryCapability: {
                        events.append("retire-capability")
                        return true
                    },
                    resolveCleanup: {
                        events.append("resolve")
                        return true
                    }
                )
        )
        XCTAssertEqual(events, ["record-rejection-retirement"])

        events.removeAll()
        XCTAssertFalse(
            AccountDeletionWorkflow
                .performDefinitiveIntakeRejectionRetirement(
                    recordRejectionRetirementPending: {
                        events.append("record-rejection-retirement")
                        return true
                    },
                    retireRecoveryCapability: {
                        events.append("retire-capability")
                        return false
                    },
                    resolveCleanup: {
                        events.append("resolve")
                        return true
                    }
                )
        )
        XCTAssertEqual(
            events,
            ["record-rejection-retirement", "retire-capability"]
        )
    }

    func testAccountDeletionKeepsRecoveryPendingWhenMarkerRemovalFails() async {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .completed,
            manualProviderRevocationRequired: false
        )

        let result = await AccountDeletionWorkflow.performAcceptedCleanup(
            validateContext: { true },
            receipt: receipt,
            recordCleanupPending: { true },
            recordManualProviderRevocation: {},
            performLocalSignOut: { true },
            purgeLocalData: { true },
            acknowledgeRecovery: { true },
            recordRecoveryRetirementPending: { true },
            retireRecoveryCapability: {
                events.append("retire-capability")
                return true
            },
            resolveCleanup: {
                events.append("resolve")
                return false
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(events, ["retire-capability", "resolve"])
    }

    func testFailedAccountDeletionPurgeLeavesRecoveryMarkerPending() async {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .completed,
            manualProviderRevocationRequired: false
        )

        let result = await AccountDeletionWorkflow.performAcceptedCleanup(
            validateContext: { true },
            receipt: receipt,
            recordCleanupPending: {
                events.append("record")
                return true
            },
            recordManualProviderRevocation: { events.append("manual") },
            performLocalSignOut: {
                events.append("signout")
                return true
            },
            purgeLocalData: {
                events.append("purge")
                return false
            },
            acknowledgeRecovery: {
                events.append("acknowledge")
                return true
            },
            recordRecoveryRetirementPending: {
                events.append("record-retirement")
                return true
            },
            retireRecoveryCapability: {
                events.append("retire-capability")
                return true
            },
            resolveCleanup: {
                events.append("resolve")
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(events, ["record", "signout", "purge"])
    }

    func testAcceptedAccountDeletionDoesNotEraseLocalStateWhenRecoveryPersistenceFails() async {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .pending,
            manualProviderRevocationRequired: true
        )

        let result = await AccountDeletionWorkflow.performAcceptedCleanup(
            validateContext: { true },
            receipt: receipt,
            recordCleanupPending: {
                events.append("record")
                return false
            },
            recordManualProviderRevocation: { events.append("manual") },
            performLocalSignOut: {
                events.append("signout")
                return true
            },
            purgeLocalData: {
                events.append("purge")
                return true
            },
            acknowledgeRecovery: {
                events.append("acknowledge")
                return true
            },
            recordRecoveryRetirementPending: {
                events.append("record-retirement")
                return true
            },
            retireRecoveryCapability: {
                events.append("retire-capability")
                return true
            },
            resolveCleanup: {
                events.append("resolve")
                return true
            }
        )

        XCTAssertFalse(result)
        XCTAssertEqual(events, ["record"])
    }

    func testDeletionBarrierAdoptsCachedSessionBeforeMarkerRemovalAndPublication() {
        var markerIsPending = true
        var events: [String] = []

        let restored = AccountDeletionWorkflow.restoreDeferredBarrierSession(
            markerIsPending: { markerIsPending },
            adoptCachedSession: {
                events.append("adopt")
                XCTAssertTrue(markerIsPending)
                return true
            },
            validateCachedSession: {
                events.append("validate")
                XCTAssertTrue(markerIsPending)
                return true
            },
            resolveCleanup: {
                events.append("resolve")
                XCTAssertTrue(markerIsPending)
                markerIsPending = false
                return true
            },
            publishCachedSession: {
                events.append("publish")
                XCTAssertFalse(markerIsPending)
            }
        )

        XCTAssertTrue(restored)
        XCTAssertEqual(events, ["adopt", "validate", "resolve", "publish"])
    }

    func testDeletionBarrierKeepsMarkerWhenAdoptedSessionCannotBeRevalidated() {
        var events: [String] = []

        let restored = AccountDeletionWorkflow.restoreDeferredBarrierSession(
            markerIsPending: { true },
            adoptCachedSession: {
                events.append("adopt")
                return true
            },
            validateCachedSession: {
                events.append("validate")
                return false
            },
            resolveCleanup: {
                events.append("resolve")
                return true
            },
            publishCachedSession: {
                events.append("publish")
            }
        )

        XCTAssertFalse(restored)
        XCTAssertEqual(events, ["adopt", "validate"])
    }

    func testDeletionBarrierDoesNotPublishWhenMarkerRemovalFails() {
        var events: [String] = []

        let restored = AccountDeletionWorkflow.restoreDeferredBarrierSession(
            markerIsPending: { true },
            adoptCachedSession: {
                events.append("adopt")
                return true
            },
            validateCachedSession: {
                events.append("validate")
                return true
            },
            resolveCleanup: {
                events.append("resolve")
                return false
            },
            publishCachedSession: {
                events.append("publish")
            }
        )

        XCTAssertFalse(restored)
        XCTAssertEqual(events, ["adopt", "validate", "resolve"])
    }

    func testPendingAccountDeletionSignsOutBeforePurgeAndResolvesLast() async {
        var events: [String] = []

        let result = await AccountDeletionWorkflow.performPendingLocalCleanup(
            validateContext: { true },
            performLocalSignOut: {
                events.append("signout")
                return true
            },
            purgeLocalData: {
                events.append("purge")
                return true
            },
            resolveCleanup: {
                events.append("resolve")
                return true
            }
        )

        XCTAssertTrue(result)
        XCTAssertEqual(events, ["signout", "purge", "resolve"])

        events.removeAll()
        let failed = await AccountDeletionWorkflow.performPendingLocalCleanup(
            validateContext: { true },
            performLocalSignOut: {
                events.append("signout")
                return true
            },
            purgeLocalData: {
                events.append("purge")
                return false
            },
            resolveCleanup: {
                events.append("resolve")
                return true
            }
        )
        XCTAssertFalse(failed)
        XCTAssertEqual(events, ["signout", "purge"])

        events.removeAll()
        let signOutFailed = await AccountDeletionWorkflow
            .performPendingLocalCleanup(
                validateContext: { true },
                performLocalSignOut: {
                    events.append("signout")
                    return false
                },
                purgeLocalData: {
                    events.append("purge")
                    return true
                },
                resolveCleanup: {
                    events.append("resolve")
                    return true
                }
            )
        XCTAssertFalse(signOutFailed)
        XCTAssertEqual(events, ["signout"])
    }
}
