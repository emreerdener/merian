enum CaptureScanAdmissionRoute: Sendable, Equatable {
    case foreground
    case queued
}

enum CaptureScanAdmissionResolution: Sendable, Equatable {
    case proceed(CaptureScanAdmissionRoute)
    case paywall
    case retryRequired
}

enum CaptureScanAdmissionPolicy {
    nonisolated static func resolve(
        isOnline: Bool,
        canStartLocally: Bool,
        previewResult: ScanAdmissionPreviewResult?
    ) -> CaptureScanAdmissionResolution {
        guard isOnline else {
            return canStartLocally ? .proceed(.queued) : .paywall
        }
        guard let previewResult else { return .retryRequired }

        switch previewResult {
        case .available(let preview):
            switch preview.decision {
            case .allowed:
                return .proceed(.foreground)
            case .dailyQuotaExhausted, .proRequired:
                return .paywall
            }
        case .connectivityUnavailable:
            return canStartLocally ? .proceed(.queued) : .paywall
        case .unavailable:
            return .retryRequired
        }
    }
}
