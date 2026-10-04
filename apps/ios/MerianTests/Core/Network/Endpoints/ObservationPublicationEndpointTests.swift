import Foundation
import os
import Testing
@testable import Merian

@Suite("Observation Publication Wire and Transport")
@MainActor
struct ObservationPublicationEndpointTests {
    static let observation = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let operation = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let analysis = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    static let taxonomy = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    static let media = [UUID(uuidString: "00000000-0000-4000-8000-000000000006")!, UUID(uuidString: "00000000-0000-4000-8000-000000000005")!]
    static func input(note: String? = nil, revision: Int = 2, media: [UUID]? = nil) throws -> ObservationPublicationRequest {
        try .init(operationID: operation, observationID: observation, analysisID: analysis,
            expectedObservationRevision: revision, expectedReviewRevision: 1, taxonomyVersionID: taxonomy,
            initialTaxonID: nil, note: note, mediaIDs: media ?? Self.media)
    }
    static func row(_ status: String = "accepted", admission: Bool = false) -> [String: Any] {
        var result: [String: Any] = ["schema_version": 1, "operation_id": operation.uuidString.lowercased(),
            "observation_id": observation.uuidString.lowercased(), "analysis_id": analysis.uuidString.lowercased(), "status": status]
        if admission { result["admitted_at"] = "2026-10-04T00:00:00.000Z" }
        return result
    }
    static func data(_ row: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: row) }
    static func json(_ row: [String: Any]) throws -> String { String(decoding: try data(row), as: UTF8.self) }

    @Test func consentRoundTripKeepsOrderNullsAndExactIdentity() throws {
        let request = try Self.input()
        let bytes = try JSONEncoder().encode(request)
        let row = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(row.keys) == Set(ObservationPublicationRequest.CodingKeys.allCases.map(\.rawValue)))
        #expect(row["note"] is NSNull); #expect(row["initial_taxon_id"] is NSNull)
        #expect(row["media_ids"] as? [String] == Self.media.map { $0.uuidString.lowercased() })
        #expect(try ObservationPublicationRequest.decode(bytes) == request)
        let status = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request.statusRequest)) as? [String: Any])
        #expect(Set(status.keys) == ["schema_version", "operation_id", "observation_id"])
    }
    @Test func requestBoundsMatchScalarLengthRevisionsAndCohort() throws {
        // 500 graphemes, 1,000 Unicode scalars. JS spreads count scalars, not graphemes.
        _ = try Self.input(note: String(repeating: "e\u{301}", count: 500))
        #expect(throws: (any Error).self) { try Self.input(note: String(repeating: "e\u{301}", count: 501)) }
        #expect(throws: (any Error).self) { try Self.input(note: String(repeating: "😀", count: 1000)) }
        #expect(throws: (any Error).self) { try Self.input(revision: -1) }
        #expect(throws: (any Error).self) { try Self.input(revision: 2_147_483_647) }
        #expect(throws: (any Error).self) { try Self.input(media: []) }
        #expect(throws: (any Error).self) { try Self.input(media: [Self.media[0], Self.media[0]]) }
        #expect(throws: (any Error).self) { try Self.input(media: (0..<7).map { _ in UUID() }) }
    }
    @Test func savedConsentRejectsDriftAndBooleanRevisions() throws {
        let request = try Self.input()
        let original = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        for patch: [String: Any] in [["owner_id": Self.operation.uuidString], ["schema_version": true],
            ["expected_review_revision": true], ["note": 3], ["media_ids": [true]],
            ["operation_id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"]] {
            let bytes = try Self.data(original.merging(patch) { _, new in new })
            #expect(throws: (any Error).self) { try ObservationPublicationRequest.decode(bytes) }
        }
        var missing = original; missing.removeValue(forKey: "note")
        #expect(throws: (any Error).self) { try ObservationPublicationRequest.decode(Self.data(missing)) }
    }
    @Test(arguments: ObservationPublicationStatus.allCases)
    func exactStatusIsHistoricalOnly(_ status: ObservationPublicationStatus) throws {
        let request = try Self.input().statusRequest
        let receipt = try ObservationPublicationReceipt.decodeStatus(Self.data(Self.row(status.rawValue)), request: request)
        #expect(receipt.status == status); #expect(receipt.analysisID == Self.analysis)
    }
    @Test func receiptsRejectWrongIdentityPrivateFieldsAndUnknownStates() throws {
        let request = try Self.input()
        for patch: [String: Any] in [["operation_id": Self.observation.uuidString.lowercased()],
            ["observation_id": Self.operation.uuidString.lowercased()], ["analysis_id": Self.operation.uuidString.lowercased()],
            ["schema_version": true], ["status": "published"], ["post_id": Self.operation.uuidString],
            ["reason": "private"], ["source": [:]], ["work_token": "private"]] {
            let bytes = try Self.data(Self.row().merging(patch) { _, new in new })
            #expect(throws: (any Error).self) { try ObservationPublicationReceipt.decodeStatus(bytes, request: request.statusRequest) }
        }
        #expect(throws: (any Error).self) { try ObservationPublicationReceipt.decodeStatus(Data(repeating: 32, count: 4097), request: request.statusRequest) }
        let accepted = try ObservationPublicationReceipt.decodeAdmission(Self.data(Self.row(admission: true)), request: request)
        #expect(accepted.status == .accepted)
        for patch: [String: Any] in [["status": "admitted"], ["admitted_at": "invalid"], ["post_id": "private"]] {
            let bytes = try Self.data(Self.row(admission: true).merging(patch) { _, new in new })
            #expect(throws: (any Error).self) { try ObservationPublicationReceipt.decodeAdmission(bytes, request: request) }
        }
    }
    @Test func liveEndpointsSendExactOperationAndMatchAnalysisWithoutLegacyFallback() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let request = try Self.input()
        let admissionJSON = try Self.json(Self.row(admission: true))
        let statusJSON = try Self.json(Self.row("photos_approved"))
        let expectedAdmission = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        let expectedStatus = String(decoding: try JSONEncoder().encode(request.statusRequest), as: UTF8.self)
        fixture.transport.register(path: "/request-observation-publication") { wire in
            try NetworkEndpointTestSupport.expectPOST(wire, function: "request-observation-publication", json: expectedAdmission)
            return try NetworkEndpointTestSupport.response(to: wire, status: 202, json: admissionJSON)
        }
        fixture.transport.register(path: "/get-observation-publication-status") { wire in
            try NetworkEndpointTestSupport.expectPOST(wire, function: "get-observation-publication-status", json: expectedStatus)
            return try NetworkEndpointTestSupport.response(to: wire, json: statusJSON)
        }
        #expect(try await fixture.client.requestObservationPublication(request, ownerID: owner).status == .accepted)
        #expect(try await fixture.client.observationPublicationStatus(request.statusRequest, ownerID: owner).status == .photosApproved)
    }
    @Test func explicitOwnerDoesNotBypassMissingCurrentAccount() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        let request = try Self.input()
        await confirmation("No publication dispatch without a current account", expectedCount: 0) { sent in
            for path in ["/request-observation-publication", "/get-observation-publication-status"] {
                fixture.transport.register(path: path) { wire in
                    sent()
                    return try NetworkEndpointTestSupport.response(to: wire, json: "{}")
                }
            }
            await #expect(throws: SupabaseAuthTransitionError.signOutSessionChanged) {
                try await fixture.client.requestObservationPublication(request, ownerID: UUID())
            }
            await #expect(throws: SupabaseAuthTransitionError.signOutSessionChanged) {
                try await fixture.client.observationPublicationStatus(request.statusRequest, ownerID: UUID())
            }
        }
        // DEBUG scoped transport skips live Auth leases. Account-switch fencing is
        // exercised at the transport/account owner, not inferred from this mock.
    }
    @Test func ambiguousAdmissionDoesNotAutomaticallyResubmit() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let request = try Self.input()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: "/request-observation-publication") { wire in
            calls.withLock { $0 += 1 }
            return try NetworkEndpointTestSupport.response(to: wire, status: 503, json: "{\"code\":\"analysis_history_unavailable\"}")
        }
        await #expect(throws: (any Error).self) { try await fixture.client.requestObservationPublication(request, ownerID: owner) }
        #expect(calls.withLock { $0 } == 1)
    }
    @Test(arguments: [false, true])
    func transientTransportFailureReturnsToDurableOwner(statusRead: Bool) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let request = try Self.input()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: statusRead ? "/get-observation-publication-status" : "/request-observation-publication") { _ in
            calls.withLock { $0 += 1 }
            throw URLError(.networkConnectionLost)
        }
        await #expect(throws: (any Error).self) {
            if statusRead { _ = try await fixture.client.observationPublicationStatus(request.statusRequest, ownerID: owner) }
            else { _ = try await fixture.client.requestObservationPublication(request, ownerID: owner) }
        }
        #expect(calls.withLock { $0 } == 1)
    }
    @Test func integralJSONNumbersAreCanonicalizedBeforeSendingAsInTheHTTPParser() throws {
        let request = try Self.input()
        let text = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        for spelling in ["1.0", "1e0"] {
            let alternate = text.replacingOccurrences(of: "\"expected_review_revision\":1", with: "\"expected_review_revision\":" + spelling)
            #expect(alternate != text)
            #expect(try ObservationPublicationRequest.decode(Data(alternate.utf8)) == request)
        }
    }

}
