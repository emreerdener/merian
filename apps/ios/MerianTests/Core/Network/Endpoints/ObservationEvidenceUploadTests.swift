import Foundation
import os
import Testing
@testable import Merian

@Suite("Observation Evidence Upload", .serialized)
@MainActor
struct ObservationEvidenceUploadTests {
    private static let observation = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private static let analysis = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    private static let media = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    private static func input() throws -> ObservationEvidenceUpload {
        try ObservationEvidenceUpload(observationID: observation, analysisID: analysis, photos: [
            .init(mediaID: media, contentType: "image/jpeg", bytes: Data([1, 2, 3]))])
    }
    private static func row(_ prepared: ObservationEvidenceUpload.Prepared) throws -> [String: Any] {
        ["schema_version": 1, "observation_id": observation.uuidString.lowercased(),
         "analysis_id": analysis.uuidString.lowercased(),
         "items": try JSONSerialization.jsonObject(with: JSONEncoder().encode(prepared.references))]
    }
    @Test func binaryFrameHasExactMetadataRawBytesAndDigest() throws {
        let prepared = try Self.input().prepare()
        let size = prepared.body.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let header = try #require(JSONSerialization.jsonObject(with: prepared.body.subdata(in: 4..<(4 + Int(size)))) as? [String: Any])
        #expect(Set(header.keys) == ["schema_version", "observation_id", "analysis_id", "photos"])
        #expect(header["observation_id"] as? String == Self.observation.uuidString.lowercased())
        #expect(prepared.body.suffix(3) == Data([1, 2, 3]))
        let photos = try #require(header["photos"] as? [[String: Any]])
        #expect(Set(photos[0].keys) == ["media_id", "content_type", "byte_count"])
        #expect(prepared.references[0].sha256 == "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")
        #expect(try Self.input().prepare().body == prepared.body)
    }
    @Test func rejectsAliasedIdentityUnsupportedMediaAndAggregateOverage() throws {
        let photo = ObservationEvidenceUpload.Photo(mediaID: Self.media, contentType: "image/jpeg", bytes: Data([1]))
        for photos in [[], [photo, photo], (0..<6).map { _ in .init(mediaID: UUID(), contentType: "image/png", bytes: Data([1])) },
                       [.init(mediaID: Self.observation, contentType: "image/jpeg", bytes: Data([1]))],
                       [.init(mediaID: Self.media, contentType: "image/heic", bytes: Data([1]))],
                       [.init(mediaID: Self.media, contentType: "image/jpeg", bytes: Data())],
                       [.init(mediaID: Self.media, contentType: "image/png", bytes: Data(repeating: 1, count: ObservationEvidenceUpload.maximumBytes)),
                        .init(mediaID: UUID(), contentType: "image/jpeg", bytes: Data([1]))]] as [[ObservationEvidenceUpload.Photo]] {
            #expect(throws: (any Error).self) { try ObservationEvidenceUpload(observationID: Self.observation, analysisID: Self.analysis, photos: photos) }
        }
        #expect(throws: (any Error).self) { try ObservationEvidenceUpload(observationID: Self.observation, analysisID: Self.observation, photos: [photo]) }
    }
    @Test func responseMustMatchExactIDsOrderBytesAndDigest() throws {
        let upload = try ObservationEvidenceUpload(observationID: Self.observation, analysisID: Self.analysis, photos: [
            .init(mediaID: Self.media, contentType: "image/jpeg", bytes: Data([1,2,3])),
            .init(mediaID: UUID(), contentType: "image/png", bytes: Data([4]))])
        let prepared = try upload.prepare(), row = try Self.row(prepared)
        let originalItems = try #require(row["items"] as? [[String: Any]])
        let good = try JSONSerialization.data(withJSONObject: row)
        #expect(try ObservationEvidenceUploadReceipt.decode(good, request: prepared).items == prepared.references)
        for patch: [String: Any] in [["schema_version": true], ["observation_id": Self.analysis.uuidString.lowercased()],
            ["analysis_id": Self.observation.uuidString.lowercased()], ["object_id": UUID().uuidString],
            ["items": originalItems.reversed().map { $0 }], ["items": []]] {
            let changed = row.merging(patch) { _, new in new }
            #expect(throws: (any Error).self) { try ObservationEvidenceUploadReceipt.decode(JSONSerialization.data(withJSONObject: changed), request: prepared) }
        }
        for patch: [String: Any] in [["kind": "description"], ["byte_count": true], ["byte_count": 4],
            ["sha256": String(repeating: "a", count: 64)], ["content_type": "image/png"], ["url": "https://example.invalid"]] {
            var changed = row, items = originalItems
            items[0].merge(patch) { _, new in new }; changed["items"] = items
            #expect(throws: (any Error).self) { try ObservationEvidenceUploadReceipt.decode(JSONSerialization.data(withJSONObject: changed), request: prepared) }
        }
        let atLimit = good + Data(repeating: 32, count: 4096 - good.count)
        #expect(try ObservationEvidenceUploadReceipt.decode(atLimit, request: prepared).items == prepared.references)
        #expect(throws: (any Error).self) { try ObservationEvidenceUploadReceipt.decode(atLimit + Data([32]), request: prepared) }
    }
    @Test func endpointSendsOneExactBinaryFrame() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let input = try Self.input(), prepared = try input.prepare()
        let response = String(decoding: try JSONSerialization.data(withJSONObject: Self.row(prepared)), as: UTF8.self)
        fixture.transport.register(path: "/upload-observation-evidence") { wire in
            #expect(wire.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
            #expect(wire.timeoutInterval == 130)
            #expect(MockURLProtocol.bodyData(for: wire) == prepared.body)
            return try NetworkEndpointTestSupport.response(to: wire, json: response)
        }
        #expect(try await fixture.client.uploadObservationEvidence(input, ownerID: owner).items == prepared.references)
    }
    @Test(arguments: [401, 503, -1]) func ambiguousFailuresDoNotRetryOrRefresh(_ status: Int) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let calls = OSAllocatedUnfairLock(initialState: 0), refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = { refreshes.withLock { $0 += 1 }; return true }
        fixture.transport.register(path: "/upload-observation-evidence") { wire in
            calls.withLock { $0 += 1 }
            if status == -1 { throw URLError(.networkConnectionLost) }
            return try NetworkEndpointTestSupport.response(to: wire, status: status, json: #"{"code":"invalid_session_token"}"#)
        }
        await #expect(throws: (any Error).self) { try await fixture.client.uploadObservationEvidence(Self.input(), ownerID: owner) }
        #expect(calls.withLock { $0 } == 1); #expect(refreshes.withLock { $0 } == 0)
    }
    @Test func missingAccountDoesNotDispatch() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        await confirmation("No upload without account", expectedCount: 0) { sent in
            fixture.transport.register(path: "/upload-observation-evidence") { wire in
                sent(); return try NetworkEndpointTestSupport.response(to: wire, json: "{}")
            }
            await #expect(throws: SupabaseAuthTransitionError.signOutSessionChanged) {
                try await fixture.client.uploadObservationEvidence(Self.input(), ownerID: UUID())
            }
        }
    }
}
