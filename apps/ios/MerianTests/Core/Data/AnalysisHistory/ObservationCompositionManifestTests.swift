import Foundation
@testable import Merian
import Testing

@Suite("Shared toolbar composition contract")
struct ObservationCompositionManifestTests {
    @Test func focusedResultPreservesSelectionAndRequiresMatchingPredecessorAndManifest() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/composition-request-v6.json")
        let vectors = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        let pageText = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/page-v1.json")
        let page = try #require(JSONSerialization.jsonObject(with: Data(pageText.utf8)) as? [String: Any])
        let items = try #require(page["items"] as? [[String: Any]])
        let snapshotText = try #require(items.first?["snapshot"] as? String)
        let baseline = try #require(JSONSerialization.jsonObject(with: Data(snapshotText.utf8)) as? [String: Any])
        for vector in vectors {
            let input = try #require(vector["input"] as? [String: Any])
            let request = try ObservationCompositionReanalysisRequest(savedBody: JSONSerialization.data(withJSONObject: input))
            var snapshot = baseline
            for key in ["observation_id", "analysis_id", "source_analysis_id", "request_digest", "evidence_manifest"] {
                snapshot[key] = input[key]
            }
            snapshot["schema_version"] = 7
            var result = try #require(snapshot["result"] as? [String: Any])
            result["scan_id"] = input["observation_id"]
            snapshot["result"] = result
            let bytes = try JSONSerialization.data(withJSONObject: snapshot)
            let decoded = try ObservationReanalysisResult.decode(bytes, matching: request)
            #expect(decoded.bytes == bytes)
            #expect(decoded.composition?.imageFocusRegions == request.manifest.imageFocusRegions)
            let source = try ObservationCompositionSource(ownerID: UUID(), observationID: request.observationID, result: decoded)
            #expect(source.imageFocusRegions == request.manifest.imageFocusRegions)
            for change: [String: Any] in [["source_analysis_id": NSNull()], ["schema_version": 6], ["schema_version": 8]] {
                var invalid = snapshot
                invalid.merge(change) { _, new in new }
                #expect(throws: (any Error).self) {
                    try ObservationReanalysisResult.decode(JSONSerialization.data(withJSONObject: invalid), matching: request)
                }
            }
        }
    }

    @Test func focusedRequestAndSourceDigestUseTypedSharedVectors() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/composition-request-v6.json")
        let rows = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        for row in rows {
            let bytes = try JSONSerialization.data(withJSONObject: #require(row["input"]), options: [.prettyPrinted, .sortedKeys])
            let request = try ObservationCompositionReanalysisRequest(savedBody: bytes)
            #expect(request.body == bytes)
            #expect(request.requestDigest == row["request_digest"] as? String, "\(row["name"] ?? "")")
            #expect(try request.sourceFingerprint() == row["fingerprint"] as? String, "\(row["name"] ?? "")")
            let rebuilt = try ObservationCompositionReanalysisRequest(observationID: request.observationID,
                analysisID: request.analysisID, sourceAnalysisID: request.sourceAnalysisID, manifestBytes: request.manifest.originalBytes)
            #expect(rebuilt.requestDigest == request.requestDigest)
            #expect(try rebuilt.sourceFingerprint() == request.sourceFingerprint())
        }
    }

    @Test func focusFingerprintUsesSharedBinary64Vectors() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/focus-fingerprint-v2.json")
        let rows = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        for row in rows {
            let bytes = try JSONSerialization.data(withJSONObject: #require(row["focus_region"]))
            let focus = try JSONDecoder().decode(NormalizedImageFocusRegion.self, from: bytes)
            #expect(focus.fingerprintFields == row["fields"] as? [String], "\(row["name"] ?? "")")
        }
    }

    @Test func focusedMetadataHasStrictSharedBoundsAndPairedInputVersion() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/composition-focus-v6.json")
        let rows = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        let vector = try #require(vectors().first(where: { $0["name"] as? String == "photo-audio" }))
        let input = try #require(vector["input"] as? [String: Any])
        let request = try ObservationCompositionReanalysisRequest(savedBody: JSONSerialization.data(withJSONObject: input))
        let original = try #require(input["evidence_manifest"] as? [String: Any])
        let originalItems = try #require(original["items"] as? [[String: Any]])
        for row in rows {
            var items = originalItems
            let index = try #require(items.firstIndex(where: { $0["kind"] as? String == "image" }))
            items[index]["focus_region"] = row["focus_region"]
            let bytes = try JSONSerialization.data(withJSONObject: ["schema_version": 6, "items": items])
            if row["valid"] as? Bool == true {
                let value = try ObservationCompositionManifest(data: bytes, observationID: request.observationID,
                    analysisID: request.analysisID, sourceAnalysisID: request.sourceAnalysisID)
                #expect(value.schemaVersion == 6)
                #expect(value.imageFocusRegions.count == 1)
                #expect(value.imageFocusRegions.values.first?.isValidEvidence == true)
                #expect(value.originalBytes == bytes)
            } else {
                #expect(throws: (any Error).self) {
                    try ObservationCompositionManifest(data: bytes, observationID: request.observationID,
                        analysisID: request.analysisID, sourceAnalysisID: request.sourceAnalysisID)
                }
            }
            if row["valid"] as? Bool == true {
                let focused = try ObservationCompositionReanalysisRequest(observationID: request.observationID,
                    analysisID: request.analysisID, sourceAnalysisID: request.sourceAnalysisID, manifestBytes: bytes)
                #expect(focused.manifest.schemaVersion == 6)
                #expect(try ObservationCompositionReanalysisRequest(savedBody: focused.body) == focused)
            } else {
                #expect(throws: (any Error).self) {
                    try ObservationCompositionReanalysisRequest(observationID: request.observationID,
                        analysisID: request.analysisID, sourceAnalysisID: request.sourceAnalysisID, manifestBytes: bytes)
                }
            }
            let old = try JSONSerialization.data(withJSONObject: ["schema_version": 5, "items": items])
            #expect(throws: (any Error).self) {
                try ObservationCompositionManifest(data: old, observationID: request.observationID,
                    analysisID: request.analysisID, sourceAnalysisID: request.sourceAnalysisID)
            }
        }
    }

    @Test func rawUnicodeSurrogatesMatchEdgeValidation() throws {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/composition-text-v5.json")
        let rows = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        let observation = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000001"))
        let child = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000002"))
        let source = try #require(UUID(uuidString: "00000000-0000-4000-8000-000000000003"))
        for row in rows {
            let data = Data(try #require(row["manifest_utf8"] as? String).utf8)
            if row["valid"] as? Bool == true {
                let value = try ObservationCompositionManifest(data: data, observationID: observation, analysisID: child, sourceAnalysisID: source)
                #expect(value.items.last == .description("🦋"))
            } else {
                #expect(throws: (any Error).self) {
                    try ObservationCompositionManifest(data: data, observationID: observation, analysisID: child, sourceAnalysisID: source)
                }
            }
        }
    }

    private func vectors() throws -> [[String: Any]] {
        let text = try DatabaseActorTestSupport.loadRepositorySource(at:
            "services/supabase/functions/_shared/analysisHistory/fixtures/composition-request-v5.json")
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
    }

    @Test func sharedAcceptanceRejectionAndSemanticFingerprint() throws {
        let values = try vectors()
        #expect(values.count == 18)
        for vector in values {
            let name = try #require(vector["name"] as? String)
            let bytes = try JSONSerialization.data(withJSONObject: #require(vector["input"]), options: [.sortedKeys, .withoutEscapingSlashes])
            if vector["valid"] as? Bool == true {
                let request = try ObservationCompositionReanalysisRequest(savedBody: bytes)
                #expect(try request.sourceFingerprint() == vector["fingerprint"] as? String, "\(name)")
                #expect(request.body == bytes)
                let rebuilt = try ObservationCompositionReanalysisRequest(observationID: request.observationID,
                    analysisID: request.analysisID, sourceAnalysisID: request.sourceAnalysisID,
                    manifestBytes: request.manifest.originalBytes)
                #expect(try rebuilt.sourceFingerprint() == request.sourceFingerprint())
            } else {
                #expect(throws: (any Error).self, "\(name)") { try ObservationCompositionReanalysisRequest(savedBody: bytes) }
            }
        }
    }

    @Test func savedBodyIsPreservedAndCannotChangeUnderTheSameDigest() throws {
        let value = try #require(vectors().first(where: { $0["name"] as? String == "photo-audio" }))
        var input = try #require(value["input"] as? [String: Any])
        let pretty = try JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let original = try ObservationCompositionReanalysisRequest(savedBody: pretty)
        #expect(original.body == pretty)
        var manifest = try #require(input["evidence_manifest"] as? [String: Any])
        let items = try #require(manifest["items"] as? [Any])
        manifest["items"] = Array(items.reversed())
        input["evidence_manifest"] = manifest
        let changed = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: (any Error).self) { try ObservationCompositionReanalysisRequest(savedBody: changed) }
    }

    @Test func compositionCannotBeReadAsAnOlderSubmissionFormat() throws {
        for vector in try vectors() where vector["valid"] as? Bool == true {
            let bytes = try JSONSerialization.data(withJSONObject: #require(vector["input"]), options: [.sortedKeys, .withoutEscapingSlashes])
            #expect(throws: (any Error).self) { try ObservationVideoReanalysisRequest(savedBody: bytes) }
            #expect(throws: (any Error).self) { try ObservationAudioReanalysisRequest(savedBody: bytes) }
        }
    }
}
