import Foundation

struct QueuedRetryPresentation: Equatable {
    enum Action: Equatable {
        case retryNow
        case viewPlans
    }

    let message: String
    let action: Action?

    static func resolve(
        queueState: ScanQueueState,
        nextRetryAt: Date?,
        errorCode: String?,
        needsAttention: Bool,
        canRetryNow: Bool,
        isOnline: Bool,
        now: Date
    ) -> QueuedRetryPresentation? {
        let requiresAttention = needsAttention || queueState == .failed
        if requiresAttention {
            let category = reasonCategory(for: errorCode)
            return QueuedRetryPresentation(
                message: category.message,
                action: attentionAction(
                    for: category,
                    canRetryNow: canRetryNow,
                    isOnline: isOnline
                )
            )
        }

        guard let nextRetryAt else { return nil }
        guard isOnline else {
            return QueuedRetryPresentation(
                message: [
                    ReasonCategory.connection.message,
                    "It will retry when your connection returns."
                ].joined(separator: " "),
                action: nil
            )
        }

        let remaining = nextRetryAt.timeIntervalSince(now)
        guard remaining > 0 else {
            // The queue state and analyzing badge already communicate that the
            // due retry is starting. Avoid a redundant transient label/button.
            return nil
        }
        let category = reasonCategory(for: errorCode)
        return QueuedRetryPresentation(
            message: [
                category.message,
                "It will retry automatically in \(countdown(remaining))."
            ].joined(separator: " "),
            action: canRetryNow ? .retryNow : nil
        )
    }

    private enum ReasonCategory: Equatable {
        case connection
        case service
        case processing
        case missingMedia
        case consent
        case entitlement
        case retryLimit
        case terminal
        case unknown

        var message: String {
            switch self {
            case .connection:
                "The analysis paused because the connection was interrupted."
            case .service:
                "The analysis couldn’t complete because Naturebook’s analysis service was temporarily unavailable."
            case .processing:
                "The analysis is taking longer than expected."
            case .missingMedia:
                "The analysis couldn’t continue because its photo or recording is no longer available on this device."
            case .consent:
                "AI analysis is paused until you review the required AI consent."
            case .entitlement:
                "This analysis needs an active plan before it can continue."
            case .retryLimit:
                "Automatic retries paused after several unsuccessful attempts."
            case .terminal:
                "Naturebook couldn’t process this observation. Try a different photo or recording."
            case .unknown:
                "The analysis couldn’t complete this time."
            }
        }
    }

    private static func reasonCategory(
        for errorCode: String?
    ) -> ReasonCategory {
        let code = errorCode?.lowercased() ?? ""
        if code == "ai_consent_required" { return .consent }
        if code == "pro_required" ||
            code == "payment_required" ||
            code == "plan_required" ||
            code == "http_402" ||
            code == "inference_http_402" ||
            code.contains("entitlement") ||
            code.contains("quota") ||
            code.contains("scan_limit") {
            return .entitlement
        }
        if code == "automatic_retry_limit_reached" ||
            code.contains("recovery_exhausted") ||
            code.contains("retry_limit") {
            return .retryLimit
        }
        if code.contains("local_media_missing") ||
            code.contains("queued_media_missing") ||
            code.contains("queued_media_invalid") ||
            code.contains("source_file_missing") ||
            code.contains("legacy_external_import") {
            return .missingMedia
        }
        if code.contains("observation_rejected") ||
            code.contains("failed_terminal") ||
            code.contains("upload_rejected") ||
            code.contains("terminal") ||
            code.contains("manifest_invalid") ||
            code.contains("staging_object_key_invalid") ||
            code.contains("staging_capture_identity_mismatch") {
            return .terminal
        }
        if code.contains("network") ||
            code.contains("transport") ||
            code.contains("timed_out") ||
            code.contains("connection") ||
            code.contains("http_408") {
            return .connection
        }
        if code.contains("server_result") ||
            code.contains("processing") ||
            code.contains("finalizing") ||
            code.contains("server_retryable_failure") {
            return .processing
        }
        if code.contains("http_5") ||
            code.contains("http_425") ||
            code.contains("http_429") ||
            code.contains("service") ||
            code.contains("inference") ||
            code.contains("failed_retryable") ||
            code.contains("upload_url_generation") ||
            code.contains("upload_error") ||
            code.contains("background_ingestion_failed") ||
            code.contains("media_finalization_failed") ||
            code.contains("video_promotion_failed") {
            return .service
        }
        return .unknown
    }

    private static func attentionAction(
        for category: ReasonCategory,
        canRetryNow: Bool,
        isOnline: Bool
    ) -> Action? {
        switch category {
        case .entitlement:
            .viewPlans
        case .consent, .missingMedia, .terminal:
            nil
        case .connection, .service, .processing, .retryLimit, .unknown:
            isOnline && canRetryNow ? .retryNow : nil
        }
    }

    private static func countdown(_ interval: TimeInterval) -> String {
        if interval < 60 {
            let seconds = max(1, Int(ceil(interval)))
            return "\(seconds) \(seconds == 1 ? "second" : "seconds")"
        }
        let minutes = max(1, Int(ceil(interval / 60)))
        return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }
}
