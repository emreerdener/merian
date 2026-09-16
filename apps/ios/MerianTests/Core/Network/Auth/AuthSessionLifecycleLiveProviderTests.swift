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
    private var continuation:
        AsyncStream<AuthSessionLifecycleSDKState>.Continuation?
    private lazy var stream = AsyncStream<AuthSessionLifecycleSDKState> {
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
                    for await state in stream {
                        guard !Task.isCancelled else { return }
                        await handler(state)
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
        continuation?.yield(state)
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

    init(userID: UUID) {
        coordinatorHarness = AuthSessionLifecycleCoordinatorHarness(
            userID: userID
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

        stream.send(state)
        await waitUntil {
            dependencies.coordinatorHarness.diagnostics.last == .processed
        }

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
        stream.send(state)
        await waitUntil {
            dependencies.coordinatorHarness.diagnostics.last
                == .deferredForActiveTransition
        }

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
        stream.send(state)
        await waitUntil {
            dependencies.coordinatorHarness.diagnostics.last
                == .deferredForActiveTransition
        }

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
        stream.send(state)
        await waitUntil {
            dependencies.coordinatorHarness.diagnostics.last
                == .deferredForActiveTransition
        }

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
        for _ in 0..<2_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for lifecycle work.", file: file, line: line)
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
