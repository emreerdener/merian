import Foundation

/// Maps provider-neutral lifecycle outcomes onto the privacy-safe Auth log.
@MainActor
enum AuthSessionLifecycleLiveDiagnostics {
    static func report(
        _ diagnostic: AuthSessionLifecycleDiagnostic,
        error: Error?
    ) {
        switch diagnostic {
        case .ghostProfileMergeStateUnreadable,
             .purchaseHandoffStateUnreadable:
            guard let error else { return }
            MerianLog.auth.error(
                "\(diagnostic.message, privacy: .public) kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
        default:
            MerianLog.auth.debug(
                "\(diagnostic.message, privacy: .public)"
            )
        }
    }
}
