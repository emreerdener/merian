import Foundation
import Testing
@testable import Merian

@Suite("Observation Reanalysis Request")
struct ObservationReanalysisRequestTests {
    private static let observation = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    private static let analysis = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    private static let source = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    private static let photo = ObservationEvidenceUpload.Reference(
        mediaID: UUID(uuidString: "00000000-0000-4000-8000-000000000005")!,
        contentType: "image/jpeg", byteCount: 3,
        sha256: "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")

    private static func request(_ evidence: [ObservationReanalysisRequest.Evidence] = [.image(photo)],
                                processor: IdentificationRecipientExpectation = .gemini) throws -> ObservationReanalysisRequest {
        try .init(observationID: observation, analysisID: analysis, sourceAnalysisID: source,
                  processor: processor, evidence: evidence)
    }

    @Test func exactBodyAndRestorationPreserveOrderedEvidenceAndIdentity() throws {
        let input = try Self.request([.description("leaf / café 🌱"), .image(Self.photo), .description("after")])
        #expect(try ObservationReanalysisRequest(savedBody: input.body) == input)
        let row = try #require(JSONSerialization.jsonObject(with: input.body) as? [String: Any])
        #expect(Set(row.keys) == ["schema_version", "observation_id", "analysis_id", "source_analysis_id",
                                  "request_digest", "evidence_manifest", "entitlement_protocol",
                                  "identification_protocol", "history_protocol", "expected_processor_permission"])
        #expect(row["source_analysis_id"] as? String == Self.source.uuidString.lowercased())
        #expect(row["history_protocol"] as? Int == 8)
        #expect(row["request_digest"] as? String == "7648c02e6a299aeaf2fe22582cfd67e085d896ecba841a485fee637597394098")
        #expect(input.body == (try Self.request(input.evidence).body))
        // Recovered bytes are not reserialized, even if an older writer formatted them differently.
        let formatted = try JSONSerialization.data(withJSONObject: row, options: [.prettyPrinted, .sortedKeys])
        #expect(try ObservationReanalysisRequest(savedBody: formatted).body == formatted)
        #expect(try Self.request(input.evidence, processor: .openAI).body != input.body)
        #expect(try Self.request(Array(input.evidence.reversed())).body != input.body)
    }

    @Test func restorationRejectsMutationUnknownFieldsAndBooleanProtocols() throws {
        let input = try Self.request()
        let row = try #require(JSONSerialization.jsonObject(with: input.body) as? [String: Any])
        for patch: [String: Any] in [["source_analysis_id": UUID().uuidString.lowercased()],
                                    ["schema_version": true], ["history_protocol": 7],
                                    ["expected_processor_permission": "recovery_only"],
                                    ["owner_id": UUID().uuidString.lowercased()],
                                    ["request_digest": String(repeating: "a", count: 64)]] {
            let modified = row.merging(patch) { _, new in new }
            #expect(throws: (any Error).self) {
                try ObservationReanalysisRequest(savedBody: JSONSerialization.data(withJSONObject: modified))
            }
        }
    }

    @Test func admissionRejectsAliasesMissingPhotosAndUnsupportedEvidence() throws {
        #expect(throws: (any Error).self) { try Self.request(processor: .recoveryOnly) }
        #expect(throws: (any Error).self) {
            try ObservationReanalysisRequest(observationID: Self.observation, analysisID: Self.analysis,
                sourceAnalysisID: Self.analysis, processor: .gemini, evidence: [.image(Self.photo)])
        }
        for evidence: [ObservationReanalysisRequest.Evidence] in [[], [.description("leaf")],
            [.image(Self.photo), .image(Self.photo)], [.image(Self.photo), .description("  \n")],
            [.image(.init(mediaID: Self.photo.mediaID, contentType: "image/heic", byteCount: 3, sha256: Self.photo.sha256))],
            [.image(.init(mediaID: Self.analysis, contentType: "image/jpeg", byteCount: 3, sha256: Self.photo.sha256))],
            [.image(.init(mediaID: Self.photo.mediaID, contentType: "image/jpeg", byteCount: 0, sha256: Self.photo.sha256))],
            [.image(Self.photo), .description(String(repeating: "e\u{301}", count: 4097))],
            [.image(Self.photo)] + Array(repeating: .description(String(repeating: "🌱", count: 8192)), count: 2)] {
            #expect(throws: (any Error).self) { try Self.request(evidence) }
        }
    }

    @Test func boundariesUseUnicodeScalarsAndAggregateBytes() throws {
        let maxPhoto = ObservationEvidenceUpload.Reference(mediaID: Self.photo.mediaID, contentType: "image/png",
            byteCount: ObservationEvidenceUpload.maximumBytes, sha256: Self.photo.sha256)
        #expect(try Self.request([.image(maxPhoto), .description(String(repeating: "🌱", count: 8192))]).evidence.count == 2)
        #expect(throws: (any Error).self) {
            try Self.request([.image(maxPhoto), .image(.init(mediaID: UUID(), contentType: "image/jpeg", byteCount: 1, sha256: Self.photo.sha256))])
        }
    }
    @Test(arguments: ObservationAnalysisReceipt.State.allCases)
    func executionReceiptIsExactAndDoesNotPretendToContainAResult(_ state: ObservationAnalysisReceipt.State) throws {
        let input = try Self.request()
        let row: [String: Any] = ["schema_version": 1, "observation_id": Self.observation.uuidString.lowercased(),
            "analysis_id": Self.analysis.uuidString.lowercased(), "state": state.rawValue]
        let bytes = try JSONSerialization.data(withJSONObject: row)
        let atLimit = bytes + Data(repeating: 32, count: 4096 - bytes.count)
        #expect(try ObservationAnalysisReceipt.decode(atLimit, request: input).state == state)
        #expect(throws: (any Error).self) { try ObservationAnalysisReceipt.decode(atLimit + Data([32]), request: input) }
        for patch: [String: Any] in [["schema_version": true], ["state": "published"],
            ["analysis_id": Self.source.uuidString.lowercased()], ["observation_id": Self.analysis.uuidString.lowercased()],
            ["result_snapshot": [:]]] {
            #expect(throws: (any Error).self) {
                try ObservationAnalysisReceipt.decode(JSONSerialization.data(withJSONObject: row.merging(patch) { _, new in new }), request: input)
            }
        }
    }

}
