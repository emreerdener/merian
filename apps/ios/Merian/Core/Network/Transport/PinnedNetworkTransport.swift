import CryptoKit
import Foundation
import os
import Security

/// Value-only certificate policy used by the pinned Supabase session delegate.
enum MerianTLSCertificatePinPolicy {
    // Leaf cert (expires approximately every 90 days).
    // Intermediate CA remains the rotation fallback.
    static let pinnedCertificateHashes: Set<String> = [
        "OYvM4tmVyyPLCSqTe1tYvZW0CKRfv4mre7EUA0eJrn0=",
        "HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="
    ]

    static func accepts(
        systemTrustIsValid: Bool,
        certificateChainHashes: [String]?
    ) -> Bool {
        guard systemTrustIsValid, let certificateChainHashes else {
            return false
        }
        return !pinnedCertificateHashes.isEmpty && certificateChainHashes.contains {
            pinnedCertificateHashes.contains($0)
        }
    }

    static func requiresPinning(host: String) -> Bool {
        let lowercaseHost = host.lowercased()
        let normalizedHost = lowercaseHost.last == "."
            ? String(lowercaseHost.dropLast())
            : lowercaseHost
        return normalizedHost == "supabase.co"
            || (
                normalizedHost.count > "supabase.co".count + 1
                    && normalizedHost.hasSuffix(".supabase.co")
            )
    }
}

/// Owns production URLSession construction and the DEBUG replacement seam.
/// Every mutable session reference is accessed under `sessionLock`.
final class PinnedNetworkTransport: @unchecked Sendable {
    private let sessionLock = NSLock()
    private var productionSession: URLSession?

    #if DEBUG
    private var storedOverridingSession: URLSession?

    var overridingSession: URLSession? {
        get { withSessionLock { storedOverridingSession } }
        set { withSessionLock { storedOverridingSession = newValue } }
    }
    #endif

    var isUsingOverridingSession: Bool {
        #if DEBUG
        withSessionLock { storedOverridingSession != nil }
        #else
        false
        #endif
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        return configuration
    }

    /// A per-operation session cannot inherit the ordinary 90-second resource ceiling.
    /// Copy DEBUG configuration, never invalidate the caller-owned injected session.
    func protectedInsightChatData(for request: URLRequest, claimExpiresAt: Date) async throws -> (Data, URLResponse) {
        let configuration = scopedConfiguration(timeout: ProtectedInsightChatBudget.requestSeconds)
        let session = URLSession(configuration: configuration, delegate: MerianTLSDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await ProtectedInsightChatDataTask().response(using: session, request: request, claimExpiresAt: claimExpiresAt)
    }

    private func scopedConfiguration(timeout: TimeInterval) -> URLSessionConfiguration {
        let configuration = Self.makeConfiguration()
        #if DEBUG
        let injected = withSessionLock { storedOverridingSession?.configuration }
        configuration.protocolClasses = injected?.protocolClasses ?? configuration.protocolClasses
        configuration.httpAdditionalHeaders = injected?.httpAdditionalHeaders
        #endif
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    /// Audio receipts have their own bounded session; ordinary requests retain the 90-second ceiling.
    func audioAnalysisData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: scopedConfiguration(timeout: ObservationAudioAnalysisTransport.requestSeconds),
                                 delegate: MerianTLSDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await PinnedBoundedJSONDataTask(maximumBytes: 4096).response(using: session, request: request,
            timeout: ObservationAudioAnalysisTransport.requestSeconds)
    }

    /// Video execution returns only a bounded state receipt under its own operation deadline.
    func videoAnalysisData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: scopedConfiguration(timeout: ObservationVideoAnalysisTransport.requestSeconds),
                                 delegate: MerianTLSDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await PinnedBoundedJSONDataTask(maximumBytes: 4096).response(using: session, request: request,
            timeout: ObservationVideoAnalysisTransport.requestSeconds)
    }

    /// Video item uploads own their deadline and streamed whole-cohort receipt cap.
    func videoEvidenceData(for request: URLRequest) async throws -> (Data, URLResponse) {
        let session = URLSession(configuration: scopedConfiguration(timeout: ObservationVideoEvidenceTransport.requestSeconds),
                                 delegate: MerianTLSDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await PinnedBoundedJSONDataTask(maximumBytes: ObservationVideoEvidenceReceipt.maximumBytes)
            .response(using: session, request: request, timeout: ObservationVideoEvidenceTransport.requestSeconds)
    }

    /// The immutable state envelope has a larger, still streamed and bounded, read-only budget.
    func audioOutcomeData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await PinnedBoundedJSONDataTask(maximumBytes: ObservationHistoryPage.maximumPageBytes)
            .response(using: activeSession, request: request, timeout: 5)
    }

    /// Reservation observations have a separate 2 KiB streamed cap and five-second deadline.
    func sourceReservationData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await PinnedBoundedJSONDataTask(maximumBytes: ObservationSourceReservationReply.maximumBytes)
            .response(using: activeSession, request: request, timeout: 5)
    }

    func initialPhotoAllocationData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await PinnedBoundedJSONDataTask(maximumBytes: InitialPhotoAllocationReply.maximumBytes)
            .response(using: activeSession, request: request, timeout: 5)
    }

    /// Fixed retirement response budget on the existing pinned session.
    func analysisRetirementData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await PinnedBoundedJSONDataTask(maximumBytes: 4096).response(using: activeSession, request: request, timeout: 5)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await activeSession.data(for: request)
    }

    /// Uses the shared pinned session while enforcing a caller-owned wall-clock
    /// deadline. This is intentionally not a retry policy.
    func data(
        for request: URLRequest,
        timeoutInterval: TimeInterval
    ) async throws -> (Data, URLResponse) {
        guard timeoutInterval.isFinite, timeoutInterval > 0 else {
            throw URLError(.timedOut)
        }
        var boundedRequest = request
        boundedRequest.cachePolicy = .reloadIgnoringLocalCacheData
        boundedRequest.timeoutInterval = timeoutInterval

        let response = try await PinnedNetworkDataTaskState().response(
            using: activeSession,
            for: boundedRequest,
            timeoutInterval: timeoutInterval
        )
        return (response.data, response.response)
    }

    func data(
        for request: URLRequest,
        delegate: URLSessionTaskDelegate
    ) async throws -> (Data, URLResponse) {
        try await activeSession.data(for: request, delegate: delegate)
    }

    func upload(
        for request: URLRequest,
        fromFile fileURL: URL
    ) async throws -> (Data, URLResponse) {
        try await activeSession.upload(for: request, fromFile: fileURL)
    }

    /// Inactive CPM transport prerequisite. The media owner must retain this
    /// handle and join its local termination before releasing a file or lease.
    func photoUploadTask() -> PinnedPhotoUploadTask { .init(session: activeSession) }

    private var activeSession: URLSession {
        withSessionLock {
            #if DEBUG
            if let storedOverridingSession { return storedOverridingSession }
            #endif
            return resolveProductionSessionLocked()
        }
    }

    #if DEBUG
    var productionSessionIdentityForTesting: ObjectIdentifier {
        withSessionLock {
            ObjectIdentifier(resolveProductionSessionLocked())
        }
    }
    #endif

    private func resolveProductionSessionLocked() -> URLSession {
        if let productionSession { return productionSession }
        let session = URLSession(
            configuration: Self.makeConfiguration(),
            delegate: MerianTLSDelegate(),
            delegateQueue: nil
        )
        productionSession = session
        return session
    }

    private func withSessionLock<Value>(
        _ operation: () -> Value
    ) -> Value {
        sessionLock.lock()
        defer { sessionLock.unlock() }
        return operation()
    }
}

/// Validates the server certificate chain for `supabase.co` and its subdomains
/// against pinned SHA-256 hashes. Pinning is skipped in DEBUG builds to support
/// local proxies.
///
/// Rotation runbook:
/// 1. Before the leaf expires, obtain its DER SHA-256 base64 value with
///    `openssl s_client` and `openssl x509`.
/// 2. Add the new leaf alongside the existing leaf and intermediate values.
/// 3. Ship the app update before removing the expired leaf value.
/// 4. Replace the intermediate value only if Supabase changes certificate
///    authorities.
private final class MerianTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (
            URLSession.AuthChallengeDisposition,
            URLCredential?
        ) -> Void
    ) {
        #if DEBUG
        completionHandler(.performDefaultHandling, nil)
        #else
        guard MerianTLSCertificatePinPolicy.requiresPinning(
            host: challenge.protectionSpace.host
        ), challenge.protectionSpace.authenticationMethod
            == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            MerianLog.network.error(
                "TLS cert pinning could not evaluate trust for \(challenge.protectionSpace.host, privacy: .public)"
            )
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let systemTrustIsValid = SecTrustEvaluateWithError(serverTrust, nil)
        let chainHashes = (
            SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate]
        )?.map { certificate in
            let data = SecCertificateCopyData(certificate) as Data
            return Data(SHA256.hash(data: data)).base64EncodedString()
        }
        guard MerianTLSCertificatePinPolicy.accepts(
            systemTrustIsValid: systemTrustIsValid,
            certificateChainHashes: chainHashes
        ) else {
            MerianLog.network.error(
                "TLS trust or cert pinning failed for \(challenge.protectionSpace.host, privacy: .public)"
            )
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
        #endif
    }
}

/// One bounded response collector. The pinned owner supplies and retires its scoped session.
struct ProtectedInsightChatDataTask: Sendable {
    func response(using session: URLSession, request: URLRequest,
                  timeout: TimeInterval = ProtectedInsightChatBudget.requestSeconds, claimExpiresAt: Date? = nil) async throws -> (Data, URLResponse) {
        try await PinnedBoundedJSONDataTask(maximumBytes: 32_768).response(using: session, request: request, timeout: timeout) {
            if let claimExpiresAt { try ProtectedInsightChatBudget.requireDispatch(claimExpiresAt: claimExpiresAt) }
        }
    }
}

/// Shared bounded JSON collection; callers own route, budget, account and mutation policy.
final class PinnedBoundedJSONDataTask: NSObject, URLSessionDataDelegate, Sendable {
    private typealias Reply = (Data, URLResponse)
    private struct State {
        var continuation: CheckedContinuation<Reply, Error>?
        var task: URLSessionDataTask?
        var response: URLResponse?
        var data = Data()
        var finished = false
    }
    private struct Completion {
        let continuation: CheckedContinuation<Reply, Error>?
        let task: URLSessionDataTask?
        let result: Result<Reply, Error>
    }
    private let tlsDelegate = MerianTLSDelegate()
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let limit: Int
    init(maximumBytes: Int) { limit = maximumBytes; super.init() }
    private static let deadlineQueue = DispatchQueue(label: "com.merian.bounded-json-deadline")

    func response(using session: URLSession, request: URLRequest, timeout: TimeInterval,
                  beforeStart: @Sendable () throws -> Void = {}) async throws -> (Data, URLResponse) {
        guard limit > 0, timeout.isFinite, timeout > 0 else { throw URLError(.timedOut) }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                do {
                    try beforeStart()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let task = session.dataTask(with: request)
                task.delegate = self
                let start = state.withLock { value in
                    guard !value.finished else { return false }
                    value.continuation = continuation
                    value.task = task
                    return true
                }
                guard start else {
                    task.cancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                task.resume()
                Self.deadlineQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(error: URLError(.timedOut))
                }
            }
        } onCancel: {
            self.finish(error: CancellationError())
        }
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
        tlsDelegate.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error: error)
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
            defer { value.continuation = nil; value.task = nil; value.response = nil; value.data = Data() }
            return Completion(continuation: value.continuation, task: value.task, result: result)
        }
        guard let pending else { return }
        if error != nil { pending.task?.cancel() }
        pending.continuation?.resume(with: pending.result)
    }
}

/// One file PUT, a bounded response wait, and an independently joined task lifetime.
/// No ticket validation, retry, remote closure or staging-copy proof is implied.
/// The caller must own the file until waitForLocalTermination() completes.
final class PinnedPhotoUploadTask: NSObject, URLSessionDataDelegate, Sendable {
    private typealias Reply = HTTPURLResponse
    private struct State {
        var started = false, callerFinished = false, terminated = false
        var continuation: CheckedContinuation<Reply, Error>?
        var task: URLSessionUploadTask?
        var response: HTTPURLResponse?
        var receivedBytes = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
    }
    private struct Completion {
        let continuation: CheckedContinuation<Reply, Error>?
        let task: URLSessionUploadTask?
        let result: Result<Reply, Error>
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let session: URLSession
    private let tlsDelegate = MerianTLSDelegate()
    private static let deadlineQueue = DispatchQueue(label: "com.merian.photo-upload-deadline")
    private static let responseLimit = 4096
    #if DEBUG
    private let completionPause: (@Sendable () -> Void)?
    private let beforeResume: (@Sendable () -> Void)?
    init(session: URLSession, completionPause: (@Sendable () -> Void)? = nil, beforeResume: (@Sendable () -> Void)? = nil) {
        self.session = session; self.completionPause = completionPause; self.beforeResume = beforeResume; super.init()
    }
    #else
    init(session: URLSession) { self.session = session; super.init() }
    #endif

    func response(for request: URLRequest, fromFile file: URL, timeout: TimeInterval, expiresAtMilliseconds: Int64? = nil) async throws -> HTTPURLResponse {
        guard state.withLock({ value in
            guard !value.started else { return false }; value.started = true; return true
        }) else { throw URLError(.badURL) }
        defer { resolveNoTask() }
        guard timeout.isFinite, timeout > 0, timeout <= 300 else { throw URLError(.timedOut) }
        guard file.isFileURL, request.httpMethod == "PUT", request.httpBody == nil, request.httpBodyStream == nil,
              let url = request.url, url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else { throw URLError(.badURL) }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                // Task creation/registration is atomic with cancellation. Even
                // a cancelled suspended task remains retained until its callback.
                var deadline = DispatchTime.now() + timeout
                var rejection: any Error = CancellationError()
                let task = state.withLock { value -> URLSessionUploadTask? in
                    guard !value.callerFinished else { return nil }
                    if let expiresAtMilliseconds {
                        let observedAt = DispatchTime.now()
                        let remaining = Double(expiresAtMilliseconds) / 1000 - Date().timeIntervalSince1970
                        guard remaining.isFinite, remaining > 0 else { rejection = URLError(.timedOut); return nil }
                        deadline = min(deadline, observedAt + remaining)
                    }
                    let task = session.uploadTask(with: request, fromFile: file)
                    task.delegate = self; value.task = task; value.continuation = continuation
                    return task
                }
                guard let task else { continuation.resume(throwing: rejection); return }
                Self.deadlineQueue.asyncAfter(deadline: deadline) { [weak self] in
                    self?.finish(error: URLError(.timedOut))
                }
                #if DEBUG
                beforeResume?()
                #endif
                guard DispatchTime.now() < deadline,
                      expiresAtMilliseconds.map({ Double($0) / 1000 > Date().timeIntervalSince1970 }) ?? true else {
                    // The suspended task is retained until its cancellation callback.
                    finish(error: URLError(.timedOut)); return
                }
                task.resume()
            }
        } onCancel: { self.finish(error: CancellationError()) }
    }

    /// Cancellation of the joiner never manufactures a drain acknowledgement.
    /// Call after response has started, including after it throws.
    func waitForLocalTermination() async {
        await withCheckedContinuation { continuation in
            let done = state.withLock { value in
                if value.terminated { return true }; value.waiters.append(continuation); return false
            }
            if done { continuation.resume() }
        }
    }
    private func resolveNoTask() {
        let waiters = state.withLock { value -> [CheckedContinuation<Void, Never>] in
            guard value.task == nil, !value.terminated else { return [] }
            value.terminated = true; defer { value.waiters.removeAll() }; return value.waiters
        }
        waiters.forEach { $0.resume() }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse,
              response.expectedContentLength <= Int64(Self.responseLimit) else {
            finish(error: URLError(.dataLengthExceedsMaximum)); completionHandler(.cancel); return
        }
        let accepted = state.withLock { value in
            guard !value.callerFinished else { return false }; value.response = response; return true
        }
        completionHandler(accepted ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overflow = state.withLock { value in
            guard !value.callerFinished else { return false }
            guard data.count <= Self.responseLimit - value.receivedBytes else { return true }
            value.receivedBytes += data.count; return false
        }
        // Count and discard; never accumulate arbitrary storage error bodies.
        if overflow { finish(error: URLError(.dataLengthExceedsMaximum)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // A presigned request must never negotiate another credential or let
        // Foundation resend the body to answer an authentication challenge.
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            finish(error: URLError(.userAuthenticationRequired))
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        tlsDelegate.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        finish(error: URLError(.redirectToNonExistentLocation)); completionHandler(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        #if DEBUG
        completionPause?()
        #endif
        finish(error: error)
        let waiters = state.withLock { value in
            value.terminated = true; value.task = nil; value.response = nil
            defer { value.waiters.removeAll() }; return value.waiters
        }
        waiters.forEach { $0.resume() }
    }
    private func finish(error: Error?) {
        let pending = state.withLock { value -> Completion? in
            guard !value.callerFinished else { return nil }
            value.callerFinished = true
            let result: Result<Reply, Error>
            if let error { result = .failure(error) } else if let response = value.response {
                result = .success(response)
            } else { result = .failure(URLError(.badServerResponse)) }
            defer { value.continuation = nil }
            return Completion(continuation: value.continuation, task: value.task, result: result)
        }
        guard let pending else { return }
        if error != nil { pending.task?.cancel() }
        pending.continuation?.resume(with: pending.result)
    }
}
