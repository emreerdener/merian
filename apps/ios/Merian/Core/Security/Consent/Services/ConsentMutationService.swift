import Foundation

@MainActor
final class ConsentMutationService {
    struct Dependencies {
        let now: () -> Date
        let makeUUID: () -> UUID
        let appVersion: () -> String
        let appBuild: () -> String
    }

    struct ConfirmationContext {
        let ownerUserId: UUID?
        let requiresReapproval: Bool
        let reapprovalBasisUserId: UUID?
        let reapprovalAIStreamHeadId: UUID?
    }

    struct ConfirmationResult: Equatable {
        let resolvedReapprovalUserId: UUID?
    }

    enum AnalyticsMutationResult: Equatable {
        case unchanged
        case persisted
    }

    private let ledgerRepository: ConsentLedgerRepository
    private let dependencies: Dependencies

    init(
        ledgerRepository: ConsentLedgerRepository,
        dependencies: Dependencies? = nil
    ) {
        self.ledgerRepository = ledgerRepository
        self.dependencies = dependencies ?? .live
    }

    func confirmRequiredConsent(
        analyticsEnabled: Bool,
        context: ConfirmationContext,
        refreshAnalyticsPermission: () -> Void
    ) throws -> ConfirmationResult {
        try ledgerRepository.ensureLedgerStorageAvailable()
        if analyticsEnabled {
            try ledgerRepository.ensureRevocationIntentStorageAvailable()
        }

        let now = dependencies.now()
        let appVersion = dependencies.appVersion()
        let appBuild = dependencies.appBuild()
        let source = ledgerRepository.ledger
        var candidate = ledgerRepository
            .ledgerByApplyingPendingAnalyticsRevocation(to: source)
        if candidate.activeUserId != context.ownerUserId {
            candidate.activeUserId = context.ownerUserId
        }

        let reapprovalAIStreamHeadId: UUID?
        if context.requiresReapproval {
            // A fresh approval must be based on the provider head fetched
            // after the server rejection. Replaying a cached grant could
            // repair a missing row but could never supersede a legitimate
            // newer revocation from another device.
            guard let ownerUserId = context.ownerUserId,
                  context.reapprovalBasisUserId == ownerUserId else {
                throw MerianError.aiConsentRequired
            }
            reapprovalAIStreamHeadId = context.reapprovalAIStreamHeadId
            candidate.requiredConsentReapprovalUserIds.remove(ownerUserId)
        } else {
            reapprovalAIStreamHeadId = nil
        }

        if context.requiresReapproval
            || ConsentStateProjectionPolicy.currentAdultEligibilityReceipt(
                ownerUserId: context.ownerUserId,
                in: source
            ) == nil {
            candidate.adultEligibilityReceipts.append(
                ConsentManager.AdultEligibilityReceipt(
                    id: dependencies.makeUUID(),
                    ownerUserId: context.ownerUserId,
                    syncedUserId: nil,
                    policyVersion: ConsentPolicy.adultEligibilityVersion,
                    confirmedAt: now,
                    confirmationMethod: .selfAttestation,
                    confirmationText: ConsentPolicy.adultConfirmationText,
                    platform: "ios",
                    appVersion: appVersion,
                    appBuild: appBuild,
                    recordedAt: nil
                )
            )
        }

        if context.requiresReapproval
            || ConsentStateProjectionPolicy.currentTermsReceipt(
                ownerUserId: context.ownerUserId,
                in: source
            ) == nil {
            candidate.termsReceipts.append(
                ConsentManager.TermsAcceptanceReceipt(
                    id: dependencies.makeUUID(),
                    ownerUserId: context.ownerUserId,
                    syncedUserId: nil,
                    termsVersion: ConsentPolicy.termsVersion,
                    acceptedAt: now,
                    acceptanceText: ConsentPolicy.combinedAcceptanceText,
                    platform: "ios",
                    appVersion: appVersion,
                    appBuild: appBuild,
                    recordedAt: nil
                )
            )
        }

        if context.requiresReapproval
            || ConsentAuthorityPolicy.currentAIConsentEvent(
                ownerUserId: context.ownerUserId,
                in: source
            )?.eventKind != .granted {
            candidate.aiConsentEvents.append(
                ConsentManager.AIConsentEvent(
                    id: dependencies.makeUUID(),
                    ownerUserId: context.ownerUserId,
                    syncedUserId: nil,
                    provider: ConsentPolicy.geminiProvider,
                    disclosureVersion:
                        ConsentPolicy.geminiDisclosureVersion,
                    eventKind: .granted,
                    occurredAt: now,
                    disclosureText: ConsentPolicy.geminiDisclosureText,
                    actionText: ConsentPolicy.combinedAcceptanceText,
                    platform: "ios",
                    appVersion: appVersion,
                    appBuild: appBuild,
                    recordedAt: nil,
                    causalParentId: context.requiresReapproval
                        ? reapprovalAIStreamHeadId
                        : ConsentAuthorityPolicy.currentAIConsentStreamHead(
                            ownerUserId: context.ownerUserId,
                            in: candidate
                        )?.id
                )
            )
        }

        let analyticsEvent = appendAnalyticsConsentEventIfNeeded(
            to: &candidate,
            enabled: analyticsEnabled,
            ownerUserId: context.ownerUserId,
            occurredAt: now,
            appVersion: appVersion,
            appBuild: appBuild
        )
        let persistenceEvent = confirmationPersistenceEvent(
            analyticsEvent: analyticsEvent,
            analyticsEnabled: analyticsEnabled,
            ownerUserId: context.ownerUserId,
            candidate: candidate
        )
        if persistenceEvent?.eventKind == .revoked {
            ledgerRepository.setAnalyticsWithdrawalInProgress(true)
            refreshAnalyticsPermission()
        }
        try ledgerRepository.persistConsentChange(
            candidate,
            analyticsEvent: persistenceEvent
        )
        return ConfirmationResult(
            resolvedReapprovalUserId: context.requiresReapproval
                ? context.ownerUserId
                : nil
        )
    }

    func setAnalyticsEnabled(
        _ enabled: Bool,
        ownerUserId: UUID?,
        refreshAnalyticsPermission: () -> Void
    ) throws -> AnalyticsMutationResult {
        try ledgerRepository.ensureLedgerStorageAvailable()
        if enabled {
            try ledgerRepository.ensureRevocationIntentStorageAvailable()
        } else {
            // Privacy withdrawal is effective in-process before either durable
            // boundary is touched.
            ledgerRepository.setAnalyticsWithdrawalInProgress(true)
            refreshAnalyticsPermission()
        }

        let source = ledgerRepository.ledger
        var candidate = ledgerRepository
            .ledgerByApplyingPendingAnalyticsRevocation(to: source)
        if candidate.activeUserId != ownerUserId {
            candidate.activeUserId = ownerUserId
        }
        let analyticsEvent = appendAnalyticsConsentEventIfNeeded(
            to: &candidate,
            enabled: enabled,
            ownerUserId: ownerUserId,
            occurredAt: dependencies.now(),
            appVersion: dependencies.appVersion(),
            appBuild: dependencies.appBuild()
        )
        let recoveryEvent = analyticsRecoveryEvent(
            enabled: enabled,
            analyticsEvent: analyticsEvent,
            ownerUserId: ownerUserId,
            candidate: candidate
        )

        guard candidate != source || recoveryEvent != nil else {
            ledgerRepository.setAnalyticsWithdrawalInProgress(false)
            refreshAnalyticsPermission()
            return .unchanged
        }

        try ledgerRepository.persistConsentChange(
            candidate,
            analyticsEvent: recoveryEvent
        )
        return .persisted
    }

    @discardableResult
    func withdrawGeminiPermission(
        hasGrantedGeminiProcessing: Bool,
        ownerUserId: UUID?
    ) throws -> Bool {
        guard hasGrantedGeminiProcessing else { return false }
        try ledgerRepository.ensureLedgerStorageAvailable()

        let source = ledgerRepository.ledger
        var candidate = source
        candidate.activeUserId = ownerUserId
        candidate.aiConsentEvents.append(ConsentManager.AIConsentEvent(
            id: dependencies.makeUUID(),
            ownerUserId: ownerUserId,
            syncedUserId: nil,
            provider: ConsentPolicy.geminiProvider,
            disclosureVersion: ConsentPolicy.geminiDisclosureVersion,
            eventKind: .revoked,
            occurredAt: dependencies.now(),
            disclosureText: ConsentPolicy.geminiDisclosureText,
            actionText: ConsentPolicy.geminiWithdrawalText,
            platform: "ios",
            appVersion: dependencies.appVersion(),
            appBuild: dependencies.appBuild(),
            recordedAt: nil,
            causalParentId: ConsentAuthorityPolicy.currentAIConsentStreamHead(
                ownerUserId: ownerUserId,
                in: candidate
            )?.id
        ))

        try ledgerRepository.persistLedger(candidate)
        return true
    }

    private func confirmationPersistenceEvent(
        analyticsEvent: ConsentManager.AnalyticsConsentEvent?,
        analyticsEnabled: Bool,
        ownerUserId: UUID?,
        candidate: ConsentManager.LocalLedger
    ) -> ConsentManager.AnalyticsConsentEvent? {
        if let analyticsEvent {
            return analyticsEvent
        }
        if analyticsEnabled,
           ledgerRepository.hasPendingAnalyticsRevocationJournal {
            return ConsentAuthorityPolicy.currentAnalyticsConsentEvent(
                ownerUserId: ownerUserId,
                in: candidate
            )
        }
        if !analyticsEnabled {
            return ledgerRepository.pendingAnalyticsRevocationEvent(
                for: ownerUserId
            )
        }
        return nil
    }

    private func analyticsRecoveryEvent(
        enabled: Bool,
        analyticsEvent: ConsentManager.AnalyticsConsentEvent?,
        ownerUserId: UUID?,
        candidate: ConsentManager.LocalLedger
    ) -> ConsentManager.AnalyticsConsentEvent? {
        if enabled,
           analyticsEvent == nil,
           ledgerRepository.hasPendingAnalyticsRevocationJournal {
            return ConsentAuthorityPolicy.currentAnalyticsConsentEvent(
                ownerUserId: ownerUserId,
                in: candidate
            )
        }
        if !enabled,
           analyticsEvent == nil,
           let pendingEvent = ledgerRepository.pendingAnalyticsRevocationEvent(
               for: ownerUserId
           ) {
            return pendingEvent
        }
        return analyticsEvent
    }

    private func appendAnalyticsConsentEventIfNeeded(
        to candidate: inout ConsentManager.LocalLedger,
        enabled: Bool,
        ownerUserId: UUID?,
        occurredAt: Date,
        appVersion: String,
        appBuild: String
    ) -> ConsentManager.AnalyticsConsentEvent? {
        let currentEvent = ConsentAuthorityPolicy.currentAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            in: candidate
        )
        let currentlyEnabled = currentEvent?.eventKind == .granted
        guard currentlyEnabled != enabled else { return nil }

        // No event is needed for the privacy-safe default state.
        guard enabled || currentEvent != nil else { return nil }

        let event = ConsentManager.AnalyticsConsentEvent(
            id: dependencies.makeUUID(),
            ownerUserId: ownerUserId,
            syncedUserId: nil,
            provider: ConsentPolicy.analyticsProvider,
            disclosureVersion: ConsentPolicy.analyticsDisclosureVersion,
            eventKind: enabled ? .granted : .revoked,
            occurredAt: occurredAt,
            disclosureText: ConsentPolicy.analyticsDisclosureText,
            actionText: enabled
                ? ConsentPolicy.analyticsDisclosureText
                : ConsentPolicy.analyticsWithdrawalText,
            platform: "ios",
            appVersion: appVersion,
            appBuild: appBuild,
            recordedAt: nil,
            causalParentId:
                ConsentAuthorityPolicy.currentAnalyticsConsentStreamHead(
                    ownerUserId: ownerUserId,
                    in: candidate
                )?.id
        )
        candidate.analyticsConsentEvents.append(event)
        return event
    }
}
