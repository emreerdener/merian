import Foundation
@testable import Merian
import os
import Testing

@MainActor
@Suite("Observation Reanalysis Recovery Transport")
struct ReanalysisRecoveryTransportTests {
    struct Reply { let bytes: Data; let body: String }
    func fixture(owner: UUID) throws -> (ObservationReanalysisRequest, Reply) {
        let (request, snapshot) = try ObservationReanalysisResultTests().fixture()
        let bytes = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        var state = try ObservationHistoryStateTests().fixture()
        state["owner_id"] = owner.uuidString.lowercased()
        state["observation_id"] = request.observationID.uuidString.lowercased()
        var analysis = try #require(state["analysis"] as? [String: Any])
        analysis["snapshot"] = try #require(String(bytes: bytes, encoding: .utf8)); state["analysis"] = analysis
        return (request, Reply(bytes: bytes, body: try #require(String(bytes: JSONSerialization.data(withJSONObject: state), encoding: .utf8))))
    }

    @Test func recoversExactChildBeforeInferenceConsentWithoutChangingSelection() async throws {
        let network = NetworkEndpointFixture(); defer { network.close() }
        let owner = try #require(network.client.overridingAuthUserID), (input, reply) = try fixture(owner: owner)
        network.client.overridingInferenceConsentCheck = { throw MerianError.aiConsentRequired }
        network.transport.register(path: "/get_owned_observation_analysis_state") { wire in
            #expect(wire.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyData(for: wire))
            let row = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(Set(row.keys) == ["p_request", "p_reader"] && row["p_reader"] as? Int == 9)
            let query = try #require(row["p_request"] as? [String: Any])
            #expect(Set(query.keys) == ["schema_version", "observation_id", "analysis_id"])
            #expect(query["schema_version"] as? Int == 1)
            #expect(query["observation_id"] as? String == input.observationID.uuidString.lowercased())
            #expect(query["analysis_id"] as? String == input.analysisID.uuidString.lowercased())
            return try NetworkEndpointTestSupport.response(to: wire, json: reply.body)
        }
        let result = try await network.client.recoverObservationAnalysis(input, expectedAuthUserID: owner, validateAttempt: {})
        #expect(result == reply.bytes)
    }

    @Test(arguments: [400, 404, 500])
    func onlyExactPostgRESTMissingPairReturnsAbsence(status: Int) async throws {
        let network = NetworkEndpointFixture(); defer { network.close() }
        let owner = try #require(network.client.overridingAuthUserID), (input, _) = try fixture(owner: owner)
        network.transport.register(path: "/get_owned_observation_analysis_state") { wire in
            try NetworkEndpointTestSupport.response(to: wire, status: status,
                json: #"{"code":"P0002","message":"analysis_history_not_found","details":null,"hint":null}"#)
        }
        #expect(try await network.client.recoverObservationAnalysis(input, expectedAuthUserID: owner, validateAttempt: {}) == nil)
    }

    @Test(arguments: [
        #"{"code":"P0001","message":"analysis_history_not_found"}"#,
        #"{"code":"P0002","message":"another_failure"}"#,
        #"{"code":"analysis_history_not_found"}"#,
        #"{"code":"P0002","message":"analysis_history_not_found","extra":true}"#,
        #"{"code":"P0002","message":"analysis_history_not_found","hint":true}"#,
        #"{"message":"analysis_history_not_found"}"#, "not-json"
    ])
    func otherErrorsNeverAuthorizeMoreWork(body: String) async throws {
        let network = NetworkEndpointFixture(); defer { network.close() }
        let owner = try #require(network.client.overridingAuthUserID), (input, _) = try fixture(owner: owner)
        network.transport.register(path: "/get_owned_observation_analysis_state") { wire in
            try NetworkEndpointTestSupport.response(to: wire, status: 404, json: body)
        }
        await #expect(throws: (any Error).self) {
            try await network.client.recoverObservationAnalysis(input, expectedAuthUserID: owner, validateAttempt: {})
        }
    }

    @Test(arguments: [401, 503])
    func failedReadNeverRefreshesOrAutomaticallyReplays(status: Int) async throws {
        let network = NetworkEndpointFixture(); defer { network.close() }
        let owner = try #require(network.client.overridingAuthUserID), (input, _) = try fixture(owner: owner)
        let sends = OSAllocatedUnfairLock(initialState: 0), refreshes = OSAllocatedUnfairLock(initialState: 0)
        network.client.overridingAuthSessionRefresh = { refreshes.withLock { $0 += 1 }; return true }
        network.transport.register(path: "/get_owned_observation_analysis_state") { wire in
            sends.withLock { $0 += 1 }
            return try NetworkEndpointTestSupport.response(to: wire, status: status, json: #"{"code":"invalid_session_token"}"#)
        }
        await #expect(throws: (any Error).self) {
            try await network.client.recoverObservationAnalysis(input, expectedAuthUserID: owner, validateAttempt: {})
        }
        #expect(sends.withLock { $0 } == 1 && refreshes.withLock { $0 } == 0)
    }

    @Test(arguments: [false, true])
    func staleAfterReadCannotReturnResultOrAbsence(absent: Bool) async throws {
        let network = NetworkEndpointFixture(); defer { network.close() }
        let owner = try #require(network.client.overridingAuthUserID), (input, reply) = try fixture(owner: owner)
        let stale = OSAllocatedUnfairLock(initialState: false)
        network.transport.register(path: "/get_owned_observation_analysis_state") { wire in
            stale.withLock { $0 = true }
            return try NetworkEndpointTestSupport.response(to: wire, status: absent ? 404 : 200,
                json: absent ? #"{"code":"P0002","message":"analysis_history_not_found"}"# : reply.body)
        }
        await #expect(throws: CancellationError.self) {
            try await network.client.recoverObservationAnalysis(input, expectedAuthUserID: owner, validateAttempt: {
                if stale.withLock({ $0 }) { throw CancellationError() }
            })
        }
    }

    @Test func malformedSuccessIsInvalidStateRatherThanTransportUncertainty() async throws {
        let network = NetworkEndpointFixture(); defer { network.close() }
        let owner = try #require(network.client.overridingAuthUserID), (input, _) = try fixture(owner: owner)
        network.transport.register(path: "/get_owned_observation_analysis_state") { wire in
            try NetworkEndpointTestSupport.response(to: wire, json: "not-json")
        }
        await #expect(throws: ObservationHistoryError.invalidSnapshot) {
            try await network.client.recoverObservationAnalysis(input, expectedAuthUserID: owner, validateAttempt: {})
        }
    }

    @Test func wrongOwnerCannotReadAndChangedProvenanceCannotRecover() async throws {
        let network = NetworkEndpointFixture(); defer { network.close() }
        let owner = try #require(network.client.overridingAuthUserID), (input, reply) = try fixture(owner: owner)
        let sends = OSAllocatedUnfairLock(initialState: 0)
        network.transport.register(path: "/get_owned_observation_analysis_state") { wire in
            sends.withLock { $0 += 1 }
            return try NetworkEndpointTestSupport.response(to: wire, json: reply.body)
        }
        await #expect(throws: (any Error).self) {
            try await network.client.recoverObservationAnalysis(input, expectedAuthUserID: UUID(), validateAttempt: {})
        }
        #expect(sends.withLock { $0 } == 0)
        let changed = try ObservationReanalysisRequest(observationID: input.observationID, analysisID: input.analysisID,
            sourceAnalysisID: UUID(), processor: input.processor, evidence: input.evidence)
        await #expect(throws: (any Error).self) {
            try await network.client.recoverObservationAnalysis(changed, expectedAuthUserID: owner, validateAttempt: {})
        }
        #expect(sends.withLock { $0 } == 1)
    }
}
