import Foundation

enum MissingScanRecoveryAction: Equatable, Sendable {
    case retryStatus
    case recover
    case deferRecovery
}

enum OwnedScanRecoveryPolicy {
    static func action(
        for jobStatus: ScanIngestionJobStatus?,
        jobStage: String? = nil,
        jobLastError: String? = nil
    ) -> MissingScanRecoveryAction {
        let normalizedStage = jobStage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedError = jobLastError?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let isModerationRejection = normalizedStage == "moderation_rejected"
            && (
                normalizedError == "multimodal media rejected by moderation."
                    || normalizedError == "media rejected by moderation."
            )
        let isProviderPolicyRejection = normalizedStage == "ai_inference_non_stop_finish"
            && (
                normalizedError == "ai finish reason: safety"
                    || normalizedError == "ai finish reason: prohibited_content"
            )
        if isModerationRejection || isProviderPolicyRejection {
            return .deferRecovery
        }

        switch jobStatus {
        case .processing?, .finalizing?, .retrying?:
            return .retryStatus
        case .failedRetryable?:
            return .deferRecovery
        case .failed?, .complete?, nil:
            return .recover
        }
    }
}
