import Foundation
@testable import Merian
import XCTest

@MainActor
final class OAuthSignInWorkflowTests: XCTestCase {
    func testOAuthSessionReplacementSuspendsBeforeInstallingAndReconcilesSuccess()
        async throws {
        var calls: [String] = []

        let installed = try await OAuthSignInWorkflow.replacingSession(
            suspendAnalytics: {
                calls.append("suspend")
                return 41
            },
            installSession: {
                calls.append("install")
                return "target-session"
            },
            currentSession: {
                calls.append("current")
                return "unexpected-session"
            },
            reconcileSession: { generation, session, disposition in
                calls.append(
                    "reconcile:\(generation):\(session ?? "nil"):\(disposition.testName)"
                )
            }
        )

        XCTAssertEqual(installed, "target-session")
        XCTAssertEqual(calls, [
            "suspend",
            "install",
            "reconcile:41:target-session:installed"
        ])
    }

    func testOAuthSessionReplacementReconcilesActualSessionOnFailure() async {
        var calls: [String] = []

        do {
            let _: String = try await OAuthSignInWorkflow.replacingSession(
                suspendAnalytics: {
                    calls.append("suspend")
                    return 42
                },
                installSession: {
                    calls.append("install")
                    throw OAuthSessionReplacementTestError.expected
                },
                currentSession: {
                    calls.append("current")
                    return "restored-session"
                },
                reconcileSession: { generation, session, disposition in
                    calls.append(
                        "reconcile:\(generation):\(session ?? "nil"):\(disposition.testName)"
                    )
                }
            )
            XCTFail("A failed session installation must be rethrown")
        } catch OAuthSessionReplacementTestError.expected {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(calls, [
            "suspend",
            "install",
            "current",
            "reconcile:42:restored-session:failed"
        ])
    }

    func testOAuthSessionReplacementRejectsPreflightCancellation() async {
        var calls: [String] = []
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await OAuthSignInWorkflow.replacingSession(
                suspendAnalytics: {
                    calls.append("suspend")
                    return 43
                },
                installSession: {
                    calls.append("install")
                    return "target-session"
                },
                currentSession: {
                    calls.append("current")
                    return "source-session"
                },
                reconcileSession: { generation, session, disposition in
                    calls.append(
                        "reconcile:\(generation):\(session ?? "nil"):\(disposition.testName)"
                    )
                }
            )
        }

        do {
            _ = try await task.value
            XCTFail("Cancellation must stop before SDK session replacement")
        } catch is CancellationError {
            XCTAssertTrue(calls.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOAuthSessionReplacementCancellationAfterSuppressionRestoresSourceWithoutInstalling()
        async {
        var calls: [String] = []
        let task = Task { @MainActor in
            try await OAuthSignInWorkflow.replacingSession(
                suspendAnalytics: {
                    calls.append("suspend")
                    withUnsafeCurrentTask { $0?.cancel() }
                    return 44
                },
                installSession: {
                    calls.append("install")
                    return "target-session"
                },
                currentSession: {
                    calls.append("current")
                    return "source-session"
                },
                reconcileSession: { generation, session, disposition in
                    calls.append(
                        "reconcile:\(generation):\(session ?? "nil"):\(disposition.testName)"
                    )
                }
            )
        }

        do {
            _ = try await task.value
            XCTFail("Cancellation must stop before SDK session replacement")
        } catch is CancellationError {
            XCTAssertEqual(
                calls,
                [
                    "suspend",
                    "current",
                    "reconcile:44:source-session:cancelled"
                ]
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOAuthSessionReplacementCancellationAfterInstallationFailsClosed()
        async {
        let gate = OAuthSessionReplacementTestGate()
        var calls: [String] = []
        let task = Task { @MainActor in
            try await OAuthSignInWorkflow.replacingSession(
                suspendAnalytics: {
                    calls.append("suspend")
                    return 45
                },
                installSession: {
                    calls.append("install")
                    await gate.wait()
                    return "target-session"
                },
                currentSession: {
                    calls.append("current")
                    return "target-session"
                },
                reconcileSession: { generation, session, disposition in
                    calls.append(
                        "reconcile:\(generation):\(session ?? "nil"):\(disposition.testName)"
                    )
                }
            )
        }

        await gate.waitUntilSuspended()
        task.cancel()
        await gate.release()

        do {
            _ = try await task.value
            XCTFail("Cancellation must reject a newly installed session")
        } catch is CancellationError {
            XCTAssertEqual(calls, [
                "suspend",
                "install",
                "current",
                "reconcile:45:target-session:cancelled"
            ])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppleCredentialRegistrationRetriesTheSameDurableRequest()
        async throws {
        var attempts = 0
        var waits = 0

        try await OAuthSignInWorkflow.registerAppleCredential(
            invoke: {
                attempts += 1
                if attempts == 1 {
                    throw URLError(.networkConnectionLost)
                }
            },
            waitBeforeRetry: {
                waits += 1
            }
        )

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(waits, 1)
    }

    func testAppleCredentialRegistrationRejectsCancellationAfterInvoke()
        async {
        let gate = OAuthSessionReplacementTestGate()
        var attempts = 0
        let task = Task { @MainActor in
            try await OAuthSignInWorkflow.registerAppleCredential(
                invoke: {
                    attempts += 1
                    await gate.wait()
                },
                waitBeforeRetry: {
                    XCTFail("Cancellation must not enter retry delay")
                }
            )
        }

        await gate.waitUntilSuspended()
        task.cancel()
        await gate.release()

        do {
            try await task.value
            XCTFail("Cancellation must reject provider registration")
        } catch is CancellationError {
            XCTAssertEqual(attempts, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppleCredentialRegistrationStopsAfterBoundedRetry() async {
        var attempts = 0

        do {
            try await OAuthSignInWorkflow.registerAppleCredential(
                invoke: {
                    attempts += 1
                    throw URLError(.cannotConnectToHost)
                },
                waitBeforeRetry: {}
            )
            XCTFail("Expected the bounded Apple registration to fail")
        } catch {
            XCTAssertEqual(
                (error as? URLError)?.code,
                .cannotConnectToHost
            )
        }

        XCTAssertEqual(attempts, 2)
    }
}

private enum OAuthSessionReplacementTestError: Error {
    case expected
}

private actor OAuthSessionReplacementTestGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func release() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private extension OAuthSessionReplacementDisposition {
    var testName: String {
        switch self {
        case .installed: "installed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
    }
}
