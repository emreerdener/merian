import Foundation
@testable import Merian
import os
import Testing

@Suite("Observation Reanalysis Preflight")
@MainActor
struct ObservationReanalysisPreflightTests {
    private func request() throws -> ObservationReanalysisPreflightRequest {
        try .init(observationID: UUID(), analysisID: UUID(), sourceAnalysisID: UUID())
    }
    private func response(_ input: ObservationReanalysisPreflightRequest) -> [String: Any] {
        ["schema_version": 1, "observation_id": input.observationID.uuidString.lowercased(),
         "analysis_id": input.analysisID.uuidString.lowercased(), "source_analysis_id": input.sourceAnalysisID.uuidString.lowercased(),
         "decision": "ready", "processor_permission": "google_gemini", "minimum_entitlement_protocol": 3,
         "minimum_identification_protocol": 0]
    }
    private func decode(_ row: [String: Any], _ input: ObservationReanalysisPreflightRequest) throws -> IdentificationRecipientExpectation {
        try ObservationReanalysisPreflightRequest.recipient(from: JSONSerialization.data(withJSONObject: row), for: input)
    }
    @Test func exactRequestHasNoContentOwnerOrProviderSelection() throws {
        let input = try request()
        let row = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        #expect(Set(row.keys) == ["schema_version", "observation_id", "analysis_id", "source_analysis_id",
                                 "entitlement_protocol", "identification_protocol", "history_protocol"])
        #expect(row["history_protocol"] as? Int == 8)
        #expect(row["identification_protocol"] as? Int == 6)
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPreflightRequest(observationID: input.observationID, analysisID: input.analysisID, sourceAnalysisID: input.analysisID)
        }
    }
    @Test func readyAndRecoveryCannotBeConfused() throws {
        let input = try request()
        #expect(try decode(response(input), input) == .gemini)
        for minimum in [4, 5, 6] {
            var row = response(input); row["processor_permission"] = "openai"; row["minimum_identification_protocol"] = minimum
            #expect(try decode(row, input) == .openAI)
        }
        var recovery = response(input); recovery["decision"] = "recovery_only"
        #expect(throws: (any Error).self) { try decode(recovery, input) }
        for key in ["processor_permission", "minimum_entitlement_protocol", "minimum_identification_protocol"] { recovery[key] = NSNull() }
        #expect(try decode(recovery, input) == .recoveryOnly)
        recovery["decision"] = "ready"
        #expect(throws: (any Error).self) { try decode(recovery, input) }
    }
    @Test func decoderRejectsIdentityDriftUnknownFieldsAndMalformedMinimums() throws {
        let input = try request()
        for patch: [String: Any] in [
            ["schema_version": true], ["schema_version": 2], ["owner_id": UUID().uuidString],
            ["observation_id": UUID().uuidString.lowercased()], ["analysis_id": UUID().uuidString.lowercased()],
            ["source_analysis_id": NSNull()], ["source_analysis_id": input.sourceAnalysisID.uuidString.uppercased()],
            ["decision": "unknown"], ["processor_permission": "recovery_only"], ["processor_permission": "unknown"],
            ["minimum_entitlement_protocol": true], ["minimum_entitlement_protocol": 4],
            ["minimum_identification_protocol": 7], ["minimum_identification_protocol": 1.5],
            ["minimum_identification_protocol": true], ["minimum_identification_protocol": -1]
        ] { #expect(throws: (any Error).self) { try decode(response(input).merging(patch) { _, new in new }, input) } }
        for key in response(input).keys {
            var row = response(input); row.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try decode(row, input) }
        }
        let bytes = try JSONSerialization.data(withJSONObject: response(input))
        #expect(throws: (any Error).self) {
            try ObservationReanalysisPreflightRequest.recipient(from: bytes + Data(repeating: 32, count: 4096), for: input)
        }
    }
    @Test func consentAndUpgradeResponsesStopDispatch() throws {
        let input = try request()
        var row = response(input); row["decision"] = "permission_required"
        #expect(throws: MerianError.aiConsentRequired) { try decode(row, input) }
        row["decision"] = "client_update_required"; row["minimum_entitlement_protocol"] = 4
        row["processor_permission"] = NSNull(); row["minimum_identification_protocol"] = NSNull()
        do { _ = try decode(row, input); Issue.record("Expected update requirement") } catch { #expect(EdgeFunctionErrorPolicy.stableCode(from: error) == "client_update_required") }
    }
    @Test func exactOwnerBoundRPCProducesLocallyRevalidatedAuthorization() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        fixture.client.overridingInferenceConsentCheck = {}
        let owner = try #require(fixture.client.overridingAuthUserID), input = try request()
        let expected = try JSONEncoder().encode(input)
        let json = try #require(String(bytes: JSONSerialization.data(withJSONObject: response(input)), encoding: .utf8))
        fixture.transport.register(path: "/get_owned_observation_reanalysis_preflight") { wire in
            let bytes = try #require(MockURLProtocol.bodyData(for: wire))
            let body = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            #expect(Set(body.keys) == ["p_request"])
            #expect(NSDictionary(dictionary: try #require(body["p_request"] as? [String: Any])) == NSDictionary(dictionary: try #require(JSONSerialization.jsonObject(with: expected) as? [String: Any])))
            return try NetworkEndpointTestSupport.response(to: wire, json: json)
        }
        let validations = OSAllocatedUnfairLock(initialState: 0)
        let auth = try await fixture.client.prepareIdentificationAuthorization(input: input, expectedAuthUserID: owner,
            validateAttempt: { validations.withLock { $0 += 1 } })
        #expect(auth.recipient == .gemini)
        try auth.validate()
        #expect(validations.withLock { $0 } == 3)
    }
    @Test(arguments: [401, 503])
    func errorsNeverRefreshOrReplay(status: Int) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID), input = try request()
        let sends = OSAllocatedUnfairLock(initialState: 0), refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = { refreshes.withLock { $0 += 1 }; return true }
        fixture.transport.register(path: "/get_owned_observation_reanalysis_preflight") { wire in
            sends.withLock { $0 += 1 }
            return try NetworkEndpointTestSupport.response(to: wire, status: status, json: #"{"code":"invalid_session_token"}"#)
        }
        await #expect(throws: (any Error).self) {
            try await fixture.client.prepareIdentificationAuthorization(input: input, expectedAuthUserID: owner)
        }
        #expect(sends.withLock { $0 } == 1); #expect(refreshes.withLock { $0 } == 0)
    }
    @Test func wrongOwnerAndStaleQueueCannotDispatch() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID), input = try request()
        await confirmation("No dispatch without current queue/account", expectedCount: 0) { sent in
            fixture.transport.register(path: "/get_owned_observation_reanalysis_preflight") { wire in
                sent(); return try NetworkEndpointTestSupport.response(to: wire, json: "{}")
            }
            await #expect(throws: (any Error).self) {
                try await fixture.client.prepareIdentificationAuthorization(input: input, expectedAuthUserID: UUID())
            }
            await #expect(throws: CancellationError.self) {
                try await fixture.client.prepareIdentificationAuthorization(input: input, expectedAuthUserID: owner,
                    validateAttempt: { throw CancellationError() })
            }
        }
    }
    @Test(arguments: [IdentificationRecipientExpectation.gemini, .openAI])
    func boundAuthorizationKeepsProcessorAndSynchronizesConsentWithoutRecipientRPC(_ processor: IdentificationRecipientExpectation) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let checks = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingInferenceConsentCheck = { checks.withLock { $0 += 1 } }
        let authorization = try await fixture.client.prepareBoundObservationReanalysisAuthorization(
            processor: processor, expectedAuthUserID: owner, validateAttempt: {})
        #expect(authorization.recipient == processor && checks.withLock { $0 } == 1)
        // No recipient route is registered: any network preflight would fail the call.
        try authorization.validate()
    }

    @Test(arguments: ["recovery", "owner", "consent", "stale-before", "stale-after", "owner-after"])
    func boundAuthorizationCannotBypassConsentOrOwnerAndClaimFences(_ reason: String) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let state = OSAllocatedUnfairLock(initialState: false)
        fixture.client.overridingInferenceConsentCheck = {
            if reason == "consent" { throw MerianError.aiConsentRequired }
            state.withLock { $0 = true }
            if reason == "owner-after" { fixture.client.overridingAuthUserID = UUID() }
        }
        await #expect(throws: (any Error).self) {
            try await fixture.client.prepareBoundObservationReanalysisAuthorization(
                processor: reason == "recovery" ? .recoveryOnly : .gemini,
                expectedAuthUserID: reason == "owner" ? UUID() : owner,
                validateAttempt: {
                    if reason == "stale-before" || (reason == "stale-after" && state.withLock({ $0 })) { throw CancellationError() }
                })
        }
        if ["recovery", "owner", "stale-before"].contains(reason) { #expect(!state.withLock { $0 }) }
    }

    @Test func boundAuthorizationRechecksClaimAtLaterDispatch() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        fixture.client.overridingInferenceConsentCheck = {}
        let owner = try #require(fixture.client.overridingAuthUserID), stale = OSAllocatedUnfairLock(initialState: false)
        let authorization = try await fixture.client.prepareBoundObservationReanalysisAuthorization(
            processor: .gemini, expectedAuthUserID: owner, validateAttempt: {
                if stale.withLock({ $0 }) { throw CancellationError() }
            })
        stale.withLock { $0 = true }
        #expect(throws: CancellationError.self) { try authorization.validate() }
    }

}
