import Foundation

/// Executes one logical authenticated request across its bounded transport,
/// route, and Auth-recovery attempts. The network client injects the
/// authenticated dispatcher backed by the single pinned-session owner; this
/// executor constructs no session or client singleton of its own.
struct AuthenticatedRequestExecutor {
    struct TransportResult {
        let data: Data
        let response: URLResponse
        /// Completes this transport attempt's upload notification. A logical
        /// request can make more than one attempt, so the callback supplied by
        /// `Request` remains intentionally idempotent across invocations.
        let notifyRequestBodySentIfNeeded: (@Sendable () -> Void)?
        let authCompletedAt: CFAbsoluteTime
    }

    struct Request {
        let url: URL
        let method: String
        let body: Data?
        let timeoutInterval: TimeInterval
        let idempotencyKey: String?
        let allowsTransientTransportRetry: Bool
        let onRequestBodySent: (@Sendable () -> Void)?
        let authTransitionOwner: AuthTransitionToken?
        let expectedAuthUserID: UUID?
    }

    struct TransportAttempt {
        let request: URLRequest
        let body: Data?
        let onRequestBodySent: (@Sendable () -> Void)?
        let authTransitionOwner: AuthTransitionToken?
        let expectedAuthUserID: UUID?
    }

    struct UnauthorizedRecoveryState {
        let hasAuthenticatedOAuth: Bool
        let isGuestUser: Bool
        let purchaseIdentityHandoffPending: Bool
    }

    struct Dependencies {
        let requestPayloadAuthUserID: () async throws -> UUID
        let performTransport: (
            TransportAttempt
        ) async throws -> TransportResult
        let refreshSession: (
            AuthenticatedRequestRetryPolicy.UnauthorizedRefreshTarget
        ) async -> Bool
        let unauthorizedRecoveryState: () async -> UnauthorizedRecoveryState
        let resetGhostSession: () async -> Bool
        let hasPendingPurchaseIdentityHandoff: () async -> Bool
        let clearLocalSessionAfterAuthFailure: () async -> Void
        let handlePaymentRequired: () async -> Void
        let handleAIConsentRequired: () async -> Void
        let sleep: (UInt64) async throws -> Void

        static func live(
            requestPayloadAuthUserID: @escaping () async throws -> UUID,
            performTransport: @escaping (
                TransportAttempt
            ) async throws -> TransportResult,
            refreshOrdinarySession: @escaping () async -> Bool
        ) -> Self {
            Self(
                requestPayloadAuthUserID: requestPayloadAuthUserID,
                performTransport: performTransport,
                refreshSession: { target in
                    switch target {
                    case .ordinary:
                        return await refreshOrdinarySession()
                    case let .transitionOwned(owner):
                        return await SupabaseManager.shared
                            .refreshExpectedSessionForAuthenticatedRequest(
                                ownedBy: owner
                            )
                    }
                },
                unauthorizedRecoveryState: {
                    let hasAuthenticatedOAuth = KeychainManager.shared.bool(
                        forKey: KeychainKeys.hasAuthenticatedOAuth
                    )
                    let isGuest = await SupabaseManager.shared.isGuestUser
                    let handoffPending = await SupabaseManager.shared
                        .hasPendingPurchaseIdentityHandoffFailClosed()
                    return UnauthorizedRecoveryState(
                        hasAuthenticatedOAuth: hasAuthenticatedOAuth,
                        isGuestUser: isGuest,
                        purchaseIdentityHandoffPending: handoffPending
                    )
                },
                resetGhostSession: {
                    await SupabaseManager.shared.resetGhostSessionForRetry()
                },
                hasPendingPurchaseIdentityHandoff: {
                    await SupabaseManager.shared
                        .hasPendingPurchaseIdentityHandoffFailClosed()
                },
                clearLocalSessionAfterAuthFailure: {
                    await SupabaseManager.shared
                        .clearLocalSessionAfterAuthFailure()
                },
                handlePaymentRequired: {
                    await MainActor.run {
                        EntitlementManager.shared
                            .invalidateComplimentaryProofAfterPaymentRequired()
                    }
                    await EntitlementManager.shared.refreshCurrentSession()
                },
                handleAIConsentRequired: {
                    await MainActor.run {
                        do {
                            try ConsentManager.shared
                                .requireCurrentConsentReapprovalAfterServerRejection()
                        } catch {
                            MerianLog.auth.error(
                                "Server-required consent reapproval could not be persisted; the in-memory gate remains closed; kind=\(MerianLog.errorKind(error), privacy: .public)."
                            )
                        }
                    }
                },
                sleep: { delay in
                    try await Task.sleep(nanoseconds: delay)
                }
            )
        }
    }

    private struct AttemptState {
        let isRetry: Bool
        let functionRouteRetryAttempt: Int
        let expectedAuthUserID: UUID?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func execute(_ request: Request) async throws
        -> (Data, HTTPURLResponse) {
        try await execute(
            request,
            state: AttemptState(
                isRetry: false,
                functionRouteRetryAttempt: 0,
                expectedAuthUserID: request.expectedAuthUserID
            )
        )
    }

    private func execute(
        _ request: Request,
        state: AttemptState
    ) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()

        // Bind every recursive attempt to the initiating account. Re-resolving
        // the current account before each attempt preserves the existing fail-
        // closed behavior when Auth rotates during a retry delay.
        let retryChainAuthUserID: UUID?
        if request.authTransitionOwner == nil {
            let initiatingUserID = try await dependencies
                .requestPayloadAuthUserID()
            retryChainAuthUserID = AuthenticatedRequestRetryPolicy.boundUserID(
                explicitUserID: state.expectedAuthUserID,
                initiatingUserID: initiatingUserID
            )
        } else {
            retryChainAuthUserID = state.expectedAuthUserID
        }

        let requestStart = CFAbsoluteTimeGetCurrent()
        var urlRequest = URLRequest(
            url: request.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: request.timeoutInterval
        )
        urlRequest.httpMethod = request.method
        urlRequest.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.setValue(
            "3",
            forHTTPHeaderField: "X-Merian-Entitlement-Protocol"
        )
        if let idempotencyKey = request.idempotencyKey {
            urlRequest.setValue(
                idempotencyKey,
                forHTTPHeaderField: "Idempotency-Key"
            )
        }
        urlRequest.httpBody = request.body

        let transport: TransportResult
        do {
            transport = try await dependencies.performTransport(
                TransportAttempt(
                    request: urlRequest,
                    body: request.body,
                    onRequestBodySent: request.onRequestBodySent,
                    authTransitionOwner: request.authTransitionOwner,
                    expectedAuthUserID: retryChainAuthUserID
                )
            )
        } catch let urlError as URLError {
            // A failed inline request can no longer exclusively own its uplink.
            // The callback is idempotent if upload progress already fired.
            request.onRequestBodySent?()
            // Normalize transport cancellation only when this task owns it.
            try Task.checkCancellation()

            let transientCodes: Set<URLError.Code> = [
                .timedOut,
                .networkConnectionLost,
                .cannotConnectToHost,
                .dnsLookupFailed,
                .notConnectedToInternet
            ]
            if request.allowsTransientTransportRetry,
               transientCodes.contains(urlError.code),
               !state.isRetry,
               AuthenticatedRequestRetryPolicy.canReplayAfterAmbiguousFailure(
                   url: request.url,
                   method: request.method,
                   idempotencyKey: request.idempotencyKey
               ) {
                MerianLog.network.debug(
                    "Transient network error \(urlError.code.rawValue, privacy: .public) — retrying in 2s."
                )
                try await dependencies.sleep(2_000_000_000)
                return try await execute(
                    request,
                    state: AttemptState(
                        isRetry: true,
                        functionRouteRetryAttempt:
                            state.functionRouteRetryAttempt,
                        expectedAuthUserID: retryChainAuthUserID
                    )
                )
            }
            throw urlError
        }

        // A response proves the body finished sending even when a custom
        // URLProtocol did not report upload progress.
        transport.notifyRequestBodySentIfNeeded?()
        try Task.checkCancellation()

        guard let httpResponse = transport.response as? HTTPURLResponse else {
            throw MerianError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            return try await handleFailure(
                request,
                state: state,
                retryChainAuthUserID: retryChainAuthUserID,
                data: transport.data,
                response: httpResponse
            )
        }

        logTiming(
            request: request,
            response: httpResponse,
            responseData: transport.data,
            requestStart: requestStart,
            authCompletedAt: transport.authCompletedAt
        )
        return (transport.data, httpResponse)
    }

    private func handleFailure(
        _ request: Request,
        state: AttemptState,
        retryChainAuthUserID: UUID?,
        data: Data,
        response: HTTPURLResponse
    ) async throws -> (Data, HTTPURLResponse) {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
        let safeCode = EdgeFunctionErrorPolicy.stableCode(responseData: data)
            ?? "unclassified"
        MerianLog.network.debug(
            "Edge function failed; route=\(request.url.lastPathComponent, privacy: .public) status=\(response.statusCode, privacy: .public) code=\(safeCode, privacy: .public)."
        )

        if EdgeFunctionRoutePolicy.isUnavailable(
            evidence: EdgeFunctionRouteResponseEvidence(response: response),
            responseData: data
        ) {
            guard let delay = EdgeFunctionRoutePolicy.unavailableRetryDelay(
                forAttempt: state.functionRouteRetryAttempt
            ) else {
                throw MerianError.edgeFunctionUnavailable
            }
            let delaySeconds = delay / 1_000_000_000
            MerianLog.network.debug(
                "Supabase route metadata unavailable for \(request.url.lastPathComponent, privacy: .public) — retrying in \(delaySeconds, privacy: .public)s (attempt \(state.functionRouteRetryAttempt + 1, privacy: .public)/\(EdgeFunctionRoutePolicy.unavailableRetryLimit, privacy: .public))."
            )
            try await dependencies.sleep(delay)
            return try await execute(
                request,
                state: AttemptState(
                    isRetry: state.isRetry,
                    functionRouteRetryAttempt:
                        state.functionRouteRetryAttempt + 1,
                    expectedAuthUserID: retryChainAuthUserID
                )
            )
        }

        if response.statusCode == 402 {
            await dependencies.handlePaymentRequired()
        }

        if response.statusCode == 403,
           EdgeFunctionErrorPolicy.stableCode(responseData: data)
            == "ai_consent_required" {
            await dependencies.handleAIConsentRequired()
            throw MerianError.aiConsentRequired
        }

        if response.statusCode == 401, !state.isRetry {
            return try await handleUnauthorized(
                request,
                state: state,
                retryChainAuthUserID: retryChainAuthUserID,
                data: data,
                errorMessage: errorMessage
            )
        }

        // A transport failure or 5xx can occur after a mutation committed.
        // Replay only reads and server-idempotency-aware calls.
        if response.statusCode >= 500,
           !state.isRetry,
           AuthenticatedRequestRetryPolicy.canReplayAfterAmbiguousFailure(
               url: request.url,
               method: request.method,
               idempotencyKey: request.idempotencyKey
           ) {
            MerianLog.network.debug(
                "Server error \(response.statusCode, privacy: .public) — retrying in 2s."
            )
            try await dependencies.sleep(2_000_000_000)
            return try await execute(
                request,
                state: AttemptState(
                    isRetry: true,
                    functionRouteRetryAttempt:
                        state.functionRouteRetryAttempt,
                    expectedAuthUserID: retryChainAuthUserID
                )
            )
        }

        throw MerianError.httpError(
            statusCode: response.statusCode,
            message: errorMessage
        )
    }

    private func handleUnauthorized(
        _ request: Request,
        state: AttemptState,
        retryChainAuthUserID: UUID?,
        data: Data,
        errorMessage: String
    ) async throws -> (Data, HTTPURLResponse) {
        guard EdgeFunctionErrorPolicy.isRefreshableAuthSessionError(
            responseData: data,
            fallbackMessage: errorMessage
        ) else {
            MerianLog.network.debug(
                "Unclassified unauthorized response preserved the active Supabase identity."
            )
            throw MerianError.invalidResponse
        }

        let refreshTarget = AuthenticatedRequestRetryPolicy
            .unauthorizedRefreshTarget(
                authTransitionOwner: request.authTransitionOwner
            )
        if await dependencies.refreshSession(refreshTarget) {
            return try await execute(
                request,
                state: AttemptState(
                    isRetry: true,
                    functionRouteRetryAttempt:
                        state.functionRouteRetryAttempt,
                    expectedAuthUserID: retryChainAuthUserID
                )
            )
        }

        let recoveryState = await dependencies.unauthorizedRecoveryState()
        if AuthenticatedRequestRetryPolicy
            .shouldRegenerateSessionAfterUnauthorized(
                responseProvesMissingSession: true,
                hasAuthenticatedOAuth:
                    recoveryState.hasAuthenticatedOAuth,
                isGuestUser: recoveryState.isGuestUser,
                purchaseIdentityHandoffPending:
                    recoveryState.purchaseIdentityHandoffPending
            ) {
            MerianLog.network.debug(
                "Missing anonymous auth session detected — regenerating anonymous session."
            )
            if await dependencies.resetGhostSession() {
                try await dependencies.sleep(1_500_000_000)
                return try await execute(
                    request,
                    state: AttemptState(
                        isRetry: true,
                        functionRouteRetryAttempt:
                            state.functionRouteRetryAttempt,
                        expectedAuthUserID: retryChainAuthUserID
                    )
                )
            }

            // A handoff may become durable between policy evaluation and the
            // attempted reset. Never clear that exact session.
            if !(await dependencies.hasPendingPurchaseIdentityHandoff()) {
                await dependencies.clearLocalSessionAfterAuthFailure()
            }
        } else {
            MerianLog.network.debug(
                "Auth session recovery failed for authenticated user; preserving local session."
            )
        }

        throw MerianError.invalidResponse
    }

    private func logTiming(
        request: Request,
        response: HTTPURLResponse,
        responseData: Data,
        requestStart: CFAbsoluteTime,
        authCompletedAt: CFAbsoluteTime
    ) {
        let responseCompletedAt = CFAbsoluteTimeGetCurrent()
        MerianLog.network.debug(
            "[⏱ BENCH] HTTP \(request.url.lastPathComponent, privacy: .public) auth=\(String(format: "%.3f", authCompletedAt - requestStart), privacy: .public)s transfer+server=\(String(format: "%.3f", responseCompletedAt - authCompletedAt), privacy: .public)s status=\(response.statusCode, privacy: .public) requestBytes=\(request.body?.count ?? 0, privacy: .public) responseBytes=\(responseData.count, privacy: .public)"
        )
        if let serverTiming = response.value(
            forHTTPHeaderField: "Server-Timing"
        ) {
            MerianLog.network.debug(
                "[⏱ BENCH] Server-Timing \(serverTiming, privacy: .public) region=\(response.value(forHTTPHeaderField: "X-Merian-Edge-Region") ?? "unknown", privacy: .public)"
            )
        }
    }
}
