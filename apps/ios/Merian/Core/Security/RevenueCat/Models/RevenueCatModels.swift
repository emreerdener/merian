import Foundation

struct SevenDayPassPurchase {
    let productIdentifier: String
    let purchaseDate: Date
}

/// Monotonic snapshot used to reject provider results that cross an Auth
/// rebind or purchase-identity handoff, even when the App User ID is reused.
struct RevenueCatProviderOperationContext: Equatable {
    let appUserID: String
    let identityGeneration: UInt64
    let handoffGeneration: UInt64
}

struct RevenueCatIdentityRequest: Equatable {
    let appUserID: String
    let authUserID: UUID
    let bindingGeneration: Int64
    let accountKind: String?
    let accountGrantsAllowed: Bool
    let usesStablePurchasePrincipal: Bool
}

struct RevenueCatIdentityLinkContext: Equatable {
    let request: RevenueCatIdentityRequest
    let generation: UInt64
    let accountGrantFenceGeneration: UInt64
}

enum RevenueCatLegacySubscriberAttributeKey: String, CaseIterable {
    case supabaseUserID = "supabase_user_id"
    case authEmail = "auth_email"
    case displayName = "display_name"
    case avatarURL = "avatar_url"
    case publicUsername = "public_username"
    case publicAuthorName = "public_author_name"
    case publicIdentitySource = "public_identity_source"
    case accountKind = "account_kind"
}

enum RevenueCatManagerError: LocalizedError {
    case identityNotReady

    var errorDescription: String? {
        switch self {
        case .identityNotReady:
            return "RevenueCat is waiting for the active Merian account. Please try again."
        }
    }
}

struct RevenueCatIdentityContext: Equatable {
    let userId: String
    let email: String?
    let displayName: String?
    let avatarUrl: String?
    let publicUsername: String?
    let publicAuthorName: String?
    let publicIdentitySource: String?
    let accountKind: String?

    var normalizedEmail: String? {
        Self.normalized(email)
    }

    var normalizedDisplayName: String? {
        if let displayName = Self.firstNonEmpty(displayName, publicAuthorName) {
            return displayName
        }
        guard let publicUsername = Self.normalized(publicUsername) else {
            return nil
        }
        return "@\(publicUsername)"
    }

    var subscriberAttributes: [String: String] {
        var attributes: [String: String] = [
            RevenueCatLegacySubscriberAttributeKey.supabaseUserID.rawValue:
                userId
        ]

        set(.authEmail, email, in: &attributes)
        set(.displayName, normalizedDisplayName, in: &attributes)
        set(.avatarURL, avatarUrl, in: &attributes)
        set(.publicUsername, publicUsername, in: &attributes)
        set(.publicAuthorName, publicAuthorName, in: &attributes)
        set(.publicIdentitySource, publicIdentitySource, in: &attributes)
        set(.accountKind, accountKind, in: &attributes)

        return attributes
    }

    static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy.compactMap(normalized).first
    }

    private func set(
        _ key: RevenueCatLegacySubscriberAttributeKey,
        _ value: String?,
        in attributes: inout [String: String]
    ) {
        guard let normalized = Self.normalized(value) else { return }
        attributes[key.rawValue] = normalized
    }
}
