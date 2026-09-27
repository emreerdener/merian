import Foundation
@testable import Merian
import Supabase
import XCTest

private actor AuthSessionLifecycleLiveSuspensionGate {
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
private final class AuthSessionLifecycleLiveStreamHarness {
    private struct Delivery {
        let state: AuthSessionLifecycleSDKState
        let completion: XCTestExpectation?
    }

    private var continuation: AsyncStream<Delivery>.Continuation?
    private lazy var stream = AsyncStream<Delivery> {
        self.continuation = $0
    }

    var currentState: AuthSessionLifecycleSDKState

    init(currentState: AuthSessionLifecycleSDKState) {
        self.currentState = currentState
    }

    func makeProvider() -> AuthSessionLifecycleLiveProvider {
        let stream = stream
        return AuthSessionLifecycleLiveProvider(
            startListening: { handler in
                Task { @MainActor in
                    for await delivery in stream {
                        guard !Task.isCancelled else { return }
                        await handler(delivery.state)
                        delivery.completion?.fulfill()
                    }
                }
            },
            currentState: { [weak self] in
                self?.currentState ?? AuthSessionLifecycleSDKState(
                    user: nil,
                    isExpired: false,
                    origin: .runtimeTransition
                )
            }
        )
    }

    func send(_ state: AuthSessionLifecycleSDKState) {
        currentState = state
        continuation?.yield(Delivery(state: state, completion: nil))
    }

    func sendAndWait(
        _ state: AuthSessionLifecycleSDKState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let completion = XCTestExpectation(description: "Auth listener handled this event")
        currentState = state
        continuation?.yield(Delivery(state: state, completion: completion))
        let result = await XCTWaiter.fulfillment(of: [completion], timeout: 5)
        XCTAssertEqual(result, .completed, file: file, line: line)
    }
}

@MainActor
private final class LifecycleLiveDependenciesHarness {
    let coordinatorHarness: AuthSessionLifecycleCoordinatorHarness
    var events: [String] = []
    var generation: UInt64 = 6
    var hasActiveTransition = false
    var deletionCleanupPending = false
    var reconciliationCheckCount = 0
    var observedSession: AuthTransitionSession?
    var receivedUser: User?

    init(userID: UUID, isAnonymous: Bool = false) {
        coordinatorHarness = AuthSessionLifecycleCoordinatorHarness(
            userID: userID,
            isAnonymous: isAnonymous
        )
        coordinatorHarness.isTestExecution = true
    }

    func dependencies() -> AuthSessionLifecycleLiveDependencies {
        AuthSessionLifecycleLiveDependencies(
            advanceAuthGeneration: {
                self.events.append("advance-generation")
                self.generation &+= 1
                self.coordinatorHarness.currentAuthGeneration =
                    self.generation
                return self.generation
            },
            authContextWillChange: {
                self.events.append("invalidate-revocation")
            },
            observeAuthSession: { session in
                self.events.append("observe-transition")
                self.observedSession = session
            },
            accountDeletionCleanupPending: {
                self.events.append("read-deletion-barrier")
                return self.deletionCleanupPending
            },
            hasActiveTransition: {
                self.events.append("read-transition")
                return self.hasActiveTransition
            },
            reconciliationContextIsCurrent: { generation in
                self.reconciliationCheckCount += 1
                return !self.hasActiveTransition
                    && generation == self.generation
            },
            makeLifecycleDependencies: { user in
                self.events.append("make-coordinator-dependencies")
                self.receivedUser = user
                self.coordinatorHarness.hasActiveTransition =
                    self.hasActiveTransition
                return self.coordinatorHarness.dependencies()
            },
            resumeDeferredCredentialRevocation: {
                self.events.append("resume-revocation")
            }
        )
    }
}

@MainActor
final class AuthSessionLifecycleLiveProviderTests: XCTestCase {
    func testSDKStateMapsInitialExpiredSessionWithoutLosingIdentity() {
        let userID = UUID()
        let user = Self.user(id: userID, isAnonymous: false)
        let state = AuthSessionLifecycleSDKState(
            user: user,
            isExpired: true,
            origin: .initialRestoration
        )

        let event = state.lifecycleEvent(authGeneration: 42)

        XCTAssertEqual(
            event.adoption,
            .awaitingRefresh(userId: userID)
        )
        XCTAssertEqual(
            event.session,
            AuthTransitionSession(
                userID: userID,
                isAnonymous: false
            )
        )
        XCTAssertEqual(event.authGeneration, 42)
        XCTAssertEqual(event.origin, .initialRestoration)
    }

    func testListenerPreservesContextInvalidationAndProjectionOrder() async {
        let userID = UUID()
        let state = AuthSessionLifecycleSDKState(
            user: Self.user(id: userID, isAnonymous: false),
            isExpired: false,
            origin: .initialRestoration
        )
        let stream = AuthSessionLifecycleLiveStreamHarness(
            currentState: state
        )
        let dependencies = LifecycleLiveDependenciesHarness(
            userID: userID
        )
        let provider = stream.makeProvider()
        provider.start(dependencies: dependencies.dependencies())

        await stream.sendAndWait(state)
        XCTAssertEqual(dependencies.coordinatorHarness.diagnostics.last, .processed)

        XCTAssertEqual(
            dependencies.events,
            [
                "advance-generation",
                "invalidate-revocation",
                "observe-transition",
                "read-deletion-barrier",
                "read-transition",
                "make-coordinator-dependencies",
                "resume-revocation"
            ]
        )
        XCTAssertEqual(dependencies.observedSession, state.session)
        XCTAssertEqual(dependencies.receivedUser?.id, userID)
        provider.cancel()
    }

    func testDeferredEventReplaysCurrentSnapshotAfterTransition() async {
        let userID = UUID()
        let state = AuthSessionLifecycleSDKState(
            user: Self.user(id: userID, isAnonymous: false),
            isExpired: false,
            origin: .runtimeTransition
        )
        let stream = AuthSessionLifecycleLiveStreamHarness(
            currentState: state
        )
        let dependencies = LifecycleLiveDependenciesHarness(
            userID: userID
        )
        dependencies.hasActiveTransition = true
        let provider = stream.makeProvider()
        provider.start(dependencies: dependencies.dependencies())
        await stream.sendAndWait(state)
        XCTAssertEqual(
            dependencies.coordinatorHarness.diagnostics.last,
            .deferredForActiveTransition
        )

        dependencies.hasActiveTransition = false
        let scheduled = provider.scheduleCurrentSessionReconciliation(
            authGeneration: dependencies.generation,
            dependencies: dependencies.dependencies()
        )
        await waitUntil {
            dependencies.coordinatorHarness.diagnostics.last == .processed
        }

        XCTAssertTrue(scheduled)
        XCTAssertEqual(
            dependencies.coordinatorHarness.diagnostics,
            [.deferredForActiveTransition, .processed]
        )
        XCTAssertEqual(
            dependencies.events.filter { $0 == "resume-revocation" }.count,
            2
        )
        provider.cancel()
    }

    func testBootstrapReconciliationRunsWithoutDeferredSDKEvent() async {
        let userID = UUID()
        let state = AuthSessionLifecycleSDKState(
            user: Self.user(id: userID, isAnonymous: true),
            isExpired: false,
            origin: .runtimeTransition
        )
        let stream = AuthSessionLifecycleLiveStreamHarness(currentState: state)
        let dependencies = LifecycleLiveDependenciesHarness(userID: userID, isAnonymous: true)
        dependencies.coordinatorHarness.isTestExecution = false
        dependencies.coordinatorHarness.currentAuthGeneration = dependencies.generation
        let provider = stream.makeProvider()
        let scheduled = provider.scheduleCurrentSessionReconciliation(
            authGeneration: dependencies.generation,
            force: true,
            dependencies: dependencies.dependencies()
        )
        await waitUntil {
            dependencies.coordinatorHarness.diagnostics.last == .processed
        }
        XCTAssertTrue(scheduled)
        XCTAssertEqual(dependencies.receivedUser?.id, userID)
        XCTAssertTrue(dependencies.coordinatorHarness.events.contains("ensure-telemetry"))
        XCTAssertTrue(dependencies.coordinatorHarness.events.contains("begin-entitlement"))
        XCTAssertEqual(dependencies.coordinatorHarness.diagnostics, [.processed])
        provider.cancel()
    }

    func testBootstrapReconciliationRejectsNewTransitionBeforeItRuns() async {
        let userID = UUID()
        let state = AuthSessionLifecycleSDKState(
            user: Self.user(id: userID, isAnonymous: true),
            isExpired: false,
            origin: .runtimeTransition
        )
        let stream = AuthSessionLifecycleLiveStreamHarness(currentState: state)
        let dependencies = LifecycleLiveDependenciesHarness(userID: userID, isAnonymous: true)
        let provider = stream.makeProvider()
        XCTAssertTrue(provider.scheduleCurrentSessionReconciliation(
            authGeneration: dependencies.generation,
            force: true,
            dependencies: dependencies.dependencies()
        ))
        dependencies.hasActiveTransition = true
        await waitUntil { dependencies.reconciliationCheckCount > 0 }
        XCTAssertTrue(dependencies.coordinatorHarness.diagnostics.isEmpty)
        provider.cancel()
    }

    func testReplayRejectsSnapshotReplacedBeforeTaskRuns() async {
        let userID = UUID()
        let state = AuthSessionLifecycleSDKState(
            user: Self.user(id: userID, isAnonymous: false),
            isExpired: false,
            origin: .runtimeTransition
        )
        let stream = AuthSessionLifecycleLiveStreamHarness(
            currentState: state
        )
        let dependencies = LifecycleLiveDependenciesHarness(
            userID: userID
        )
        dependencies.hasActiveTransition = true
        let provider = stream.makeProvider()
        provider.start(dependencies: dependencies.dependencies())
        await stream.sendAndWait(state)
        XCTAssertEqual(
            dependencies.coordinatorHarness.diagnostics.last,
            .deferredForActiveTransition
        )

        dependencies.hasActiveTransition = false
        let scheduled = provider.scheduleCurrentSessionReconciliation(
            authGeneration: dependencies.generation,
            dependencies: dependencies.dependencies()
        )
        stream.currentState = AuthSessionLifecycleSDKState(
            user: nil,
            isExpired: false,
            origin: .runtimeTransition
        )
        await waitUntil {
            dependencies.reconciliationCheckCount > 0
        }

        XCTAssertTrue(scheduled)
        XCTAssertEqual(
            dependencies.coordinatorHarness.diagnostics,
            [.deferredForActiveTransition]
        )
        XCTAssertEqual(
            dependencies.events.filter { $0 == "resume-revocation" }.count,
            1
        )
        provider.cancel()
    }

    func testRestartClearsDeferredReplayFromReplacedListener() async {
        let userID = UUID()
        let state = AuthSessionLifecycleSDKState(
            user: Self.user(id: userID, isAnonymous: false),
            isExpired: false,
            origin: .runtimeTransition
        )
        let stream = AuthSessionLifecycleLiveStreamHarness(
            currentState: state
        )
        let dependencies = LifecycleLiveDependenciesHarness(
            userID: userID
        )
        dependencies.hasActiveTransition = true
        let provider = stream.makeProvider()
        let liveDependencies = dependencies.dependencies()
        provider.start(dependencies: liveDependencies)
        await stream.sendAndWait(state)
        XCTAssertEqual(
            dependencies.coordinatorHarness.diagnostics.last,
            .deferredForActiveTransition
        )

        provider.start(dependencies: liveDependencies)
        dependencies.hasActiveTransition = false

        XCTAssertFalse(
            provider.scheduleCurrentSessionReconciliation(
                authGeneration: dependencies.generation,
                dependencies: liveDependencies
            )
        )
        XCTAssertEqual(
            dependencies.coordinatorHarness.diagnostics,
            [.deferredForActiveTransition]
        )
        provider.cancel()
    }

    func testRestartCancelsTrailingEffectFromSuspendedListener() async {
        let userID = UUID()
        let state = AuthSessionLifecycleSDKState(
            user: Self.user(id: userID, isAnonymous: false),
            isExpired: false,
            origin: .runtimeTransition
        )
        let stream = AuthSessionLifecycleLiveStreamHarness(
            currentState: state
        )
        let dependencies = LifecycleLiveDependenciesHarness(
            userID: userID
        )
        let gate = AuthSessionLifecycleLiveSuspensionGate()
        dependencies.coordinatorHarness.isTestExecution = false
        dependencies.coordinatorHarness.suspendTelemetry = {
            await gate.wait()
        }
        let provider = stream.makeProvider()
        let liveDependencies = dependencies.dependencies()
        provider.start(dependencies: liveDependencies)
        stream.send(state)
        await gate.waitUntilSuspended()

        provider.start(dependencies: liveDependencies)
        await gate.release()
        await waitUntil {
            dependencies.coordinatorHarness.diagnostics.last == .processed
        }

        XCTAssertFalse(
            dependencies.events.contains("resume-revocation")
        )
        provider.cancel()
    }

    func testProviderDeinitCancelsSuspendedListenerWithoutSelfRetention() {
        let state = AuthSessionLifecycleSDKState(
            user: nil,
            isExpired: false,
            origin: .runtimeTransition
        )
        let stream = AuthSessionLifecycleLiveStreamHarness(
            currentState: state
        )
        let dependencies = LifecycleLiveDependenciesHarness(
            userID: UUID()
        )
        var provider: AuthSessionLifecycleLiveProvider? =
            stream.makeProvider()
        provider?.start(dependencies: dependencies.dependencies())
        weak let releasedProvider = provider

        provider = nil

        XCTAssertNil(releasedProvider)
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !predicate() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for lifecycle work.", file: file, line: line)
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch {
                XCTFail("Lifecycle wait cancelled.", file: file, line: line)
                return
            }
        }
    }

    private static func user(id: UUID, isAnonymous: Bool) -> User {
        User(
            id: id,
            appMetadata: [:],
            userMetadata: [:],
            aud: "authenticated",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isAnonymous: isAnonymous
        )
    }
}
