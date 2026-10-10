import Foundation
@testable import Merian
import Testing

@Suite("Prepared video source reservation parity")
struct ObservationVideoSourceReservationTests {
    private let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000090")!
    private func fixtures(_ name: String) throws -> [[String: Any]] {
        let source = try DatabaseActorTestSupport.loadRepositorySource(
            at: "services/supabase/functions/_shared/analysisHistory/fixtures/\(name).json")
        return try #require(JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]])
    }
    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    private func identity(_ index: Int = 0) throws -> ObservationVideoSourceIdentity {
        try .init(input: data(#require(fixtures("video-source-fingerprint-v1")[index]["input"])))
    }
    private func replies(_ index: Int = 0) throws -> [[String: Any]] {
        try #require(fixtures("video-source-reservation-v2")[index]["replies"] as? [[String: Any]])
    }

    @Test func sharedAudioSilentAndUnicodeIdentitiesAndAllReplies() throws {
        let vectors = try fixtures("video-source-reservation-v2")
        #expect(vectors.count == 3)
        #expect(ObservationVideoSourceIdentity.readerVersion == 12)
        for index in vectors.indices {
            let target = try identity(index)
            #expect(try target.recoveryBody() == data(#require(vectors[index]["identity"])))
            #expect(try target.recoveryBody().count <= 2048)
            let rows = try replies(index)
            #expect(rows.count == 7)
            let decoded = try rows.map { try ObservationVideoSourceReservationReply(data: data($0), identity: target, ownerID: owner) }
            #expect(decoded[0].state == .reserved)
            #expect(decoded[1].state == .unavailable)
            #expect(Set(rows.dropFirst(2).compactMap { $0["reason"] as? String }) == Set(ObservationVideoSourceReservationReply.Hold.allCases.map(\.rawValue)))
            for (row, reply) in zip(rows, decoded) {
                #expect(reply.data == (try data(row)))
                #expect(reply.identity == target && reply.ownerID == owner)
                if let raw = row["reason"] as? String {
                    #expect(reply.state == .held(try #require(ObservationVideoSourceReservationReply.Hold(rawValue: raw))))
                }
            }
        }
    }

    @Test func exactSavedInputAndEnvelopeSurviveRestoration() throws {
        for vector in try fixtures("video-request-v4") {
            let row = try #require(vector["input"] as? [String: Any])
            let pretty = try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            let video = try ObservationVideoReanalysisRequest(savedBody: pretty)
            let request = try ObservationVideoSourceReservationRequest(video: video)
            #expect(request.input == pretty)
            let expected = Data("{\"schema_version\":2,\"input\":".utf8) + pretty
                + Data(",\"fingerprint_version\":1,\"fingerprint\":\"\(request.identity.fingerprint)\"}".utf8)
            #expect(request.body == expected)
            #expect(try ObservationVideoSourceReservationRequest(savedInput: pretty, savedBody: expected) == request)
            #expect(throws: (any Error).self) {
                try ObservationVideoSourceReservationRequest(savedInput: data(row), savedBody: expected)
            }
            #expect(throws: (any Error).self) {
                try ObservationSourceReservationRequest(savedInput: pretty, savedBody: expected)
            }
            for bad in [Data(), expected + Data(" ".utf8), Data(repeating: 32, count: 1_048_577)] {
                #expect(throws: (any Error).self) { try ObservationVideoSourceReservationRequest(savedInput: pretty, savedBody: bad) }
            }
            var changed = row; changed["request_digest"] = String(repeating: "0", count: 64)
            #expect(throws: (any Error).self) {
                try ObservationVideoSourceReservationRequest(savedInput: data(changed), savedBody: expected)
            }
        }
    }

    @Test func directVideoInputRejectsFoundationAlternateEncodings() throws {
        let vector = try #require(fixtures("video-request-v4").first)
        let text = try #require(vector["canonical_body"] as? String)
        for encoding in [String.Encoding.utf16, .utf32] {
            let encoded = try #require(text.data(using: encoding))
            // Foundation support differs by platform; rejection at either boundary is safe.
            #expect(throws: (any Error).self) { try ObservationVideoSourceIdentity(input: encoded) }
            if let video = try? ObservationVideoReanalysisRequest(savedBody: encoded) {
                #expect(throws: (any Error).self) { try ObservationVideoSourceReservationRequest(video: video) }
            }
        }
        #expect(throws: (any Error).self) { try ObservationVideoSourceIdentity(input: Data(repeating: 32, count: 1_044_481)) }
    }

    @Test func everyReplyStateRequiresEveryIdentityFieldAndOwner() throws {
        let target = try identity()
        for row in try replies() {
            for key in ["schema_version", "observation_id", "source_analysis_id", "analysis_id", "request_digest", "fingerprint_version", "fingerprint", "owner_id"] {
                var changed = row; changed.removeValue(forKey: key)
                #expect(throws: (any Error).self) { try ObservationVideoSourceReservationReply(data: data(changed), identity: target, ownerID: owner) }
                changed[key] = "wrong"
                #expect(throws: (any Error).self) { try ObservationVideoSourceReservationReply(data: data(changed), identity: target, ownerID: owner) }
            }
            #expect(throws: (any Error).self) { try ObservationVideoSourceReservationReply(data: data(row), identity: identity(1), ownerID: owner) }
            #expect(throws: (any Error).self) { try ObservationVideoSourceReservationReply(data: data(row), identity: target, ownerID: UUID()) }
        }
    }

    @Test func closedStatesReasonsAndStrictScalarTypes() throws {
        let target = try identity(), row = try replies()[0]
        let patches: [[String: Any]] = [
            ["schema_version": 1], ["schema_version": true], ["schema_version": 2.5], ["fingerprint_version": true],
            ["fingerprint_version": "1"], ["state": "not_found"], ["state": "retired_unfunded"],
            ["state": "complete"], ["state": "dispatched"], ["state": "held"],
            ["state": "held", "reason": "unknown"], ["reason": "source_occupied"], ["operation_id": UUID().uuidString]
        ]
        for patch in patches {
            #expect(throws: (any Error).self) {
                try ObservationVideoSourceReservationReply(data: data(row.merging(patch) { _, new in new }), identity: target, ownerID: owner)
            }
        }
    }

    @Test func byteBoundsAndStrictUTF8RejectAlternateEncodings() throws {
        let target = try identity(), valid = try data(replies()[0])
        let text = try #require(String(data: valid, encoding: .utf8))
        for bad in [Data(), Data(repeating: 32, count: 2049), Data([0xc3, 0x28]), Data("[]".utf8),
                    Data("{".utf8), try #require(text.data(using: .utf16))] {
            #expect(throws: (any Error).self) { try ObservationVideoSourceReservationReply(data: bad, identity: target, ownerID: owner) }
        }
    }
}
