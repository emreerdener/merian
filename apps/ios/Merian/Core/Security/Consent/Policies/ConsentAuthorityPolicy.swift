import Foundation

@MainActor
enum ConsentAuthorityPolicy {
    static func isAuthoritativeAnalyticsGrant(
        _ event: ConsentManager.AnalyticsConsentEvent?,
        for userId: UUID
    ) -> Bool {
        guard let event else { return false }
        return event.ownerUserId == userId
            && event.syncedUserId == userId
            && event.provider == ConsentPolicy.analyticsProvider
            && event.disclosureVersion == ConsentPolicy.analyticsDisclosureVersion
            && event.eventKind == .granted
    }

    static func isAuthoritativeRequiredConsent(
        _ remoteState: ConsentManager.RemoteState,
        for userId: UUID
    ) -> Bool {
        guard let adultReceipt = remoteState.adultEligibilityReceipt,
              adultReceipt.ownerUserId == userId,
              adultReceipt.syncedUserId == userId,
              adultReceipt.policyVersion
                == ConsentPolicy.adultEligibilityVersion,
              let termsReceipt = remoteState.termsReceipt,
              termsReceipt.ownerUserId == userId,
              termsReceipt.syncedUserId == userId,
              termsReceipt.termsVersion == ConsentPolicy.termsVersion,
              let streamHead = remoteState.aiConsentStreamHead else {
            return false
        }
        return streamHead.ownerUserId == userId
            && streamHead.syncedUserId == userId
            && streamHead.provider == ConsentPolicy.geminiProvider
            && streamHead.disclosureVersion
                == ConsentPolicy.geminiDisclosureVersion
            && streamHead.eventKind == .granted
    }

    static func currentAIConsentEvent(
        ownerUserId: UUID?,
        in source: ConsentManager.LocalLedger
    ) -> ConsentManager.AIConsentEvent? {
        // Resolve the provider-wide head before checking its disclosure. A
        // prior-version revocation may be the newest accepted user action.
        guard let streamHead = currentAIConsentStreamHead(
            ownerUserId: ownerUserId,
            in: source
        ), streamHead.disclosureVersion
            == ConsentPolicy.geminiDisclosureVersion else {
            return nil
        }
        return streamHead
    }

    static func currentAnalyticsConsentEvent(
        ownerUserId: UUID?,
        in source: ConsentManager.LocalLedger
    ) -> ConsentManager.AnalyticsConsentEvent? {
        // Only the all-version provider head can authorize the SDK. Filtering
        // first would hide a delayed withdrawal from older disclosure copy.
        guard let streamHead = currentAnalyticsConsentStreamHead(
            ownerUserId: ownerUserId,
            in: source
        ), streamHead.disclosureVersion
            == ConsentPolicy.analyticsDisclosureVersion else {
            return nil
        }
        return streamHead
    }

    static func currentAIConsentStreamHead(
        ownerUserId: UUID?,
        in source: ConsentManager.LocalLedger
    ) -> ConsentManager.AIConsentEvent? {
        let matchingEvents = source.aiConsentEvents.filter {
            $0.ownerUserId == ownerUserId
                && $0.provider == ConsentPolicy.geminiProvider
                && !isSuperseded($0)
        }
        if let pendingEvent = matchingEvents.last(where: {
            $0.syncedUserId == nil || $0.syncedUserId != $0.ownerUserId
        }) {
            return pendingEvent
        }
        return matchingEvents.max(by: aiConsentEventPrecedes)
    }

    static func currentAnalyticsConsentStreamHead(
        ownerUserId: UUID?,
        in source: ConsentManager.LocalLedger
    ) -> ConsentManager.AnalyticsConsentEvent? {
        let matchingEvents = source.analyticsConsentEvents.filter {
            $0.ownerUserId == ownerUserId
                && $0.provider == ConsentPolicy.analyticsProvider
                && !isSuperseded($0)
        }
        if let pendingEvent = matchingEvents.last(where: {
            $0.syncedUserId == nil || $0.syncedUserId != $0.ownerUserId
        }) {
            return pendingEvent
        }
        return matchingEvents.max(by: analyticsConsentEventPrecedes)
    }

    private static func isSuperseded(
        _ event: ConsentManager.AIConsentEvent
    ) -> Bool {
        event.supersededByEventId != nil || event.supersededByRevision != nil
    }

    private static func isSuperseded(
        _ event: ConsentManager.AnalyticsConsentEvent
    ) -> Bool {
        event.supersededByEventId != nil || event.supersededByRevision != nil
    }

    private static func aiConsentEventPrecedes(
        _ lhs: ConsentManager.AIConsentEvent,
        _ rhs: ConsentManager.AIConsentEvent
    ) -> Bool {
        if let lhsRevision = lhs.consentRevision,
           let rhsRevision = rhs.consentRevision,
           lhsRevision != rhsRevision {
            return lhsRevision < rhsRevision
        }
        if lhs.consentRevision == nil, rhs.consentRevision != nil {
            return true
        }
        if lhs.consentRevision != nil, rhs.consentRevision == nil {
            return false
        }
        let lhsDate = lhs.recordedAt ?? lhs.occurredAt
        let rhsDate = rhs.recordedAt ?? rhs.occurredAt
        if lhsDate == rhsDate {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhsDate < rhsDate
    }

    private static func analyticsConsentEventPrecedes(
        _ lhs: ConsentManager.AnalyticsConsentEvent,
        _ rhs: ConsentManager.AnalyticsConsentEvent
    ) -> Bool {
        if let lhsRevision = lhs.consentRevision,
           let rhsRevision = rhs.consentRevision,
           lhsRevision != rhsRevision {
            return lhsRevision < rhsRevision
        }
        if lhs.consentRevision == nil, rhs.consentRevision != nil {
            return true
        }
        if lhs.consentRevision != nil, rhs.consentRevision == nil {
            return false
        }
        let lhsDate = lhs.recordedAt ?? lhs.occurredAt
        let rhsDate = rhs.recordedAt ?? rhs.occurredAt
        if lhsDate == rhsDate {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhsDate < rhsDate
    }
}

extension ConsentManager {
    static func isAuthoritativeAnalyticsGrant(
        _ event: AnalyticsConsentEvent?,
        for userId: UUID
    ) -> Bool {
        ConsentAuthorityPolicy.isAuthoritativeAnalyticsGrant(
            event,
            for: userId
        )
    }

    static func isAuthoritativeRequiredConsent(
        _ remoteState: RemoteState,
        for userId: UUID
    ) -> Bool {
        ConsentAuthorityPolicy.isAuthoritativeRequiredConsent(
            remoteState,
            for: userId
        )
    }
}
