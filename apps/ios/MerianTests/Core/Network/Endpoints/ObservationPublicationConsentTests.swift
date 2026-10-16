import Foundation
import os
import Testing
@testable import Merian

@Suite("Observation Publication Consent Preflight")
@MainActor
struct ObservationPublicationConsentTests {
    typealias Fixture = ObservationPublicationEndpointTests
    static let request = ObservationPublicationConsentRequest(observationID: Fixture.observation, analysisID: Fixture.analysis)
    static func photo(_ index: Int = 100) -> [String: Any] {
        ["media_id": String(format: "00000000-0000-4000-8000-%012d", index), "content_type": "image/jpeg",
         "byte_count": 10, "sha256": String(repeating: "a", count: 64)]
    }
    static func row(media: [[String: Any]]? = nil) -> [String: Any] {
        ["schema_version": 1, "observation_id": Fixture.observation.uuidString.lowercased(),
         "analysis_id": Fixture.analysis.uuidString.lowercased(), "expected_observation_revision": 2,
         "expected_review_revision": 1, "taxonomy_version_id": Fixture.taxonomy.uuidString.lowercased(),
         "initial_taxon_id": NSNull(), "media": media ?? [photo()]]
    }
    static func decode(_ row: [String: Any]) throws -> ObservationPublicationConsentSnapshot {
        try .decode(Fixture.data(row), request: request)
    }

    @Test func requestHasOnlyExplicitHistoricalIdentityWithoutMintingAnOperation() throws {
        let row = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.request)) as? [String: Any])
        #expect(Set(row.keys) == ["schema_version", "observation_id", "analysis_id"])
        #expect(row["observation_id"] as? String == Fixture.observation.uuidString.lowercased())
        #expect(row["analysis_id"] as? String == Fixture.analysis.uuidString.lowercased())
    }
    @Test func all64CandidatesPreserveOrderWithoutWideningReceiptLimits() throws {
        let photos = (1...64).map { Self.photo(100 - $0) }
        let bytes = try Fixture.data(Self.row(media: photos))
        #expect(bytes.count > 4096)
        let snapshot = try ObservationPublicationConsentSnapshot.decode(bytes, request: Self.request)
        #expect(snapshot.analysisID == Fixture.analysis)
        #expect(snapshot.observationID == Fixture.observation)
        #expect(snapshot.expectedObservationRevision == 2); #expect(snapshot.expectedReviewRevision == 1)
        #expect(snapshot.taxonomyVersionID == Fixture.taxonomy); #expect(snapshot.initialTaxonID == nil)
        let atLimit = bytes + Data(repeating: 32, count: 32 * 1024 - bytes.count)
        #expect(try ObservationPublicationConsentSnapshot.decode(atLimit, request: Self.request) == snapshot)
        #expect(throws: (any Error).self) {
            try ObservationPublicationConsentSnapshot.decode(atLimit + Data([32]), request: Self.request)
        }
        #expect(snapshot.media.map { $0.mediaID.uuidString.lowercased() } == photos.compactMap { $0["media_id"] as? String })
        #expect(throws: (any Error).self) { try ObservationPublicationWire.object(bytes, keys: Set(Self.row().keys)) }
        #expect(throws: (any Error).self) {
            try ObservationPublicationConsentSnapshot.decode(bytes + Data(repeating: 32, count: 32 * 1024), request: Self.request)
        }
    }
    @Test func rootRejectsDriftWrongIdentityBooleanRevisionAndNonNullTaxon() throws {
        for patch: [String: Any] in [
            ["schema_version": true], ["schema_version": 2], ["analysis_id": Fixture.operation.uuidString.lowercased()],
            ["observation_id": Fixture.operation.uuidString.lowercased()], ["taxonomy_version_id": NSNull()],
            ["taxonomy_version_id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"], ["initial_taxon_id": Fixture.taxonomy.uuidString],
            ["expected_review_revision": true], ["expected_review_revision": -1], ["expected_observation_revision": 2.5],
            ["expected_observation_revision": 2_147_483_647], ["operation_id": Fixture.operation.uuidString],
            ["post_id": Fixture.operation.uuidString], ["note": "private"], ["visibility": true], ["media": NSNull()]
        ] {
            #expect(throws: (any Error).self) { try Self.decode(Self.row().merging(patch) { _, new in new }) }
        }
        for key in Self.row().keys {
            var row = Self.row(); row.removeValue(forKey: key)
            #expect(throws: (any Error).self) { try Self.decode(row) }
        }
    }
    @Test func exactCandidateShapeBoundsAndAggregateAreEnforced() throws {
        for patch: [String: Any] in [
            ["kind": "image"], ["object_id": Fixture.operation.uuidString], ["url": "https://example.invalid"],
            ["media_id": NSNull()], ["content_type": "image/gif"], ["byte_count": true], ["byte_count": 0],
            ["byte_count": -1], ["byte_count": 1.5], ["byte_count": 33_554_433],
            ["sha256": String(repeating: "A", count: 64)], ["sha256": String(repeating: "a", count: 64) + "\n"],
            ["sha256": String(repeating: "a", count: 63)]
        ] {
            #expect(throws: (any Error).self) { try Self.decode(Self.row(media: [Self.photo().merging(patch) { _, new in new }])) }
        }
        for media in [[], [Self.photo(), Self.photo()], (1...65).map { Self.photo($0) }] {
            #expect(throws: (any Error).self) { try Self.decode(Self.row(media: media)) }
        }
        let maximum = Self.photo().merging(["byte_count": 33_554_432]) { _, new in new }
        #expect(try Self.decode(Self.row(media: [maximum])).media[0].byteCount == 33_554_432)
        #expect(throws: (any Error).self) { try Self.decode(Self.row(media: [maximum, Self.photo(101)])) }
        for mime in ["image/png", "image/heic"] {
            #expect(try Self.decode(Self.row(media: [Self.photo().merging(["content_type": mime]) { _, new in new }])).media[0].contentType == mime)
        }
    }
    @Test func endpointUsesExpectedOwnerAndOnlyThePreflightRoute() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let expected = String(decoding: try JSONEncoder().encode(Self.request), as: UTF8.self)
        let response = try Fixture.json(Self.row())
        fixture.transport.register(path: "/prepare-observation-publication-consent") { wire in
            try NetworkEndpointTestSupport.expectPOST(wire, function: "prepare-observation-publication-consent", json: expected)
            return try NetworkEndpointTestSupport.response(to: wire, json: response)
        }
        #expect(try await fixture.client.prepareObservationPublicationConsent(Self.request, ownerID: owner).analysisID == Fixture.analysis)
    }
    @Test func missingAccountCannotDispatchPreflight() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        await confirmation("No preflight dispatch without current account", expectedCount: 0) { sent in
            fixture.transport.register(path: "/prepare-observation-publication-consent") { wire in
                sent(); return try NetworkEndpointTestSupport.response(to: wire, json: "{}")
            }
            await #expect(throws: SupabaseAuthTransitionError.signOutSessionChanged) {
                try await fixture.client.prepareObservationPublicationConsent(Self.request, ownerID: UUID())
            }
        }
    }
    @Test func failureReturnsToForegroundOwnerWithoutHiddenReplay() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: "/prepare-observation-publication-consent") { _ in
            calls.withLock { $0 += 1 }; throw URLError(.networkConnectionLost)
        }
        await #expect(throws: (any Error).self) { try await fixture.client.prepareObservationPublicationConsent(Self.request, ownerID: owner) }
        #expect(calls.withLock { $0 } == 1)
    }
    @Test func classified401ReturnsWithoutRefreshingOrReplaying() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let refreshes = OSAllocatedUnfairLock(initialState: 0), sends = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = {
            refreshes.withLock { $0 += 1 }; return true
        }
        fixture.transport.register(path: "/prepare-observation-publication-consent") { wire in
            sends.withLock { $0 += 1 }
            return try NetworkEndpointTestSupport.response(to: wire, status: 401, json: #"{"code":"invalid_session_token"}"#)
        }
        do {
            _ = try await fixture.client.prepareObservationPublicationConsent(Self.request, ownerID: owner)
            Issue.record("Expected a classified authentication failure")
        } catch MerianError.httpError(let status, _) { #expect(status == 401) }
        #expect(refreshes.withLock { $0 } == 0); #expect(sends.withLock { $0 } == 1)
    }

}
