import Foundation

/// Adapts the purchase-identity store's domain failures to the established
/// Auth-transition errors without moving Keychain ownership into Auth.
@MainActor
struct PurchaseIdentityHandoffAuthJournal {
    private let store: PurchaseIdentityHandoffStore

    init(store: PurchaseIdentityHandoffStore) {
        self.store = store
    }

    func loadLegacyHandoff() throws -> PendingSignOutPurchaseHandoff? {
        do {
            return try store.loadPendingSignOutPurchaseHandoff()
        } catch is PurchaseIdentityHandoffStoreError {
            throw SupabaseAuthTransitionError
                .signOutPurchaseHandoffPersistenceFailed
        }
    }

    func persistLegacyHandoff(
        _ pending: PendingSignOutPurchaseHandoff
    ) throws {
        do {
            try store.persistPendingSignOutPurchaseHandoff(pending)
        } catch is PurchaseIdentityHandoffStoreError {
            throw SupabaseAuthTransitionError
                .signOutPurchaseHandoffPersistenceFailed
        }
    }

    func clearLegacyHandoff() throws {
        try store.clearPendingSignOutPurchaseHandoff()
    }

    func loadStableRotation() throws
        -> PendingPurchasePrincipalAuthRotation? {
        do {
            return try store.loadPendingPurchasePrincipalAuthRotation()
        } catch is PurchaseIdentityHandoffStoreError {
            throw SupabaseAuthTransitionError
                .purchasePrincipalRotationPersistenceFailed
        }
    }

    func persistStableRotation(
        _ pending: ServerPrincipalRotation
    ) throws {
        do {
            try store.persistPendingPurchasePrincipalAuthRotation(pending)
        } catch is PurchaseIdentityHandoffStoreError {
            throw SupabaseAuthTransitionError
                .purchasePrincipalRotationPersistenceFailed
        }
    }

    func clearStableRotation() throws {
        try store.clearPendingPurchasePrincipalAuthRotation()
    }
}
