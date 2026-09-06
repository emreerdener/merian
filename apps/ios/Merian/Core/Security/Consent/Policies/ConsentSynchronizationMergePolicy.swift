import Foundation

@MainActor
enum ConsentSynchronizationMergePolicy {
    struct Result {
        let ledger: ConsentManager.LocalLedger
        let hasAuthoritativeRequiredConsent: Bool
        let analyticsCloudAuthorityState:
            ConsentManager.AnalyticsCloudAuthorityState
        let requiredConsentReapprovalAIStreamHeadId: UUID?
    }

    static func merging(
        _ remoteState: ConsentManager.RemoteState,
        into ledger: ConsentManager.LocalLedger,
        for userId: UUID
    ) -> Result {
        var candidate = ledger

        if let receipt = remoteState.adultEligibilityReceipt {
            upsert(
                receipt,
                in: &candidate.adultEligibilityReceipts,
                id: \.id
            )
        }
        if let receipt = remoteState.termsReceipt {
            upsert(receipt, in: &candidate.termsReceipts, id: \.id)
        }
        for event in [
            remoteState.aiConsentEvent,
            remoteState.aiConsentStreamHead
        ].compactMap({ $0 }) {
            upsert(event, in: &candidate.aiConsentEvents, id: \.id)
        }
        for event in [
            remoteState.analyticsConsentEvent,
            remoteState.analyticsConsentStreamHead
        ].compactMap({ $0 }) {
            upsert(event, in: &candidate.analyticsConsentEvents, id: \.id)
        }

        candidate.activeUserId = userId
        return Result(
            ledger: candidate,
            hasAuthoritativeRequiredConsent:
                ConsentAuthorityPolicy.isAuthoritativeRequiredConsent(
                    remoteState,
                    for: userId
                ),
            analyticsCloudAuthorityState: .resolvedRemote(
                userId: userId,
                granted: ConsentAuthorityPolicy.isAuthoritativeAnalyticsGrant(
                    remoteState.analyticsConsentStreamHead,
                    for: userId
                )
            ),
            requiredConsentReapprovalAIStreamHeadId:
                remoteState.aiConsentStreamHead?.id
        )
    }

    private static func upsert<Element>(
        _ element: Element,
        in elements: inout [Element],
        id: KeyPath<Element, UUID>
    ) {
        if let index = elements.firstIndex(where: {
            $0[keyPath: id] == element[keyPath: id]
        }) {
            elements[index] = element
        } else {
            elements.append(element)
        }
    }
}
