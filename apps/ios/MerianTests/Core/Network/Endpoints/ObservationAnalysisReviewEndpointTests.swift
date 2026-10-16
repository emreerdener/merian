import Foundation
@testable import Merian
import os
import Testing

@Suite("Observation Analysis Review Wire and Transport")
@MainActor
struct ObservationAnalysisReviewEndpointTests {
    nonisolated static let observation = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
    nonisolated static let analysis = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000002")!
    nonisolated static let operation = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000003")!
    nonisolated static let rejection = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000004")!
    nonisolated static var decisions: [ObservationAnalysisReviewRequest.Decision] {
        [.reject, .undo(rejectionOperationID: rejection), .undoConfirmation(confirmationOperationID: rejection), .confirmPrimary, .confirmName("Examplea testus")]
    }
    static func input(_ decision: ObservationAnalysisReviewRequest.Decision = .reject) throws -> ObservationAnalysisReviewRequest {
        try .init(observationID: observation, analysisID: analysis, operationID: operation,
                  expectedObservationRevision: 8, expectedReviewRevision: 2, decision: decision)
    }
    static func row(_ request: ObservationAnalysisReviewRequest) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
    }
    static func data(_ row: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) }
    static func receipt(_ request: ObservationAnalysisReviewRequest, outcome: String = "applied") throws -> Data {
        var value = try row(request); value["outcome"] = outcome
        if outcome == "applied" { value["observation_revision"] = 9; value["review_revision"] = 3 }
        return try data(value)
    }

    @Test(arguments: decisions)
    func exactRoundTripAndReceiptBinding(_ decision: ObservationAnalysisReviewRequest.Decision) throws {
        let request = try Self.input(decision)
        #expect(try ObservationAnalysisReviewRequest.decode(request.encoded()) == request)
        let row = try Self.row(request)
        #expect(row.count == 8)
        if decision == .reject { #expect(row["undo_operation_id"] is NSNull) }
        if decision == .confirmPrimary { #expect(row["scientific_name"] is NSNull) }
        #expect(try ObservationAnalysisReviewReceipt.decode(Self.receipt(request), request: request).outcome == .applied(observationRevision: 9, reviewRevision: 3))
        #expect(try ObservationAnalysisReviewReceipt.decode(Self.receipt(request, outcome: "revision_conflict"), request: request).outcome == .revisionConflict)
        if decision.isConfirmation {
            #expect(try ObservationAnalysisReviewReceipt.decode(Self.receipt(request, outcome: "not_verified"), request: request).outcome == .notVerified)
        } else {
            #expect(throws: (any Error).self) { try ObservationAnalysisReviewReceipt.decode(Self.receipt(request, outcome: "not_verified"), request: request) }
        }
    }
    @Test func candidateReferenceRoundTripAndFixedConfirmationRoute() async throws {
        let reference = try ObservationAnalysisCandidateReference(analysisID: Self.analysis, ordinal: 1, scientificName: "Examplea alternative")
        let decision = ObservationAnalysisReviewRequest.Decision.confirmCandidate(reference), request = try Self.input(decision)
        let row = try Self.row(request)
        #expect(row.count == 9 && row["schema_version"] as? Int == 2 && row["action"] as? String == "confirm_name")
        #expect(try ObservationAnalysisReviewRequest.decode(request.encoded()) == request)
        for outcome in ["applied", "not_verified", "revision_conflict"] {
            let receipt = try ObservationAnalysisReviewReceipt.decode(Self.receipt(request, outcome: outcome), request: request)
            #expect(receipt.request == request)
            #expect(try ObservationAnalysisReviewReceipt.decode(receipt.encoded(), request: request) == receipt)
        }
        try await fixedRoutesCarryOriginalOperationAndOwner(decision)
        let referenceRow = try #require(row["candidate_reference"] as? [String: Any])
        for patch: [String: Any] in [["ordinal": 2], ["ordinal": true], ["ordinal": -1], ["version": 2],
            ["analysis_id": Self.observation.uuidString.lowercased()], ["representation": "display_candidates"], ["name": "Examplea alternative"]] {
            var changed = row; changed["candidate_reference"] = referenceRow.merging(patch) { _, next in next }
            #expect(throws: (any Error).self) { try ObservationAnalysisReviewRequest.decode(Self.data(changed)) }
        }
        for patch: [String: Any] in [["schema_version": 1], ["schema_version": 3], ["action": "confirm_primary"], ["scientific_name": NSNull()]] {
            #expect(throws: (any Error).self) { try ObservationAnalysisReviewRequest.decode(Self.data(row.merging(patch) { _, next in next })) }
        }
        var changed = try Self.row(request); changed["candidate_reference"] = referenceRow.merging(["ordinal": 0]) { _, next in next }
        let other = try ObservationAnalysisReviewRequest.decode(Self.data(changed))
        #expect(throws: (any Error).self) { try ObservationAnalysisReviewReceipt.decode(Self.receipt(other), request: request) }
        #expect(throws: (any Error).self) {
            try ObservationAnalysisReviewRequest(observationID: Self.observation, analysisID: Self.observation, operationID: Self.operation,
                expectedObservationRevision: 8, expectedReviewRevision: 2, decision: decision)
        }
    }

    @Test func exactRequestRejectsDriftAndBounds() throws {
        let original = try Self.row(Self.input())
        let patches: [[String: Any]] = [["schema_version": true], ["expected_review_revision": true],
            ["expected_observation_revision": -1], ["expected_review_revision": 2_147_483_647],
            ["expected_review_revision": 2.5], ["operation_id": Self.operation.uuidString], ["owner_id": Self.observation.uuidString],
            ["action": "carry"], ["undo_operation_id": Self.rejection.uuidString.lowercased()], ["scientific_name": NSNull()]]
        for patch in patches {
            #expect(throws: (any Error).self) { try ObservationAnalysisReviewRequest.decode(Self.data(original.merging(patch) { _, next in next })) }
        }
        var missing = original; missing.removeValue(forKey: "undo_operation_id")
        #expect(throws: (any Error).self) { try ObservationAnalysisReviewRequest.decode(Self.data(missing)) }
        missing = original; missing["action"] = "undo"
        #expect(throws: (any Error).self) { try ObservationAnalysisReviewRequest.decode(Self.data(missing)) }
        #expect(throws: (any Error).self) { try ObservationAnalysisReviewRequest.decode(Data(repeating: 32, count: 2049)) }
        let integral = (try #require(String(bytes: Self.data(original), encoding: .utf8))).replacingOccurrences(of: "\"expected_review_revision\":2", with: "\"expected_review_revision\":2e0")
        #expect(try ObservationAnalysisReviewRequest.decode(Data(integral.utf8)) == Self.input())
    }
    @Test func scientificNamesMatchJavaScriptWithoutNormalization() throws {
        for name in [String(repeating: "😀", count: 80), "Examplea\u{0085}testus", "e\u{301}", "é"] {
            _ = try Self.input(.confirmName(name))
        }
        for name in ["", " Examplea", "Examplea\u{FEFF}", "Examplea\n", "Ex\u{7F}amplea", String(repeating: "😀", count: 81)] {
            #expect(throws: (any Error).self) { try Self.input(.confirmName(name)) }
        }
        let composed = try Self.input(.confirmName("é")), decomposed = try Self.input(.confirmName("e\u{301}"))
        #expect(composed != decomposed)
        #expect(throws: (any Error).self) { try ObservationAnalysisReviewReceipt.decode(Self.receipt(decomposed), request: composed) }
    }
    @Test func receiptsRequireExactIdentityRevisionAndOutcomeFields() throws {
        let request = try Self.input()
        let original = try #require(JSONSerialization.jsonObject(with: Self.receipt(request)) as? [String: Any])
        for patch: [String: Any] in [["analysis_id": Self.observation.uuidString.lowercased()], ["operation_id": Self.rejection.uuidString.lowercased()],
            ["expected_review_revision": 3], ["observation_revision": 8], ["review_revision": true],
            ["review_revision": 4], ["selected_analysis_id": Self.analysis.uuidString.lowercased()], ["outcome": "accepted"], ["outcome": "revision_conflict"]] {
            #expect(throws: (any Error).self) { try ObservationAnalysisReviewReceipt.decode(Self.data(original.merging(patch) { _, next in next }), request: request) }
        }
        var missing = original; missing.removeValue(forKey: "review_revision")
        #expect(throws: (any Error).self) { try ObservationAnalysisReviewReceipt.decode(Self.data(missing), request: request) }
        #expect(throws: (any Error).self) { try ObservationAnalysisReviewReceipt.decode(Data(repeating: 32, count: 4097), request: request) }
    }
    @Test(arguments: decisions)
    func fixedRoutesCarryOriginalOperationAndOwner(_ decision: ObservationAnalysisReviewRequest.Decision) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID), request = try Self.input(decision)
        let response = try #require(String(bytes: Self.receipt(request), encoding: .utf8))
        let original = try request.encoded()
        let path = decision.isConfirmation ? "/functions/v1/confirm-observation-analysis" : "/rest/v1/rpc/review_owned_observation_analysis"
        fixture.transport.register(path: path) { wire in
            #expect(wire.url?.path == path); #expect(wire.httpMethod == "POST")
            #expect(wire.cachePolicy == .reloadIgnoringLocalCacheData)
            #expect(wire.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            let body = try #require(MockURLProtocol.bodyData(for: wire))
            if decision.isConfirmation {
                #expect(try NetworkEndpointTestSupport.canonicalRequestJSON(body) == original)
            } else {
                let row = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                #expect(Set(row.keys) == ["p_request", "p_reader"]); #expect(row["p_reader"] as? Int == 10)
                #expect(try Self.data(#require(row["p_request"] as? [String: Any])) == original)
            }
            return try NetworkEndpointTestSupport.response(to: wire, json: response)
        }
        #expect(try await fixture.client.reviewObservationAnalysis(request, ownerID: owner, validateAttempt: {}).request == request)
    }
    @Test(arguments: [false, true], [401, 409, 503, -1])
    func failuresNeverRefreshOrReplay(confirmation: Bool, status: Int) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let request = try Self.input(confirmation ? .confirmPrimary : .reject)
        let calls = OSAllocatedUnfairLock(initialState: 0), refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = { refreshes.withLock { $0 += 1 }; return true }
        fixture.transport.register(path: confirmation ? "/confirm-observation-analysis" : "/review_owned_observation_analysis") { wire in
            calls.withLock { $0 += 1 }
            if status == -1 { throw URLError(.networkConnectionLost) }
            return try NetworkEndpointTestSupport.response(to: wire, status: status, json: "{\"code\":\"analysis_history_unavailable\"}")
        }
        await #expect(throws: (any Error).self) { try await fixture.client.reviewObservationAnalysis(request, ownerID: owner, validateAttempt: {}) }
        #expect(calls.withLock { $0 } == 1); #expect(refreshes.withLock { $0 } == 0)
    }
    @Test(arguments: [false, true])
    func missingGatewayRouteReturnsWithoutRedispatch(confirmation: Bool) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let request = try Self.input(confirmation ? .confirmPrimary : .reject)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: confirmation ? "/confirm-observation-analysis" : "/review_owned_observation_analysis") { wire in
            calls.withLock { $0 += 1 }
            let url = try #require(wire.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil,
                headerFields: ["SB-Error-Code": "NOT_FOUND"]))
            return (response, Data("{\"code\":\"NOT_FOUND\"}".utf8))
        }
        await #expect(throws: MerianError.edgeFunctionUnavailable) {
            try await fixture.client.reviewObservationAnalysis(request, ownerID: owner, validateAttempt: {})
        }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test(arguments: [false, true])
    func attemptValidationPreventsDispatchAfterPreparation(confirmation: Bool) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let request = try Self.input(confirmation ? .confirmPrimary : .reject)
        var checks = 0
        fixture.transport.register(path: confirmation ? "/confirm-observation-analysis" : "/review_owned_observation_analysis") { _ in
            Issue.record("Invalidated review reached dispatch"); throw URLError(.badServerResponse)
        }
        await #expect(throws: CancellationError.self) {
            try await fixture.client.reviewObservationAnalysis(request, ownerID: owner, validateAttempt: {
                checks += 1
                throw CancellationError()
            })
        }
        #expect(checks == 1)
    }

    @Test(arguments: [false, true])
    func missingAccountNeverDispatches(confirmation: Bool) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        let request = try Self.input(confirmation ? .confirmPrimary : .reject)
        await #expect(throws: SupabaseAuthTransitionError.signOutSessionChanged) {
            try await fixture.client.reviewObservationAnalysis(request, ownerID: UUID(), validateAttempt: {})
        }
    }
}
