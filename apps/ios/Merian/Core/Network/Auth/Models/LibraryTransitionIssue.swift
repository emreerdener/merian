import Foundation
enum LibraryTransitionIssue: String, Identifiable, Equatable {
    case pendingChanges
    case needsAttention
    case unreadable
    case transferPending
    case accountRecoveryRequired
    var id: String { rawValue }
    var message: String {
        switch self {
        case .pendingChanges:
            "Your library has changes waiting to sync. Keep syncing, then try again."
        case .needsAttention:
            "Some library changes need attention before you can change accounts. Review pending changes to retry or repair them."
        case .unreadable:
            "Your library or its recovery information could not be read. Your account has not been replaced. Retry when the device is unlocked."
        case .transferPending:
            "Finish the current library transfer before changing accounts again."
        case .accountRecoveryRequired:
            "Naturebook couldn’t verify the account for this library. Your data has been preserved. Recover access to the library’s account before trying again."
        }
    }
}
