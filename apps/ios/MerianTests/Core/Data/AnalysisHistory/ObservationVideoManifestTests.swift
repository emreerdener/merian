import Foundation
@testable import Merian
import Testing

@Suite("Private video manifest parity")
struct ObservationVideoManifestTests {
    private func vectors() throws -> [[String: Any]] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at: "services/supabase/functions/_shared/analysisHistory/fixtures/video-manifest-v4.json")
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }

    private func identifier(_ vector: [String: Any], _ key: String) throws -> UUID {
        let string = try #require(vector[key] as? String)
        return try #require(UUID(uuidString: string))
    }

    private func decode(_ vector: [String: Any], pretty: Bool = false) throws -> ObservationVideoManifest {
        let manifest = try #require(vector["manifest"])
        let data = try JSONSerialization.data(withJSONObject: manifest, options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys])
        return try ObservationVideoManifest(data: data, observationID: identifier(vector, "observation_id"), analysisID: identifier(vector, "analysis_id"))
    }

    @Test func sharedAcceptanceAndRejectionVectors() throws {
        let fixtures = try vectors()
        #expect(fixtures.count == 40)
        for vector in fixtures {
            let name = try #require(vector["name"] as? String)
            if vector["valid"] as? Bool == true {
                let decoded = try decode(vector)
                #expect(decoded.provenance.frames.count == 5, "\(name)")
                #expect(decoded.provenance.source.mediaID == decoded.provenance.frames[0].sourceMediaID)
            } else {
                #expect(throws: (any Error).self, "\(name)") { try decode(vector) }
            }
        }
    }

    @Test func typedProvenanceAndExactSavedBytes() throws {
        let vector = try #require(vectors().first)
        let compact = try decode(vector)
        let pretty = try decode(vector, pretty: true)
        #expect(compact.originalBytes != pretty.originalBytes)
        #expect(compact.provenance == pretty.provenance)
        #expect(compact.descriptions == ["  synthetic first  ", "🦋 e\u{0301}", "\u{0085}"])
        #expect(compact.provenance.audio?.startTicks == 600)
        #expect(compact.provenance.audio?.endTicks == 1800)
        #expect(compact.provenance.audio?.sampleCount == 88200)
        let restored = try ObservationVideoManifest(data: pretty.originalBytes, observationID: identifier(vector, "observation_id"), analysisID: identifier(vector, "analysis_id"))
        #expect(restored == pretty)
    }

    @Test func canonicalEncoderRoundTripsEveryAcceptedGoldenVector() throws {
        for vector in try vectors() where vector["valid"] as? Bool == true {
            let original = try decode(vector)
            let graph = original.provenance
            let rebuilt = try ObservationVideoManifest.prepared(source: graph.source, parameters: graph.parameters,
                                                               frames: graph.frames, audio: graph.audio, descriptions: original.descriptions,
                                                               observationID: identifier(vector, "observation_id"), analysisID: identifier(vector, "analysis_id"))
            #expect(rebuilt.provenance == graph)
            #expect(rebuilt.descriptions == original.descriptions)
            let request = try ObservationVideoReanalysisRequest(observationID: identifier(vector, "observation_id"),
                                                                analysisID: identifier(vector, "analysis_id"), sourceAnalysisID: UUID(), manifestBytes: rebuilt.originalBytes)
            #expect(request.manifest == rebuilt)
            #expect(try ObservationVideoReanalysisRequest(savedBody: request.body) == request)
        }
    }

    @Test func encoderRejectsDuplicateArtifactsAndWrongSourceLink() throws {
        let vector = try #require(vectors().first)
        let original = try decode(vector)
        let graph = original.provenance
        for crossSource in [false, true] {
            var frames = graph.frames
            let frame = frames[1]
            frames[1] = .init(index: frame.index, sourceMediaID: crossSource ? UUID() : frame.sourceMediaID,
                              requestedTimeTicks: frame.requestedTimeTicks, actualTimeTicks: frame.actualTimeTicks,
                              artifact: crossSource ? frame.artifact : frames[0].artifact)
            #expect(throws: (any Error).self) {
                try ObservationVideoManifest.prepared(source: graph.source, parameters: graph.parameters, frames: frames,
                                                      audio: graph.audio, descriptions: original.descriptions,
                                                      observationID: identifier(vector, "observation_id"), analysisID: identifier(vector, "analysis_id"))
            }
        }
    }

    @Test func boundedDecoderAndIdentityScope() throws {
        let vector = try #require(vectors().first)
        let value = try decode(vector)
        let owner = try #require(UUID(uuidString: vector["observation_id"] as? String ?? ""))
        for bytes in [Data(), Data(repeating: 32, count: 1_044_481)] {
            #expect(throws: (any Error).self) { try ObservationVideoManifest(data: bytes, observationID: owner, analysisID: UUID()) }
        }
        #expect(throws: (any Error).self) { try ObservationVideoManifest(data: value.originalBytes, observationID: owner, analysisID: owner) }
        #expect(throws: (any Error).self) { try ObservationVideoManifest(data: value.originalBytes, observationID: owner, analysisID: value.provenance.source.mediaID) }
        #expect(throws: (any Error).self) { try ObservationAudioReanalysisRequest(savedBody: value.originalBytes) }
    }
}

extension ObservationVideoManifestTests {
    @Test func sharedResult5VectorsKeepInputAndResultVersionsSeparate() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/video-result-v5.json")
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let vectors = try #require(fixture["cases"] as? [[String: Any]])
        let manifests = try self.vectors()
        #expect(vectors.count == 51)
        for vector in vectors {
            var snapshot = try #require(fixture["base_snapshot"] as? [String: Any])
            let manifest = manifests[try #require(vector["manifest_index"] as? Int)]
            snapshot["evidence_manifest"] = manifest["manifest"]
            snapshot["observation_id"] = manifest["observation_id"]
            snapshot["analysis_id"] = manifest["analysis_id"]
            snapshot["source_analysis_id"] = vector["source_analysis_id"]
            snapshot["schema_version"] = vector["schema_version"]
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
            let observation = try #require(snapshot["observation_id"] as? String)
            let name = try #require(vector["name"] as? String)
            if vector["valid"] as? Bool == true {
                let result = try ObservationHistoryPage.snapshot(data, observationID: observation, ordinal: 1)
                #expect(result.version == 5 && result.video != nil, "\(name)")
                #expect(result.bytes == data && result.photos.isEmpty && result.audio == nil)
                #expect(result.video?.provenance.frames.count == 5)
                #expect(result.completedAt != nil && result.importedAt == nil)
            } else {
                #expect(throws: (any Error).self, "\(name)") {
                    try ObservationHistoryPage.snapshot(data, observationID: observation, ordinal: 1)
                }
            }
        }
    }
}
