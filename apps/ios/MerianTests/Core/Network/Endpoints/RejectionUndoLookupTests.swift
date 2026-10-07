import Foundation
@testable import Merian
import os
import Testing

@MainActor
struct RejectionUndoLookupTests {
    @Test func exactOwnerLookupHasFixedRouteAndDoesNotRetry() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let lookup = ObservationRejectionUndoLookup(observationID: UUID(), analysisID: UUID(), observationRevision: 9, reviewRevision: 2)
        let path = "/rest/v1/rpc/get_owned_observation_rejection_undo"
        var row = try lookup.object(); row["status"] = "unavailable"; row["reason"] = "receipt_unavailable"
        let response = try #require(String(data: JSONSerialization.data(withJSONObject: row), encoding: .utf8))
        fixture.transport.register(path: path) { request in
            #expect(request.timeoutInterval == 5 && request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == nil)
            return try NetworkEndpointTestSupport.response(to: request, json: response)
        }
        var validated = 0
        let result = try await fixture.client.observationRejectionUndo(lookup, ownerID: owner, validateAttempt: { validated += 1 })
        #expect(result.outcome == .unavailable(.receiptUnavailable) && validated == 1)
    }
    @Test func strictResponseRejectsSubstitutionAndPrivateFields() throws {
        let lookup = ObservationRejectionUndoLookup(observationID: UUID(), analysisID: UUID(), observationRevision: 9, reviewRevision: 2)
        var row = try lookup.object()
        row.merge(["status": "available", "rejection_operation_id": UUID().uuidString.lowercased()]) { _, new in new }
        _ = try ObservationRejectionUndoReply(data: JSONSerialization.data(withJSONObject: row), request: lookup)
        for patch: [String: Any] in [["confirmation_action": "reject"], ["expected_review_revision": 3], ["expected_review_revision": true],
            ["analysis_id": UUID().uuidString.lowercased()], ["scientific_name": "Private"], ["receipt": [:]]] {
            #expect(throws: (any Error).self) {
                try ObservationRejectionUndoReply(data: JSONSerialization.data(withJSONObject: row.merging(patch) { _, new in new }), request: lookup)
            }
        }
        #expect(throws: (any Error).self) { try ObservationRejectionUndoReply(data: Data(repeating: 32, count: 4097), request: lookup) }
    }
    @Test(arguments: [401, 404, 503, -1])
    func failuresNeverRefreshOrReplay(status: Int) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let lookup = ObservationRejectionUndoLookup(observationID: UUID(), analysisID: UUID(), observationRevision: 9, reviewRevision: 2)
        let calls = OSAllocatedUnfairLock(initialState: 0), refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = { refreshes.withLock { $0 += 1 }; return true }
        fixture.transport.register(path: "/get_owned_observation_rejection_undo") { wire in
            calls.withLock { $0 += 1 }
            if status == -1 { throw URLError(.networkConnectionLost) }
            return try NetworkEndpointTestSupport.response(to: wire, status: status, json: "{}")
        }
        await #expect(throws: (any Error).self) {
            try await fixture.client.observationRejectionUndo(lookup, ownerID: owner, validateAttempt: {})
        }
        #expect(calls.withLock { $0 } == 1 && refreshes.withLock { $0 } == 0)
    }
    @Test func staleAttemptAfterAuthCannotDispatchLookup() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let lookup = ObservationRejectionUndoLookup(observationID: UUID(), analysisID: UUID(), observationRevision: 9, reviewRevision: 2)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: "/get_owned_observation_rejection_undo") { wire in
            calls.withLock { $0 += 1 }
            return try NetworkEndpointTestSupport.response(to: wire, json: "{}")
        }
        await #expect(throws: (any Error).self) {
            try await fixture.client.observationRejectionUndo(lookup, ownerID: owner,
                validateAttempt: { throw ObservationHistoryError.accountChanged })
        }
        #expect(calls.withLock { $0 } == 0)
    }

}
