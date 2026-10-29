import Foundation
import os

struct PinnedNetworkResponse: Sendable {
    let data: Data
    let response: URLResponse
}

/// One request has two lifetimes: the caller's bounded wait and URLSession's
/// actual task. Cancellation ends the first promptly. Only task completion (or
/// proof that no task was created) ends the second. This is not remote closure
/// or proof of physical staging-file cleanup.
final class PinnedNetworkDataTaskState: Sendable {
    private typealias Continuation = CheckedContinuation<PinnedNetworkResponse, Error>
    private struct State {
        var responseStarted = false
        var continuation: Continuation?
        var task: URLSessionDataTask?
        var taskWasCreated = false
        var callerFinished = false
        var locallyTerminated = false
        var terminationWaiters: [CheckedContinuation<Void, Never>] = []
    }
    private struct Completion {
        let continuation: Continuation?
        let task: URLSessionDataTask?
    }
    private static let deadlineQueue = DispatchQueue(
        label: "com.merian.pinned-network-deadline", qos: .userInitiated
    )
    private let state = OSAllocatedUnfairLock(initialState: State())
    #if DEBUG
    private let completionPause: (@Sendable () -> Void)?
    init(completionPause: (@Sendable () -> Void)? = nil) { self.completionPause = completionPause }
    #endif

    func response(using session: URLSession, for request: URLRequest,
                  timeoutInterval: TimeInterval) async throws -> PinnedNetworkResponse {
        let ownsResponse = state.withLock { value in
            guard !value.responseStarted else { return false }
            value.responseStarted = true
            return true
        }
        guard ownsResponse else { throw URLError(.badURL) }
        defer { resolveWithoutTask() }
        guard timeoutInterval.isFinite, timeoutInterval > 0 else { throw URLError(.timedOut) }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                start(using: session, for: request, timeoutInterval: timeoutInterval,
                      continuation: continuation)
            }
        } onCancel: {
            self.finish(with: .failure(CancellationError()), cancellingRequest: true)
        }
    }

    /// Must be joined after starting response(), including after that await
    /// throws. A cancelled joining task still waits. Ordinary response callers
    /// do not join implicitly, preserving their prompt deadline behavior.
    func waitForLocalTermination() async {
        await withCheckedContinuation { continuation in
            let alreadyTerminated = state.withLock { value in
                if value.locallyTerminated { return true }
                value.terminationWaiters.append(continuation)
                return false
            }
            if alreadyTerminated { continuation.resume() }
        }
    }

    private func start(using session: URLSession, for request: URLRequest,
                       timeoutInterval: TimeInterval, continuation: Continuation) {
        let deadline = DispatchTime.now() + timeoutInterval
        // Creation and registration are atomic with cancellation. If cancellation
        // wins, no task is created; otherwise completion owns the drain witness.
        let task = state.withLock { value -> URLSessionDataTask? in
            guard !value.callerFinished else { return nil }
            let task = session.dataTask(with: request) { data, response, error in
                // Retain this state until URLSession acknowledges termination,
                // even when the bounded caller has already returned.
                self.complete(data: data, response: response, error: error)
            }
            value.continuation = continuation
            value.task = task
            value.taskWasCreated = true
            return task
        }
        guard let task else {
            continuation.resume(throwing: CancellationError())
            return
        }
        task.resume()
        Self.deadlineQueue.asyncAfter(deadline: deadline) { [weak self] in
            self?.finish(with: .failure(URLError(.timedOut)), cancellingRequest: true)
        }
    }

    private func complete(data: Data?, response: URLResponse?, error: Error?) {
        #if DEBUG
        completionPause?()
        #endif
        let result: Result<PinnedNetworkResponse, Error>
        if let error { result = .failure(error) }
        else if let response { result = .success(.init(data: data ?? Data(), response: response)) }
        else { result = .failure(URLError(.badServerResponse)) }
        finish(with: result, cancellingRequest: false)
        let waiters = state.withLock { value in
            value.locallyTerminated = true
            value.task = nil // Break the task/completion/state retention cycle only here.
            defer { value.terminationWaiters.removeAll() }
            return value.terminationWaiters
        }
        for waiter in waiters { waiter.resume() }
    }

    private func resolveWithoutTask() {
        let waiters = state.withLock { value -> [CheckedContinuation<Void, Never>] in
            guard !value.taskWasCreated, !value.locallyTerminated else { return [] }
            value.locallyTerminated = true
            defer { value.terminationWaiters.removeAll() }
            return value.terminationWaiters
        }
        for waiter in waiters { waiter.resume() }
    }

    private func finish(with result: Result<PinnedNetworkResponse, Error>, cancellingRequest: Bool) {
        let pending = state.withLock { value -> Completion? in
            guard !value.callerFinished else { return nil }
            value.callerFinished = true
            defer { value.continuation = nil }
            return Completion(continuation: value.continuation, task: value.task)
        }
        guard let pending else { return }
        if cancellingRequest { pending.task?.cancel() }
        pending.continuation?.resume(with: result)
    }
}
