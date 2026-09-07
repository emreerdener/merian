import Foundation

enum OfflineQueueRetryDisposition: Equatable {
    case success
    case retry(after: TimeInterval, code: String, message: String?)
    case waitForServer(after: TimeInterval, code: String, message: String?)
    case needsAttention(code: String, message: String?)
    case terminal(code: String, message: String?)
}

enum OfflineQueueRetryPolicy {
    enum Scope: Sendable {
        case scanAnalysis
        case maintenance
    }

    static let maximumAutomaticRetryAttempts = 10
    static let maximumRetryDelay: TimeInterval = 30
    static let maximumMaintenanceRetryDelay: TimeInterval = 15 * 60
    static let maximumServerDirectedRetryDelay: TimeInterval = 15 * 60
    static let retryJitterFraction = 0.2

    static func maximumDelay(for scope: Scope) -> TimeInterval {
        switch scope {
        case .scanAnalysis:
            maximumRetryDelay
        case .maintenance:
            maximumMaintenanceRetryDelay
        }
    }

    static func delay(
        forAttempt attempt: Int,
        scope: Scope = .scanAnalysis
    ) -> TimeInterval {
        let exponent = max(0, attempt)
        let base = pow(2.0, Double(exponent))
        return min(maximumDelay(for: scope), max(5, base))
    }

    static func jitteredDelay(
        forAttempt attempt: Int,
        scope: Scope = .scanAnalysis
    ) -> TimeInterval {
        let baseDelay = delay(forAttempt: attempt, scope: scope)
        let multiplier = Double.random(in: (1 - retryJitterFraction)...(1 + retryJitterFraction))
        return min(
            maximumDelay(for: scope),
            max(5, baseDelay * multiplier)
        )
    }

    static func scanRetryDelay(
        forAttempt attempt: Int,
        serverMinimumDelay: TimeInterval?
    ) -> TimeInterval {
        let boundedServerMinimum = min(
            max(serverMinimumDelay ?? 0, 0),
            maximumServerDirectedRetryDelay
        )
        return max(
            jitteredDelay(forAttempt: attempt, scope: .scanAnalysis),
            boundedServerMinimum
        )
    }

    static func canScheduleAutomaticRetry(currentAttempt: Int) -> Bool {
        currentAttempt < maximumAutomaticRetryAttempts
    }

    static func automaticRetryLimitMessage() -> String {
        [
            "Naturebook retried this scan several times and paused automatic retry.",
            "You can retry manually when the connection or Naturebook service is stable."
        ].joined(separator: " ")
    }

    static func classifyUpload(error: Error?, statusCode: Int?, currentAttempt: Int) -> OfflineQueueRetryDisposition {
        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorFileDoesNotExist, NSURLErrorCannotOpenFile:
                    return .needsAttention(
                        code: "local_media_missing",
                        message: "A local media file is missing. Keep the queued scan so the user can retry after restoring or cancel it."
                    )
                case NSURLErrorTimedOut,
                     NSURLErrorNetworkConnectionLost,
                     NSURLErrorNotConnectedToInternet,
                     NSURLErrorDataNotAllowed,
                     NSURLErrorInternationalRoamingOff:
                    return retryOrPause(
                        currentAttempt: currentAttempt,
                        code: "network_unavailable",
                        message: error.localizedDescription
                    )
                default:
                    return retryOrPause(
                        currentAttempt: currentAttempt,
                        code: "upload_transport_error",
                        message: error.localizedDescription
                    )
                }
            }
            return retryOrPause(
                currentAttempt: currentAttempt,
                code: "upload_error",
                message: error.localizedDescription
            )
        }

        guard let statusCode else {
            return retryOrPause(
                currentAttempt: currentAttempt,
                code: "upload_missing_status",
                message: "The upload finished without an HTTP status."
            )
        }

        if statusCode == 200 { return .success }
        if [408, 409, 425, 429, 500, 502, 503, 504].contains(statusCode) {
            return retryOrPause(
                currentAttempt: currentAttempt,
                code: "upload_http_\(statusCode)",
                message: "The media upload endpoint returned HTTP \(statusCode)."
            )
        }

        return .needsAttention(
            code: "upload_rejected_http_\(statusCode)",
            message: "The media upload endpoint permanently rejected the queued media with HTTP \(statusCode)."
        )
    }

    private static func retryOrPause(
        currentAttempt: Int,
        code: String,
        message: String?
    ) -> OfflineQueueRetryDisposition {
        guard canScheduleAutomaticRetry(currentAttempt: currentAttempt) else {
            return .needsAttention(
                code: "automatic_retry_limit_reached",
                message: automaticRetryLimitMessage()
            )
        }
        return .retry(
            after: jitteredDelay(forAttempt: currentAttempt + 1),
            code: code,
            message: message
        )
    }
}
