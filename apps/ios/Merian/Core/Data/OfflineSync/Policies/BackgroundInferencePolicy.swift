import Foundation

enum ScanStatusRecoveryAction: Equatable {
    case recovered
    case waitForServer(TimeInterval)
    case retryAfter(TimeInterval)
    case terminalFailure(String?)
    case unresolved
}

enum BackgroundInferenceResponseDisposition: Equatable {
    case success
    case retry
    case consentRequired
    case needsAttention
    case terminal
}

enum BackgroundInferencePolicy {
    static let requiredConsentAttentionMessage =
        "Complete the required age, Terms, and Google Gemini consent step. Naturebook will automatically resume the eligible saved scan; if it stays paused, you can retry it from Scans."

    static func shouldRetryBackgroundInferenceRouteFailure(
        statusCode: Int?,
        functionRouteEvidence: EdgeFunctionRouteResponseEvidence?,
        responseData: Data
    ) -> Bool {
        guard statusCode == 404,
              let functionRouteEvidence else {
            return false
        }
        return EdgeFunctionRoutePolicy.isUnavailable(
            evidence: functionRouteEvidence,
            responseData: responseData
        )
    }

    static func backgroundInferenceResponseDisposition(
        statusCode: Int?,
        functionRouteEvidence: EdgeFunctionRouteResponseEvidence?,
        responseData: Data
    ) -> BackgroundInferenceResponseDisposition {
        guard let statusCode else {
            return .retry
        }
        if statusCode == 200 {
            guard !responseData.isEmpty,
                  let wrapper = try? JSONDecoder().decode(
                      EdgeResponseWrapper.self,
                      from: responseData
                  ),
                  IdentifySuccessEnvelopeValidator.isUsable(wrapper) else {
                return .retry
            }
            return .success
        }
        if shouldRetryBackgroundInferenceRouteFailure(
            statusCode: statusCode,
            functionRouteEvidence: functionRouteEvidence,
            responseData: responseData
        ) {
            return .retry
        }
        if statusCode >= 500
            || [401, 408, 409, 425, 429].contains(statusCode) {
            return .retry
        }
        if statusCode == 403,
           EdgeFunctionErrorPolicy.stableCode(responseData: responseData)
            == "ai_consent_required" {
            return .consentRequired
        }
        if statusCode == 400,
           EdgeFunctionErrorPolicy.stableCode(responseData: responseData)
            == "observation_rejected" {
            return .terminal
        }
        if (400...499).contains(statusCode) {
            return .needsAttention
        }
        return .retry
    }

    static func requiresMediaRestagingAfterServerFailure(
        _ response: ScanStatusResponse
    ) -> Bool {
        guard response.status == .notFound,
              response.jobStatus == .failedRetryable else {
            return false
        }
        switch response.jobStage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "background_ingestion_failed",
             "media_finalization_failed",
             "identity_merge_interrupted",
             "video_promotion_failed",
             "scan_insert_started":
            return true
        default:
            return false
        }
    }

    static func scanStatusRecoveryAction(
        for response: ScanStatusResponse,
        now: Date = Date(),
        defaultPollDelay: TimeInterval = 15,
        defaultRetryDelay: TimeInterval = 30
    ) -> ScanStatusRecoveryAction {
        if response.isFound {
            return .recovered
        }

        func boundedDelay(
            from isoString: String?,
            fallback: TimeInterval
        ) -> TimeInterval {
            guard let isoString,
                  let date = parseRetryAfterDate(isoString) else {
                return fallback
            }
            return min(max(date.timeIntervalSince(now), 1), 300)
        }

        switch response.jobStatus {
        case .processing, .finalizing:
            return .waitForServer(boundedDelay(
                from: response.retryAfter,
                fallback: defaultPollDelay
            ))
        case .retrying:
            return .waitForServer(boundedDelay(
                from: response.retryAfter,
                fallback: defaultRetryDelay
            ))
        case .failedRetryable:
            return .retryAfter(boundedDelay(
                from: response.retryAfter,
                fallback: defaultRetryDelay
            ))
        case .failed:
            return .terminalFailure(response.lastError)
        case .complete, nil:
            return .unresolved
        }
    }

    /// A retryable server failure first writes a generation-fenced local retry.
    /// Once that durable marker survives its delay (and any required media
    /// restaging), the next exact-generation preflight must be allowed to send
    /// the identify request that can reclaim the backend attempt. Treating that
    /// same status as server-owned again creates a status/upload loop with no
    /// provider request.
    static func scanStatusActionPermitsInferenceDispatch(
        _ action: ScanStatusRecoveryAction,
        hasScheduledServerFailureRetry: Bool
    ) -> Bool {
        switch action {
        case .unresolved:
            true
        case .retryAfter:
            hasScheduledServerFailureRetry
        case .recovered, .waitForServer, .terminalFailure:
            false
        }
    }

    static func parseRetryAfterDate(_ rawValue: String) -> Date? {
        if let seconds = TimeInterval(rawValue) {
            return Date().addingTimeInterval(seconds)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        if let date = formatter.date(from: rawValue) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }
}
