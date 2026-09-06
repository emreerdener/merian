import Foundation

@MainActor
final class ConsentLedgerRepository {
    private let store: ConsentLedgerStoring
    private var stateChangeHandler: (@MainActor () -> Void)?

    private(set) var ledger: ConsentManager.LocalLedger = .empty
    private var pendingAnalyticsRevocationJournal:
        ConsentManager.AnalyticsRevocationJournal?
    private(set) var isLedgerStorageUncertain = true
    private(set) var isRevocationIntentStorageUncertain = true
    private(set) var isAnalyticsWithdrawalInProgress = false

    var hasPendingAnalyticsRevocationJournal: Bool {
        pendingAnalyticsRevocationJournal != nil
    }

    init(store: ConsentLedgerStoring) {
        self.store = store
        loadLedger()
        loadAnalyticsRevocationJournal()

        guard !isLedgerStorageUncertain,
              !isRevocationIntentStorageUncertain,
              hasPendingAnalyticsRevocationJournal else {
            return
        }

        do {
            try recoverPendingAnalyticsRevocation()
        } catch {
            MerianLog.auth.error(
                "Analytics withdrawal recovery remains pending; kind=\(MerianLog.errorKind(error), privacy: .public)."
            )
        }
    }

    func setStateChangeHandler(
        _ handler: @escaping @MainActor () -> Void
    ) {
        stateChangeHandler = handler
    }

    func ensureLedgerStorageAvailable() throws {
        guard !isLedgerStorageUncertain else {
            throw ConsentPersistenceError.storedLedgerUnavailable
        }
    }

    func ensureRevocationIntentStorageAvailable() throws {
        guard !isRevocationIntentStorageUncertain else {
            throw ConsentPersistenceError.revocationIntentInvalid
        }
    }

    func setAnalyticsWithdrawalInProgress(_ isInProgress: Bool) {
        isAnalyticsWithdrawalInProgress = isInProgress
        notifyStateChanged()
    }

    func persistLedger(
        _ candidate: ConsentManager.LocalLedger
    ) throws {
        try ensureLedgerStorageAvailable()
        let data: Data
        do {
            data = try JSONEncoder().encode(candidate)
        } catch {
            throw ConsentPersistenceError.encodingFailed
        }
        try store.saveLedgerData(data)
        ledger = candidate
        notifyStateChanged()
    }

    func persistConsentChange(
        _ candidate: ConsentManager.LocalLedger,
        analyticsEvent: ConsentManager.AnalyticsConsentEvent?
    ) throws {
        switch analyticsEvent?.eventKind {
        case .revoked:
            guard let analyticsEvent else { return }
            try persistAnalyticsRevocation(
                candidate,
                event: analyticsEvent
            )
        case .granted:
            try ensureRevocationIntentStorageAvailable()
            try persistLedger(candidate)
            if hasPendingAnalyticsRevocationJournal {
                do {
                    try clearAnalyticsRevocationJournal()
                } catch {
                    isAnalyticsWithdrawalInProgress = true
                    notifyStateChanged()
                    throw error
                }
            }
            isAnalyticsWithdrawalInProgress = false
            notifyStateChanged()
        case nil:
            try persistLedger(candidate)
        }
    }

    func activateLedger(for userId: UUID) throws {
        guard ledger.activeUserId != userId else { return }
        // Account restoration stays fail-closed until this verified local
        // activation is followed by the manager's authoritative remote merge.
        try persistLedger(
            ConsentLedgerOwnershipPolicy.activating(ledger, for: userId)
        )
    }

    func rebindLedger(
        from ghostUserId: UUID,
        to permanentUserId: UUID
    ) throws {
        let source = ledgerByApplyingPendingAnalyticsRevocation(to: ledger)
        try persistLedger(
            ConsentLedgerOwnershipPolicy.rebinding(
                source,
                from: ghostUserId,
                to: permanentUserId
            )
        )
    }

    func recoverPendingAnalyticsRevocation() throws {
        guard hasPendingAnalyticsRevocationJournal else { return }
        let candidate = ledgerByApplyingPendingAnalyticsRevocation(to: ledger)
        try persistLedger(candidate)
        try clearAnalyticsRevocationJournal()
        isAnalyticsWithdrawalInProgress = false
        notifyStateChanged()
    }

    func rebindPendingAnalyticsRevocationJournal(
        from ghostUserId: UUID,
        to permanentUserId: UUID
    ) throws {
        guard let journal = pendingAnalyticsRevocationJournal,
              let rebound = ConsentLedgerOwnershipPolicy
                .rebindingAnalyticsRevocationJournal(
                    journal,
                    from: ghostUserId,
                    to: permanentUserId
                ) else {
            return
        }
        try saveAnalyticsRevocationJournal(rebound)
    }

    func ledgerByApplyingPendingAnalyticsRevocation(
        to source: ConsentManager.LocalLedger
    ) -> ConsentManager.LocalLedger {
        guard !pendingAnalyticsRevocationIntents.isEmpty else { return source }
        var candidate = source
        for intent in pendingAnalyticsRevocationIntents
        where !candidate.analyticsConsentEvents.contains(where: {
            $0.id == intent.event.id
        }) {
            candidate.analyticsConsentEvents.append(intent.event)
        }
        return candidate
    }

    func pendingAnalyticsRevocationEvent(
        for ownerUserId: UUID?
    ) -> ConsentManager.AnalyticsConsentEvent? {
        for intent in pendingAnalyticsRevocationIntents.reversed() {
            let effectiveEvent = ledger.analyticsConsentEvents.first(where: {
                $0.id == intent.event.id
            }) ?? intent.event
            if effectiveEvent.ownerUserId == nil
                || effectiveEvent.ownerUserId == ownerUserId {
                return effectiveEvent
            }
        }
        return nil
    }

    func pendingAnalyticsRevocationApplies(
        to ownerUserId: UUID?
    ) -> Bool {
        pendingAnalyticsRevocationEvent(for: ownerUserId) != nil
    }

    private var pendingAnalyticsRevocationIntents:
        [ConsentManager.AnalyticsRevocationIntent] {
        pendingAnalyticsRevocationJournal?.intents ?? []
    }

    private func loadLedger() {
        do {
            if let data = try store.loadLedgerData() {
                do {
                    ledger = try JSONDecoder().decode(
                        ConsentManager.LocalLedger.self,
                        from: data
                    )
                    isLedgerStorageUncertain = false
                } catch {
                    ledger = .empty
                    isLedgerStorageUncertain = true
                    MerianLog.auth.error(
                        "Consent ledger decoding failed; all consent gates remain closed."
                    )
                }
            } else {
                ledger = .empty
                isLedgerStorageUncertain = false
            }
        } catch {
            ledger = .empty
            isLedgerStorageUncertain = true
            MerianLog.auth.error(
                "Consent ledger loading failed; all consent gates remain closed; kind=\(MerianLog.errorKind(error), privacy: .public)."
            )
        }
    }

    private func loadAnalyticsRevocationJournal() {
        do {
            if let data = try store.loadAnalyticsRevocationIntentData() {
                do {
                    let journal = try JSONDecoder().decode(
                        ConsentManager.AnalyticsRevocationJournal.self,
                        from: data
                    )
                    if journal.formatVersion
                        == ConsentManager.AnalyticsRevocationJournal
                            .currentFormatVersion,
                       !journal.intents.isEmpty,
                       journal.intents.allSatisfy({ intent in
                           intent.event.eventKind == .revoked
                               && intent.event.provider
                                   == ConsentPolicy.analyticsProvider
                       }) {
                        pendingAnalyticsRevocationJournal = journal
                        isRevocationIntentStorageUncertain = false
                    } else {
                        pendingAnalyticsRevocationJournal = nil
                        isRevocationIntentStorageUncertain = true
                    }
                } catch {
                    pendingAnalyticsRevocationJournal = nil
                    isRevocationIntentStorageUncertain = true
                    MerianLog.auth.error(
                        "Analytics withdrawal journal decoding failed; analytics remains disabled."
                    )
                }
            } else {
                pendingAnalyticsRevocationJournal = nil
                isRevocationIntentStorageUncertain = false
            }
        } catch {
            pendingAnalyticsRevocationJournal = nil
            isRevocationIntentStorageUncertain = true
            MerianLog.auth.error(
                "Analytics withdrawal journal loading failed; analytics remains disabled; kind=\(MerianLog.errorKind(error), privacy: .public)."
            )
        }
    }

    private func persistAnalyticsRevocation(
        _ candidate: ConsentManager.LocalLedger,
        event: ConsentManager.AnalyticsConsentEvent
    ) throws {
        if pendingAnalyticsRevocationIntents.contains(where: {
            $0.event.id == event.id
        }) {
            // The write-ahead record was already verified by an earlier
            // attempt, so retry only the primary ledger boundary.
        } else {
            let intent = ConsentManager.AnalyticsRevocationIntent(event: event)
            var journal = pendingAnalyticsRevocationJournal
                ?? ConsentManager.AnalyticsRevocationJournal(intents: [])
            journal.intents.append(intent)
            do {
                try saveAnalyticsRevocationJournal(journal)
            } catch {
                // The atomic ledger remains a second independent way to make
                // the withdrawal durable. Only fail if both boundaries fail.
                do {
                    try persistLedger(candidate)
                    isAnalyticsWithdrawalInProgress = false
                    notifyStateChanged()
                    return
                } catch {
                    notifyStateChanged()
                    throw error
                }
            }
        }

        do {
            try persistLedger(candidate)
        } catch {
            // The intent is already durable and is deliberately retained.
            // It will be replayed on restart or the next retry.
            notifyStateChanged()
            throw error
        }

        do {
            try clearAnalyticsRevocationJournal()
        } catch {
            // Cleanup failure is privacy-safe: the durable ledger contains the
            // revocation and the retained intent continues to force analytics
            // off. Recovery will retry deletion on the next launch.
            MerianLog.auth.error(
                "Analytics withdrawal journal cleanup remains pending; kind=\(MerianLog.errorKind(error), privacy: .public)."
            )
        }
        isAnalyticsWithdrawalInProgress = false
        notifyStateChanged()
    }

    private func saveAnalyticsRevocationJournal(
        _ journal: ConsentManager.AnalyticsRevocationJournal
    ) throws {
        try ensureRevocationIntentStorageAvailable()
        let data: Data
        do {
            data = try JSONEncoder().encode(journal)
        } catch {
            throw ConsentPersistenceError.encodingFailed
        }
        try store.saveAnalyticsRevocationIntentData(data)
        pendingAnalyticsRevocationJournal = journal
        isRevocationIntentStorageUncertain = false
        notifyStateChanged()
    }

    private func clearAnalyticsRevocationJournal() throws {
        try store.clearAnalyticsRevocationIntentData()
        pendingAnalyticsRevocationJournal = nil
        isRevocationIntentStorageUncertain = false
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        stateChangeHandler?()
    }
}
