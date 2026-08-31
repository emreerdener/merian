enum QueuedScanningPresentation {
    struct RotationID: Hashable {
        let scanID: String
        let queueStateRawValue: Int
        let isOnline: Bool
        let serverJobStatus: String?
        let needsAttention: Bool
        let hasScheduledRetry: Bool
    }

    static func rotationID(
        scanID: String,
        isLiveVisualHandoff: Bool,
        queueState: ScanQueueState,
        isOnline: Bool,
        serverJobStatus: ScanIngestionJobStatus?,
        needsAttention: Bool,
        hasScheduledRetry: Bool
    ) -> RotationID {
        if isLiveVisualHandoff {
            // Durable upload and save-state changes belong to the same visible
            // analysis. Connectivity is a temporary overlay, so none of those
            // values may restart its phrase cursor.
            return RotationID(
                scanID: scanID,
                queueStateRawValue: -1,
                isOnline: false,
                serverJobStatus: nil,
                needsAttention: false,
                hasScheduledRetry: false
            )
        }
        return RotationID(
            scanID: scanID,
            queueStateRawValue: queueState.rawValue,
            isOnline: isOnline,
            serverJobStatus: serverJobStatus?.rawValue,
            needsAttention: needsAttention,
            hasScheduledRetry: hasScheduledRetry
        )
    }

    static func phrases(
        queueState: ScanQueueState,
        isOnline: Bool,
        serverJobStatus: ScanIngestionJobStatus?,
        needsAttention: Bool,
        hasScheduledRetry: Bool,
        hasVideo: Bool,
        isLiveVisualHandoff: Bool,
        contextualPhrases: [String],
        genericPhrases: [String]
    ) -> [String] {
        if isLiveVisualHandoff {
            return liveVisualHandoffPhrases(
                isOnline: isOnline,
                contextualPhrases: contextualPhrases,
                genericPhrases: genericPhrases
            )
        }
        guard isOnline else {
            return ["Waiting for connection"]
        }
        guard !needsAttention, queueState != .failed else {
            return ["Scan needs attention"]
        }

        switch queueState {
        case .pending:
            return [
                "Preparing scan",
                "Securing media",
                "Preparing upload"
            ]
        case .uploading:
            return [
                "Uploading media",
                "Securing scan",
                "Preparing analysis"
            ]
        case .staged:
            if hasScheduledRetry {
                return [
                    "Scan safely queued",
                    "Waiting to retry"
                ]
            }
            return [
                "Preparing analysis",
                "Checking uploaded media",
                "Starting identification"
            ]
        case .inferencing:
            switch serverJobStatus {
            case .finalizing:
                return hasVideo
                    ? [
                        "Finalizing video scan",
                        "Saving video",
                        "Preparing results"
                    ]
                    : ["Finalizing scan", "Saving scan", "Preparing results"]
            case .retrying, .failedRetryable:
                return ["Retrying analysis", "Reconnecting to analysis"]
            case .failed:
                return ["Scan needs attention"]
            case .complete:
                return ["Preparing results", "Finishing scan"]
            case .processing, nil:
                return genericPhrases
            }
        case .externalImport:
            return ["Recovering scan"]
        case .failed:
            return ["Scan needs attention"]
        }
    }

    static func liveVisualHandoffPhrases(
        isOnline: Bool,
        contextualPhrases: [String],
        genericPhrases: [String]
    ) -> [String] {
        guard isOnline else {
            return ["Waiting for connection"]
        }
        return contextualPhrases.isEmpty
            ? genericPhrases
            : contextualPhrases
    }
}
