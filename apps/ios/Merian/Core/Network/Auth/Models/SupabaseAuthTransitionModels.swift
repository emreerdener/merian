import Foundation

enum SupabaseAuthTransitionError: LocalizedError {
    case signOutInProgress
    case invalidOAuthIdentityToken
    case guestMergeSessionChanged
    case guestMergeHandoffPersistenceFailed
    case signOutPurchaseHandoffPersistenceFailed
    case signOutPurchaseContinuityPending
    case signOutSessionChanged
    case purchasePrincipalRotationPersistenceFailed
    case accountDeletionRecoveryPersistenceFailed
    case accountDeletionRecoveryPending
    case accountBoundWorkQuiescenceFailed

    var errorDescription: String? {
        switch self {
        case .signOutInProgress:
            return "Authentication is changing. Try again in a moment."
        case .invalidOAuthIdentityToken:
            return "The identity provider returned an invalid token."
        case .guestMergeSessionChanged:
            return "Your signed-out session changed before the account upgrade could be secured."
        case .guestMergeHandoffPersistenceFailed:
            return "The account upgrade could not be secured on this device. Your signed-out session is unchanged."
        case .signOutPurchaseHandoffPersistenceFailed:
            return "Purchase access could not be secured on this device. Your account is still signed in."
        case .signOutPurchaseContinuityPending:
            return "Purchase access is still syncing after sign-out. Please try again."
        case .signOutSessionChanged:
            return "The signed-out session changed before purchase access finished syncing."
        case .purchasePrincipalRotationPersistenceFailed:
            return "Purchase access could not be secured on this device. Your account is still signed in."
        case .accountDeletionRecoveryPersistenceFailed:
            return "Account deletion could not be secured on this device. Your account is unchanged."
        case .accountDeletionRecoveryPending:
            return "Account deletion cleanup is still finishing on this device."
        case .accountBoundWorkQuiescenceFailed:
            return "Background work could not be safely paused. Your account is unchanged. Try again."
        }
    }
}

enum AuthTransitionProvider: String, Equatable, Sendable {
    case apple
    case google
}

enum AuthTransitionKind: Equatable, Sendable {
    case oauth(AuthTransitionProvider)
    case authenticationCallback
    case anonymousBootstrap
    case signOut
    case recovery
    case accountDeletion
    case accountDeletionCleanup
}

enum AuthTransitionPhase: String, Equatable, Sendable {
    case preparing
    case awaitingProvider
    case installingSession
    case bindingPurchases
    case deletingAccount
    case finalizing
}

enum AuthSessionAdoption: Equatable {
    case signedOut
    case awaitingRefresh(userId: UUID)
    case authenticated(userId: UUID)
}

struct AuthTransitionSession: Equatable, Sendable {
    let userID: UUID
    let isAnonymous: Bool
}

struct AuthTransitionToken: Equatable, Sendable {
    let id: UUID
    let kind: AuthTransitionKind
}

struct AuthTransitionState: Equatable, Sendable {
    let token: AuthTransitionToken
    var phase: AuthTransitionPhase
    let sourceSession: AuthTransitionSession?
    var expectedSession: AuthTransitionSession?
    var authGeneration: UInt64
}

struct AccountBoundWorkLease: Equatable, Sendable {
    let id: UUID
    let session: AuthTransitionSession
}
