import Foundation
import os

/// Shared bounded JSON collection; callers own route, budget, account and mutation policy.
final class PinnedBoundedJSONDataTask: NSObject, URLSessionDataDelegate, Sendable {
    private typealias Reply = (Data, URLResponse)
    private struct State {
        var continuation: CheckedContinuation<Reply, Error>?
        var task: URLSessionDataTask?
        var response: URLResponse?
        var data = Data()
        var started = false
        var finished = false
        var terminated = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private struct Completion {
        let continuation: CheckedContinuation<Reply, Error>?
        let task: URLSessionDataTask?
        let result: Result<Reply, Error>
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let limit: Int
    #if DEBUG
    private let completionPause: (@Sendable () -> Void)?
    private let beforeResume: (@Sendable () -> Void)?
    init(maximumBytes: Int, completionPause: (@Sendable () -> Void)? = nil, beforeResume: (@Sendable () -> Void)? = nil) {
        limit = maximumBytes; self.completionPause = completionPause; self.beforeResume = beforeResume; super.init()
    }
    #else
    init(maximumBytes: Int) { limit = maximumBytes; super.init() }
    #endif
    private static let deadlineQueue = DispatchQueue(label: "com.merian.bounded-json-deadline")

    /// Ordinary callers keep prompt completion; only retained mutation owners join.
    func joinedResponse(using session: URLSession, request: URLRequest, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        do {
            let result = try await response(using: session, request: request, timeout: timeout)
            await waitForLocalTermination()
            try Task.checkCancellation()
            return result
        } catch {
            await waitForLocalTermination()
            throw error
        }
    }

    func response(using session: URLSession, request: URLRequest, timeout: TimeInterval,
                  beforeStart: @Sendable () throws -> Void = {}) async throws -> (Data, URLResponse) {
        guard state.withLock({ value in
            guard !value.started else { return false }; value.started = true; return true
        }) else { throw URLError(.badURL) }
        defer { resolveWithoutTask() }
        guard limit > 0, timeout.isFinite, timeout > 0 else { throw URLError(.timedOut) }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                do { try beforeStart() } catch { continuation.resume(throwing: error); return }
                let deadline = DispatchTime.now() + timeout
                let task = state.withLock { value -> URLSessionDataTask? in
                    guard !value.finished else { return nil }
                    let task = session.dataTask(with: request)
                    task.delegate = self; value.continuation = continuation; value.task = task
                    return task
                }
                guard let task else { continuation.resume(throwing: CancellationError()); return }
                Self.deadlineQueue.asyncAfter(deadline: deadline) { [weak self] in
                    self?.finish(error: URLError(.timedOut))
                }
                #if DEBUG
                beforeResume?()
                #endif
                guard DispatchTime.now() < deadline else { finish(error: URLError(.timedOut)); return }
                task.resume()
            }
        } onCancel: { self.finish(error: CancellationError()) }
    }

    /// A cancelled waiter still needs the actual callback, never caller completion.
    func waitForLocalTermination() async {
        await withCheckedContinuation { continuation in
            let done = state.withLock { value in
                if value.terminated { return true }; value.waiters.append(continuation); return false
            }
            if done { continuation.resume() }
        }
    }
    private func resolveWithoutTask() {
        let waiters = state.withLock { value -> [CheckedContinuation<Void, Never>] in
            guard value.task == nil, !value.terminated else { return [] }
            value.terminated = true; defer { value.waiters.removeAll() }; return value.waiters
        }
        waiters.forEach { $0.resume() }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, response.expectedContentLength <= Int64(limit),
              http.statusCode != 200 || http.mimeType?.lowercased() == "application/json" else {
            completionHandler(.cancel)
            finish(error: MerianError.invalidResponse)
            return
        }
        let accepted = state.withLock { value in
            guard !value.finished else { return false }
            value.response = response
            return true
        }
        completionHandler(accepted ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overflow = state.withLock { value in
            guard !value.finished else { return false }
            guard data.count <= limit - value.data.count else { return true }
            value.data.append(data)
            return false
        }
        if overflow { finish(error: MerianError.invalidResponse) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            finish(error: MerianError.invalidResponse)
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        PinnedNetworkTransport.handleServerTrustChallenge(session, challenge: challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        #if DEBUG
        completionPause?()
        #endif
        finish(error: error)
        let waiters = state.withLock { value in
            value.terminated = true; value.task = nil
            defer { value.waiters.removeAll() }; return value.waiters
        }
        waiters.forEach { $0.resume() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
        finish(error: MerianError.invalidResponse)
    }

    private func finish(error: Error?) {
        let pending = state.withLock { value -> Completion? in
            guard !value.finished else { return nil }
            value.finished = true
            let result: Result<Reply, Error>
            if let error { result = .failure(error) } else if let response = value.response {
                result = .success((value.data, response))
            } else { result = .failure(MerianError.invalidResponse) }
            defer { value.continuation = nil; value.response = nil; value.data = Data() }
            return Completion(continuation: value.continuation, task: value.task, result: result)
        }
        guard let pending else { return }
        if error != nil { pending.task?.cancel() }
        pending.continuation?.resume(with: pending.result)
    }
}
