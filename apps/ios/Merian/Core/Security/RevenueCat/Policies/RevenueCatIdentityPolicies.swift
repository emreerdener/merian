import Foundation

enum RevenueCatAppUserIDPolicy {
    /// RevenueCat App User IDs are case-sensitive. Merian uses the uppercase
    /// RFC 4122 representation emitted by Swift as the single cross-system ID.
    static func canonicalID(for userID: UUID) -> String {
        userID.uuidString.uppercased()
    }
}

enum RevenueCatAccountMutationPolicy {
    static let ghostAccountKind = "anonymous"
    static let permanentAccountKind = "authenticated"

    static func accountKind(isAnonymous: Bool) -> String {
        isAnonymous ? ghostAccountKind : permanentAccountKind
    }

    static func normalizedAccountKind(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !value.isEmpty else {
            return nil
        }
        return value.lowercased()
    }

    static func allowsProviderMutation(accountKind: String?) -> Bool {
        switch normalizedAccountKind(accountKind) {
        case ghostAccountKind, permanentAccountKind:
            return true
        default:
            return false
        }
    }

    static func isReady(
        identityReady: Bool,
        requestedAccountKind: String?,
        linkedAccountKind: String?
    ) -> Bool {
        let requested = normalizedAccountKind(requestedAccountKind)
        let linked = normalizedAccountKind(linkedAccountKind)
        return identityReady
            && requested == linked
            && allowsProviderMutation(accountKind: linked)
    }
}

enum RevenueCatPurchaseMutationPolicy {
    static func isReady(
        providerIdentityReady: Bool,
        identityHandoffPending: Bool
    ) -> Bool {
        providerIdentityReady && !identityHandoffPending
    }
}

enum RevenueCatIdentityRebindPolicy {
    /// Any change to the Auth binding closes local paid readiness before the
    /// RevenueCat SDK or server projection is consulted. This is especially
    /// important for a stable purchase principal: the provider App User ID may
    /// remain unchanged while account-scoped grants must stop following the
    /// previous Auth user immediately.
    static func requiresPaidReadinessReset(
        linkedAppUserID: String?,
        linkedAuthUserID: UUID?,
        linkedBindingGeneration: Int64?,
        linkedAccountKind: String?,
        nextAppUserID: String,
        nextAuthUserID: UUID,
        nextBindingGeneration: Int64,
        nextAccountKind: String?
    ) -> Bool {
        linkedAppUserID != nextAppUserID
            || linkedAuthUserID != nextAuthUserID
            || linkedBindingGeneration != nextBindingGeneration
            || RevenueCatAccountMutationPolicy.normalizedAccountKind(
                linkedAccountKind
            ) != RevenueCatAccountMutationPolicy.normalizedAccountKind(
                nextAccountKind
            )
    }
}
