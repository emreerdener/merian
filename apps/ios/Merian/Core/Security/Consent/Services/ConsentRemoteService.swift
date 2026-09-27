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
        var appendOpenAIConsentEvent: @MainActor (
            ConsentRemoteWire.AIConsentEventAppend
        ) async throws -> [ConsentRemoteWire.ConsentAppendResult] = { _ in
            throw MerianError.aiConsentRequired
        }
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
            confirmed_at: ConsentRemoteMapping.timestamp(receipt.confirmedAt),
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
                  ConsentRemoteMapping.matchesAdultEligibilityReceipt(
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
        guard ConsentRemoteMapping.matchesAdultEligibilityReceipt(
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
            accepted_at: ConsentRemoteMapping.timestamp(receipt.acceptedAt),
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
                  ConsentRemoteMapping.matchesTermsReceipt(
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
        guard ConsentRemoteMapping.matchesTermsReceipt(
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
        guard let processor = AIConsentProcessor(rawValue: event.provider),
              event.ownerUserId == userId else {
            throw MerianError.invalidResponse
        }
        let parameters = ConsentRemoteWire.AIConsentEventAppend(
            p_id: event.id,
            p_disclosure_version: event.disclosureVersion,
            p_event_kind: event.eventKind.rawValue,
            p_occurred_at: ConsentRemoteMapping.timestamp(event.occurredAt),
            p_disclosure_text: event.disclosureText,
            p_action_text: event.actionText,
            p_platform: event.platform,
            p_app_version: event.appVersion,
            p_app_build: event.appBuild,
            p_causal_parent_id: event.causalParentId
        )

        do {
            let results: [ConsentRemoteWire.ConsentAppendResult]
            switch processor {
            case .gemini:
                results = try await dependencies.appendAIConsentEvent(parameters)
            case .openAI:
                results = try await dependencies.appendOpenAIConsentEvent(parameters)
            }
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
                  let recordedAt = ConsentRemoteMapping.date(recordedAtString) else {
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
                  ConsentRemoteMapping.matchesAIConsentAppendRetry(
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
            p_occurred_at: ConsentRemoteMapping.timestamp(event.occurredAt),
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
                  let recordedAt = ConsentRemoteMapping.date(recordedAtString) else {
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
                  ConsentRemoteMapping.matchesAnalyticsConsentAppendRetry(
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
            adultEligibilityReceipt: try ConsentRemoteMapping.firstMappedRemoteRow(
                rows.adultEligibilityReceipts,
                using: ConsentRemoteMapping.localAdultEligibilityReceipt
            ),
            termsReceipt: try ConsentRemoteMapping.firstMappedRemoteRow(
                rows.termsReceipts,
                using: ConsentRemoteMapping.localTermsReceipt
            ),
            aiConsentEvent: try ConsentRemoteMapping.firstMappedRemoteRow(
                rows.aiConsentEvents,
                using: ConsentRemoteMapping.localAIConsentEvent
            ),
            analyticsConsentEvent: try ConsentRemoteMapping.firstMappedRemoteRow(
                rows.analyticsConsentEvents,
                using: ConsentRemoteMapping.localAnalyticsConsentEvent
            ),
            aiConsentStreamHead: try ConsentRemoteMapping.firstMappedRemoteRow(
                rows.aiConsentStreamHeads,
                using: ConsentRemoteMapping.localAIConsentEvent
            ),
            analyticsConsentStreamHead: try ConsentRemoteMapping.firstMappedRemoteRow(
                rows.analyticsConsentStreamHeads,
                using: ConsentRemoteMapping.localAnalyticsConsentEvent
            ),
            openAIConsentStreamHead: try ConsentRemoteMapping.firstMappedRemoteRow(
                rows.openAIConsentStreamHeads,
                using: { row in
                    guard row.user_id == userId,
                          row.provider == ConsentPolicy.openAIProvider else { return nil }
                    return ConsentRemoteMapping.localAIConsentEvent(row)
                }
            )
        )
    }

    private func fetchAdultEligibilityReceipt(
        id: UUID,
        userId: UUID
    ) async throws -> ConsentManager.AdultEligibilityReceipt? {
        let rows = try await dependencies.fetchAdultEligibilityReceipt(id, userId)
        return try ConsentRemoteMapping.firstMappedRemoteRow(
            rows,
            using: ConsentRemoteMapping.localAdultEligibilityReceipt
        )
    }

    private func fetchTermsReceipt(
        id: UUID,
        userId: UUID
    ) async throws -> ConsentManager.TermsAcceptanceReceipt? {
        let rows = try await dependencies.fetchTermsReceipt(id, userId)
        return try ConsentRemoteMapping.firstMappedRemoteRow(
            rows,
            using: ConsentRemoteMapping.localTermsReceipt
        )
    }

    private func fetchAIConsentEvent(
        id: UUID,
        userId: UUID
    ) async throws -> ConsentManager.AIConsentEvent? {
        let rows = try await dependencies.fetchAIConsentEvent(id, userId)
        return try ConsentRemoteMapping.firstMappedRemoteRow(
            rows,
            using: ConsentRemoteMapping.localAIConsentEvent
        )
    }

    private func fetchAnalyticsConsentEvent(
        id: UUID,
        userId: UUID
    ) async throws -> ConsentManager.AnalyticsConsentEvent? {
        let rows = try await dependencies.fetchAnalyticsConsentEvent(id, userId)
        return try ConsentRemoteMapping.firstMappedRemoteRow(
            rows,
            using: ConsentRemoteMapping.localAnalyticsConsentEvent
        )
    }

}
