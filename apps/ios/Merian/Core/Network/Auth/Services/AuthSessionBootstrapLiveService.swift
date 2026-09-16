import Foundation
import Supabase

/// One Supabase Auth session projected for provider-neutral bootstrap policy.
/// The SDK user is retained only so the facade can publish the established
/// observable `User` value after the coordinator admits the transition.
@MainActor
struct AuthSessionBootstrapLiveSession {
    let user: User
    let identity: AuthTransitionSession
    let isExpired: Bool
}

/// Owns the request-scoped Supabase Auth operations used only by initial
/// session resolution and anonymous bootstrap. Transition ownership, task
/// lifetime, publication, purchase identity, and entitlement work remain in
/// `AuthSessionBootstrapCoordinator` and the facade's injected effects.
@MainActor
struct AuthSessionBootstrapLiveService {
    typealias ReadSessionOperation = @MainActor () async throws -> Session
    typealias CurrentSessionOperation = @MainActor () -> Session?
    typealias CreateAnonymousSessionOperation = @MainActor () async throws
        -> Session

    private let readSessionOperation: ReadSessionOperation
    private let currentSessionOperation: CurrentSessionOperation
    private let createAnonymousSessionOperation: CreateAnonymousSessionOperation

    init(
        readSession: @escaping ReadSessionOperation,
        currentSession: @escaping CurrentSessionOperation,
        createAnonymousSession: @escaping CreateAnonymousSessionOperation
    ) {
        readSessionOperation = readSession
        currentSessionOperation = currentSession
        createAnonymousSessionOperation = createAnonymousSession
    }

    func currentSession() -> AuthSessionBootstrapLiveSession? {
        currentSessionOperation().map {
            Self.bootstrapSession(from: $0, isExpired: $0.isExpired)
        }
    }

    func loadSession() async throws -> AuthSessionBootstrapLiveSession {
        let session = try await readSessionOperation()
        return Self.bootstrapSession(
            from: session,
            isExpired: session.isExpired
        )
    }

    func createAnonymousSession() async throws
        -> AuthSessionBootstrapLiveSession {
        let session = try await createAnonymousSessionOperation()
        return Self.bootstrapSession(from: session, isExpired: false)
    }

    func isSessionMissingError(_ error: Error) -> Bool {
        if let authError = error as? AuthError,
           case .sessionMissing = authError {
            return true
        }
        let description = String(describing: error)
        return description.contains("sessionNotFound")
            || description.contains("sessionMissing")
    }

    private static func bootstrapSession(
        from session: Session,
        isExpired: Bool
    ) -> AuthSessionBootstrapLiveSession {
        AuthSessionBootstrapLiveSession(
            user: session.user,
            identity: AuthTransitionSession(
                userID: session.user.id,
                isAnonymous: session.user.isAnonymous
            ),
            isExpired: isExpired
        )
    }
}
