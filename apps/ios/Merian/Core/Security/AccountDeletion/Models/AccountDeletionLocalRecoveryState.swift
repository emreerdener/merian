enum AccountDeletionLocalRecoveryState: String, Equatable {
    /// The user confirmed deletion and the durable barrier was written before
    /// Keychain capability creation. Relaunch may create or reuse the proof only
    /// while the exact cached Auth session still exists.
    case capabilityPreparationPending = "capability_preparation_pending"
    /// Protocol v2 preparation was acknowledged without creating a deletion
    /// job. The commit request has not started; recovery may cancel this state
    /// without erasing local data.
    case capabilityPreparedPending = "capability_prepared_pending"
    /// The authenticated intake may be in flight or may have committed without
    /// returning a receipt. The exact cached Auth session must be retained so
    /// the idempotent request can be retried after relaunch.
    case intakePending = "intake_pending"
    /// The server returned its durable receipt. Local Auth, SwiftData, and all
    /// account-scoped preference/cache surfaces may be erased; the marker is
    /// cleared only after the complete local purge is verified.
    case cleanupPending = "cleanup_pending"
    /// Current protocol: the authenticated request may have committed and the
    /// device-held recovery capability must remain readable before any local
    /// account lifecycle can resume.
    case capabilityIntakePending = "capability_intake_pending"
    /// Current protocol: server acceptance was recovered or received. Local
    /// erasure must be acknowledged with the same capability before state is
    /// retired.
    case capabilityCleanupPending = "capability_cleanup_pending"
    /// The server acknowledged device cleanup. Relaunch re-verifies local Auth
    /// absence and idempotent data purge before capability/marker retirement;
    /// a crash after Keychain deletion can finish without the removed proof.
    case capabilityRetirementPending = "capability_retirement_pending"
    /// Durable deletion intake was definitively rejected before it could
    /// commit. Relaunch may retire only the unused Keychain proof and marker;
    /// it must not sign out or erase local data.
    case capabilityRejectionRetirementPending =
        "capability_rejection_retirement_pending"
    /// Keychain contained a proof while the UserDefaults phase was absent or
    /// secure storage could not be inspected before Auth bootstrap. Recovery is
    /// capability-only and must never submit a deletion for the current session.
    case capabilityLookupPending = "capability_lookup_pending"

    var isIntakePending: Bool {
        self == .intakePending ||
            self == .capabilityPreparationPending ||
            self == .capabilityPreparedPending ||
            self == .capabilityIntakePending
    }

    var requiresRecoveryCapability: Bool {
        self == .capabilityIntakePending ||
            self == .capabilityCleanupPending
    }
}
