import Foundation
@testable import Merian
import os
import Testing

@Suite("Observation Audio Evidence Upload", .serialized)
@MainActor
struct ObservationAudioEvidenceUploadTests {
    private static let observation = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private static let analysis = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    private static let media = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    private static func input() throws -> ObservationAudioEvidenceUpload {
        try ObservationAudioEvidenceUpload(observationID: observation, analysisID: analysis, mediaID: media,
            bytes: makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 1, sampleAt: { _ in 123 }))
    }
    private static func row(_ prepared: ObservationAudioEvidenceUpload.Prepared) -> [String: Any] {
        let audio = prepared.reference
        return ["schema_version": 1, "observation_id": Self.observation.uuidString.lowercased(),
                "analysis_id": Self.analysis.uuidString.lowercased(), "items": [["kind": "audio",
                "media_id": audio.mediaID.uuidString.lowercased(), "content_type": "audio/wav",
                "byte_count": audio.byteCount, "sha256": audio.sha256]]]
    }
    @Test func frameOwnsExactBytesAndReceiptRejectsSubstitution() throws {
        let input = try Self.input(), prepared = try input.prepare()
        let length = prepared.body.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        let metadata = try #require(JSONSerialization.jsonObject(with: prepared.body.subdata(in: 4..<(4 + length))) as? [String: Any])
        #expect(Set(metadata.keys) == ["schema_version", "observation_id", "analysis_id", "audio"])
        #expect(prepared.body.suffix(input.bytes.count) == input.bytes)
        #expect(try input.prepare().body == prepared.body)
        let row = Self.row(prepared)
        let items = try #require(row["items"] as? [[String: Any]])
        for patch: [String: Any] in [["schema_version": true], ["observation_id": Self.analysis.uuidString.lowercased()],
            ["analysis_id": Self.observation.uuidString.lowercased()], ["object_id": "forbidden"], ["items": []], ["items": items + items]] {
            #expect(throws: (any Error).self) {
                try ObservationAudioEvidenceUploadReceipt.decode(JSONSerialization.data(withJSONObject: row.merging(patch) { _, new in new }), request: prepared)
            }
        }
        for patch: [String: Any] in [["kind": "image"], ["content_type": "audio/mp4"], ["byte_count": true],
            ["byte_count": 48], ["sha256": String(repeating: "a", count: 64)], ["media_id": Self.analysis.uuidString.lowercased()], ["url": "forbidden"]] {
            var changed = row
            changed["items"] = [items[0].merging(patch) { _, new in new }]
            #expect(throws: (any Error).self) {
                try ObservationAudioEvidenceUploadReceipt.decode(JSONSerialization.data(withJSONObject: changed), request: prepared)
            }
        }
        let good = try JSONSerialization.data(withJSONObject: row)
        #expect(try ObservationAudioEvidenceUploadReceipt.decode(good, request: prepared).reference == prepared.reference)
        #expect(throws: (any Error).self) {
            try ObservationAudioEvidenceUploadReceipt.decode(good + Data(repeating: 32, count: 4097 - good.count), request: prepared)
        }
    }
    @Test func malformedAudioNeverReachesTransport() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        await confirmation("No malformed audio upload", expectedCount: 0) { sent in
            fixture.transport.register(path: "/upload-observation-audio") { wire in
                sent(); return try NetworkEndpointTestSupport.response(to: wire, json: "{}")
            }
            await #expect(throws: (any Error).self) {
                try await fixture.client.uploadObservationAudioEvidence(.init(observationID: Self.observation,
                    analysisID: Self.analysis, mediaID: Self.media, bytes: Data(repeating: 0, count: 46)), ownerID: owner, validateAttempt: {})
            }
        }
    }
    @Test func endpointSendsOneExactBinaryFrame() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let input = try Self.input(), prepared = try input.prepare()
        let response = try #require(String(data: JSONSerialization.data(withJSONObject: Self.row(prepared)), encoding: .utf8))
        fixture.transport.register(path: "/upload-observation-audio") { wire in
            #expect(wire.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
            #expect(wire.timeoutInterval == 130)
            #expect(wire.value(forHTTPHeaderField: IdentificationRecipientExpectation.header) == nil)
            #expect(wire.value(forHTTPHeaderField: IdentificationDispatchAuthorization.protocolHeader) == nil)
            #expect(MockURLProtocol.bodyData(for: wire) == prepared.body)
            return try NetworkEndpointTestSupport.response(to: wire, json: response)
        }
        #expect(try await fixture.client.uploadObservationAudioEvidence(input, ownerID: owner, validateAttempt: {}).reference == prepared.reference)
    }
    @Test(arguments: [401, 404, 503, -1]) func ambiguousFailuresDoNotRetryOrRefresh(_ status: Int) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID)
        let calls = OSAllocatedUnfairLock(initialState: 0), refreshes = OSAllocatedUnfairLock(initialState: 0)
        fixture.client.overridingAuthSessionRefresh = { refreshes.withLock { $0 += 1 }; return true }
        fixture.transport.register(path: "/upload-observation-audio") { wire in
            calls.withLock { $0 += 1 }
            if status == -1 { throw URLError(.networkConnectionLost) }
            return try NetworkEndpointTestSupport.response(to: wire, status: status, json: #"{"code":"invalid_session_token"}"#)
        }
        await #expect(throws: (any Error).self) { try await fixture.client.uploadObservationAudioEvidence(Self.input(), ownerID: owner, validateAttempt: {}) }
        #expect(calls.withLock { $0 } == 1); #expect(refreshes.withLock { $0 } == 0)
    }
    @Test(arguments: [1, 2, 3, 4]) func staleClaimStopsPreparationDispatchOrReceipt(_ phase: Int) async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        let owner = try #require(fixture.client.overridingAuthUserID), input = try Self.input()
        let response = try #require(String(data: JSONSerialization.data(withJSONObject: Self.row(input.prepare())), encoding: .utf8))
        let sent = OSAllocatedUnfairLock(initialState: 0)
        fixture.transport.register(path: "/upload-observation-audio") { wire in
            sent.withLock { $0 += 1 }
            return try NetworkEndpointTestSupport.response(to: wire, json: response)
        }
        var validations = 0
        await #expect(throws: CancellationError.self) {
            try await fixture.client.uploadObservationAudioEvidence(input, ownerID: owner) {
                validations += 1
                if validations == phase { throw CancellationError() }
            }
        }
        #expect(validations == phase)
        #expect(sent.withLock { $0 } == (phase == 4 ? 1 : 0))
    }
    @Test func missingAccountDoesNotDispatch() async throws {
        let fixture = NetworkEndpointFixture(); defer { fixture.close() }
        fixture.client.overridingAuthUserID = nil
        await confirmation("No upload without account", expectedCount: 0) { sent in
            fixture.transport.register(path: "/upload-observation-audio") { wire in
                sent(); return try NetworkEndpointTestSupport.response(to: wire, json: "{}")
            }
            await #expect(throws: SupabaseAuthTransitionError.signOutSessionChanged) {
                try await fixture.client.uploadObservationAudioEvidence(Self.input(), ownerID: UUID(), validateAttempt: {})
            }
        }
    }
}
