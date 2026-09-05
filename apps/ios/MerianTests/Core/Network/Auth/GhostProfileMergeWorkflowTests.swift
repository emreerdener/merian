import Foundation
@testable import Merian
import XCTest

@MainActor
final class GhostProfileMergeWorkflowTests: XCTestCase {
    private enum StubError: Error {
        case expected
    }

    func testGhostHandoffClearsQueueOnlyAfterServerAndLocalCompletion() async throws {
        var calls: [String] = []

        try await GhostProfileMergeWorkflow.finalizeHandoff(
            completeServerHandoff: { calls.append("server") },
            synchronizeProviderPurchases: { calls.append("provider") },
            rebindAndSynchronizeLocalEvidence: { calls.append("local") },
            clearPendingHandoff: { calls.append("clear") }
        )

        XCTAssertEqual(calls, ["server", "provider", "local", "clear"])
    }

    func testGhostHandoffRetainsQueueWhenServerOrLocalCompletionFails() async {
        var serverFailureCalls: [String] = []
        await expectFailure {
            try await GhostProfileMergeWorkflow.finalizeHandoff(
                completeServerHandoff: {
                    serverFailureCalls.append("server")
                    throw StubError.expected
                },
                synchronizeProviderPurchases: {
                    serverFailureCalls.append("provider")
                },
                rebindAndSynchronizeLocalEvidence: {
                    serverFailureCalls.append("local")
                },
                clearPendingHandoff: {
                    serverFailureCalls.append("clear")
                }
            )
        }
        XCTAssertEqual(serverFailureCalls, ["server"])

        var providerFailureCalls: [String] = []
        await expectFailure {
            try await GhostProfileMergeWorkflow.finalizeHandoff(
                completeServerHandoff: {
                    providerFailureCalls.append("server")
                },
                synchronizeProviderPurchases: {
                    providerFailureCalls.append("provider")
                    throw StubError.expected
                },
                rebindAndSynchronizeLocalEvidence: {
                    providerFailureCalls.append("local")
                },
                clearPendingHandoff: {
                    providerFailureCalls.append("clear")
                }
            )
        }
        XCTAssertEqual(providerFailureCalls, ["server", "provider"])

        var localFailureCalls: [String] = []
        await expectFailure {
            try await GhostProfileMergeWorkflow.finalizeHandoff(
                completeServerHandoff: {
                    localFailureCalls.append("server")
                },
                synchronizeProviderPurchases: {
                    localFailureCalls.append("provider")
                },
                rebindAndSynchronizeLocalEvidence: {
                    localFailureCalls.append("local")
                    throw StubError.expected
                },
                clearPendingHandoff: {
                    localFailureCalls.append("clear")
                }
            )
        }
        XCTAssertEqual(localFailureCalls, ["server", "provider", "local"])
    }

    func testGhostHandoffRemovalFailureRemainsRetryable() async {
        var calls: [String] = []
        await expectFailure {
            try await GhostProfileMergeWorkflow.finalizeHandoff(
                completeServerHandoff: { calls.append("server") },
                synchronizeProviderPurchases: { calls.append("provider") },
                rebindAndSynchronizeLocalEvidence: { calls.append("local") },
                clearPendingHandoff: {
                    calls.append("clear")
                    throw StubError.expected
                }
            )
        }
        XCTAssertEqual(calls, ["server", "provider", "local", "clear"])
    }

    func testGhostHandoffRejectsPreflightCancellationBeforeServerWork() async {
        var calls: [String] = []
        let task = Task { @MainActor in
            try await GhostProfileMergeWorkflow.finalizeHandoff(
                completeServerHandoff: { calls.append("server") },
                synchronizeProviderPurchases: { calls.append("provider") },
                rebindAndSynchronizeLocalEvidence: { calls.append("local") },
                clearPendingHandoff: { calls.append("clear") }
            )
        }
        task.cancel()

        do {
            try await task.value
            XCTFail("Cancellation must stop before server completion")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(calls.isEmpty)
    }

    func testGhostHandoffRetainsProofAfterEachAsyncPhaseCancellation() async {
        for cancelledPhase in ["server", "provider", "local"] {
            var calls: [String] = []
            let task = Task { @MainActor in
                try await GhostProfileMergeWorkflow.finalizeHandoff(
                    completeServerHandoff: {
                        calls.append("server")
                        Self.cancelCurrentTask(
                            if: cancelledPhase == "server"
                        )
                    },
                    synchronizeProviderPurchases: {
                        calls.append("provider")
                        Self.cancelCurrentTask(
                            if: cancelledPhase == "provider"
                        )
                    },
                    rebindAndSynchronizeLocalEvidence: {
                        calls.append("local")
                        Self.cancelCurrentTask(
                            if: cancelledPhase == "local"
                        )
                    },
                    clearPendingHandoff: { calls.append("clear") }
                )
            }

            do {
                try await task.value
                XCTFail("Cancellation must retain the durable proof")
            } catch is CancellationError {
            } catch {
                XCTFail("Unexpected error: \(error)")
            }

            let expectedPrefix = ["server", "provider", "local"].prefix {
                $0 != cancelledPhase
            }
            XCTAssertEqual(
                calls,
                Array(expectedPrefix) + [cancelledPhase]
            )
        }
    }

    func testGhostHandoffSessionFenceFailureStopsBeforeProviderWork() async {
        var calls: [String] = []

        await expectFailure {
            try await GhostProfileMergeWorkflow.finalizeHandoff(
                completeServerHandoff: {
                    calls.append("session-check")
                    throw SupabaseAuthTransitionError.guestMergeSessionChanged
                },
                synchronizeProviderPurchases: { calls.append("provider") },
                rebindAndSynchronizeLocalEvidence: { calls.append("local") },
                clearPendingHandoff: { calls.append("clear") }
            )
        }
        XCTAssertEqual(calls, ["session-check"])
    }

    private func expectFailure(
        _ operation: @MainActor () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected operation to fail")
        } catch {}
    }

    private static func cancelCurrentTask(if shouldCancel: Bool) {
        guard shouldCancel else { return }
        withUnsafeCurrentTask { $0?.cancel() }
    }
}
