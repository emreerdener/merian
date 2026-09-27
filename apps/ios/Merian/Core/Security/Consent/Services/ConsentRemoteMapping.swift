import Foundation

@MainActor
enum ConsentRemoteMapping {
    /// An empty successful query is authoritative absence. A present row that
    /// cannot map is malformed evidence and must not be collapsed into absence.
    static func firstMappedRemoteRow<RemoteRow, LocalValue>(
        _ rows: [RemoteRow],
        using transform: (RemoteRow) -> LocalValue?
    ) throws -> LocalValue? {
        guard let row = rows.first else {
            return nil
        }
        guard let value = transform(row) else {
            throw MerianError.invalidResponse
        }
        return value
    }

    static func localAdultEligibilityReceipt(
        _ row: ConsentRemoteWire.AdultEligibilityReceipt
    ) -> ConsentManager.AdultEligibilityReceipt? {
        guard let method = ConsentManager.AdultConfirmationMethod(
            rawValue: row.confirmation_method
        ), let confirmedAt = date(row.confirmed_at),
           let recordedAt = date(row.recorded_at) else {
            return nil
        }
        return ConsentManager.AdultEligibilityReceipt(
            id: row.id,
            ownerUserId: row.user_id,
            syncedUserId: row.user_id,
            policyVersion: row.policy_version,
            confirmedAt: confirmedAt,
            confirmationMethod: method,
            confirmationText: row.confirmation_text,
            platform: row.platform,
            appVersion: row.app_version,
            appBuild: row.app_build,
            recordedAt: recordedAt
        )
    }

    static func localTermsReceipt(
        _ row: ConsentRemoteWire.TermsReceipt
    ) -> ConsentManager.TermsAcceptanceReceipt? {
        guard let acceptedAt = date(row.accepted_at),
              let recordedAt = date(row.recorded_at) else {
            return nil
        }
        return ConsentManager.TermsAcceptanceReceipt(
            id: row.id,
            ownerUserId: row.user_id,
            syncedUserId: row.user_id,
            termsVersion: row.terms_version,
            acceptedAt: acceptedAt,
            acceptanceText: row.acceptance_text,
            platform: row.platform,
            appVersion: row.app_version,
            appBuild: row.app_build,
            recordedAt: recordedAt
        )
    }

    static func localAIConsentEvent(
        _ row: ConsentRemoteWire.AIConsentEvent
    ) -> ConsentManager.AIConsentEvent? {
        guard let eventKind = ConsentManager.AIConsentEventKind(
            rawValue: row.event_kind
        ), let occurredAt = date(row.occurred_at),
           let recordedAt = date(row.recorded_at) else {
            return nil
        }
        return ConsentManager.AIConsentEvent(
            id: row.id,
            ownerUserId: row.user_id,
            syncedUserId: row.user_id,
            provider: row.provider,
            disclosureVersion: row.disclosure_version,
            eventKind: eventKind,
            occurredAt: occurredAt,
            disclosureText: row.disclosure_text,
            actionText: row.action_text,
            platform: row.platform,
            appVersion: row.app_version,
            appBuild: row.app_build,
            recordedAt: recordedAt,
            causalParentId: row.causal_parent_id,
            consentRevision: row.consent_revision
        )
    }

    static func localAnalyticsConsentEvent(
        _ row: ConsentRemoteWire.AnalyticsConsentEvent
    ) -> ConsentManager.AnalyticsConsentEvent? {
        guard let eventKind = ConsentManager.AnalyticsConsentEventKind(
            rawValue: row.event_kind
        ), let occurredAt = date(row.occurred_at),
           let recordedAt = date(row.recorded_at) else {
            return nil
        }
        return ConsentManager.AnalyticsConsentEvent(
            id: row.id,
            ownerUserId: row.user_id,
            syncedUserId: row.user_id,
            provider: row.provider,
            disclosureVersion: row.disclosure_version,
            eventKind: eventKind,
            occurredAt: occurredAt,
            disclosureText: row.disclosure_text,
            actionText: row.action_text,
            platform: row.platform,
            appVersion: row.app_version,
            appBuild: row.app_build,
            recordedAt: recordedAt,
            causalParentId: row.causal_parent_id,
            consentRevision: row.consent_revision
        )
    }

    // Compare decoded wire instants; reformatting can truncate another millisecond.
    static func matchesAdultEligibilityReceipt(
        _ existing: ConsentManager.AdultEligibilityReceipt,
        requested: ConsentManager.AdultEligibilityReceipt,
        userId: UUID
    ) -> Bool {
        existing.id == requested.id
            && existing.ownerUserId == userId
            && existing.syncedUserId == userId
            && existing.policyVersion == requested.policyVersion
            && existing.confirmedAt == date(timestamp(requested.confirmedAt))
            && existing.confirmationMethod == requested.confirmationMethod
            && existing.confirmationText == requested.confirmationText
            && existing.platform == requested.platform
            && existing.appVersion == requested.appVersion
            && existing.appBuild == requested.appBuild
            && existing.recordedAt != nil
    }

    static func matchesTermsReceipt(
        _ existing: ConsentManager.TermsAcceptanceReceipt,
        requested: ConsentManager.TermsAcceptanceReceipt,
        userId: UUID
    ) -> Bool {
        existing.id == requested.id
            && existing.ownerUserId == userId
            && existing.syncedUserId == userId
            && existing.termsVersion == requested.termsVersion
            && existing.acceptedAt == date(timestamp(requested.acceptedAt))
            && existing.acceptanceText == requested.acceptanceText
            && existing.platform == requested.platform
            && existing.appVersion == requested.appVersion
            && existing.appBuild == requested.appBuild
            && existing.recordedAt != nil
    }

    /// A fetch-after-error is only a retry recovery path when the server row
    /// matches the immutable action that was sent. Revocations intentionally
    /// ignore the requested parent because the RPC may have rebased it.
    static func matchesAIConsentAppendRetry(
        _ existing: ConsentManager.AIConsentEvent,
        requested: ConsentManager.AIConsentEvent,
        userId: UUID
    ) -> Bool {
        existing.id == requested.id
            && existing.ownerUserId == userId
            && existing.syncedUserId == userId
            && existing.provider == requested.provider
            && existing.disclosureVersion == requested.disclosureVersion
            && existing.eventKind == requested.eventKind
            && existing.occurredAt == date(timestamp(requested.occurredAt))
            && existing.disclosureText == requested.disclosureText
            && existing.actionText == requested.actionText
            && existing.platform == requested.platform
            && existing.appVersion == requested.appVersion
            && existing.appBuild == requested.appBuild
            && existing.recordedAt != nil
            && existing.consentRevision != nil
            && (
                requested.eventKind == .revoked
                    || existing.causalParentId == requested.causalParentId
            )
    }

    static func matchesAnalyticsConsentAppendRetry(
        _ existing: ConsentManager.AnalyticsConsentEvent,
        requested: ConsentManager.AnalyticsConsentEvent,
        userId: UUID
    ) -> Bool {
        existing.id == requested.id
            && existing.ownerUserId == userId
            && existing.syncedUserId == userId
            && existing.provider == requested.provider
            && existing.disclosureVersion == requested.disclosureVersion
            && existing.eventKind == requested.eventKind
            && existing.occurredAt == date(timestamp(requested.occurredAt))
            && existing.disclosureText == requested.disclosureText
            && existing.actionText == requested.actionText
            && existing.platform == requested.platform
            && existing.appVersion == requested.appVersion
            && existing.appBuild == requested.appBuild
            && existing.recordedAt != nil
            && existing.consentRevision != nil
            && (
                requested.eventKind == .revoked
                    || existing.causalParentId == requested.causalParentId
            )
    }

    static func timestamp(_ date: Date) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        )
    }

    static func date(_ timestamp: String) -> Date? {
        if let date = try? Date(
            timestamp,
            strategy: Date.ISO8601FormatStyle(
                includingFractionalSeconds: true
            )
        ) {
            return date
        }
        return try? Date(
            timestamp,
            strategy: Date.ISO8601FormatStyle(
                includingFractionalSeconds: false
            )
        )
    }
}
