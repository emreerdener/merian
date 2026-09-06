import Foundation
@testable import Merian

@MainActor
extension ConsentRemoteServiceTests {
    func makeService(
        insertAdult: @escaping @MainActor (
            ConsentRemoteWire.AdultEligibilityReceiptInsert
        ) async throws -> Void = { _ in throw StubError.unexpected },
        insertTerms: @escaping @MainActor (
            ConsentRemoteWire.TermsReceiptInsert
        ) async throws -> Void = { _ in throw StubError.unexpected },
        appendAI: @escaping @MainActor (
            ConsentRemoteWire.AIConsentEventAppend
        ) async throws -> [ConsentRemoteWire.ConsentAppendResult] = { _ in
            throw StubError.unexpected
        },
        appendAnalytics: @escaping @MainActor (
            ConsentRemoteWire.AnalyticsConsentEventAppend
        ) async throws -> [ConsentRemoteWire.ConsentAppendResult] = { _ in
            throw StubError.unexpected
        },
        fetchAdult: @escaping @MainActor (
            UUID,
            UUID
        ) async throws -> [ConsentRemoteWire.AdultEligibilityReceipt] = { _, _ in
            throw StubError.unexpected
        },
        fetchTerms: @escaping @MainActor (
            UUID,
            UUID
        ) async throws -> [ConsentRemoteWire.TermsReceipt] = { _, _ in
            throw StubError.unexpected
        },
        fetchAI: @escaping @MainActor (
            UUID,
            UUID
        ) async throws -> [ConsentRemoteWire.AIConsentEvent] = { _, _ in
            throw StubError.unexpected
        },
        fetchAnalytics: @escaping @MainActor (
            UUID,
            UUID
        ) async throws -> [ConsentRemoteWire.AnalyticsConsentEvent] = { _, _ in
            throw StubError.unexpected
        },
        fetchRemoteRows: @escaping @MainActor (
            UUID
        ) async throws -> ConsentRemoteWire.RemoteRows = { _ in
            throw StubError.unexpected
        }
    ) -> ConsentRemoteService {
        ConsentRemoteService(
            dependencies: .init(
                insertAdultEligibilityReceipt: insertAdult,
                insertTermsReceipt: insertTerms,
                appendAIConsentEvent: appendAI,
                appendAnalyticsConsentEvent: appendAnalytics,
                fetchAdultEligibilityReceipt: fetchAdult,
                fetchTermsReceipt: fetchTerms,
                fetchAIConsentEvent: fetchAI,
                fetchAnalyticsConsentEvent: fetchAnalytics,
                fetchRemoteRows: fetchRemoteRows
            )
        )
    }

    func adultReceipt(
        userId: UUID
    ) -> ConsentManager.AdultEligibilityReceipt {
        .init(
            id: UUID(),
            ownerUserId: userId,
            syncedUserId: nil,
            policyVersion: ConsentPolicy.adultEligibilityVersion,
            confirmedAt: Date(timeIntervalSince1970: 1_786_000_000.125),
            confirmationMethod: .selfAttestation,
            confirmationText: ConsentPolicy.adultConfirmationText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: nil
        )
    }

    func termsReceipt(
        userId: UUID
    ) -> ConsentManager.TermsAcceptanceReceipt {
        .init(
            id: UUID(),
            ownerUserId: userId,
            syncedUserId: nil,
            termsVersion: ConsentPolicy.termsVersion,
            acceptedAt: Date(timeIntervalSince1970: 1_786_000_001.25),
            acceptanceText: ConsentPolicy.combinedAcceptanceText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: nil
        )
    }

    func aiEvent(
        userId: UUID,
        eventKind: ConsentManager.AIConsentEventKind,
        causalParentId: UUID?,
        disclosureVersion: String = ConsentPolicy.geminiDisclosureVersion
    ) -> ConsentManager.AIConsentEvent {
        .init(
            id: UUID(),
            ownerUserId: userId,
            syncedUserId: nil,
            provider: ConsentPolicy.geminiProvider,
            disclosureVersion: disclosureVersion,
            eventKind: eventKind,
            occurredAt: Date(timeIntervalSince1970: 1_786_000_002.375),
            disclosureText: ConsentPolicy.geminiDisclosureText,
            actionText: eventKind == .granted
                ? ConsentPolicy.combinedAcceptanceText
                : ConsentPolicy.geminiWithdrawalText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: nil,
            causalParentId: causalParentId,
            consentRevision: nil,
            supersededByEventId: nil,
            supersededByRevision: nil
        )
    }

    func analyticsEvent(
        userId: UUID,
        eventKind: ConsentManager.AnalyticsConsentEventKind,
        causalParentId: UUID?,
        disclosureVersion: String = ConsentPolicy.analyticsDisclosureVersion
    ) -> ConsentManager.AnalyticsConsentEvent {
        .init(
            id: UUID(),
            ownerUserId: userId,
            syncedUserId: nil,
            provider: ConsentPolicy.analyticsProvider,
            disclosureVersion: disclosureVersion,
            eventKind: eventKind,
            occurredAt: Date(timeIntervalSince1970: 1_786_000_003.5),
            disclosureText: ConsentPolicy.analyticsDisclosureText,
            actionText: eventKind == .granted
                ? ConsentPolicy.analyticsDisclosureText
                : ConsentPolicy.analyticsWithdrawalText,
            platform: "ios",
            appVersion: "1.0.3",
            appBuild: "275",
            recordedAt: nil,
            causalParentId: causalParentId,
            consentRevision: nil,
            supersededByEventId: nil,
            supersededByRevision: nil
        )
    }

    func remoteAdultRow(
        from receipt: ConsentManager.AdultEligibilityReceipt,
        userId: UUID,
        confirmationMethod: String? = nil,
        confirmationText: String? = nil
    ) -> ConsentRemoteWire.AdultEligibilityReceipt {
        .init(
            id: receipt.id,
            user_id: userId,
            policy_version: receipt.policyVersion,
            confirmed_at: timestamp(receipt.confirmedAt),
            confirmation_method: confirmationMethod
                ?? receipt.confirmationMethod.rawValue,
            confirmation_text: confirmationText ?? receipt.confirmationText,
            platform: receipt.platform,
            app_version: receipt.appVersion,
            app_build: receipt.appBuild,
            recorded_at: "2026-08-04T12:34:56.789Z"
        )
    }

    func remoteTermsRow(
        from receipt: ConsentManager.TermsAcceptanceReceipt,
        userId: UUID,
        acceptanceText: String? = nil
    ) -> ConsentRemoteWire.TermsReceipt {
        .init(
            id: receipt.id,
            user_id: userId,
            terms_version: receipt.termsVersion,
            accepted_at: timestamp(receipt.acceptedAt),
            acceptance_text: acceptanceText ?? receipt.acceptanceText,
            platform: receipt.platform,
            app_version: receipt.appVersion,
            app_build: receipt.appBuild,
            recorded_at: "2026-08-04T12:35:56Z"
        )
    }

    func remoteAIEventRow(
        from event: ConsentManager.AIConsentEvent,
        userId: UUID,
        causalParentId: UUID? = nil,
        consentRevision: Int64 = 1
    ) -> ConsentRemoteWire.AIConsentEvent {
        .init(
            id: event.id,
            user_id: userId,
            provider: event.provider,
            disclosure_version: event.disclosureVersion,
            event_kind: event.eventKind.rawValue,
            occurred_at: timestamp(event.occurredAt),
            disclosure_text: event.disclosureText,
            action_text: event.actionText,
            platform: event.platform,
            app_version: event.appVersion,
            app_build: event.appBuild,
            recorded_at: "2026-08-04T12:36:56.789Z",
            causal_parent_id: causalParentId ?? event.causalParentId,
            consent_revision: consentRevision
        )
    }

    func remoteAnalyticsEventRow(
        from event: ConsentManager.AnalyticsConsentEvent,
        userId: UUID,
        eventKind: String? = nil,
        actionText: String? = nil,
        causalParentId: UUID? = nil,
        consentRevision: Int64 = 1
    ) -> ConsentRemoteWire.AnalyticsConsentEvent {
        .init(
            id: event.id,
            user_id: userId,
            provider: event.provider,
            disclosure_version: event.disclosureVersion,
            event_kind: eventKind ?? event.eventKind.rawValue,
            occurred_at: timestamp(event.occurredAt),
            disclosure_text: event.disclosureText,
            action_text: actionText ?? event.actionText,
            platform: event.platform,
            app_version: event.appVersion,
            app_build: event.appBuild,
            recorded_at: "2026-08-04T12:37:56.789Z",
            causal_parent_id: causalParentId ?? event.causalParentId,
            consent_revision: consentRevision
        )
    }

    func timestamp(_ date: Date) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        )
    }

    func parsedDate(_ timestamp: String) -> Date? {
        try? Date(
            timestamp,
            strategy: Date.ISO8601FormatStyle(
                includingFractionalSeconds: timestamp.contains(".")
            )
        )
    }
}
