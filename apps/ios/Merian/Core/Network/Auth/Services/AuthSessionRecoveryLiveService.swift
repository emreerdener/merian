import Foundation
import Supabase

/// One Supabase Auth session projected for provider-neutral recovery policy.
/// The SDK user remains available only for facade-owned adoption, publication,
/// public-author refresh, purchase-identity, entitlement, and generation-fence
/// effects.
@MainActor
struct AuthSessionRecoveryLiveSession {
    let user: User
    let identity: AuthTransitionSession
}

/// Owns the request-scoped Supabase Auth operations used by session recovery.
/// Transition ownership, cancellation, anonymous replacement, publication,
/// local cleanup, purchase identity, and entitlement work remain with the
/// coordinator and facade-provided effects.
@MainActor
struct AuthSessionRecoveryLiveService {
    typealias RefreshSessionOperation = @MainActor () async throws -> Session
    typealias ReadSessionOperation = @MainActor () async throws -> Session
    typealias LocalSignOutOperation = @MainActor () async throws -> Void

    private let refreshSessionOperation: RefreshSessionOperation
    private let readSessionOperation: ReadSessionOperation
    private let localSignOutOperation: LocalSignOutOperation

    init(
        refreshSession: @escaping RefreshSessionOperation,
        readSession: @escaping ReadSessionOperation,
        localSignOut: @escaping LocalSignOutOperation
    ) {
        refreshSessionOperation = refreshSession
        readSessionOperation = readSession
        localSignOutOperation = localSignOut
    }

    func refreshSession() async throws -> AuthSessionRecoveryLiveSession {
        Self.recoverySession(from: try await refreshSessionOperation())
    }

    func loadSession() async throws -> AuthSessionRecoveryLiveSession {
        Self.recoverySession(from: try await readSessionOperation())
    }

    func signOutLocalSession() async throws {
        try await localSignOutOperation()
    }

    private static func recoverySession(
        from session: Session
    ) -> AuthSessionRecoveryLiveSession {
        AuthSessionRecoveryLiveSession(
            user: session.user,
            identity: AuthTransitionSession(
                userID: session.user.id,
                isAnonymous: session.user.isAnonymous
            )
        )
    }
}
