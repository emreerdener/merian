import Foundation
import os

/// Executes one authenticated URLSession attempt. Logical retry and recovery
/// remain in `AuthenticatedRequestExecutor`.
final class AuthenticatedTransportDispatcher {
    private let sessionTransport: PinnedNetworkTransport

    #if DEBUG
    var overridingAuthUserID: UUID?
    var overridingAuthSessionRefresh: (@Sendable () async -> Bool)?
    #endif

    init(sessionTransport: PinnedNetworkTransport) {
        self.sessionTransport = sessionTransport
    }

    func refreshActiveSessionForRetry() async -> Bool {
        #if DEBUG
        if let overridingAuthSessionRefresh {
            return await overridingAuthSessionRefresh()
        }
        #endif
        return await SupabaseManager.shared.refreshActiveSessionForRetry()
    }

    func requestPayloadAuthUserID() async throws -> UUID {
        #if DEBUG
        if sessionTransport.isUsingOverridingSession {
            guard let overridingAuthUserID else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            return overridingAuthUserID
        }
        #endif
        return try await MainActor.run {
            let manager = SupabaseManager.shared
            let lease = try manager.beginUnownedAccountBoundWork()
            defer { manager.finishAccountBoundWork(lease) }
            return lease.session.userID
        }
    }

    func makeAuthenticatedJSONRequest(
        url: URL,
        bodyData: Data,
        timeoutInterval: TimeInterval = 90,
        idempotencyKey: String? = nil,
        expectedAuthUserID: UUID? = nil
    ) async throws -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeoutInterval
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "3",
            forHTTPHeaderField: "X-Merian-Entitlement-Protocol"
        )
        if let idempotencyKey {
            request.setValue(
                idempotencyKey,
                forHTTPHeaderField: "Idempotency-Key"
            )
        }
        request.httpBody = bodyData

        let accountWorkLease = try await acquireAccountWorkLeaseIfRequired(
            expectedAuthUserID: expectedAuthUserID
        )

        do {
            #if DEBUG
            if !sessionTransport.isUsingOverridingSession {
                request = try await applyingAuthHeaders(
                    to: request,
                    expectedAuthUserID: expectedAuthUserID
                )
            }
            #else
            request = try await applyingAuthHeaders(
                to: request,
                expectedAuthUserID: expectedAuthUserID
            )
            #endif
            try await finishAndValidate(accountWorkLease)
            return request
        } catch {
            await finish(accountWorkLease)
            throw error
        }
    }

    func perform(
        _ attempt: AuthenticatedRequestExecutor.TransportAttempt
    ) async throws -> AuthenticatedRequestExecutor.TransportResult {
        let accountWorkLease: AccountBoundWorkLease?
        if attempt.authTransitionOwner == nil {
            accountWorkLease = try await acquireAccountWorkLeaseIfRequired(
                expectedAuthUserID: attempt.expectedAuthUserID
            )
        } else {
            accountWorkLease = nil
        }

        do {
            try await validateTransitionOwner(attempt.authTransitionOwner)

            var request = attempt.request
            #if DEBUG
            if !sessionTransport.isUsingOverridingSession {
                request = try await applyingAuthHeaders(
                    to: request,
                    authTransitionOwner: attempt.authTransitionOwner,
                    expectedAuthUserID: attempt.expectedAuthUserID
                )
            }
            #else
            request = try await applyingAuthHeaders(
                to: request,
                authTransitionOwner: attempt.authTransitionOwner,
                expectedAuthUserID: attempt.expectedAuthUserID
            )
            #endif
            try Task.checkCancellation()

            let constrainedNetwork = await MainActor.run {
                OfflineQueueManager.shared.isCurrentNetworkConstrained
            }
            try Task.checkCancellation()
            request.setValue(
                constrainedNetwork ? "true" : "false",
                forHTTPHeaderField: "X-Merian-Constrained-Network"
            )
            let authCompletedAt = CFAbsoluteTimeGetCurrent()

            let transportResult = try await dispatch(
                request: request,
                body: attempt.body,
                onRequestBodySent: attempt.onRequestBodySent
            )

            try await validateTransitionOwner(attempt.authTransitionOwner)
            try await finishAndValidate(accountWorkLease)

            return AuthenticatedRequestExecutor.TransportResult(
                data: transportResult.data,
                response: transportResult.response,
                notifyRequestBodySentIfNeeded:
                    transportResult.notifyRequestBodySentIfNeeded,
                authCompletedAt: authCompletedAt
            )
        } catch {
            await finish(accountWorkLease)
            throw error
        }
    }

    private func acquireAccountWorkLeaseIfRequired(
        expectedAuthUserID: UUID?
    ) async throws -> AccountBoundWorkLease? {
        #if DEBUG
        guard !sessionTransport.isUsingOverridingSession,
              !TestExecutionCoordinator.isRunningTests else {
            return nil
        }
        #endif

        if let admitted = try? await SupabaseManager.shared
            .beginUnownedAccountBoundWork(
                expectedUserID: expectedAuthUserID
            ) {
            return admitted
        }

        // A genuinely missing session may require serialized anonymous
        // bootstrap before exact-account admission can succeed.
        _ = try await SupabaseManager.shared.getValidAuthHeaders(
            expectedUserID: expectedAuthUserID
        )
        return try await SupabaseManager.shared.beginUnownedAccountBoundWork(
            expectedUserID: expectedAuthUserID
        )
    }

    private func applyingAuthHeaders(
        to request: URLRequest,
        authTransitionOwner: AuthTransitionToken? = nil,
        expectedAuthUserID: UUID?
    ) async throws -> URLRequest {
        var request = request
        let authHeaders = try await SupabaseManager.shared.getValidAuthHeaders(
            ownedBy: authTransitionOwner,
            expectedUserID: expectedAuthUserID
        )
        for (key, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func validateTransitionOwner(
        _ owner: AuthTransitionToken?
    ) async throws {
        guard let owner else { return }
        guard await SupabaseManager.shared.ownsAuthTransition(owner) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
    }

    private func finishAndValidate(
        _ lease: AccountBoundWorkLease?
    ) async throws {
        guard let lease else { return }
        guard await SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(lease)
        else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        await SupabaseManager.shared.finishAccountBoundWork(lease)
    }

    private func finish(_ lease: AccountBoundWorkLease?) async {
        guard let lease else { return }
        await SupabaseManager.shared.finishAccountBoundWork(lease)
    }

    private func dispatch(
        request: URLRequest,
        body: Data?,
        onRequestBodySent: (@Sendable () -> Void)?
    ) async throws -> TransportDispatchResult {
        guard let body, let onRequestBodySent else {
            let (data, response) = try await sessionTransport.data(for: request)
            return TransportDispatchResult(
                data: data,
                response: response,
                notifyRequestBodySentIfNeeded: nil
            )
        }

        let delegate = MerianRequestUploadDelegate(
            expectedBodyBytes: body.count,
            onBodySent: onRequestBodySent
        )
        let (data, response) = try await sessionTransport.data(
            for: request,
            delegate: delegate
        )
        let notify: @Sendable () -> Void = {
            delegate.notifyBodySentIfNeeded()
        }
        return TransportDispatchResult(
            data: data,
            response: response,
            notifyRequestBodySentIfNeeded: notify
        )
    }
}

private struct TransportDispatchResult {
    let data: Data
    let response: URLResponse
    let notifyRequestBodySentIfNeeded: (@Sendable () -> Void)?
}

private final class MerianRequestUploadDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable {
    private let expectedBodyBytes: Int64
    private let onBodySent: @Sendable () -> Void
    private let lock = NSLock()
    private var didNotify = false

    init(
        expectedBodyBytes: Int,
        onBodySent: @escaping @Sendable () -> Void
    ) {
        self.expectedBodyBytes = Int64(expectedBodyBytes)
        self.onBodySent = onBodySent
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesSent >= expectedBodyBytes else { return }
        notifyBodySentIfNeeded()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        guard let transaction = metrics.transactionMetrics.last else { return }
        let requestUpload = transaction.requestStartDate.flatMap { start in
            transaction.requestEndDate.map { $0.timeIntervalSince(start) }
        }
        let timeToFirstByte = transaction.requestEndDate.flatMap { requestEnd in
            transaction.responseStartDate.map { $0.timeIntervalSince(requestEnd) }
        }
        let responseTransfer = transaction.responseStartDate.flatMap { responseStart in
            transaction.responseEndDate.map {
                $0.timeIntervalSince(responseStart)
            }
        }
        MerianLog.network.debug(
            "[⏱ BENCH] URLSession request_upload=\(String(format: "%.3f", requestUpload ?? 0), privacy: .public)s ttfb_after_upload=\(String(format: "%.3f", timeToFirstByte ?? 0), privacy: .public)s response_transfer=\(String(format: "%.3f", responseTransfer ?? 0), privacy: .public)s"
        )
    }

    func notifyBodySentIfNeeded() {
        lock.lock()
        let shouldNotify = !didNotify
        didNotify = true
        lock.unlock()
        if shouldNotify { onBodySent() }
    }
}
