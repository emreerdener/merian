import Foundation
import Testing

@testable import Merian

@Suite("Authenticated Request Executor")
struct AuthenticatedRequestExecutorTests {
    @Test func retryKeepsExactBodyAndInitiatingAccountBinding() async throws {
        let initiatingUserID = UUID()
        let replacementUserID = UUID()
        let body = Data(#"{"scan_id":"scan-1"}"#.utf8)
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [initiatingUserID, replacementUserID],
            outcomes: [
                .response(statusCode: 500, data: Data("{}".utf8)),
                .response(statusCode: 200, data: Data(#"{"ok":true}"#.utf8))
            ]
        )
        let executor = makeExecutor(probe: probe)

        let result = try await executor.execute(try makeRequest(
            function: "identify-multimodal",
            body: body,
            idempotencyKey: "stable-key"
        ))

        #expect(result.0 == Data(#"{"ok":true}"#.utf8))
        #expect(probe.authUserIDRequestCount == 2)
        #expect(probe.sleeps == [2_000_000_000])
        #expect(probe.attempts.count == 2)
        for attempt in probe.attempts {
            #expect(attempt.expectedAuthUserID == initiatingUserID)
            #expect(attempt.request.httpBody == body)
            #expect(attempt.request.timeoutInterval == 37)
            #expect(
                attempt.request.value(
                    forHTTPHeaderField: "Idempotency-Key"
                ) == "stable-key"
            )
            #expect(
                attempt.request.value(
                    forHTTPHeaderField: "X-Merian-Entitlement-Protocol"
                ) == "3"
            )
        }
    }

    @Test func refreshableUnauthorizedAppliesOrdinaryRefreshAndRetriesOnce()
        async throws {
        let userID = UUID()
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [userID, userID],
            outcomes: [
                .response(
                    statusCode: 401,
                    data: Data(#"{"code":"invalid_session_token"}"#.utf8)
                ),
                .response(statusCode: 200, data: Data("{}".utf8))
            ],
            refreshResult: true
        )

        _ = try await makeExecutor(probe: probe).execute(try makeRequest(
            function: "get-explore-feed"
        ))

        #expect(probe.refreshTargets == [.ordinary])
        #expect(probe.attempts.count == 2)
        #expect(probe.sleeps.isEmpty)
        #expect(
            probe.attempts.allSatisfy {
                $0.expectedAuthUserID == userID
            }
        )
    }

    @Test func transitionOwnedUnauthorizedUsesItsExactRefreshTarget()
        async throws {
        let owner = AuthTransitionToken(id: UUID(), kind: .accountDeletion)
        let expectedUserID = UUID()
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [],
            outcomes: [
                .response(
                    statusCode: 401,
                    data: Data(#"{"code":"auth_session_missing"}"#.utf8)
                ),
                .response(statusCode: 200, data: Data("{}".utf8))
            ],
            refreshResult: true
        )

        _ = try await makeExecutor(probe: probe).execute(try makeRequest(
            function: "safe-delete",
            authTransitionOwner: owner,
            expectedAuthUserID: expectedUserID
        ))

        #expect(probe.authUserIDRequestCount == 0)
        #expect(probe.refreshTargets == [.transitionOwned(owner)])
        #expect(probe.attempts.count == 2)
        #expect(probe.attempts.allSatisfy {
            $0.authTransitionOwner == owner
                && $0.expectedAuthUserID == expectedUserID
        })
    }

    @Test func unavailableRouteUsesBoundedOneTwoFourSecondSchedule()
        async throws {
        let userID = UUID()
        let unavailable = AuthenticatedRequestExecutorProbe.Outcome.response(
            statusCode: 404,
            data: Data(#"{"code":"NOT_FOUND"}"#.utf8),
            headers: ["SB-Error-Code": "NOT_FOUND"]
        )
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [userID, userID, userID, userID],
            outcomes: [unavailable, unavailable, unavailable, unavailable]
        )

        do {
            _ = try await makeExecutor(probe: probe).execute(try makeRequest(
                function: "get-explore-feed"
            ))
            Issue.record("Expected bounded route-unavailable failure")
        } catch MerianError.edgeFunctionUnavailable {
            // Expected after the fourth attempt exhausts the 1/2/4 schedule.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(probe.attempts.count == 4)
        #expect(probe.authUserIDRequestCount == 4)
        #expect(probe.sleeps == [
            1_000_000_000,
            2_000_000_000,
            4_000_000_000
        ])
    }

    @Test func paymentRequiredRunsEntitlementRecoveryBeforeReturningHTTPError()
        async throws {
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [UUID()],
            outcomes: [
                .response(
                    statusCode: 402,
                    data: Data(#"{"code":"payment_required"}"#.utf8)
                )
            ]
        )

        do {
            _ = try await makeExecutor(probe: probe).execute(try makeRequest(
                function: "identify-multimodal"
            ))
            Issue.record("Expected payment-required HTTP failure")
        } catch let MerianError.httpError(statusCode, message) {
            #expect(statusCode == 402)
            #expect(message == #"{"code":"payment_required"}"#)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(probe.paymentRequiredCount == 1)
        #expect(probe.aiConsentRequiredCount == 0)
        #expect(probe.attempts.count == 1)
    }

    @Test func serverConsentRejectionClosesConsentGateWithoutRetry()
        async throws {
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [UUID()],
            outcomes: [
                .response(
                    statusCode: 403,
                    data: Data(#"{"code":"ai_consent_required"}"#.utf8)
                )
            ]
        )

        await #expect(throws: MerianError.aiConsentRequired) {
            try await makeExecutor(probe: probe).execute(try makeRequest(
                function: "identify-multimodal"
            ))
        }

        #expect(probe.aiConsentRequiredCount == 1)
        #expect(probe.paymentRequiredCount == 0)
        #expect(probe.attempts.count == 1)
        #expect(probe.sleeps.isEmpty)
    }

    @Test func missingGuestSessionRegeneratesAndRetriesWithBoundAccount()
        async throws {
        let initiatingUserID = UUID()
        let replacementUserID = UUID()
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [initiatingUserID, replacementUserID],
            outcomes: [
                .response(
                    statusCode: 401,
                    data: Data(#"{"code":"auth_session_missing"}"#.utf8)
                ),
                .response(statusCode: 200, data: Data("{}".utf8))
            ],
            unauthorizedRecoveryState: .init(
                hasAuthenticatedOAuth: false,
                isGuestUser: true,
                purchaseIdentityHandoffPending: false
            ),
            resetGhostSessionResult: true
        )

        _ = try await makeExecutor(probe: probe).execute(try makeRequest(
            function: "get-explore-feed"
        ))

        #expect(probe.refreshTargets == [.ordinary])
        #expect(probe.resetGhostSessionCount == 1)
        #expect(probe.clearLocalSessionCount == 0)
        #expect(probe.sleeps == [1_500_000_000])
        #expect(probe.attempts.count == 2)
        #expect(probe.attempts.allSatisfy {
            $0.expectedAuthUserID == initiatingUserID
        })
    }

    @Test func transientRetryNotifiesBodyReleaseForEachCompletedAttempt()
        async throws {
        let userID = UUID()
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [userID, userID],
            outcomes: [
                .urlError(.networkConnectionLost),
                .response(statusCode: 200, data: Data("{}".utf8))
            ]
        )

        _ = try await makeExecutor(probe: probe).execute(try makeRequest(
            function: "get-explore-feed",
            body: Data("{}".utf8),
            onRequestBodySent: {
                probe.recordRequestBodySent()
            }
        ))

        // The failed attempt releases immediately. The successful attempt's
        // response then invokes its transport fallback. Production callbacks
        // are idempotent because a logical request can reach both paths.
        #expect(probe.requestBodySentCount == 2)
        #expect(probe.attempts.count == 2)
        #expect(probe.sleeps == [2_000_000_000])
    }

    @Test func cancelledOwnerStopsBeforeIdentityOrTransportDispatch()
        async throws {
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [UUID()],
            outcomes: [.response(statusCode: 200, data: Data("{}".utf8))]
        )
        let executor = makeExecutor(probe: probe)
        let request = try makeRequest(function: "get-explore-feed")
        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await executor.execute(request)
        }

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected before account or transport work begins.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(probe.authUserIDRequestCount == 0)
        #expect(probe.attempts.isEmpty)
    }

    private func makeRequest(
        function: String,
        body: Data? = nil,
        idempotencyKey: String? = nil,
        onRequestBodySent: (@Sendable () -> Void)? = nil,
        authTransitionOwner: AuthTransitionToken? = nil,
        expectedAuthUserID: UUID? = nil
    ) throws -> AuthenticatedRequestExecutor.Request {
        let url = try #require(URL(
            string: "https://example.supabase.co/functions/v1/\(function)"
        ))
        return AuthenticatedRequestExecutor.Request(
            url: url,
            method: "POST",
            body: body,
            timeoutInterval: 37,
            idempotencyKey: idempotencyKey,
            allowsTransientTransportRetry: true,
            onRequestBodySent: onRequestBodySent,
            authTransitionOwner: authTransitionOwner,
            expectedAuthUserID: expectedAuthUserID
        )
    }

    private func makeExecutor(
        probe: AuthenticatedRequestExecutorProbe
    ) -> AuthenticatedRequestExecutor {
        AuthenticatedRequestExecutor(dependencies: .init(
            requestPayloadAuthUserID: {
                try probe.nextAuthUserID()
            },
            performTransport: { attempt in
                try probe.perform(attempt)
            },
            refreshSession: { target in
                probe.refresh(target)
            },
            unauthorizedRecoveryState: {
                probe.unauthorizedRecoveryState
            },
            resetGhostSession: {
                probe.resetGhostSession()
            },
            hasPendingPurchaseIdentityHandoff: {
                probe.purchaseIdentityHandoffPending
            },
            clearLocalSessionAfterAuthFailure: {
                probe.recordLocalSessionClear()
            },
            handlePaymentRequired: {
                probe.recordPaymentRequired()
            },
            handleAIConsentRequired: {
                probe.recordAIConsentRequired()
            },
            sleep: { delay in
                probe.recordSleep(delay)
            }
        ))
    }
}

private final class AuthenticatedRequestExecutorProbe: @unchecked Sendable {
    enum Outcome {
        case response(
            statusCode: Int,
            data: Data,
            headers: [String: String] = ["X-Merian-Handler": "1"]
        )
        case urlError(URLError.Code)
    }

    struct Attempt {
        let request: URLRequest
        let authTransitionOwner: AuthTransitionToken?
        let expectedAuthUserID: UUID?
    }

    private let lock = NSLock()
    private var remainingAuthUserIDs: [UUID]
    private var remainingOutcomes: [Outcome]
    private var capturedAttempts: [Attempt] = []
    private var capturedRefreshTargets: [
        AuthenticatedRequestRetryPolicy.UnauthorizedRefreshTarget
    ] = []
    private var capturedSleeps: [UInt64] = []
    private var capturedAuthUserIDRequestCount = 0
    private var capturedRequestBodySentCount = 0
    private var capturedResetGhostSessionCount = 0
    private var capturedClearLocalSessionCount = 0
    private var capturedPaymentRequiredCount = 0
    private var capturedAIConsentRequiredCount = 0
    private let refreshResult: Bool
    private let resetGhostSessionResult: Bool

    let unauthorizedRecoveryState:
        AuthenticatedRequestExecutor.UnauthorizedRecoveryState
    let purchaseIdentityHandoffPending: Bool

    init(
        authUserIDs: [UUID],
        outcomes: [Outcome],
        refreshResult: Bool = false,
        unauthorizedRecoveryState:
            AuthenticatedRequestExecutor.UnauthorizedRecoveryState = .init(
                hasAuthenticatedOAuth: true,
                isGuestUser: false,
                purchaseIdentityHandoffPending: false
            ),
        resetGhostSessionResult: Bool = false,
        purchaseIdentityHandoffPending: Bool = false
    ) {
        remainingAuthUserIDs = authUserIDs
        remainingOutcomes = outcomes
        self.refreshResult = refreshResult
        self.unauthorizedRecoveryState = unauthorizedRecoveryState
        self.resetGhostSessionResult = resetGhostSessionResult
        self.purchaseIdentityHandoffPending =
            purchaseIdentityHandoffPending
    }

    var attempts: [Attempt] {
        locked { capturedAttempts }
    }

    var refreshTargets: [
        AuthenticatedRequestRetryPolicy.UnauthorizedRefreshTarget
    ] {
        locked { capturedRefreshTargets }
    }

    var sleeps: [UInt64] {
        locked { capturedSleeps }
    }

    var authUserIDRequestCount: Int {
        locked { capturedAuthUserIDRequestCount }
    }

    var requestBodySentCount: Int {
        locked { capturedRequestBodySentCount }
    }

    var resetGhostSessionCount: Int {
        locked { capturedResetGhostSessionCount }
    }

    var clearLocalSessionCount: Int {
        locked { capturedClearLocalSessionCount }
    }

    var paymentRequiredCount: Int {
        locked { capturedPaymentRequiredCount }
    }

    var aiConsentRequiredCount: Int {
        locked { capturedAIConsentRequiredCount }
    }

    func nextAuthUserID() throws -> UUID {
        try locked {
            capturedAuthUserIDRequestCount += 1
            guard !remainingAuthUserIDs.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return remainingAuthUserIDs.removeFirst()
        }
    }

    func perform(
        _ attempt: AuthenticatedRequestExecutor.TransportAttempt
    ) throws -> AuthenticatedRequestExecutor.TransportResult {
        try locked {
            capturedAttempts.append(Attempt(
                request: attempt.request,
                authTransitionOwner: attempt.authTransitionOwner,
                expectedAuthUserID: attempt.expectedAuthUserID
            ))
            guard !remainingOutcomes.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            switch remainingOutcomes.removeFirst() {
            case let .urlError(code):
                throw URLError(code)
            case let .response(statusCode, data, headers):
                guard let requestURL = attempt.request.url,
                      let response = HTTPURLResponse(
                    url: requestURL,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: headers
                ) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return AuthenticatedRequestExecutor.TransportResult(
                    data: data,
                    response: response,
                    notifyRequestBodySentIfNeeded:
                        attempt.body != nil
                            ? attempt.onRequestBodySent
                            : nil,
                    authCompletedAt: CFAbsoluteTimeGetCurrent()
                )
            }
        }
    }

    func refresh(
        _ target: AuthenticatedRequestRetryPolicy.UnauthorizedRefreshTarget
    ) -> Bool {
        locked {
            capturedRefreshTargets.append(target)
            return refreshResult
        }
    }

    func recordSleep(_ delay: UInt64) {
        locked { capturedSleeps.append(delay) }
    }

    func recordRequestBodySent() {
        locked { capturedRequestBodySentCount += 1 }
    }

    func resetGhostSession() -> Bool {
        locked {
            capturedResetGhostSessionCount += 1
            return resetGhostSessionResult
        }
    }

    func recordLocalSessionClear() {
        locked { capturedClearLocalSessionCount += 1 }
    }

    func recordPaymentRequired() {
        locked { capturedPaymentRequiredCount += 1 }
    }

    func recordAIConsentRequired() {
        locked { capturedAIConsentRequiredCount += 1 }
    }

    private func locked<Value>(_ operation: () throws -> Value) rethrows
        -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
