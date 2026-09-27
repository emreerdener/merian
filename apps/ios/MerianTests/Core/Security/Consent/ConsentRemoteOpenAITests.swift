import Foundation
import Testing

@testable import Merian

extension ConsentRemoteServiceTests {
    @Test @MainActor
    func testOpenAIUsesItsOwnRPCAndPreservesCausalResult() async throws {
        let userId = UUID()
        let event = aiEvent(
            userId: userId, eventKind: .granted, causalParentId: nil,
            disclosureVersion: ConsentPolicy.openAIDisclosureVersion, processor: .openAI)
        var openAICalls = 0
        let service = makeService(
            appendAI: { _ in
                Issue.record("OpenAI reached Gemini RPC")
                throw StubError.unexpected
            },
            appendOpenAI: { parameters in
                openAICalls += 1
                #expect(parameters.p_id == event.id)
                #expect(parameters.p_disclosure_version == ConsentPolicy.openAIDisclosureVersion)
                return [
                    .init(
                        accepted: true, event_revision: 71, accepted_parent_id: nil,
                        authoritative_revision: 71, authoritative_event_id: event.id,
                        recorded_at: "2026-09-26T01:00:00.000Z")
                ]
            })
        let result = try await service.insertAIConsentEvent(event, for: userId, validateSynchronization: {})
        #expect(openAICalls == 1)
        #expect(result.provider == ConsentPolicy.openAIProvider)
        #expect(result.consentRevision == 71)
        #expect(result.syncedUserId == userId)
    }

    @Test @MainActor
    func testOpenAIAmbiguousWriteCannotRecoverFromGeminiRow() async throws {
        let userId = UUID()
        let event = aiEvent(
            userId: userId, eventKind: .granted, causalParentId: nil,
            disclosureVersion: ConsentPolicy.openAIDisclosureVersion, processor: .openAI)
        let mismatchedRow = ConsentRemoteWire.AIConsentEvent(
            id: event.id, user_id: userId, provider: ConsentPolicy.geminiProvider,
            disclosure_version: event.disclosureVersion, event_kind: "granted",
            occurred_at: timestamp(event.occurredAt), disclosure_text: event.disclosureText,
            action_text: event.actionText, platform: event.platform, app_version: event.appVersion,
            app_build: event.appBuild, recorded_at: "2026-09-26T01:00:00.000Z",
            causal_parent_id: nil, consent_revision: 72
        )
        let service = makeService(
            fetchAI: { _, _ in [mismatchedRow] },
            appendOpenAI: { _ in throw StubError.unexpected })
        do {
            _ = try await service.insertAIConsentEvent(event, for: userId, validateSynchronization: {})
            Issue.record("Cross-provider readback confirmed the OpenAI append")
        } catch { #expect(error is StubError) }
    }

    @Test @MainActor
    func testOpenAIHeadIsSeparateAndMalformedRecipientFailsClosed() async throws {
        let userId = UUID()
        let event = aiEvent(
            userId: userId, eventKind: .revoked, causalParentId: nil,
            disclosureVersion: "2026-09-25", processor: .openAI)
        let row = remoteAIEventRow(from: event, userId: userId)
        let rows = ConsentRemoteWire.RemoteRows(
            adultEligibilityReceipts: [], termsReceipts: [],
            aiConsentEvents: [], analyticsConsentEvents: [], aiConsentStreamHeads: [],
            analyticsConsentStreamHeads: [], openAIConsentStreamHeads: [row])
        let service = makeService(fetchRemoteRows: { _ in rows })
        let remote = try await service.fetchRemoteState(for: userId, validateSynchronization: {})
        #expect(remote.aiConsentStreamHead == nil)
        #expect(remote.openAIConsentStreamHead?.provider == ConsentPolicy.openAIProvider)
        #expect(remote.openAIConsentStreamHead?.eventKind == .revoked)
        #expect(!(ConsentAuthorityPolicy.isAuthoritativeRequiredConsent(remote, for: userId)))
        let wrongOwnerService = makeService(fetchRemoteRows: { _ in rows })
        do {
            _ = try await wrongOwnerService.fetchRemoteState(for: UUID(), validateSynchronization: {})
            Issue.record("Wrong-owner OpenAI head was accepted")
        } catch { #expect(error as? MerianError == .invalidResponse) }
    }
}
