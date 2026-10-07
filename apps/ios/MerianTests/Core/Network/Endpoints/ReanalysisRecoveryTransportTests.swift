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

@MainActor
@Suite("Observation Execution Status Transport")
struct ObservationExecutionStatusTransportTests {
    func reply(_ request: ObservationAnalysisExecutionLookup, owner: UUID, state: String = "absent") -> [String: Any] {
        request.object().merging(["owner_id": owner.uuidString.lowercased(), "state": state]) { _, value in value }
    }

    @Test func strictStatusNeverBecomesExecutionPermission() throws {
        let request = ObservationAnalysisExecutionLookup(try ObservationReanalysisResultTests().fixture().0), owner = UUID()
        for state in ObservationAnalysisExecutionStatus.State.allCases {
            let data = try JSONSerialization.data(withJSONObject: reply(request, owner: owner, state: state.rawValue))
            #expect(try ObservationAnalysisExecutionStatus(data: data, request: request, ownerID: owner).state == state)
        }
        let valid = reply(request, owner: owner)
        for (key, value) in ["schema_version": true, "owner_id": UUID().uuidString.lowercased(),
                             "analysis_id": UUID().uuidString.lowercased(), "observation_id": UUID().uuidString.lowercased(),
                             "source_analysis_id": NSNull(), "request_digest": String(repeating: "b", count: 64), "state": "held", "extra": true] as [String: Any] {
            var changed = valid; changed[key] = value
            #expect(throws: (any Error).self) {
                try ObservationAnalysisExecutionStatus(data: JSONSerialization.data(withJSONObject: changed), request: request, ownerID: owner)
            }
        }
        for key in valid.keys {
            var changed = valid; changed.removeValue(forKey: key)
            #expect(throws: (any Error).self) {
                try ObservationAnalysisExecutionStatus(data: JSONSerialization.data(withJSONObject: changed), request: request, ownerID: owner)
            }
        }
        for data in [Data("null".utf8), Data(), Data(repeating: 32, count: 4097)] {
            #expect(throws: (any Error).self) { try ObservationAnalysisExecutionStatus(data: data, request: request, ownerID: owner) }
        }
    }

    @Test func exactNullableSourceSupportedWithoutRelaxingPhotoReanalysis() throws {
        let owner = UUID()
        let lookup = try ObservationAnalysisExecutionLookup(observationID: UUID(), analysisID: UUID(), sourceAnalysisID: nil,
                                                           requestDigest: String(repeating: "a", count: 64))
        #expect(lookup.object()["source_analysis_id"] is NSNull)
        let data = try JSONSerialization.data(withJSONObject: reply(lookup, owner: owner))
        #expect(try ObservationAnalysisExecutionStatus(data: data, request: lookup, ownerID: owner).state == .absent)
        var mismatched = reply(lookup, owner: owner); mismatched["source_analysis_id"] = UUID().uuidString.lowercased()
        #expect(throws: (any Error).self) {
            try ObservationAnalysisExecutionStatus(data: JSONSerialization.data(withJSONObject: mismatched), request: lookup, ownerID: owner)
        }
        #expect(throws: (any Error).self) {
            try ObservationAnalysisExecutionLookup(observationID: owner, analysisID: owner, sourceAnalysisID: nil, requestDigest: String(repeating: "a", count: 64))
        }
    }

    @Test(arguments: [200, 401, 503])
    func fixedBoundedReadNeverRetries(status: Int) async throws {
        let network = NetworkEndpointFixture(); defer { network.close() }
        let owner = try #require(network.client.overridingAuthUserID), input = ObservationAnalysisExecutionLookup(try ObservationReanalysisResultTests().fixture().0)
        let body = try #require(String(data: JSONSerialization.data(withJSONObject: reply(input, owner: owner)), encoding: .utf8))
        let sends = OSAllocatedUnfairLock(initialState: 0), refreshes = OSAllocatedUnfairLock(initialState: 0)
        network.client.overridingInferenceConsentCheck = { throw MerianError.aiConsentRequired }
        network.client.overridingAuthSessionRefresh = { refreshes.withLock { $0 += 1 }; return true }
        network.transport.register(path: "/get_owned_observation_analysis_execution") { wire in
            sends.withLock { $0 += 1 }
            #expect(wire.httpMethod == "POST" && wire.timeoutInterval == 5)
            #expect(wire.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            let sentBody = try #require(MockURLProtocol.bodyData(for: wire))
            let row = try #require(JSONSerialization.jsonObject(with: sentBody) as? [String: Any])
            #expect(Set(row.keys) == ["p_request", "p_reader"] && row["p_reader"] as? Int == 9)
            let sentRequest = try #require(row["p_request"] as? [String: Any])
            #expect(NSDictionary(dictionary: sentRequest) == NSDictionary(dictionary: input.object()))
            return try NetworkEndpointTestSupport.response(to: wire, status: status, json: body)
        }
        if status == 200 {
            let value = try await network.client.reanalysisStatusTransport().read(input, ownerID: owner, validateAttempt: {})
            #expect(value.state == .absent)
        } else {
            await #expect(throws: (any Error).self) {
                try await network.client.reanalysisStatusTransport().read(input, ownerID: owner, validateAttempt: {})
            }
        }
        #expect(sends.withLock { $0 } == 1 && refreshes.withLock { $0 } == 0)
    }

    @Test(arguments: [false, true])
    func staleClaimBeforeDispatchOrAfterReplyCannotReturnStatus(afterReply: Bool) async throws {
        let network = NetworkEndpointFixture(); defer { network.close() }
        let owner = try #require(network.client.overridingAuthUserID), input = ObservationAnalysisExecutionLookup(try ObservationReanalysisResultTests().fixture().0)
        let body = try #require(String(data: JSONSerialization.data(withJSONObject: reply(input, owner: owner)), encoding: .utf8))
        let stale = OSAllocatedUnfairLock(initialState: false), sends = OSAllocatedUnfairLock(initialState: 0)
        network.transport.register(path: "/get_owned_observation_analysis_execution") { wire in
            sends.withLock { $0 += 1 }; stale.withLock { $0 = true }
            return try NetworkEndpointTestSupport.response(to: wire, json: body)
        }
        var validations = 0
        await #expect(throws: CancellationError.self) {
            try await network.client.reanalysisStatusTransport().read(input, ownerID: owner, validateAttempt: {
                validations += 1
                if stale.withLock({ $0 }) || (!afterReply && validations == 2) { throw CancellationError() }
            })
        }
        #expect(sends.withLock { $0 } == (afterReply ? 1 : 0))
    }
}
