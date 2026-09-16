import Foundation

struct PurchaseIdentitySessionContext: Equatable {
    let userID: UUID
    let isAnonymous: Bool
    let authGeneration: UInt64

    var accountKind: String {
        RevenueCatAccountMutationPolicy.accountKind(
            isAnonymous: isAnonymous
        )
    }
}

struct PurchaseIdentitySessionSnapshot {
    let userID: UUID
    let isAnonymous: Bool
    let isExpired: Bool
    let linkLegacyProviderIdentity: @MainActor () async -> Void

    func matches(_ context: PurchaseIdentitySessionContext) -> Bool {
        userID == context.userID && isAnonymous == context.isAnonymous
    }
}

struct PurchaseIdentityProviderState: Equatable {
    let isIdentityReady: Bool
    let linkedAuthUserID: UUID?
    let linkedAccountKind: String?

    func matches(_ context: PurchaseIdentitySessionContext) -> Bool {
        isIdentityReady
            && linkedAuthUserID == context.userID
            && linkedAccountKind == context.accountKind
    }
}

struct PurchaseIdentityAccountWorkLease {
    let isCurrent: @MainActor () -> Bool
    let finish: @MainActor () -> Void
}
