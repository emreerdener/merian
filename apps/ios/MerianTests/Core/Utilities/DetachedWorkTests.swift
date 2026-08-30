import XCTest

@testable import Merian

final class DetachedWorkTests: XCTestCase {
    func testValuePropagatesParentCancellationToDetachedOperation() async {
        let probe = DetachedWorkCancellationProbe()
        let parentTask = Task { () -> Bool in
            do {
                _ = try await DetachedWork.value(
                    category: .imagePreparation
                ) {
                    await probe.markStarted()
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch is CancellationError {
                        await probe.markCancelled()
                        throw CancellationError()
                    }
                    return true
                }
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }

        await probe.waitUntilStarted()
        parentTask.cancel()

        let parentObservedCancellation = await parentTask.value
        XCTAssertTrue(parentObservedCancellation)
        let detachedOperationObservedCancellation = await probe
            .didObserveCancellation
        XCTAssertTrue(detachedOperationObservedCancellation)
    }
}

private actor DetachedWorkCancellationProbe {
    private var didStart = false
    private var didCancel = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    var didObserveCancellation: Bool {
        didCancel
    }

    func markStarted() {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func markCancelled() {
        didCancel = true
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}
