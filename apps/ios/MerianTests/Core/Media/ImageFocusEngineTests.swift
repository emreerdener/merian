import Foundation
import Testing
@testable import Merian

@Suite("Image focus worker termination", .serialized)
struct ImageFocusEngineTests {
    @Test(arguments: [false, true])
    func outcomeDoesNotReleaseBlockedWorkerAndLateSuccessCannotReplaceIt(cancel: Bool) async {
        let started = Signal(), registered = Signal(), exited = Signal()
        let release = DispatchSemaphore(value: 0)
        let state = ImageFocusWorkerState.qualification(worker: {
            Task { await started.open() }
            release.wait()
            return .noCandidates
        }, drainRegistered: { Task { await registered.open() } })
        defer { release.signal() }
        state.start(imageData: Data())
        await started.wait()
        if cancel { state.cancel(with: .cancelled) }
        let outcome = await state.outcome()
        #expect(outcome == (cancel ? .cancelled : .timedOut))
        let drain = Task { await state.drain(); await exited.open() }
        await registered.wait()
        #expect(!(await exited.isOpen))
        release.signal()
        await drain.value
        #expect(await exited.isOpen)
        #expect(await state.outcome() == outcome)
        await state.drain() // Already terminated; repeated recovery is read-only.
    }

    @Test func cancellationBeforeDispatchNeverStartsWorkerAndStillDrains() async {
        let started = StartFlag()
        let state = ImageFocusWorkerState.qualification(worker: {
            started.mark(); return .noCandidates
        })
        state.cancel(with: .cancelled)
        state.start(imageData: Data())
        #expect(await state.outcome() == .cancelled)
        await state.drain()
        #expect(!started.value)
    }

    @Test func cancellationOfDrainWaiterCannotFabricateTermination() async {
        let started = Signal(), registered = Signal(), exited = Signal()
        let release = DispatchSemaphore(value: 0)
        let state = ImageFocusWorkerState.qualification(worker: {
            Task { await started.open() }; release.wait(); return .failed
        }, drainRegistered: { Task { await registered.open() } })
        defer { release.signal() }
        state.start(imageData: Data())
        await started.wait()
        let drain = Task { await state.drain(); await exited.open() }
        await registered.wait()
        drain.cancel(); state.cancel(with: .cancelled)
        #expect(!(await exited.isOpen))
        release.signal(); await drain.value
        #expect(await exited.isOpen)
    }

    @Test func successfulWorkerSupportsMultipleDrainWaiters() async {
        let release = DispatchSemaphore(value: 0)
        let registered = Counter()
        let state = ImageFocusWorkerState.qualification(worker: {
            release.wait(); return .noCandidates
        }, drainRegistered: { Task { await registered.increment() } })
        defer { release.signal() }
        state.start(imageData: Data())
        let first = Task { await state.drain() }, second = Task { await state.drain() }
        await registered.wait(for: 2)
        release.signal()
        await first.value; await second.value
        // Fixture scheduling can cross the unchanged visible deadline. Either
        // outcome is valid; termination itself is independent of that deadline.
        let result = await state.outcome()
        #expect(result == .noCandidates || result == .timedOut)
    }

    @Test @MainActor func cancellationBeforeRequestInstallationPreventsPerformAndWaitsForExit() async throws {
        let installed = Signal(), registered = Signal(), exited = Signal()
        let performed = StartFlag(), reached = StartFlag(), release = DispatchSemaphore(value: 0)
        let state = ImageFocusWorkerState.qualification(beforeInstall: {
            reached.mark(); Task { await installed.open() }; release.wait()
        }, beforePerform: { performed.mark() }, finished: { Task { await installed.open() } }, drainRegistered: { Task { await registered.open() } })
        defer { release.signal() }
        state.start(imageData: PhotoPreparationTestHarness.image())
        await installed.wait()
        try #require(reached.value) // Unexpected early exit fails instead of hanging at the barrier.
        state.cancel(with: .cancelled)
        let outcome = await state.outcome()
        #expect(outcome == .cancelled)
        let drain = Task { await state.drain(); await exited.open() }
        await registered.wait()
        #expect(!(await exited.isOpen))
        #expect(!performed.value)
        release.signal(); await drain.value
        #expect(!performed.value)
        #expect(await state.outcome() == outcome)
    }

    actor Signal {
        private(set) var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func open() { isOpen = true; let pending = waiters; waiters.removeAll(); for waiter in pending { waiter.resume() } }
        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }
    final class StartFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var started = false
        func mark() { lock.lock(); started = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return started }
    }
    actor Counter {
        private var count = 0
        private var target = 0
        private var waiter: CheckedContinuation<Void, Never>?
        func increment() { count += 1; if count >= target { waiter?.resume(); waiter = nil } }
        func wait(for target: Int) async {
            if count >= target { return }
            self.target = target
            await withCheckedContinuation { waiter = $0 }
        }
    }
}
