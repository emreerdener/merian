/// Single source of truth for app-owned Keychain key strings.
enum KeychainKeys {
    /// Distinguishes OAuth-authenticated users from anonymous ghost sessions.
    static let hasAuthenticatedOAuth = "Merian_HasAuthenticatedOAuth"
    /// Retired presentation-only logout marker. Kept only so upgraded clients
    /// can delete the old Keychain entry before restoring account state.
    static let legacyGhostModeUserID = "Merian_GhostModeUserID_v1"
    /// Provider-bound, one-use proof retained until the server confirms that
    /// both the guest data merge and Auth cleanup completed.
    static let pendingGhostProfileMerge = "Merian_PendingGhostProfileMerge"
    /// Device-only, one-use proof retained until RevenueCat confirms that the
    /// StoreKit purchase moved to the fresh anonymous sign-out identity.
    static let pendingSignOutPurchaseHandoff =
        "Merian_PendingSignOutPurchaseHandoff_v1"
    /// Stable, device-only capability used to resolve a server-owned purchase
    /// principal. The RevenueCat ID itself is never persisted as authority.
    static let purchasePrincipalInstallationCapability =
        "Merian_PurchasePrincipalInstallationCapability_v1"
    /// Device-only monotonic counter paired with the installation capability.
    /// Every resolver attempt advances and verifies it before network I/O so a
    /// delayed request from an older Auth session cannot overwrite a newer
    /// server binding.
    static let purchasePrincipalBindingIntentGeneration =
        "Merian_PurchasePrincipalBindingIntentGeneration_v1"
    /// Monotonic device-only evidence that this capability has activated a
    /// stable principal. It blocks later missing-route or legacy fallback.
    static let purchasePrincipalStableActivationFingerprint =
        "Merian_PurchasePrincipalStableActivationFingerprint_v1"
    /// Write-ahead journal for a server-prepared, capability-bound Auth
    /// rotation. The raw one-use proof stays device-only until the exact fresh
    /// anonymous destination claims it; the v1 key also recognizes older
    /// client-only markers and keeps them fail-closed.
    static let pendingPurchasePrincipalAuthRotation =
        "Merian_PendingPurchasePrincipalAuthRotation_v1"
    /// Device-only proof used only to recover or acknowledge a deletion that
    /// the authenticated backend already accepted. The server stores its hash;
    /// the raw capability never identifies or initiates an account deletion.
    static let accountDeletionRecoveryCapability =
        "Merian_AccountDeletionRecoveryCapability_v1"
    /// Write-ahead journal that keeps analytics fail-closed if the larger
    /// consent ledger cannot persist one or more account-wide withdrawals.
    static let analyticsRevocationIntent =
        "Merian_AnalyticsRevocationIntent_v1"
}
