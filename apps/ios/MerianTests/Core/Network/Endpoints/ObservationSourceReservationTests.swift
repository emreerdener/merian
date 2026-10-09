import Foundation
@testable import Merian
import Testing

struct ObservationSourceReservationTests {
    static let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let observation = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let analysis = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    static let source = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    static let media = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!

    static func candidate(_ kind: String = "audio") throws -> ObservationSourceReservationRequest {
        if kind == "audio" {
            return try .init(audio: .init(observationID: observation, analysisID: analysis, sourceAnalysisID: source,
                evidence: [.description("before / 🌱"), .audio(.init(mediaID: media, contentType: "audio/wav",
                    byteCount: 46, sha256: String(repeating: "a", count: 64)))]))
        }
        return try .init(photo: .init(observationID: observation, analysisID: analysis, sourceAnalysisID: source,
            processor: kind == "openai" ? .openAI : .gemini,
            evidence: [.image(.init(mediaID: media, contentType: "image/jpeg", byteCount: 46,
                sha256: String(repeating: "a", count: 64))), .description("after / 🌱")]))
    }

    static func receipt(_ candidate: ObservationSourceReservationRequest, state: String = "reserved") -> [String: Any] {
        var row: [String: Any] = ["schema_version": 1, "owner_id": owner.uuidString.lowercased(),
            "observation_id": candidate.observationID.uuidString.lowercased(),
            "source_analysis_id": candidate.sourceAnalysisID.uuidString.lowercased(), "state": state]
        if state == "reserved" {
            row["analysis_id"] = candidate.analysisID.uuidString.lowercased()
            row["request_digest"] = candidate.requestDigest
            row["fingerprint_version"] = 1; row["fingerprint"] = candidate.fingerprint
        }
        if state == "held" { row["reason"] = "source_occupied" }
        return row
    }

    @Test(arguments: ["audio", "gemini", "openai"])
    func exactSavedInputAndCandidateSurviveRecovery(kind: String) throws {
        let candidate = try Self.candidate(kind)
        let row = try #require(JSONSerialization.jsonObject(with: candidate.input) as? [String: Any])
        let formatted = try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys])
        let spaced = try kind == "audio"
            ? ObservationSourceReservationRequest(audio: .init(savedBody: formatted))
            : ObservationSourceReservationRequest(photo: .init(savedBody: formatted))
        #expect(spaced.input == formatted && spaced.body.range(of: formatted) != nil)
        #expect(spaced.fingerprint == candidate.fingerprint && spaced.requestDigest == candidate.requestDigest)
        #expect(try ObservationSourceReservationRequest(savedInput: spaced.input, savedBody: spaced.body) == spaced)
        #expect(throws: (any Error).self) {
            try ObservationSourceReservationRequest(savedInput: spaced.input, savedBody: candidate.body)
        }
        let wire = try #require(JSONSerialization.jsonObject(with: candidate.body) as? [String: Any])
        #expect(Set(wire.keys) == ["schema_version", "input", "fingerprint_version", "fingerprint"])
        #expect(wire["fingerprint"] as? String == (try ObservationSourceFingerprint(input: candidate.input).sha256))
    }

    @Test func corruptSavedCandidateNeverRestoresFromCurrentInput() throws {
        let candidate = try Self.candidate()
        for data in [Data(), Data("{}".utf8), candidate.body + Data(" ".utf8),
                     Data(repeating: 32, count: ObservationSourceReservationRequest.maximumBytes + 1)] {
            #expect(throws: (any Error).self) { try ObservationSourceReservationRequest(savedInput: candidate.input, savedBody: data) }
        }
        #expect(throws: (any Error).self) {
            try ObservationSourceReservationRequest(savedInput: Data(repeating: 32, count: 1_044_481), savedBody: candidate.body)
        }
    }

    @Test func maximumSavedInputFitsWithoutTruncation() throws {
        let original = try Self.candidate()
        let input = original.input + Data(repeating: 32, count: 1_044_480 - original.input.count)
        let candidate = try ObservationSourceReservationRequest(audio: .init(savedBody: input))
        #expect(candidate.input == input && candidate.body.count == input.count + 134)
        #expect(candidate.body.count <= ObservationSourceReservationRequest.maximumBytes)
        #expect(try ObservationSourceReservationRequest(savedInput: input, savedBody: candidate.body) == candidate)
        #expect(throws: (any Error).self) { try ObservationAudioReanalysisRequest(savedBody: input + Data(" ".utf8)) }
    }

    @Test(arguments: ["reserved", "held", "unavailable"])
    func exactClosedObservationsRetainRawBytes(state: String) throws {
        let candidate = try Self.candidate(), bytes = try JSONSerialization.data(withJSONObject: Self.receipt(candidate, state: state))
        let reply = try ObservationSourceReservationReply(data: bytes, request: candidate, ownerID: Self.owner)
        let expected: ObservationSourceReservationReply.State = state == "reserved" ? .reserved : state == "held" ? .held(.sourceOccupied) : .unavailable
        #expect(reply.state == expected && reply.data == bytes)
        #expect(reply.request == candidate && reply.ownerID == Self.owner)
    }

    @Test func allHoldReasonsAreClosedAndNoForeignFieldsAreExposed() throws {
        let candidate = try Self.candidate()
        for reason in ["source_occupied", "ambiguous_occupancy", "coverage_incomplete", "malformed_linkage", "terminal_unproven"] {
            var row = Self.receipt(candidate, state: "held"); row["reason"] = reason
            _ = try ObservationSourceReservationReply(data: JSONSerialization.data(withJSONObject: row), request: candidate, ownerID: Self.owner)
        }
        for state in ["held", "unavailable"] {
            var row = Self.receipt(candidate, state: state); row["analysis_id"] = candidate.analysisID.uuidString.lowercased()
            #expect(throws: (any Error).self) {
                try ObservationSourceReservationReply(data: JSONSerialization.data(withJSONObject: row), request: candidate, ownerID: Self.owner)
            }
        }
    }

    @Test func forgedReceiptsAndWrongVariantsFailClosed() throws {
        let candidate = try Self.candidate()
        let patches: [[String: Any]] = [["schema_version": true], ["owner_id": Self.source.uuidString.lowercased()],
            ["observation_id": Self.source.uuidString.lowercased()], ["source_analysis_id": Self.analysis.uuidString.lowercased()],
            ["analysis_id": Self.source.uuidString.lowercased()], ["request_digest": String(repeating: "f", count: 64)],
            ["fingerprint": String(repeating: "f", count: 64)], ["fingerprint_version": true], ["fingerprint_version": 2],
            ["extra": 1], ["state": "retired_unfunded"], ["state": "complete"], ["state": "held", "reason": "unknown"]]
        for patch in patches {
            let row = Self.receipt(candidate).merging(patch) { _, new in new }
            #expect(throws: (any Error).self) {
                try ObservationSourceReservationReply(data: JSONSerialization.data(withJSONObject: row), request: candidate, ownerID: Self.owner)
            }
        }
        let bytes = try JSONSerialization.data(withJSONObject: Self.receipt(candidate))
        let exact = bytes + Data(repeating: 32, count: 2_048 - bytes.count)
        _ = try ObservationSourceReservationReply(data: exact, request: candidate, ownerID: Self.owner)
        #expect(throws: (any Error).self) {
            try ObservationSourceReservationReply(data: exact + Data(" ".utf8), request: candidate, ownerID: Self.owner)
        }
    }
}
