@testable import Merian
import XCTest

private actor AuthLifecycleReplayTestGate {
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
final class AuthLifecycleReplayCoordinatorTests:
    XCTestCase {
    func testReplacementCancelsStaleLifecycleReplay() async {
        let coordinator = AuthLifecycleReplayCoordinator()
        let firstGate = AuthLifecycleReplayTestGate()
        var events: [String] = []

        coordinator.observeLifecycleEvent(deferredByActiveTransition: true)
        coordinator.scheduleIfNeeded {
            await firstGate.wait()
            guard !Task.isCancelled else { return }
            events.append("stale")
        }
        await firstGate.waitUntilSuspended()

        coordinator.observeLifecycleEvent(deferredByActiveTransition: true)
        coordinator.scheduleIfNeeded {
            events.append("current")
        }
        while events.isEmpty {
            await Task.yield()
        }
        await firstGate.release()
        await Task.yield()

        XCTAssertEqual(events, ["current"])
    }

    func testCoordinatorDeinitDoesNotAwaitSuspendedReplay() async {
        let gate = AuthLifecycleReplayTestGate()
        var coordinator: AuthLifecycleReplayCoordinator? =
            AuthLifecycleReplayCoordinator()
        weak let weakCoordinator = coordinator

        coordinator?.observeLifecycleEvent(
            deferredByActiveTransition: true
        )
        coordinator?.scheduleIfNeeded {
            await gate.wait()
        }
        await gate.waitUntilSuspended()
        coordinator = nil

        XCTAssertNil(weakCoordinator)
        await gate.release()
    }

    func testNewTransitionCancelsReplayAndCarriesDeferredObligation()
        async {
        let coordinator = AuthLifecycleReplayCoordinator()
        let gate = AuthLifecycleReplayTestGate()
        var events: [String] = []

        coordinator.observeLifecycleEvent(deferredByActiveTransition: true)
        coordinator.scheduleIfNeeded {
            await gate.wait()
            guard !Task.isCancelled else { return }
            events.append("stale")
        }
        await gate.waitUntilSuspended()

        coordinator.authTransitionWillBegin()
        let didScheduleReplacement = coordinator.scheduleIfNeeded {
            events.append("current")
        }
        while events.isEmpty {
            await Task.yield()
        }
        await gate.release()
        await Task.yield()

        XCTAssertTrue(didScheduleReplacement)
        XCTAssertEqual(events, ["current"])
    }

    func testNewStableEventClearsDeferredReplayObligation() async {
        let coordinator = AuthLifecycleReplayCoordinator()
        var didRun = false

        coordinator.observeLifecycleEvent(deferredByActiveTransition: true)
        coordinator.observeLifecycleEvent(deferredByActiveTransition: false)
        let scheduled = coordinator.scheduleIfNeeded {
            didRun = true
        }
        await Task.yield()

        XCTAssertFalse(scheduled)
        XCTAssertFalse(didRun)
    }

    func testStableTransitionWithoutDeferredEventDoesNotScheduleReplay()
        async {
        let coordinator = AuthLifecycleReplayCoordinator()
        var didRun = false

        let scheduled = coordinator.scheduleIfNeeded {
            didRun = true
        }
        await Task.yield()

        XCTAssertFalse(scheduled)
        XCTAssertFalse(didRun)
    }
}
