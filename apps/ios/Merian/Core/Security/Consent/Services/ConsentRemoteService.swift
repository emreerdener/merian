import Foundation

@MainActor
struct ConsentRemoteService {
    typealias SynchronizationValidator = @MainActor () throws -> Void

    struct Dependencies {
        let insertAdultEligibilityReceipt: @MainActor (
            ConsentRemoteWire.AdultEligibilityReceiptInsert
        ) async throws -> Void
        let insertTermsReceipt: @MainActor (
            ConsentRemoteWire.TermsReceiptInsert
        ) async throws -> Void
        let appendAIConsentEvent: @MainActor (
            ConsentRemoteWire.AIConsentEventAppend
        ) async throws -> [ConsentRemoteWire.ConsentAppendResult]
        let appendAnalyticsConsentEvent: @MainActor (
            ConsentRemoteWire.AnalyticsConsentEventAppend
        ) async throws -> [ConsentRemoteWire.ConsentAppendResult]
        let fetchAdultEligibilityReceipt: @MainActor (
            UUID,
            UUID
        ) async throws -> [ConsentRemoteWire.AdultEligibilityReceipt]
        let fetchTermsReceipt: @MainActor (
            UUID,
            UUID
        ) async throws -> [ConsentRemoteWire.TermsReceipt]
        let fetchAIConsentEvent: @MainActor (
            UUID,
            UUID
        ) async throws -> [ConsentRemoteWire.AIConsentEvent]
        let fetchAnalyticsConsentEvent: @MainActor (
            UUID,
            UUID
        ) async throws -> [ConsentRemoteWire.AnalyticsConsentEvent]
        let fetchRemoteRows: @MainActor (
            UUID
        ) async throws -> ConsentRemoteWire.RemoteRows
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func insertAdultEligibilityReceipt(
        _ receipt: ConsentManager.AdultEligibilityReceipt,
        for userId: UUID,
        validateSynchronization: SynchronizationValidator
    ) async throws -> ConsentManager.AdultEligibilityReceipt {
        let row = ConsentRemoteWire.AdultEligibilityReceiptInsert(
            id: receipt.id,
            user_id: userId,
            policy_version: receipt.policyVersion,
            confirmed_at: Self.timestamp(receipt.confirmedAt),
            confirmation_method: receipt.confirmationMethod.rawValue,
            confirmation_text: receipt.confirmationText,
            platform: receipt.platform,
            app_version: receipt.appVersion,
            app_build: receipt.appBuild
        )

        do {
            try await dependencies.insertAdultEligibilityReceipt(row)
            try validateSynchronization()
        } catch {
            try validateSynchronization()
            let existingReceipt = try await fetchAdultEligibilityReceipt(
                id: receipt.id,
                userId: userId
            )
            try validateSynchronization()
            guard let existingReceipt,
                  Self.matchesAdultEligibilityReceipt(
                      existingReceipt,
                      requested: receipt,
                      userId: userId
                  ) else {
                throw error
            }
            return existingReceipt
        }

        let insertedReceipt = try await fetchAdultEligibilityReceipt(
            id: receipt.id,
            userId: userId
        )
        try validateSynchronization()
        guard let insertedReceipt else {
            throw MerianError.aiConsentRequired
        }
        guard Self.matchesAdultEligibilityReceipt(
            insertedReceipt,
            requested: receipt,
            userId: userId
        ) else {
            throw MerianError.invalidResponse
        }
        return insertedReceipt
    }

    func insertTermsReceipt(
        _ receipt: ConsentManager.TermsAcceptanceReceipt,
        for userId: UUID,
        validateSynchronization: SynchronizationValidator
    ) async throws -> ConsentManager.TermsAcceptanceReceipt {
        let row = ConsentRemoteWire.TermsReceiptInsert(
            id: receipt.id,
            user_id: userId,
            terms_version: receipt.termsVersion,
            accepted_at: Self.timestamp(receipt.acceptedAt),
            acceptance_text: receipt.acceptanceText,
            platform: receipt.platform,
            app_version: receipt.appVersion,
            app_build: receipt.appBuild
        )

        do {
            try await dependencies.insertTermsReceipt(row)
            try validateSynchronization()
        } catch {
            try validateSynchronization()
            let existingReceipt = try await fetchTermsReceipt(
                id: receipt.id,
                userId: userId
            )
            try validateSynchronization()
            guard let existingReceipt,
                  Self.matchesTermsReceipt(
                      existingReceipt,
                      requested: receipt,
                      userId: userId
                  ) else {
                throw error
            }
            return existingReceipt
        }

        let insertedReceipt = try await fetchTermsReceipt(
            id: receipt.id,
            userId: userId
        )
        try validateSynchronization()
        guard let insertedReceipt else {
            throw MerianError.aiConsentRequired
        }
        guard Self.matchesTermsReceipt(
            insertedReceipt,
            requested: receipt,
            userId: userId
        ) else {
            throw MerianError.invalidResponse
        }
        return insertedReceipt
    }

    func insertAIConsentEvent(
        _ event: ConsentManager.AIConsentEvent,
        for userId: UUID,
        validateSynchronization: SynchronizationValidator
    ) async throws -> ConsentManager.AIConsentEvent {
        let parameters = ConsentRemoteWire.AIConsentEventAppend(
            p_id: event.id,
            p_disclosure_version: event.disclosureVersion,
            p_event_kind: event.eventKind.rawValue,
            p_occurred_at: Self.timestamp(event.occurredAt),
            p_disclosure_text: event.disclosureText,
            p_action_text: event.actionText,
            p_platform: event.platform,
            p_app_version: event.appVersion,
            p_app_build: event.appBuild,
            p_causal_parent_id: event.causalParentId
        )

        do {
            let results = try await dependencies.appendAIConsentEvent(parameters)
            try validateSynchronization()

            guard results.count == 1 else {
                throw MerianError.invalidResponse
            }
            let result = results[0]
            guard result.accepted else {
                var supersededEvent = event
                supersededEvent.supersededByEventId =
                    result.authoritative_event_id
                supersededEvent.supersededByRevision =
                    result.authoritative_revision
                return supersededEvent
            }

            guard let eventRevision = result.event_revision,
                  let recordedAtString = result.recorded_at,
                  let recordedAt = Self.date(recordedAtString) else {
                throw MerianError.invalidResponse
            }
            var synchronizedEvent = event
            synchronizedEvent.syncedUserId = userId
            synchronizedEvent.causalParentId = result.accepted_parent_id
            synchronizedEvent.consentRevision = eventRevision
            synchronizedEvent.recordedAt = recordedAt
            synchronizedEvent.supersededByEventId = nil
            synchronizedEvent.supersededByRevision = nil
            return synchronizedEvent
        } catch {
            try validateSynchronization()
            let existingEvent = try await fetchAIConsentEvent(
                id: event.id,
                userId: userId
            )
            try validateSynchronization()
            guard let existingEvent,
                  Self.matchesAIConsentAppendRetry(
                      existingEvent,
                      requested: event,
                      userId: userId
                  ) else {
                throw error
            }
            return existingEvent
        }
    }

    func insertAnalyticsConsentEvent(
        _ event: ConsentManager.AnalyticsConsentEvent,
        for userId: UUID,
        validateSynchronization: SynchronizationValidator
    ) async throws -> ConsentManager.AnalyticsConsentEvent {
        let parameters = ConsentRemoteWire.AnalyticsConsentEventAppend(
            p_id: event.id,
            p_disclosure_version: event.disclosureVersion,
            p_event_kind: event.eventKind.rawValue,
            p_occurred_at: Self.timestamp(event.occurredAt),
            p_disclosure_text: event.disclosureText,
            p_action_text: event.actionText,
            p_platform: event.platform,
            p_app_version: event.appVersion,
            p_app_build: event.appBuild,
            p_causal_parent_id: event.causalParentId
        )

        do {
            let results = try await dependencies.appendAnalyticsConsentEvent(
                parameters
            )
            try validateSynchronization()

            guard results.count == 1 else {
                throw MerianError.invalidResponse
            }
            let result = results[0]
            guard result.accepted else {
                var supersededEvent = event
                supersededEvent.supersededByEventId =
                    result.authoritative_event_id
                supersededEvent.supersededByRevision =
                    result.authoritative_revision
                return supersededEvent
            }

            guard let eventRevision = result.event_revision,
                  let recordedAtString = result.recorded_at,
                  let recordedAt = Self.date(recordedAtString) else {
                throw MerianError.invalidResponse
            }
            var synchronizedEvent = event
            synchronizedEvent.syncedUserId = userId
            synchronizedEvent.causalParentId = result.accepted_parent_id
            synchronizedEvent.consentRevision = eventRevision
            synchronizedEvent.recordedAt = recordedAt
            synchronizedEvent.supersededByEventId = nil
            synchronizedEvent.supersededByRevision = nil
            return synchronizedEvent
        } catch {
            try validateSynchronization()
            let existingEvent = try await fetchAnalyticsConsentEvent(
                id: event.id,
                userId: userId
            )
            try validateSynchronization()
            guard let existingEvent,
                  Self.matchesAnalyticsConsentAppendRetry(
                      existingEvent,
                      requested: event,
                      userId: userId
                  ) else {
                throw error
            }
            return existingEvent
        }
    }

    func fetchRemoteState(
        for userId: UUID,
        validateSynchronization: SynchronizationValidator
    ) async throws -> ConsentManager.RemoteState {
        let rows = try await dependencies.fetchRemoteRows(userId)
        try validateSynchronization()
        return ConsentManager.RemoteState(
            adultEligibilityReceipt: try Self.firstMappedRemoteRow(
                rows.adultEligibilityReceipts,
                using: Self.localAdultEligibilityReceipt
            ),
            termsReceipt: try Self.firstMappedRemoteRow(
                rows.termsReceipts,
                using: Self.localTermsReceipt
            ),
            aiConsentEvent: try Self.firstMappedRemoteRow(
                rows.aiConsentEvents,
                using: Self.localAIConsentEvent
            ),
            analyticsConsentEvent: try Self.firstMappedRemoteRow(
                rows.analyticsConsentEvents,
                using: Self.localAnalyticsConsentEvent
            ),
            aiConsentStreamHead: try Self.firstMappedRemoteRow(
                rows.aiConsentStreamHeads,
                using: Self.localAIConsentEvent
            ),
            analyticsConsentStreamHead: try Self.firstMappedRemoteRow(
                rows.analyticsConsentStreamHeads,
                using: Self.localAnalyticsConsentEvent
            ),
        )
    }

    private func fetchAdultEligibilityReceipt(
        id: UUID,
        userId: UUID
    ) async throws -> ConsentManager.AdultEligibilityReceipt? {
        let rows = try await dependencies.fetchAdultEligibilityReceipt(id, userId)
        return try Self.firstMappedRemoteRow(
            rows,
            using: Self.localAdultEligibilityReceipt
        )
    }

    private func fetchTermsReceipt(
        id: UUID,
        userId: UUID
    ) async throws -> ConsentManager.TermsAcceptanceReceipt? {
        let rows = try await dependencies.fetchTermsReceipt(id, userId)
        return try Self.firstMappedRemoteRow(
            rows,
            using: Self.localTermsReceipt
        )
    }

    private func fetchAIConsentEvent(
        id: UUID,
        userId: UUID
    ) async throws -> ConsentManager.AIConsentEvent? {
        let rows = try await dependencies.fetchAIConsentEvent(id, userId)
        return try Self.firstMappedRemoteRow(
            rows,
            using: Self.localAIConsentEvent
        )
    }

    private func fetchAnalyticsConsentEvent(
        id: UUID,
        userId: UUID
    ) async throws -> ConsentManager.AnalyticsConsentEvent? {
        let rows = try await dependencies.fetchAnalyticsConsentEvent(id, userId)
        return try Self.firstMappedRemoteRow(
            rows,
            using: Self.localAnalyticsConsentEvent
        )
    }

    /// An empty successful query is authoritative absence. A present row that
    /// cannot map is malformed evidence and must not be collapsed into absence.
    private static func firstMappedRemoteRow<RemoteRow, LocalValue>(
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

    private static func localAdultEligibilityReceipt(
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

    private static func localTermsReceipt(
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

    private static func localAIConsentEvent(
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

    private static func localAnalyticsConsentEvent(
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

    private static func matchesAdultEligibilityReceipt(
        _ existing: ConsentManager.AdultEligibilityReceipt,
        requested: ConsentManager.AdultEligibilityReceipt,
        userId: UUID
    ) -> Bool {
        existing.id == requested.id
            && existing.ownerUserId == userId
            && existing.syncedUserId == userId
            && existing.policyVersion == requested.policyVersion
            && timestamp(existing.confirmedAt) == timestamp(requested.confirmedAt)
            && existing.confirmationMethod == requested.confirmationMethod
            && existing.confirmationText == requested.confirmationText
            && existing.platform == requested.platform
            && existing.appVersion == requested.appVersion
            && existing.appBuild == requested.appBuild
            && existing.recordedAt != nil
    }

    private static func matchesTermsReceipt(
        _ existing: ConsentManager.TermsAcceptanceReceipt,
        requested: ConsentManager.TermsAcceptanceReceipt,
        userId: UUID
    ) -> Bool {
        existing.id == requested.id
            && existing.ownerUserId == userId
            && existing.syncedUserId == userId
            && existing.termsVersion == requested.termsVersion
            && timestamp(existing.acceptedAt) == timestamp(requested.acceptedAt)
            && existing.acceptanceText == requested.acceptanceText
            && existing.platform == requested.platform
            && existing.appVersion == requested.appVersion
            && existing.appBuild == requested.appBuild
            && existing.recordedAt != nil
    }

    /// A fetch-after-error is only a retry recovery path when the server row
    /// matches the immutable action that was sent. Revocations intentionally
    /// ignore the requested parent because the RPC may have rebased it.
    private static func matchesAIConsentAppendRetry(
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
            && timestamp(existing.occurredAt) == timestamp(requested.occurredAt)
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

    private static func matchesAnalyticsConsentAppendRetry(
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
            && timestamp(existing.occurredAt) == timestamp(requested.occurredAt)
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

    private static func timestamp(_ date: Date) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        )
    }

    private static func date(_ timestamp: String) -> Date? {
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
