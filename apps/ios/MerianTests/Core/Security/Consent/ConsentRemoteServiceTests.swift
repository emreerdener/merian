import Foundation
@testable import Merian
import Testing

@MainActor
@Suite("Consent Remote Service")
struct ConsentRemoteServiceTests {
    enum StubError: Error, Equatable {
        case transport
        case unexpected
    }

    @Test func receiptAdaptersPreservePayloadsAndMapReadBack() async throws {
        let userId = UUID()
        let adult = adultReceipt(userId: userId)
        let terms = termsReceipt(userId: userId)
        let adultRow = remoteAdultRow(from: adult, userId: userId)
        let termsRow = remoteTermsRow(from: terms, userId: userId)
        var capturedAdult: ConsentRemoteWire.AdultEligibilityReceiptInsert?
        var capturedTerms: ConsentRemoteWire.TermsReceiptInsert?
        var validationCount = 0
        let service = makeService(
            insertAdult: { capturedAdult = $0 },
            insertTerms: { capturedTerms = $0 },
            fetchAdult: { id, fetchedUserId in
                #expect(id == adult.id)
                #expect(fetchedUserId == userId)
                return [adultRow]
            },
            fetchTerms: { id, fetchedUserId in
                #expect(id == terms.id)
                #expect(fetchedUserId == userId)
                return [termsRow]
            }
        )

        let synchronizedAdult = try await service.insertAdultEligibilityReceipt(
            adult,
            for: userId,
            validateSynchronization: { validationCount += 1 }
        )
        let synchronizedTerms = try await service.insertTermsReceipt(
            terms,
            for: userId,
            validateSynchronization: { validationCount += 1 }
        )

        #expect(
            capturedAdult == .init(
                id: adult.id,
                user_id: userId,
                policy_version: adult.policyVersion,
                confirmed_at: timestamp(adult.confirmedAt),
                confirmation_method: adult.confirmationMethod.rawValue,
                confirmation_text: adult.confirmationText,
                platform: adult.platform,
                app_version: adult.appVersion,
                app_build: adult.appBuild
            )
        )
        #expect(
            capturedTerms == .init(
                id: terms.id,
                user_id: userId,
                terms_version: terms.termsVersion,
                accepted_at: timestamp(terms.acceptedAt),
                acceptance_text: terms.acceptanceText,
                platform: terms.platform,
                app_version: terms.appVersion,
                app_build: terms.appBuild
            )
        )
        #expect(synchronizedAdult.ownerUserId == userId)
        #expect(synchronizedAdult.syncedUserId == userId)
        #expect(synchronizedAdult.recordedAt == parsedDate(adultRow.recorded_at))
        #expect(synchronizedTerms.ownerUserId == userId)
        #expect(synchronizedTerms.syncedUserId == userId)
        #expect(synchronizedTerms.recordedAt == parsedDate(termsRow.recorded_at))
        #expect(validationCount == 4)
    }

    @Test func receiptInsertFailureRecoversOnlyFromExistingRow() async throws {
        let userId = UUID()
        let adult = adultReceipt(userId: userId)
        let adultRow = remoteAdultRow(from: adult, userId: userId)
        var validationCount = 0
        let recoveredService = makeService(
            insertAdult: { _ in throw StubError.transport },
            fetchAdult: { _, _ in [adultRow] }
        )

        let recovered = try await recoveredService.insertAdultEligibilityReceipt(
            adult,
            for: userId,
            validateSynchronization: { validationCount += 1 }
        )

        #expect(recovered.id == adult.id)
        #expect(recovered.syncedUserId == userId)
        #expect(validationCount == 2)

        let missingService = makeService(
            insertAdult: { _ in throw StubError.transport },
            fetchAdult: { _, _ in [] }
        )
        await #expect(throws: StubError.transport) {
            try await missingService.insertAdultEligibilityReceipt(
                adult,
                for: userId,
                validateSynchronization: {}
            )
        }
    }

    @Test func ambiguousReceiptInsertRejectsMismatchedImmutablePayload() async {
        let userId = UUID()
        let adult = adultReceipt(userId: userId)
        let terms = termsReceipt(userId: userId)
        let adultService = makeService(
            insertAdult: { _ in throw StubError.transport },
            fetchAdult: { _, _ in
                [
                    remoteAdultRow(
                        from: adult,
                        userId: userId,
                        confirmationText: "Different immutable copy"
                    )
                ]
            }
        )
        let termsService = makeService(
            insertTerms: { _ in throw StubError.transport },
            fetchTerms: { _, _ in
                [
                    remoteTermsRow(
                        from: terms,
                        userId: userId,
                        acceptanceText: "Different immutable copy"
                    )
                ]
            }
        )

        await #expect(throws: StubError.transport) {
            try await adultService.insertAdultEligibilityReceipt(
                adult,
                for: userId,
                validateSynchronization: {}
            )
        }
        await #expect(throws: StubError.transport) {
            try await termsService.insertTermsReceipt(
                terms,
                for: userId,
                validateSynchronization: {}
            )
        }
    }

    @Test func successfulReceiptInsertRejectsMismatchedReadBack() async {
        let userId = UUID()
        let adult = adultReceipt(userId: userId)
        let terms = termsReceipt(userId: userId)
        let adultService = makeService(
            insertAdult: { _ in },
            fetchAdult: { _, _ in
                [
                    remoteAdultRow(
                        from: adult,
                        userId: userId,
                        confirmationText: "Different immutable copy"
                    )
                ]
            }
        )
        let termsService = makeService(
            insertTerms: { _ in },
            fetchTerms: { _, _ in
                [
                    remoteTermsRow(
                        from: terms,
                        userId: userId,
                        acceptanceText: "Different immutable copy"
                    )
                ]
            }
        )

        await #expect(throws: MerianError.invalidResponse) {
            try await adultService.insertAdultEligibilityReceipt(
                adult,
                for: userId,
                validateSynchronization: {}
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await termsService.insertTermsReceipt(
                terms,
                for: userId,
                validateSynchronization: {}
            )
        }
    }

    @Test func acceptedAIAppendPersistsServerParentRevisionAndTimestamp() async throws {
        let userId = UUID()
        let observedParent = UUID()
        let acceptedParent = UUID()
        let event = aiEvent(
            userId: userId,
            eventKind: .granted,
            causalParentId: observedParent
        )
        var captured: ConsentRemoteWire.AIConsentEventAppend?
        var validationCount = 0
        let service = makeService(appendAI: { parameters in
            captured = parameters
            return [
                .init(
                    accepted: true,
                    event_revision: 42,
                    accepted_parent_id: acceptedParent,
                    authoritative_revision: 42,
                    authoritative_event_id: event.id,
                    recorded_at: "2026-08-04T12:34:56.789Z"
                )
            ]
        })

        let synchronized = try await service.insertAIConsentEvent(
            event,
            for: userId,
            validateSynchronization: { validationCount += 1 }
        )

        #expect(
            captured == .init(
                p_id: event.id,
                p_disclosure_version: event.disclosureVersion,
                p_event_kind: event.eventKind.rawValue,
                p_occurred_at: timestamp(event.occurredAt),
                p_disclosure_text: event.disclosureText,
                p_action_text: event.actionText,
                p_platform: event.platform,
                p_app_version: event.appVersion,
                p_app_build: event.appBuild,
                p_causal_parent_id: observedParent
            )
        )
        #expect(synchronized.syncedUserId == userId)
        #expect(synchronized.causalParentId == acceptedParent)
        #expect(synchronized.consentRevision == 42)
        #expect(
            synchronized.recordedAt
                == parsedDate("2026-08-04T12:34:56.789Z")
        )
        #expect(synchronized.supersededByEventId == nil)
        #expect(synchronized.supersededByRevision == nil)
        #expect(validationCount == 1)
    }

    @Test func rejectedAnalyticsGrantBecomesSupersededLocalEvidence() async throws {
        let userId = UUID()
        let authoritativeEventId = UUID()
        let event = analyticsEvent(
            userId: userId,
            eventKind: .granted,
            causalParentId: UUID()
        )
        var captured: ConsentRemoteWire.AnalyticsConsentEventAppend?
        let service = makeService(appendAnalytics: { parameters in
            captured = parameters
            return [
                .init(
                    accepted: false,
                    event_revision: nil,
                    accepted_parent_id: nil,
                    authoritative_revision: 51,
                    authoritative_event_id: authoritativeEventId,
                    recorded_at: nil
                )
            ]
        })

        let superseded = try await service.insertAnalyticsConsentEvent(
            event,
            for: userId,
            validateSynchronization: {}
        )

        #expect(
            captured == .init(
                p_id: event.id,
                p_disclosure_version: event.disclosureVersion,
                p_event_kind: event.eventKind.rawValue,
                p_occurred_at: timestamp(event.occurredAt),
                p_disclosure_text: event.disclosureText,
                p_action_text: event.actionText,
                p_platform: event.platform,
                p_app_version: event.appVersion,
                p_app_build: event.appBuild,
                p_causal_parent_id: event.causalParentId
            )
        )
        #expect(superseded.syncedUserId == nil)
        #expect(superseded.supersededByEventId == authoritativeEventId)
        #expect(superseded.supersededByRevision == 51)
    }

    @Test func ambiguousRevocationAppendAcceptsServerRebasedParent() async throws {
        let userId = UUID()
        let event = aiEvent(
            userId: userId,
            eventKind: .revoked,
            causalParentId: UUID()
        )
        let serverParent = UUID()
        let existingRow = remoteAIEventRow(
            from: event,
            userId: userId,
            causalParentId: serverParent,
            consentRevision: 52
        )
        var validationCount = 0
        let service = makeService(
            appendAI: { _ in throw StubError.transport },
            fetchAI: { id, fetchedUserId in
                #expect(id == event.id)
                #expect(fetchedUserId == userId)
                return [existingRow]
            }
        )

        let recovered = try await service.insertAIConsentEvent(
            event,
            for: userId,
            validateSynchronization: { validationCount += 1 }
        )

        #expect(recovered.causalParentId == serverParent)
        #expect(recovered.consentRevision == 52)
        #expect(validationCount == 2)
    }

    @Test func ambiguousGrantAppendRejectsMismatchedImmutablePayload() async {
        let userId = UUID()
        let event = analyticsEvent(
            userId: userId,
            eventKind: .granted,
            causalParentId: UUID()
        )
        let mismatchedRow = remoteAnalyticsEventRow(
            from: event,
            userId: userId,
            actionText: "Different immutable copy"
        )
        let service = makeService(
            appendAnalytics: { _ in throw StubError.transport },
            fetchAnalytics: { _, _ in [mismatchedRow] }
        )

        await #expect(throws: StubError.transport) {
            try await service.insertAnalyticsConsentEvent(
                event,
                for: userId,
                validateSynchronization: {}
            )
        }
    }

    @Test func malformedAcceptedAppendRemainsFailClosed() async {
        let userId = UUID()
        let event = aiEvent(
            userId: userId,
            eventKind: .granted,
            causalParentId: nil
        )
        let service = makeService(
            appendAI: { _ in
                [
                    .init(
                        accepted: true,
                        event_revision: nil,
                        accepted_parent_id: nil,
                        authoritative_revision: 1,
                        authoritative_event_id: event.id,
                        recorded_at: nil
                    )
                ]
            },
            fetchAI: { _, _ in [] }
        )

        await #expect(throws: MerianError.invalidResponse) {
            try await service.insertAIConsentEvent(
                event,
                for: userId,
                validateSynchronization: {}
            )
        }
    }

    @Test func remoteStateMapsCurrentRowsAndProviderHeadsIndependently() async throws {
        let userId = UUID()
        let adult = adultReceipt(userId: userId)
        let terms = termsReceipt(userId: userId)
        let currentAI = aiEvent(
            userId: userId,
            eventKind: .granted,
            causalParentId: nil
        )
        let aiHead = aiEvent(
            userId: userId,
            eventKind: .revoked,
            causalParentId: currentAI.id,
            disclosureVersion: "prior-ai-disclosure"
        )
        let currentAnalytics = analyticsEvent(
            userId: userId,
            eventKind: .granted,
            causalParentId: nil
        )
        let analyticsHead = analyticsEvent(
            userId: userId,
            eventKind: .revoked,
            causalParentId: currentAnalytics.id,
            disclosureVersion: "prior-analytics-disclosure"
        )
        let rows = ConsentRemoteWire.RemoteRows(
            adultEligibilityReceipts: [
                remoteAdultRow(from: adult, userId: userId)
            ],
            termsReceipts: [remoteTermsRow(from: terms, userId: userId)],
            aiConsentEvents: [
                remoteAIEventRow(
                    from: currentAI,
                    userId: userId,
                    consentRevision: 40
                )
            ],
            analyticsConsentEvents: [
                remoteAnalyticsEventRow(
                    from: currentAnalytics,
                    userId: userId,
                    consentRevision: 41
                )
            ],
            aiConsentStreamHeads: [
                remoteAIEventRow(
                    from: aiHead,
                    userId: userId,
                    consentRevision: 42
                )
            ],
            analyticsConsentStreamHeads: [
                remoteAnalyticsEventRow(
                    from: analyticsHead,
                    userId: userId,
                    consentRevision: 43
                )
            ]
        )
        var fetchedUserId: UUID?
        var validationCount = 0
        let service = makeService(fetchRemoteRows: {
            fetchedUserId = $0
            return rows
        })

        let state = try await service.fetchRemoteState(
            for: userId,
            validateSynchronization: { validationCount += 1 }
        )

        #expect(fetchedUserId == userId)
        #expect(state.adultEligibilityReceipt?.id == adult.id)
        #expect(state.termsReceipt?.id == terms.id)
        #expect(state.aiConsentEvent?.id == currentAI.id)
        #expect(state.analyticsConsentEvent?.id == currentAnalytics.id)
        #expect(state.aiConsentStreamHead?.id == aiHead.id)
        #expect(state.analyticsConsentStreamHead?.id == analyticsHead.id)
        #expect(state.aiConsentStreamHead?.disclosureVersion == "prior-ai-disclosure")
        #expect(
            state.analyticsConsentStreamHead?.disclosureVersion
                == "prior-analytics-disclosure"
        )
        #expect(validationCount == 1)
    }

    @Test func malformedPresentRemoteStateEvidenceFailsClosed() async {
        let userId = UUID()
        let adult = adultReceipt(userId: userId)
        let analytics = analyticsEvent(
            userId: userId,
            eventKind: .granted,
            causalParentId: nil
        )
        let malformedAdultRows = ConsentRemoteWire.RemoteRows(
            adultEligibilityReceipts: [
                remoteAdultRow(
                    from: adult,
                    userId: userId,
                    confirmationMethod: "unsupported"
                )
            ],
            termsReceipts: [],
            aiConsentEvents: [],
            analyticsConsentEvents: [],
            aiConsentStreamHeads: [],
            analyticsConsentStreamHeads: []
        )
        let malformedHeadRows = ConsentRemoteWire.RemoteRows(
            adultEligibilityReceipts: [],
            termsReceipts: [],
            aiConsentEvents: [],
            analyticsConsentEvents: [],
            aiConsentStreamHeads: [],
            analyticsConsentStreamHeads: [
                remoteAnalyticsEventRow(
                    from: analytics,
                    userId: userId,
                    eventKind: "unsupported"
                )
            ]
        )
        let adultService = makeService(fetchRemoteRows: { _ in
            malformedAdultRows
        })
        let headService = makeService(fetchRemoteRows: { _ in
            malformedHeadRows
        })

        await #expect(throws: MerianError.invalidResponse) {
            try await adultService.fetchRemoteState(
                for: userId,
                validateSynchronization: {}
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await headService.fetchRemoteState(
                for: userId,
                validateSynchronization: {}
            )
        }
    }

    @Test func synchronizationFenceStopsRecoveryFetchAfterSuspension() async {
        let userId = UUID()
        let adult = adultReceipt(userId: userId)
        var fetchCount = 0
        var validationCount = 0
        let service = makeService(
            insertAdult: { _ in },
            fetchAdult: { _, _ in
                fetchCount += 1
                return []
            }
        )

        await #expect(throws: CancellationError.self) {
            try await service.insertAdultEligibilityReceipt(
                adult,
                for: userId,
                validateSynchronization: {
                    validationCount += 1
                    throw CancellationError()
                }
            )
        }

        #expect(validationCount == 2)
        #expect(fetchCount == 0)
    }

    @Test func causalAppendWireKeysRemainExact() throws {
        let parameters = ConsentRemoteWire.AIConsentEventAppend(
            p_id: UUID(),
            p_disclosure_version: "disclosure",
            p_event_kind: "granted",
            p_occurred_at: "2026-08-04T12:34:56.789Z",
            p_disclosure_text: "Disclosure",
            p_action_text: "Action",
            p_platform: "ios",
            p_app_version: "1.0.3",
            p_app_build: "275",
            p_causal_parent_id: UUID()
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters))
                as? [String: Any]
        )

        #expect(
            Set(object.keys) == [
                "p_id",
                "p_disclosure_version",
                "p_event_kind",
                "p_occurred_at",
                "p_disclosure_text",
                "p_action_text",
                "p_platform",
                "p_app_version",
                "p_app_build",
                "p_causal_parent_id"
            ]
        )
        #expect(object["p_user_id"] == nil)
        #expect(object["provider"] == nil)
        #expect(object["consent_revision"] == nil)
    }

    @Test func causalAppendResultDecodesExactWireShape() throws {
        let acceptedParentId = UUID()
        let authoritativeEventId = UUID()
        let json = """
        {
          "accepted": true,
          "event_revision": 52,
          "accepted_parent_id": "\(acceptedParentId.uuidString)",
          "authoritative_revision": 52,
          "authoritative_event_id": "\(authoritativeEventId.uuidString)",
          "recorded_at": "2026-08-04T12:34:56.789Z"
        }
        """
        let data = try #require(json.data(using: .utf8))

        let result = try JSONDecoder().decode(
            ConsentRemoteWire.ConsentAppendResult.self,
            from: data
        )

        #expect(result.accepted)
        #expect(result.event_revision == 52)
        #expect(result.accepted_parent_id == acceptedParentId)
        #expect(result.authoritative_revision == 52)
        #expect(result.authoritative_event_id == authoritativeEventId)
        #expect(result.recorded_at == "2026-08-04T12:34:56.789Z")
    }
}
