import Foundation
import SwiftData

/// Existing accepted account scopes remain the only purge authority. A manifest,
/// native profile or terminal receipt can never create this authorization.
@MainActor
enum SharedMediaNativeErasureAuthorization {
    case signOut(LibrarySignOutJournalStore.RecoveryScope)
    case accountDeletion(AccountDeletionLocalCleanupStore.RecoveryScope)

    struct Identity: Equatable {
        let operation: SharedMediaNativeErasureHeader.Operation
        let operationID: UUID
        let signOutOwnerID: UUID?
    }

    func require(container: ModelContainer) throws -> Identity {
        try Task.checkCancellation()
        switch self {
        case .signOut(let scope):
            guard scope.allowsLibraryPurge, scope.journal.version == 2,
                  let operationID = scope.journal.cleanupOperationID else { throw SharedMediaStorageFailure.closed }
            return .init(operation: .signOut, operationID: operationID, signOutOwnerID: scope.journal.sourceUserID)
        case .accountDeletion(let scope):
            guard scope.permitsLibraryPurge(in: container), let operationID = scope.cleanupOperationID else {
                throw SharedMediaStorageFailure.closed
            }
            // Accepted deletion deliberately survives verified local sign-out.
            // Its scope binds the captured library, not a surviving Auth user.
            return .init(operation: .accountDeletion, operationID: operationID, signOutOwnerID: nil)
        }
    }

    func require(header: SharedMediaNativeErasureHeader, profile: SharedMediaNativeAppProfile,
                 container: ModelContainer) throws {
        let identity = try require(container: container)
        guard header.operation == identity.operation, header.operationID == identity.operationID,
              identity.signOutOwnerID.map({ $0 == profile.ownerID }) ?? true else { throw SharedMediaStorageFailure.conflict }
        _ = try header.encoded(profile: profile)
    }
}
