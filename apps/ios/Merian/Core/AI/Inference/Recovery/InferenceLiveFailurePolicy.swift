import Foundation

/// Stateless decisions for the live pipelines. The engine retains exact-attempt
/// validation, queue ownership, and execution of every recovery side effect.
enum InferenceLiveFailurePolicy {
    enum Mode: Equatable, Sendable {
        case visual
        case nonVisual(hasAudio: Bool)

        var cancellationReason: String {
            self == .visual ? "live_request_cancelled" : "live_nonvisual_cancelled"
        }

        var transportCancellationReason: String {
            self == .visual ? "live_transport_cancelled" : "live_nonvisual_transport_cancelled"
        }

        var failureReason: String {
            self == .visual ? "live_request_failed" : "live_nonvisual_failed"
        }
    }

    enum Interruption: Equatable, Sendable {
        case taskCancellation
        case ownershipCancellation
        case transportCancellation
    }

    enum RateLimit: String, Equatable, Sendable {
        case user = "ai_user_rate_limit_exceeded"
        case ip = "ai_ip_rate_limit_exceeded"
    }

    enum Failure: Equatable, Sendable {
        case recoverableConflict
        case consentRequired
        case proRequired
        case dailyQuotaExceeded
        case rateLimited(RateLimit)
        case observationRejected
        case visualDecoding
        case connectivity
        case service

        var recordsCircuitFailure: Bool {
            self == .connectivity || self == .service
        }

        var triggersErrorFeedback: Bool {
            self != .recoverableConflict && self != .dailyQuotaExceeded
        }

        func telemetryEvent(for mode: Mode) -> String {
            switch self {
            case .recoverableConflict:
                return "InferenceCompletionRecovery"
            case .consentRequired:
                return "InferenceConsentRequired"
            case .proRequired:
                return "InferenceProRequired"
            case .dailyQuotaExceeded:
                return "InferenceDailyQuotaExceeded"
            case .rateLimited:
                return "InferenceRateLimited"
            case .observationRejected:
                return "InferenceObservationRejected"
            case .visualDecoding:
                return "APIDecodingFailure"
            case .connectivity:
                return "InferenceNetworkFailure"
            case .service:
                return mode == .nonVisual(hasAudio: false)
                    ? "DescribeInferenceFailure"
                    : "InferenceServiceFailure"
            }
        }
    }

    /// Task cancellation, logical ownership loss, and URLSession cancellation
    /// have different queue handoff rules. In particular, cancellation of the
    /// Swift task takes precedence even if a non-cooperative provider throws a
    /// different error afterward.
    static func interruption(
        for error: Error,
        isTaskCancelled: Bool
    ) -> Interruption? {
        if isTaskCancelled {
            return .taskCancellation
        }
        if error is CancellationError {
            return .ownershipCancellation
        }
        if (error as? URLError)?.code == .cancelled {
            return .transportCancellation
        }
        return nil
    }

    static func isConnectivityFailure(_ error: Error) -> Bool {
        if (error as? MerianError) == .networkTimeout {
            return true
        }
        return ScanConnectivityFailurePolicy.isDurableRecoveryFailure(error)
    }

    /// Called only after the engine has handled interruption/queue handoff and
    /// proven the full live attempt still owns terminal failure publication.
    /// Existing Network helpers decode stable codes; no transport is invoked.
    static func failure(for error: Error, mode: Mode) -> Failure {
        if MerianNetworkClient.isRecoverableInferenceConflict(error) {
            return .recoverableConflict
        }
        if (error as? MerianError) == .aiConsentRequired {
            return .consentRequired
        }
        if let policyFailure = providerPolicyFailure(for: error) {
            return policyFailure
        }
        // The nonvisual pipeline intentionally retains generic failure copy,
        // telemetry, and circuit accounting for unreadable responses.
        if mode == .visual, (error as? MerianError) == .decodingFailed {
            return .visualDecoding
        }
        return isConnectivityFailure(error) ? .connectivity : .service
    }

    private static func providerPolicyFailure(for error: Error) -> Failure? {
        guard case let MerianError.httpError(statusCode, _) = error,
              let code = EdgeFunctionErrorPolicy.stableCode(from: error) else {
            return nil
        }
        switch (statusCode, code) {
        case (402, "pro_required"):
            return .proRequired
        case (429, "ai_quota_daily_exceeded"):
            return .dailyQuotaExceeded
        case (429, RateLimit.user.rawValue):
            return .rateLimited(.user)
        case (429, RateLimit.ip.rawValue):
            return .rateLimited(.ip)
        case (400, "observation_rejected"):
            return .observationRejected
        default:
            return nil
        }
    }
}
