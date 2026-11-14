import Foundation

/// Process-local completion scope acquired from the original authenticated
/// request, before dispatch. It is never serialized into completion evidence.
/// The pipeline retains it through persistence and releases it on every exit.
@MainActor
final class InferenceCompletionAccountScope {
    nonisolated let ownerID: UUID
    private let isCurrent: () -> Bool
    private let release: () -> Void
    private var finished = false

    init(ownerID: UUID, isCurrent: @escaping () -> Bool, release: @escaping () -> Void) {
        self.ownerID = ownerID
        self.isCurrent = isCurrent
        self.release = release
    }

    static func begin(ownerID: UUID) throws -> InferenceCompletionAccountScope {
        let manager = SupabaseManager.shared
        let lease = try manager.beginUnownedAccountBoundWork(expectedUserID: ownerID)
        return .init(ownerID: lease.session.userID,
            isCurrent: { manager.isAccountBoundWorkLeaseCurrent(lease) },
            release: { manager.finishAccountBoundWork(lease) })
    }

    func validate() throws {
        try Task.checkCancellation()
        guard !finished, isCurrent() else { throw SupabaseAuthTransitionError.signOutSessionChanged }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        release()
    }
}
