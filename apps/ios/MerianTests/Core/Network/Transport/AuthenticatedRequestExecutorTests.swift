import Foundation
import Testing

@testable import Merian

@Suite("Authenticated Request Executor")
struct AuthenticatedRequestExecutorTests {
    @Test func failedIdentificationResponsesAreMeasuredBeforeErrorHandling() async throws {
        for status in [400, 503] {
            let probe = AuthenticatedRequestExecutorProbe(
                authUserIDs: [UUID()],
                outcomes: [.response(statusCode: status, data: Data("synthetic-private-response".utf8))]
            )
            var records: [String] = []
            let executor = makeExecutor(probe: probe, recordIdentificationMeasurement: { records.append($0) })
            do {
                _ = try await executor.execute(try makeRequest(function: "identify-multimodal"))
                Issue.record("Expected failed identification")
            } catch {
                // The HTTP response must be recorded even if retry/error handling throws.
            }
            #expect(records.count == 1)
            let text = try #require(records.first)
            #expect(!text.contains("synthetic-private-response"))
            let value = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            #expect(value["status"] as? Int == status)
            #expect(value["delivery"] as? String == "unavailable")
            #expect(value["diagnostics"] is NSNull)
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    @MainActor
    @Test func onlyInitialLiveFixedContextResponseGetsProfile() async throws {
        let header = "{\"version\":1,\"provider\":\"gemini\",\"requestedModel\":\"gemini-2.5-pro\",\"returnedModel\":\"gemini-2.5-pro\",\"backendBundleSha256\":\"\(String(repeating: "a", count: 64))\",\"usage\":null}"
        let success = AuthenticatedRequestExecutorProbe.Outcome.response(
            statusCode: 200, data: Data("{}".utf8), headers: ["X-Merian-Identification": header]
        )
        let attempts: [[AuthenticatedRequestExecutorProbe.Outcome]] = [
            [success], [.urlError(.networkConnectionLost), success],
            [.response(statusCode: 503, data: Data("{}".utf8)), success],
            [.response(statusCode: 404, data: Data(#"{"code":"NOT_FOUND"}"#.utf8), headers: ["SB-Error-Code": "NOT_FOUND"]), success]
        ]
        for current in [true, false] {
            for outcomes in attempts {
                let probe = AuthenticatedRequestExecutorProbe(authUserIDs: [UUID(), UUID()], outcomes: outcomes)
                var records: [String] = []
                let executor = makeExecutor(probe: probe, recordIdentificationMeasurement: { records.append($0) })
                let body = try fixedAudioMeasurementTestBody()
                var request = try makeRequest(function: "identify-multimodal", body: body, idempotencyKey: "synthetic-key")
                request.measurementContext = IdentificationMeasurementContext.fixedAudio(
                    body: body, telemetry: DebugIdentificationReplayProfile.audioMinimalV1.makeTelemetry(),
                    validateAttempt: { if !current { throw CancellationError() } }
                )
                _ = try await executor.execute(request)
                let record = try #require(records.last)
                let value = try #require(JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any])
                if current && outcomes.count == 1 {
                    #expect(value["contextProfile"] as? String == "audio-minimal-v1")
                } else {
                    #expect(value["contextProfile"] is NSNull)
                }
            }
        }
    }
    #endif

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

    @Test func unauthorizedRecoveryCanBeDeferredToDurableRetryOwner()
        async throws {
        let userID = UUID()
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [userID],
            outcomes: [
                .response(
                    statusCode: 401,
                    data: Data(
                        #"{"code":"invalid_session_token"}"#.utf8
                    )
                )
            ],
            refreshResult: true
        )

        do {
            _ = try await makeExecutor(probe: probe).execute(try makeRequest(
                function: "sync-collections",
                allowsUnauthorizedSessionRecovery: false
            ))
            Issue.record("Expected deferred unauthorized failure")
        } catch MerianError.httpError(let statusCode, _) {
            #expect(statusCode == 401)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(probe.refreshTargets.isEmpty)
        #expect(probe.attempts.count == 1)
        #expect(probe.resetGhostSessionCount == 0)
        #expect(probe.clearLocalSessionCount == 0)
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

    @Test func cancellationDuringUnauthorizedRefreshStopsBeforeAuthMutation()
        async throws {
        let userID = UUID()
        let probe = AuthenticatedRequestExecutorProbe(
            authUserIDs: [userID],
            outcomes: [
                .response(
                    statusCode: 401,
                    data: Data(#"{"code":"auth_session_missing"}"#.utf8)
                )
            ],
            cancelDuringRefresh: true,
            unauthorizedRecoveryState: .init(
                hasAuthenticatedOAuth: false,
                isGuestUser: true,
                purchaseIdentityHandoffPending: false
            ),
            resetGhostSessionResult: true
        )

        let executor = makeExecutor(probe: probe)
        let request = try makeRequest(function: "get-explore-feed")
        let task = Task {
            try await executor.execute(request)
        }

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected only for the child request task.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(probe.refreshTargets == [.ordinary])
        #expect(probe.resetGhostSessionCount == 0)
        #expect(probe.clearLocalSessionCount == 0)
        #expect(probe.attempts.count == 1)
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
        expectedAuthUserID: UUID? = nil,
        allowsUnauthorizedSessionRecovery: Bool = true
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
            allowsUnauthorizedSessionRecovery:
                allowsUnauthorizedSessionRecovery,
            onRequestBodySent: onRequestBodySent,
            authTransitionOwner: authTransitionOwner,
            expectedAuthUserID: expectedAuthUserID
        )
    }

    private func makeExecutor(
        probe: AuthenticatedRequestExecutorProbe,
        recordIdentificationMeasurement: @escaping (String) -> Void = { _ in }
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
        ), recordIdentificationMeasurement: recordIdentificationMeasurement)
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
    private let cancelDuringRefresh: Bool
    private let resetGhostSessionResult: Bool

    let unauthorizedRecoveryState:
        AuthenticatedRequestExecutor.UnauthorizedRecoveryState
    let purchaseIdentityHandoffPending: Bool

    init(
        authUserIDs: [UUID],
        outcomes: [Outcome],
        refreshResult: Bool = false,
        cancelDuringRefresh: Bool = false,
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
        self.cancelDuringRefresh = cancelDuringRefresh
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
            if cancelDuringRefresh {
                withUnsafeCurrentTask { $0?.cancel() }
            }
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
