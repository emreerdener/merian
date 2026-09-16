import Foundation

extension AuthenticationCallbackDiagnostics {
    @MainActor
    static let live = Self { diagnostic, error in
        switch diagnostic {
        case .transitionRejected:
            MerianLog.auth.debug(
                "Ignored an authentication callback while another identity transition is pending."
            )
        case .sourceSessionRejected:
            MerianLog.auth.debug(
                "Ignored an authentication callback that cannot replace the current signed-out profile."
            )
        case .completionFailed:
            let errorKind = error.map { MerianLog.errorKind($0) }
                ?? "UnavailableError"
            MerianLog.auth.debug(
                "Authentication callback failed; kind=\(errorKind, privacy: .public)"
            )
        }
    }
}
