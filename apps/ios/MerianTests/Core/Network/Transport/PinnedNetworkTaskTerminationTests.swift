import Foundation
import os
import Testing

@testable import Merian

@Suite("Pinned network local task termination", .serialized)
struct PinnedNetworkTaskTerminationTests {
    @Test(arguments: [false, true])
    func callerCompletionDoesNotReleaseTaskLifetime(timeout: Bool) async throws {
        let pause = CompletionPause()
        let state = PinnedNetworkDataTaskState(completionPause: { pause.wait() })
        let session = hangingSession()
        defer { pause.release(); session.invalidateAndCancel() }
        let call = Task {
            try await state.response(using: session, for: request(), timeoutInterval: timeout ? 0.05 : 10)
        }
        if !timeout {
            try await waitUntil { await sessionHasTask(session) }
            call.cancel()
        }
        let start = ContinuousClock.now
        switch await call.result {
        case .success: Issue.record("A hanging request unexpectedly succeeded")
        case .failure(let error):
            if timeout { #expect((error as? URLError)?.code == .timedOut) }
            else { #expect(error is CancellationError) }
        }
        #expect(start.duration(to: .now) < .seconds(1))
        try await waitUntil { pause.entered }
        await #expect(throws: (any Error).self) {
            try await state.response(using: session, for: request(), timeoutInterval: 0)
        }
        let joined = OSAllocatedUnfairLock(initialState: 0)
        let joins = (0..<3).map { _ in Task {
            await state.waitForLocalTermination()
            joined.withLock { $0 += 1 }
        } }
        // Account shutdown may already be cancelled. It must still join local
        // termination; cancellation cannot manufacture a drain acknowledgement.
        joins[0].cancel()
        try await Task.sleep(for: .milliseconds(30))
        #expect(joined.withLock { $0 } == 0)
        pause.release()
        for join in joins { await join.value }
        #expect(joined.withLock { $0 } == 3)
        await state.waitForLocalTermination() // Late joins are also idempotent.
    }

    @Test func transportRetainsStateAfterCancelledCallerDropsIt() async throws {
        let pause = CompletionPause()
        var state: PinnedNetworkDataTaskState? = .init(completionPause: { pause.wait() })
        weak var weakState = state
        let session = hangingSession()
        defer { pause.release(); session.invalidateAndCancel() }
        let call = Task { [state = state!] in
            try await state.response(using: session, for: request(), timeoutInterval: 0.03)
        }
        _ = await call.result
        try await waitUntil { pause.entered }
        state = nil
        #expect(weakState != nil)
        pause.release()
        // Completion breaks the state/task cycle even when nobody joins it.
        try await waitUntil { weakState == nil }
    }

    @Test(arguments: [false, true])
    func noTaskCanTerminateWithoutCallback(cancelled: Bool) async throws {
        let gate = StartGate()
        let state = PinnedNetworkDataTaskState()
        let session = hangingSession()
        defer { session.invalidateAndCancel() }
        let call = Task {
            await gate.wait()
            return try await state.response(using: session, for: request(), timeoutInterval: cancelled ? 1 : 0)
        }
        if cancelled { call.cancel() }
        await gate.open()
        if case .success = await call.result { Issue.record("Rejected start succeeded") }
        await state.waitForLocalTermination()
        let tasks = await session.allTasks
        #expect(tasks.isEmpty)
    }

    @Test func successAndDuplicateResponseKeepOneTaskLifetime() async throws {
        let mock = ScopedMockTransport(), state = PinnedNetworkDataTaskState()
        let session = mock.makeSession()
        defer { session.invalidateAndCancel() }
        mock.register(path: "/local-termination") { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data([7]))
        }
        let result = try await state.response(using: session, for: request(), timeoutInterval: 1)
        #expect(result.data == Data([7]))
        await state.waitForLocalTermination()
        await #expect(throws: (any Error).self) {
            try await state.response(using: session, for: request(), timeoutInterval: 1)
        }
        await state.waitForLocalTermination()
    }

    private func request() -> URLRequest {
        URLRequest(url: URL(string: "https://example.supabase.co/local-termination")!)
    }
    private func hangingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TerminationHangingProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func sessionHasTask(_ session: URLSession) async -> Bool { !(await session.allTasks).isEmpty }
    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await predicate()) {
            guard ContinuousClock.now < deadline else {
                Issue.record("Termination boundary did not arrive")
                throw URLError(.timedOut)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class CompletionPause: Sendable {
    private let reached = OSAllocatedUnfairLock(initialState: false)
    private let semaphore = DispatchSemaphore(value: 0)
    var entered: Bool { reached.withLock { $0 } }
    func wait() {
        reached.withLock { $0 = true }
        // Bound a failed test without manufacturing a production drain timeout.
        _ = semaphore.wait(timeout: .now() + 5)
    }
    func release() { semaphore.signal() }
}
private actor StartGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func open() { isOpen = true; waiter?.resume(); waiter = nil }
}
private final class TerminationHangingProtocol: URLProtocol {
    override static func canInit(with _: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}
