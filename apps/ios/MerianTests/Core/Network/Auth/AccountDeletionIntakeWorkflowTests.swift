import Foundation
@testable import Merian
import XCTest

@MainActor
final class AccountDeletionIntakeWorkflowTests: XCTestCase {
    func testAccountDeletionRejectsPreflightCancellationBeforePersistence() async {
        var events: [String] = []
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await AccountDeletionWorkflow.performDurableIntake(
                recordIntakePending: {
                    events.append("record-intent")
                    return true
                },
                requestDeletion: {
                    events.append("request")
                    return self.acceptedAccountDeletionReceipt
                },
                verifyResultContext: {
                    events.append("verify-context")
                },
                clearIntakeAfterDefinitiveRejection: {
                    events.append("clear")
                }
            )
        }

        do {
            _ = try await task.value
            XCTFail("Cancellation must stop before durable intake persistence")
        } catch is CancellationError {
            XCTAssertTrue(events.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAccountDeletionCancellationAfterPersistenceRetainsIntentWithoutDispatch() async {
        var events: [String] = []
        let task = Task { @MainActor in
            try await AccountDeletionWorkflow.performDurableIntake(
                recordIntakePending: {
                    events.append("record-intent")
                    withUnsafeCurrentTask { $0?.cancel() }
                    return true
                },
                requestDeletion: {
                    events.append("request")
                    return self.acceptedAccountDeletionReceipt
                },
                verifyResultContext: {
                    events.append("verify-context")
                },
                clearIntakeAfterDefinitiveRejection: {
                    events.append("clear")
                }
            )
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must stop before destructive intake")
        } catch is CancellationError {
            XCTAssertEqual(events, ["record-intent"])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAccountDeletionPersistsIntentBeforeRequestAndRetainsAmbiguousFailure() async {
        var events: [String] = []

        do {
            _ = try await AccountDeletionWorkflow.performDurableIntake(
                recordIntakePending: {
                    events.append("record-intent")
                    return true
                },
                requestDeletion: {
                    events.append("request")
                    throw URLError(.networkConnectionLost)
                },
                verifyResultContext: {
                    events.append("verify-context")
                },
                clearIntakeAfterDefinitiveRejection: {
                    events.append("clear")
                }
            )
            XCTFail("Expected the ambiguous request to fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }

        XCTAssertEqual(
            events,
            ["record-intent", "request", "verify-context"]
        )
    }

    func testAccountDeletionClearsIntentOnlyAfterDefinitiveClientRejection() async {
        var events: [String] = []

        do {
            _ = try await AccountDeletionWorkflow.performDurableIntake(
                recordIntakePending: {
                    events.append("record-intent")
                    return true
                },
                requestDeletion: {
                    events.append("request")
                    throw MerianError.httpError(
                        statusCode: 409,
                        message: #"{"code":"purchase_continuity_pending"}"#
                    )
                },
                verifyResultContext: {
                    events.append("verify-context")
                },
                clearIntakeAfterDefinitiveRejection: {
                    events.append("clear")
                }
            )
            XCTFail("Expected the rejected request to fail")
        } catch {
            XCTAssertTrue(
                AccountDeletionTransitionPolicy
                    .isDefinitiveIntakeRejection(error)
            )
        }

        XCTAssertEqual(
            events,
            ["record-intent", "request", "verify-context", "clear"]
        )
    }

    func testAccountDeletionDoesNotDispatchWhenIntentPersistenceFails() async {
        var events: [String] = []

        do {
            _ = try await AccountDeletionWorkflow.performDurableIntake(
                recordIntakePending: {
                    events.append("record-intent")
                    return false
                },
                requestDeletion: {
                    events.append("request")
                    return AccountDeletionReceipt(
                        success: true,
                        status: .pending,
                        manualProviderRevocationRequired: false
                    )
                },
                verifyResultContext: {
                    events.append("verify-context")
                },
                clearIntakeAfterDefinitiveRejection: {
                    events.append("clear")
                }
            )
            XCTFail("Expected persistence failure")
        } catch {
            guard case SupabaseAuthTransitionError
                .accountDeletionRecoveryPersistenceFailed = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }

        XCTAssertEqual(events, ["record-intent"])
    }

    func testAccountDeletionVerifiesTransitionContextAfterReceipt() async throws {
        var events: [String] = []
        let receipt = AccountDeletionReceipt(
            success: true,
            status: .pending,
            manualProviderRevocationRequired: false
        )

        let result = try await AccountDeletionWorkflow.performDurableIntake(
            recordIntakePending: {
                events.append("record-intent")
                return true
            },
            requestDeletion: {
                events.append("request")
                return receipt
            },
            verifyResultContext: {
                events.append("verify-context")
            },
            clearIntakeAfterDefinitiveRejection: {
                events.append("clear")
            }
        )

        XCTAssertEqual(result, receipt)
        XCTAssertEqual(
            events,
            ["record-intent", "request", "verify-context"]
        )
    }

    func testAccountDeletionKeepsIntentWhenFailureContextIsStale() async {
        var events: [String] = []

        do {
            _ = try await AccountDeletionWorkflow.performDurableIntake(
                recordIntakePending: {
                    events.append("record-intent")
                    return true
                },
                requestDeletion: {
                    events.append("request")
                    throw MerianError.httpError(
                        statusCode: 409,
                        message: #"{"code":"purchase_continuity_pending"}"#
                    )
                },
                verifyResultContext: {
                    events.append("verify-context")
                    throw SupabaseAuthTransitionError.signOutSessionChanged
                },
                clearIntakeAfterDefinitiveRejection: {
                    events.append("clear")
                }
            )
            XCTFail("Expected stale request context")
        } catch SupabaseAuthTransitionError.signOutSessionChanged {
            // Expected: stale network results cannot retire the durable fence.
        } catch {
            XCTFail("Unexpected stale-context error: \(error)")
        }

        XCTAssertEqual(
            events,
            ["record-intent", "request", "verify-context"]
        )
    }

    func testPreparedAccountDeletionPersistsMarkersBeforeCommit() async throws {
        var events: [String] = []
        let preparation = preparedAccountDeletionReceipt
        let accepted = acceptedAccountDeletionReceipt

        let receipt = try await AccountDeletionWorkflow.performPreparedIntake(
            prepareDeletion: {
                events.append("prepare")
                return preparation
            },
            verifyPreparationContext: {
                events.append("verify-preparation-context")
                return true
            },
            recordCapabilityPreparedPending: {
                events.append("record-prepared")
                return true
            },
            recordIntakePending: {
                events.append("record-intake")
                return true
            },
            commitDeletion: {
                events.append("commit")
                return accepted
            },
            verifyCommitContext: {
                events.append("verify-commit-context")
                return true
            }
        )

        XCTAssertEqual(receipt, accepted)
        XCTAssertEqual(
            events,
            [
                "prepare",
                "verify-preparation-context",
                "record-prepared",
                "record-intake",
                "commit",
                "verify-commit-context"
            ]
        )
    }

    func testPreparedAccountDeletionCancellationAfterPreparationStopsBeforeCommit() async {
        var events: [String] = []
        let task = Task { @MainActor in
            try await AccountDeletionWorkflow.performPreparedIntake(
                prepareDeletion: {
                    events.append("prepare")
                    withUnsafeCurrentTask { $0?.cancel() }
                    return self.preparedAccountDeletionReceipt
                },
                verifyPreparationContext: {
                    events.append("verify-preparation-context")
                    return true
                },
                recordCapabilityPreparedPending: {
                    events.append("record-prepared")
                    return true
                },
                recordIntakePending: {
                    events.append("record-intake")
                    return true
                },
                commitDeletion: {
                    events.append("commit")
                    return self.acceptedAccountDeletionReceipt
                },
                verifyCommitContext: {
                    events.append("verify-commit-context")
                    return true
                }
            )
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must stop before deletion commit")
        } catch is CancellationError {
            XCTAssertEqual(
                events,
                ["prepare", "verify-preparation-context"]
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreparedAccountDeletionCancellationAfterMarkersStopsBeforeCommit() async {
        var events: [String] = []
        let task = Task { @MainActor in
            try await AccountDeletionWorkflow.performPreparedIntake(
                prepareDeletion: {
                    events.append("prepare")
                    return self.preparedAccountDeletionReceipt
                },
                verifyPreparationContext: {
                    events.append("verify-preparation-context")
                    return true
                },
                recordCapabilityPreparedPending: {
                    events.append("record-prepared")
                    return true
                },
                recordIntakePending: {
                    events.append("record-intake")
                    withUnsafeCurrentTask { $0?.cancel() }
                    return true
                },
                commitDeletion: {
                    events.append("commit")
                    return self.acceptedAccountDeletionReceipt
                },
                verifyCommitContext: {
                    events.append("verify-commit-context")
                    return true
                }
            )
        }
        do {
            _ = try await task.value
            XCTFail("Cancellation must retain markers without committing")
        } catch is CancellationError {
            XCTAssertEqual(
                events,
                [
                    "prepare",
                    "verify-preparation-context",
                    "record-prepared",
                    "record-intake"
                ]
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPreparedAccountDeletionStopsBeforeCommitWhenPreparationCannotBecomeDurable() async {
        let failureCases: [PreparedAccountDeletionIntakeFailureCase] = [
            .init(
                name: "stale preparation context",
                hasPreparationContext: false,
                recordsPrepared: true,
                recordsIntake: true,
                expectedEvents: ["prepare", "verify-preparation-context"]
            ),
            .init(
                name: "prepared marker failure",
                hasPreparationContext: true,
                recordsPrepared: false,
                recordsIntake: true,
                expectedEvents: [
                    "prepare",
                    "verify-preparation-context",
                    "record-prepared"
                ]
            ),
            .init(
                name: "intake marker failure",
                hasPreparationContext: true,
                recordsPrepared: true,
                recordsIntake: false,
                expectedEvents: [
                    "prepare",
                    "verify-preparation-context",
                    "record-prepared",
                    "record-intake"
                ]
            )
        ]
        let preparation = preparedAccountDeletionReceipt
        let accepted = acceptedAccountDeletionReceipt

        for failureCase in failureCases {
            var events: [String] = []
            do {
                _ = try await AccountDeletionWorkflow.performPreparedIntake(
                    prepareDeletion: {
                        events.append("prepare")
                        return preparation
                    },
                    verifyPreparationContext: {
                        events.append("verify-preparation-context")
                        return failureCase.hasPreparationContext
                    },
                    recordCapabilityPreparedPending: {
                        events.append("record-prepared")
                        return failureCase.recordsPrepared
                    },
                    recordIntakePending: {
                        events.append("record-intake")
                        return failureCase.recordsIntake
                    },
                    commitDeletion: {
                        events.append("commit")
                        return accepted
                    },
                    verifyCommitContext: {
                        events.append("verify-commit-context")
                        return true
                    }
                )
                XCTFail("Expected \(failureCase.name)")
            } catch SupabaseAuthTransitionError
                .accountDeletionRecoveryPersistenceFailed {
                // Expected: no destructive commit follows a failed fence.
            } catch {
                XCTFail("Unexpected \(failureCase.name) error: \(error)")
            }

            XCTAssertEqual(
                events,
                failureCase.expectedEvents,
                failureCase.name
            )
        }
    }

    func testPreparedAccountDeletionRejectsStaleCommitContext() async {
        var events: [String] = []
        let preparation = preparedAccountDeletionReceipt
        let accepted = acceptedAccountDeletionReceipt

        do {
            _ = try await AccountDeletionWorkflow.performPreparedIntake(
                prepareDeletion: {
                    events.append("prepare")
                    return preparation
                },
                verifyPreparationContext: {
                    events.append("verify-preparation-context")
                    return true
                },
                recordCapabilityPreparedPending: {
                    events.append("record-prepared")
                    return true
                },
                recordIntakePending: {
                    events.append("record-intake")
                    return true
                },
                commitDeletion: {
                    events.append("commit")
                    return accepted
                },
                verifyCommitContext: {
                    events.append("verify-commit-context")
                    return false
                }
            )
            XCTFail("Expected stale commit context")
        } catch SupabaseAuthTransitionError.signOutSessionChanged {
            // Expected: an accepted receipt cannot cross transition context.
        } catch {
            XCTFail("Unexpected stale-context error: \(error)")
        }

        XCTAssertEqual(
            events,
            [
                "prepare",
                "verify-preparation-context",
                "record-prepared",
                "record-intake",
                "commit",
                "verify-commit-context"
            ]
        )
    }

    func testPreparedAccountDeletionRejectsStalePreparationFailureContext() async {
        var events: [String] = []

        do {
            _ = try await AccountDeletionWorkflow.performPreparedIntake(
                prepareDeletion: {
                    events.append("prepare")
                    throw MerianError.httpError(
                        statusCode: 409,
                        message: #"{"code":"purchase_continuity_pending"}"#
                    )
                },
                verifyPreparationContext: {
                    events.append("verify-preparation-context")
                    return false
                },
                recordCapabilityPreparedPending: {
                    events.append("record-prepared")
                    return true
                },
                recordIntakePending: {
                    events.append("record-intake")
                    return true
                },
                commitDeletion: {
                    events.append("commit")
                    return self.acceptedAccountDeletionReceipt
                },
                verifyCommitContext: {
                    events.append("verify-commit-context")
                    return true
                }
            )
            XCTFail("Expected stale preparation failure context")
        } catch SupabaseAuthTransitionError
            .accountDeletionRecoveryPersistenceFailed {
            // Expected: a stale rejection cannot reach outer recovery policy.
        } catch {
            XCTFail("Unexpected stale-context error: \(error)")
        }

        XCTAssertEqual(events, ["prepare", "verify-preparation-context"])
    }

    func testPreparedAccountDeletionRejectsStaleCommitFailureContext() async {
        var events: [String] = []

        do {
            _ = try await AccountDeletionWorkflow.performPreparedIntake(
                prepareDeletion: {
                    events.append("prepare")
                    return self.preparedAccountDeletionReceipt
                },
                verifyPreparationContext: {
                    events.append("verify-preparation-context")
                    return true
                },
                recordCapabilityPreparedPending: {
                    events.append("record-prepared")
                    return true
                },
                recordIntakePending: {
                    events.append("record-intake")
                    return true
                },
                commitDeletion: {
                    events.append("commit")
                    throw MerianError.httpError(
                        statusCode: 409,
                        message: #"{"code":"purchase_continuity_pending"}"#
                    )
                },
                verifyCommitContext: {
                    events.append("verify-commit-context")
                    return false
                }
            )
            XCTFail("Expected stale commit failure context")
        } catch SupabaseAuthTransitionError.signOutSessionChanged {
            // Expected: a stale rejection cannot reach outer recovery policy.
        } catch {
            XCTFail("Unexpected stale-context error: \(error)")
        }

        XCTAssertEqual(
            events,
            [
                "prepare",
                "verify-preparation-context",
                "record-prepared",
                "record-intake",
                "commit",
                "verify-commit-context"
            ]
        )
    }

    private var preparedAccountDeletionReceipt:
        AccountDeletionPreparationReceipt {
        AccountDeletionPreparationReceipt(
            success: true,
            status: .prepared,
            protocolVersion: 2,
            recoveryCapabilityExpiresAt:
                AccountDeletionTestSupport.futureExpiry
        )
    }

    private var acceptedAccountDeletionReceipt: AccountDeletionReceipt {
        AccountDeletionReceipt(
            success: true,
            status: .pending,
            manualProviderRevocationRequired: false,
            recoveryCapabilityExpiresAt:
                AccountDeletionTestSupport.futureExpiry,
            protocolVersion: 2
        )
    }
}

private struct PreparedAccountDeletionIntakeFailureCase {
    let name: String
    let hasPreparationContext: Bool
    let recordsPrepared: Bool
    let recordsIntake: Bool
    let expectedEvents: [String]
}
