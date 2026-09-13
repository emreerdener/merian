import Foundation

@MainActor
enum ConsentStateProjectionPolicy {
    struct CurrentState: Equatable {
        let ownerUserId: UUID?
        let hasConfirmedAdultEligibility: Bool
        let hasAcceptedTerms: Bool
        let hasGrantedGeminiProcessing: Bool
        let hasGrantedPostHogAnalytics: Bool
    }

    struct AnalyticsPermission: Equatable {
        let isEnabled: Bool
        let ownerUserId: UUID?
    }

    struct RequiredConsentEvidence: Equatable {
        let hasConfirmedAdultEligibility: Bool
        let hasAcceptedTerms: Bool
        let hasGrantedGeminiProcessing: Bool

        var isComplete: Bool {
            hasConfirmedAdultEligibility
                && hasAcceptedTerms
                && hasGrantedGeminiProcessing
        }
    }

    static func currentOwnerUserId(
        currentSessionUserId: UUID?,
        hasObservedSession: Bool,
        ledgerActiveUserId: UUID?
    ) -> UUID? {
        if let currentSessionUserId {
            return currentSessionUserId
        }
        if hasObservedSession {
            // Once Auth has explicitly resolved to no session, never expose a
            // prior account's choices. Nil still permits newly completed,
            // not-yet-bound evidence until ghost Auth assigns an account UUID.
            return nil
        }
        // During cold-start Auth restoration, use persisted account evidence
        // provisionally. The first Auth event confirms it or closes every gate.
        return ledgerActiveUserId
    }

    static func currentState(
        ledger: ConsentManager.LocalLedger,
        ownerUserId: UUID?,
        inMemoryReapprovalUserIds: Set<UUID>,
        isLedgerStorageUncertain: Bool,
        isRevocationIntentStorageUncertain: Bool,
        isAnalyticsWithdrawalInProgress: Bool,
        pendingAnalyticsRevocationApplies: Bool
    ) -> CurrentState {
        let requiredConsent = requiredConsentEvidence(
            for: ownerUserId,
            ledger: ledger,
            inMemoryUserIds: inMemoryReapprovalUserIds
        )
        let hasStoredAnalyticsGrant = ConsentAuthorityPolicy
            .currentAnalyticsConsentEvent(
                ownerUserId: ownerUserId,
                in: ledger
            )?.eventKind == .granted
        return CurrentState(
            ownerUserId: ownerUserId,
            hasConfirmedAdultEligibility:
                requiredConsent.hasConfirmedAdultEligibility,
            hasAcceptedTerms: requiredConsent.hasAcceptedTerms,
            hasGrantedGeminiProcessing:
                requiredConsent.hasGrantedGeminiProcessing,
            hasGrantedPostHogAnalytics: !isLedgerStorageUncertain
                && !isRevocationIntentStorageUncertain
                && !isAnalyticsWithdrawalInProgress
                && !pendingAnalyticsRevocationApplies
                && hasStoredAnalyticsGrant
        )
    }

    static func requiredConsentEvidence(
        for ownerUserId: UUID?,
        ledger: ConsentManager.LocalLedger,
        inMemoryUserIds: Set<UUID>
    ) -> RequiredConsentEvidence {
        let requiresReapproval = requiresRequiredConsentReapproval(
            for: ownerUserId,
            ledger: ledger,
            inMemoryUserIds: inMemoryUserIds
        )
        return RequiredConsentEvidence(
            hasConfirmedAdultEligibility: !requiresReapproval
                && currentAdultEligibilityReceipt(
                    ownerUserId: ownerUserId,
                    in: ledger
                ) != nil,
            hasAcceptedTerms: !requiresReapproval
                && currentTermsReceipt(
                    ownerUserId: ownerUserId,
                    in: ledger
                ) != nil,
            hasGrantedGeminiProcessing: !requiresReapproval
                && ConsentAuthorityPolicy.currentAIConsentEvent(
                    ownerUserId: ownerUserId,
                    in: ledger
                )?.eventKind == .granted
        )
    }

    static func hasCurrentRequiredConsent(
        currentSessionUserId: UUID?,
        ledgerActiveUserId: UUID?,
        hasConfirmedAdultEligibility: Bool,
        hasAcceptedTerms: Bool,
        hasGrantedGeminiProcessing: Bool
    ) -> Bool {
        let accountMatches = currentSessionUserId == nil
            || ledgerActiveUserId == nil
            || currentSessionUserId == ledgerActiveUserId
        return accountMatches
            && hasConfirmedAdultEligibility
            && hasAcceptedTerms
            && hasGrantedGeminiProcessing
    }

    static func pendingCloudRecordCount(
        in ledger: ConsentManager.LocalLedger
    ) -> Int {
        let activeUserId = ledger.activeUserId
        let pendingAdultReceipts = ledger.adultEligibilityReceipts.filter {
            $0.ownerUserId == activeUserId
                && isPending(
                    syncedUserId: $0.syncedUserId,
                    activeUserId: activeUserId
                )
        }.count
        let pendingTerms = ledger.termsReceipts.filter {
            $0.ownerUserId == activeUserId
                && isPending(
                    syncedUserId: $0.syncedUserId,
                    activeUserId: activeUserId
                )
        }.count
        let pendingAIEvents = ledger.aiConsentEvents.filter {
            $0.ownerUserId == activeUserId
                && $0.supersededByEventId == nil
                && $0.supersededByRevision == nil
                && isPending(
                    syncedUserId: $0.syncedUserId,
                    activeUserId: activeUserId
                )
        }.count
        let pendingAnalyticsEvents = ledger.analyticsConsentEvents.filter {
            $0.ownerUserId == activeUserId
                && $0.supersededByEventId == nil
                && $0.supersededByRevision == nil
                && isPending(
                    syncedUserId: $0.syncedUserId,
                    activeUserId: activeUserId
                )
        }.count
        return pendingAdultReceipts
            + pendingTerms
            + pendingAIEvents
            + pendingAnalyticsEvents
    }

    static func hasCloudReadyCurrentConsent(
        for userId: UUID,
        cloudReadyUserId: UUID?,
        ledger: ConsentManager.LocalLedger
    ) -> Bool {
        guard cloudReadyUserId == userId,
              ledger.activeUserId == userId,
              currentAdultEligibilityReceipt(
                  ownerUserId: userId,
                  in: ledger
              )?.syncedUserId == userId,
              currentTermsReceipt(
                  ownerUserId: userId,
                  in: ledger
              )?.syncedUserId == userId,
              let event = ConsentAuthorityPolicy.currentAIConsentEvent(
                  ownerUserId: userId,
                  in: ledger
              ) else {
            return false
        }
        return event.eventKind == .granted && event.syncedUserId == userId
    }

    static func currentTermsReceipt(
        ownerUserId: UUID?,
        in ledger: ConsentManager.LocalLedger
    ) -> ConsentManager.TermsAcceptanceReceipt? {
        ledger.termsReceipts
            .filter {
                $0.ownerUserId == ownerUserId
                    && $0.termsVersion == ConsentPolicy.termsVersion
            }
            .max { lhs, rhs in
                (lhs.recordedAt ?? lhs.acceptedAt)
                    < (rhs.recordedAt ?? rhs.acceptedAt)
            }
    }

    static func currentAdultEligibilityReceipt(
        ownerUserId: UUID?,
        in ledger: ConsentManager.LocalLedger
    ) -> ConsentManager.AdultEligibilityReceipt? {
        ledger.adultEligibilityReceipts
            .filter {
                $0.ownerUserId == ownerUserId
                    && $0.policyVersion
                        == ConsentPolicy.adultEligibilityVersion
            }
            .max { lhs, rhs in
                (lhs.recordedAt ?? lhs.confirmedAt)
                    < (rhs.recordedAt ?? rhs.confirmedAt)
            }
    }

    static func requiresRequiredConsentReapproval(
        for ownerUserId: UUID?,
        ledger: ConsentManager.LocalLedger,
        inMemoryUserIds: Set<UUID>
    ) -> Bool {
        guard let ownerUserId else { return false }
        return ledger.requiredConsentReapprovalUserIds.contains(ownerUserId)
            || inMemoryUserIds.contains(ownerUserId)
    }

    static func analyticsPermission(
        ledgerActiveUserId: UUID?,
        currentSessionUserId: UUID?,
        isSuppressedForGhostHandoff: Bool,
        isSuppressedForAccountTransition: Bool,
        cloudAuthorityState: ConsentManager.AnalyticsCloudAuthorityState,
        isLedgerStorageUncertain: Bool,
        isRevocationIntentStorageUncertain: Bool,
        isAnalyticsWithdrawalInProgress: Bool,
        pendingAnalyticsRevocationApplies: Bool,
        hasGrantedPostHogAnalytics: Bool
    ) -> AnalyticsPermission {
        let accountMatches: Bool
        if let ledgerActiveUserId {
            accountMatches = currentSessionUserId == ledgerActiveUserId
        } else {
            accountMatches = currentSessionUserId == nil
        }

        let isEnabled = !isSuppressedForGhostHandoff
            && !isSuppressedForAccountTransition
            && cloudAuthorityState.allowsCapture(for: currentSessionUserId)
            && !isLedgerStorageUncertain
            && !isRevocationIntentStorageUncertain
            && !isAnalyticsWithdrawalInProgress
            && !pendingAnalyticsRevocationApplies
            && accountMatches
            && hasGrantedPostHogAnalytics
        return AnalyticsPermission(
            isEnabled: isEnabled,
            ownerUserId: isEnabled
                ? currentSessionUserId ?? ledgerActiveUserId
                : nil
        )
    }

    private static func isPending(
        syncedUserId: UUID?,
        activeUserId: UUID?
    ) -> Bool {
        guard let activeUserId else { return true }
        return syncedUserId != activeUserId
    }
}
