import Foundation
@testable import Merian
import XCTest

private actor AuthLocalSignOutTestGate {
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

@MainActor
private final class AuthLocalSignOutTestHarness {
    var events: [String] = []
    var transitionIsOwned = true
    var quiescenceSucceeds = true
    var ownsCallCount = 0
    var loseTransitionOnThirdCheck = false
    var sdkError: Error?
    var bootstrapGate: AuthLocalSignOutTestGate?
    var sdkGate: AuthLocalSignOutTestGate?

    var beginCount: Int {
        events.filter { $0 == "begin" }.count
    }

    var sdkCount: Int {
        events.filter { $0 == "sdk-sign-out" }.count
    }

    var externalCount: Int {
        events.filter { $0 == "external-sign-out" }.count
    }

    var finishCount: Int {
        events.filter { $0 == "finish" }.count
    }

    func dependencies() -> AuthLocalSignOutDependencies {
        AuthLocalSignOutDependencies(
            state: AuthLocalSignOutStateBoundary(
                begin: { [self] in
                    events.append("begin")
                    return AuthLocalSignOutPreparation(
                        awaitCancelledBootstrap: { [self] in
                            events.append("await-bootstrap")
                            if let bootstrapGate {
                                await bootstrapGate.wait()
                            }
                        }
                    )
                },
                finish: { [self] in
                    events.append("finish")
                }
            ),
            transition: AuthLocalSignOutTransitionBoundary(
                owns: { [self] _ in
                    ownsCallCount += 1
                    if loseTransitionOnThirdCheck,
                       ownsCallCount >= 3 {
                        return false
                    }
                    return transitionIsOwned
                },
                awaitAccountWorkQuiescence: { [self] in
                    events.append("quiesce")
                    return quiescenceSucceeds
                },
                updateForSessionInstallation: { [self] _ in
                    events.append("update")
                },
                adoptSignedOutSession: { [self] _ in
                    events.append("adopt-signed-out")
                }
            ),
            operations: AuthLocalSignOutOperationBoundary(
                signOutSDKSession: { [self] in
                    events.append("sdk-sign-out")
                    if let sdkGate {
                        await sdkGate.wait()
                    }
                    if let sdkError {
                        throw sdkError
                    }
                },
                finishExternalSignOut: { [self] in
                    events.append("external-sign-out")
                }
            ),
            diagnose: { [self] diagnostic, _ in
                switch diagnostic {
                case .sdkSignOutFailed:
                    events.append("diagnose-sdk-failure")
                case .completed:
                    events.append("diagnose-completed")
                }
            }
        )
    }
}

@MainActor
final class AuthLocalSignOutCoordinatorTests: XCTestCase {
    func testSignOutPreservesStateTransitionAndEffectOrder() async {
        let harness = AuthLocalSignOutTestHarness()
        let coordinator = AuthLocalSignOutCoordinator()

        await coordinator.signOut(
            ownedBy: Self.transition,
            dependencies: harness.dependencies()
        )

        XCTAssertEqual(
            harness.events,
            [
                "quiesce",
                "begin",
                "update",
                "adopt-signed-out",
                "await-bootstrap",
                "sdk-sign-out",
                "external-sign-out",
                "diagnose-completed",
                "finish"
            ]
        )
        XCTAssertFalse(coordinator.isRunning)
    }

    func testConcurrentSignOutCallsShareOneRetainedTask() async {
        let gate = AuthLocalSignOutTestGate()
        let harness = AuthLocalSignOutTestHarness()
        harness.sdkGate = gate
        let coordinator = AuthLocalSignOutCoordinator()

        let first = Task { @MainActor in
            await coordinator.signOut(
                ownedBy: Self.transition,
                dependencies: harness.dependencies()
            )
        }
        await gate.waitUntilSuspended()
        let second = Task { @MainActor in
            await coordinator.signOut(
                ownedBy: Self.transition,
                dependencies: harness.dependencies()
            )
        }
        await Task.yield()

        XCTAssertEqual(harness.beginCount, 1)
        XCTAssertEqual(harness.sdkCount, 1)
        XCTAssertTrue(coordinator.isRunning)

        await gate.release()
        await first.value
        await second.value

        XCTAssertEqual(harness.beginCount, 1)
        XCTAssertEqual(harness.sdkCount, 1)
        XCTAssertEqual(harness.externalCount, 1)
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testSDKFailureStillCompletesExternalAndLocalCleanup() async {
        let harness = AuthLocalSignOutTestHarness()
        harness.sdkError = AuthLocalSignOutCoordinatorTestError.sdk
        let coordinator = AuthLocalSignOutCoordinator()

        await coordinator.signOut(
            ownedBy: Self.transition,
            dependencies: harness.dependencies()
        )

        XCTAssertEqual(harness.sdkCount, 1)
        XCTAssertEqual(harness.externalCount, 1)
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertTrue(harness.events.contains("diagnose-sdk-failure"))
        XCTAssertTrue(harness.events.contains("diagnose-completed"))
    }

    func testFailedQuiescenceStopsBeforeLocalStateMutation() async {
        let harness = AuthLocalSignOutTestHarness()
        harness.quiescenceSucceeds = false
        let coordinator = AuthLocalSignOutCoordinator()

        await coordinator.signOut(
            ownedBy: Self.transition,
            dependencies: harness.dependencies()
        )

        XCTAssertEqual(harness.events, ["quiesce"])
        XCTAssertFalse(coordinator.isRunning)
    }

    func testTransitionLossAfterBootstrapStopsBeforeSDKMutation() async {
        let harness = AuthLocalSignOutTestHarness()
        harness.loseTransitionOnThirdCheck = true
        let coordinator = AuthLocalSignOutCoordinator()

        await coordinator.signOut(
            ownedBy: Self.transition,
            dependencies: harness.dependencies()
        )

        XCTAssertEqual(harness.sdkCount, 0)
        XCTAssertEqual(harness.externalCount, 0)
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testCancellationWhileAwaitingBootstrapStopsBeforeSDKMutation() async {
        let gate = AuthLocalSignOutTestGate()
        let harness = AuthLocalSignOutTestHarness()
        harness.bootstrapGate = gate
        let coordinator = AuthLocalSignOutCoordinator()
        let signOut = Task { @MainActor in
            await coordinator.signOut(
                ownedBy: Self.transition,
                dependencies: harness.dependencies()
            )
        }
        await gate.waitUntilSuspended()

        coordinator.cancel()
        await gate.release()
        await signOut.value

        XCTAssertEqual(harness.sdkCount, 0)
        XCTAssertEqual(harness.externalCount, 0)
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testCancellationRetainsTaskUntilDeferredCleanupFinishes() async {
        let gate = AuthLocalSignOutTestGate()
        let harness = AuthLocalSignOutTestHarness()
        harness.bootstrapGate = gate
        let coordinator = AuthLocalSignOutCoordinator()
        let first = Task { @MainActor in
            await coordinator.signOut(
                ownedBy: Self.transition,
                dependencies: harness.dependencies()
            )
        }
        await gate.waitUntilSuspended()

        coordinator.cancel()
        XCTAssertTrue(coordinator.isRunning)

        let overlapping = Task { @MainActor in
            await coordinator.signOut(
                ownedBy: Self.transition,
                dependencies: harness.dependencies()
            )
        }
        await Task.yield()

        XCTAssertEqual(harness.beginCount, 1)
        XCTAssertEqual(harness.finishCount, 0)

        await gate.release()
        await first.value
        await overlapping.value

        XCTAssertEqual(harness.beginCount, 1)
        XCTAssertEqual(harness.sdkCount, 0)
        XCTAssertEqual(harness.externalCount, 0)
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertFalse(coordinator.isRunning)
    }

    func testCancellationAfterSDKMutationStillCompletesExternalCleanup() async {
        let gate = AuthLocalSignOutTestGate()
        let harness = AuthLocalSignOutTestHarness()
        harness.sdkGate = gate
        let coordinator = AuthLocalSignOutCoordinator()
        let signOut = Task { @MainActor in
            await coordinator.signOut(
                ownedBy: Self.transition,
                dependencies: harness.dependencies()
            )
        }
        await gate.waitUntilSuspended()

        coordinator.cancel()
        XCTAssertTrue(coordinator.isRunning)

        await gate.release()
        await signOut.value

        XCTAssertEqual(harness.sdkCount, 1)
        XCTAssertEqual(harness.externalCount, 1)
        XCTAssertEqual(harness.finishCount, 1)
        XCTAssertTrue(harness.events.contains("diagnose-completed"))
        XCTAssertFalse(coordinator.isRunning)
    }

    private static let transition = AuthTransitionToken(
        id: UUID(uuidString: "66666666-6666-4666-8666-666666666666")!,
        kind: .recovery
    )
}

@MainActor
final class AuthLocalSignOutFacadeTests: XCTestCase {
    func testFacadeClosesRequestGateBeforeSDKInvalidation() async {
        let manager = SupabaseManager.shared
        manager.isAuthenticated = true
        var observedLocalSignOutBeforeRemoteCall = false
        var requestWasBlockedDuringRemoteCall = false

        await manager.signOut(
            performRemoteSignOut: { [manager] in
                observedLocalSignOutBeforeRemoteCall =
                    !manager.isAuthenticated && manager.isSigningOut

                do {
                    _ = try await manager.getValidAuthHeaders()
                } catch SupabaseAuthTransitionError.signOutInProgress {
                    requestWasBlockedDuringRemoteCall = true
                } catch {
                    XCTFail("Unexpected auth transition error: \(error)")
                }
            },
            performExternalSignOut: {}
        )

        XCTAssertTrue(observedLocalSignOutBeforeRemoteCall)
        XCTAssertTrue(requestWasBlockedDuringRemoteCall)
        XCTAssertFalse(manager.isSigningOut)
        XCTAssertFalse(manager.isAuthenticated)
    }
}

private enum AuthLocalSignOutCoordinatorTestError: Error {
    case sdk
}
