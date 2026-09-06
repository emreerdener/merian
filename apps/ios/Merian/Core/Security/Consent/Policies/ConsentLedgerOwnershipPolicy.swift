import Foundation

@MainActor
enum ConsentLedgerOwnershipPolicy {
    static func rebinding(
        _ source: ConsentManager.LocalLedger,
        from ghostUserId: UUID,
        to permanentUserId: UUID
    ) -> ConsentManager.LocalLedger {
        var rebound = source
        rebound.activeUserId = permanentUserId

        for index in rebound.adultEligibilityReceipts.indices
        where rebound.adultEligibilityReceipts[index].ownerUserId == ghostUserId {
            let synchronizedUserId = rebound
                .adultEligibilityReceipts[index].syncedUserId
            rebound.adultEligibilityReceipts[index].ownerUserId = permanentUserId
            rebound.adultEligibilityReceipts[index].syncedUserId =
                reboundSynchronizationOwner(
                    synchronizedUserId,
                    from: ghostUserId,
                    to: permanentUserId
                )
        }

        for index in rebound.termsReceipts.indices
        where rebound.termsReceipts[index].ownerUserId == ghostUserId {
            let synchronizedUserId = rebound.termsReceipts[index].syncedUserId
            rebound.termsReceipts[index].ownerUserId = permanentUserId
            rebound.termsReceipts[index].syncedUserId =
                reboundSynchronizationOwner(
                    synchronizedUserId,
                    from: ghostUserId,
                    to: permanentUserId
                )
        }

        for index in rebound.aiConsentEvents.indices
        where rebound.aiConsentEvents[index].ownerUserId == ghostUserId {
            let synchronizedUserId = rebound.aiConsentEvents[index].syncedUserId
            rebound.aiConsentEvents[index].ownerUserId = permanentUserId
            rebound.aiConsentEvents[index].syncedUserId =
                reboundSynchronizationOwner(
                    synchronizedUserId,
                    from: ghostUserId,
                    to: permanentUserId
                )
        }

        for index in rebound.analyticsConsentEvents.indices
        where rebound.analyticsConsentEvents[index].ownerUserId == ghostUserId {
            let synchronizedUserId = rebound
                .analyticsConsentEvents[index].syncedUserId
            rebound.analyticsConsentEvents[index].ownerUserId = permanentUserId
            rebound.analyticsConsentEvents[index].syncedUserId =
                reboundSynchronizationOwner(
                    synchronizedUserId,
                    from: ghostUserId,
                    to: permanentUserId
                )
        }

        if rebound.requiredConsentReapprovalUserIds.remove(ghostUserId) != nil {
            rebound.requiredConsentReapprovalUserIds.insert(permanentUserId)
        }

        return rebound
    }

    static func activating(
        _ source: ConsentManager.LocalLedger,
        for userId: UUID
    ) -> ConsentManager.LocalLedger {
        var activated = source
        activated.activeUserId = userId
        return activated
    }

    static func rebindingAnalyticsRevocationJournal(
        _ source: ConsentManager.AnalyticsRevocationJournal,
        from ghostUserId: UUID,
        to permanentUserId: UUID
    ) -> ConsentManager.AnalyticsRevocationJournal? {
        var rebound = source
        var didChange = false
        for index in rebound.intents.indices
        where rebound.intents[index].event.ownerUserId == ghostUserId {
            rebound.intents[index].event.ownerUserId = permanentUserId
            rebound.intents[index].event.syncedUserId =
                reboundSynchronizationOwner(
                    rebound.intents[index].event.syncedUserId,
                    from: ghostUserId,
                    to: permanentUserId
                )
            didChange = true
        }
        return didChange ? rebound : nil
    }

    private static func reboundSynchronizationOwner(
        _ synchronizedUserId: UUID?,
        from ghostUserId: UUID,
        to permanentUserId: UUID
    ) -> UUID? {
        guard synchronizedUserId == ghostUserId else {
            return nil
        }
        return permanentUserId
    }
}

extension ConsentManager {
    static func rebinding(
        _ source: LocalLedger,
        from ghostUserId: UUID,
        to permanentUserId: UUID
    ) -> LocalLedger {
        ConsentLedgerOwnershipPolicy.rebinding(
            source,
            from: ghostUserId,
            to: permanentUserId
        )
    }

    static func activating(
        _ source: LocalLedger,
        for userId: UUID
    ) -> LocalLedger {
        ConsentLedgerOwnershipPolicy.activating(source, for: userId)
    }
}
