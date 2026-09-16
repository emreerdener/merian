import Foundation

enum AuthSessionLifecycleOrigin: Equatable, Sendable {
    case initialRestoration
    case runtimeTransition
}

struct AuthSessionLifecycleEvent: Equatable {
    let adoption: AuthSessionAdoption
    let session: AuthTransitionSession?
    let authGeneration: UInt64
    let origin: AuthSessionLifecycleOrigin
}

enum AuthSessionLifecycleDiagnostic: Equatable, Sendable {
    case deferredForAccountDeletionCleanup
    case deferredForActiveTransition
    case ghostProfileMergeStateUnreadable
    case purchaseHandoffStateUnreadable
    case authenticatedEventIgnoredDuringSignOut
    case refreshEventIgnoredDuringSignOut
    case cachedSessionAwaitingRefresh
    case invalidEvent
    case processed

    var message: String {
        switch self {
        case .deferredForAccountDeletionCleanup:
            "Deferred an SDK auth event until accepted account deletion cleanup finishes."
        case .deferredForActiveTransition:
            "Deferred an SDK auth event to the active authentication transition."
        case .ghostProfileMergeStateUnreadable:
            "Could not read the signed-out handoff queue; analytics remains suppressed;"
        case .purchaseHandoffStateUnreadable:
            "Could not read the sign-out purchase handoff; purchase mutations remain disabled;"
        case .authenticatedEventIgnoredDuringSignOut:
            "Ignored authenticated SDK event while sign-out is in progress."
        case .refreshEventIgnoredDuringSignOut:
            "Ignored refreshing SDK session while sign-out is in progress."
        case .cachedSessionAwaitingRefresh:
            "Cached auth session is awaiting refresh; consent restoration remains pending."
        case .invalidEvent:
            "Ignored an inconsistent authentication lifecycle event."
        case .processed:
            "Processed an authentication state change."
        }
    }
}
