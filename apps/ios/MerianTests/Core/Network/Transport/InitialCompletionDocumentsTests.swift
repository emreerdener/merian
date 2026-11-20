import CryptoKit
import Foundation
@testable import Merian
import Testing

private final class InitialCompletionBundleAnchor: NSObject {}

struct InitialCompletionStatusTestFixture: Decodable, Sendable {
    struct Reply: Decodable, Sendable { let name: String, outcome: String, bytes: String; let result_canonical: String? }
    let original: InitialCompletionDocuments.CpmBinding
    let acknowledgement: String
    let replies: [Reply]
    static func load() throws -> Self {
        struct Envelope: Decodable { let status_reply: InitialCompletionStatusTestFixture }
        let url = try #require(Bundle(for: InitialCompletionBundleAnchor.self)
            .url(forResource: "InitialCompletionFixtures", withExtension: "json"))
        return try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url)).status_reply
    }
}

@Suite("Private initial completion document parity")
struct InitialCompletionDocumentsTests {
    @Test func statusReplyPreservesOriginalBytesAndRejectsMixedOrForeignFacts() throws {
        let fixture = try InitialCompletionStatusTestFixture.load()
        let admission = try InitialCompletionDocuments.CpmAdmission(acknowledgement: Data(fixture.acknowledgement.utf8), original: fixture.original)
        #expect(fixture.replies.count == 3)
        for reply in fixture.replies {
            let bytes = Data(reply.bytes.utf8)
            let value = try InitialCompletionDocuments.statusAcquisition(bytes, admission: admission)
            #expect((value != nil) == (reply.outcome == "found"))
            if let expected = reply.result_canonical { #expect(value?.result.result == Data(expected.utf8)) }
            let fields = try #require(InitialAnalysisCanonical.parse(bytes).object)
            var variants: [[String: InitialAnalysisCanonical.Value]] = []
            var extra = fields; extra["legacy"] = .boolean(true); variants.append(extra)
            var absent = fields; absent.removeValue(forKey: "reference_canonical"); variants.append(absent)
            var foreign = fields; foreign["admission_canonical"] = .string("{}"); variants.append(foreign)
            var mixed = fields; mixed["result_digest"] = reply.outcome == "found" ? .null : .string(String(repeating: "0", count: 64)); variants.append(mixed)
            var unknown = fields; unknown["outcome"] = .string("unknown"); variants.append(unknown)
            for variant in variants {
                let changed = try InitialAnalysisCanonical.encode(.object(variant))
                #expect(throws: (any Error).self) { try InitialCompletionDocuments.statusAcquisition(changed, admission: admission) }
            }
        }
    }

    @Test func statusEnvelopeHasSeparateBoundWithoutWideningInnerDocuments() throws {
        let escaped = Data(("{\"a\":\"" + String(repeating: "\\\"", count: 600_000) + "\"}").utf8)
        #expect(escaped.count > InitialAnalysisCanonical.maximumBytes)
        #expect(throws: (any Error).self) { try InitialAnalysisCanonical.parse(escaped) }
        let parsed = try InitialAnalysisCanonical.parseCompletionStatus(escaped)
        #expect(parsed.object?["a"]?.string?.utf8.count == 600_000)
        #expect(throws: (any Error).self) { try InitialAnalysisCanonical.encode(parsed) }
        let oversized = Data(repeating: 32, count: InitialCompletionDocuments.statusResponseMaximumBytes + 1)
        #expect(throws: (any Error).self) { try InitialAnalysisCanonical.parseCompletionStatus(oversized) }
    }
    private struct Fixtures: Decodable {
        struct Document: Decodable { let name: String; let valid: Bool; let receipt: String; let projection: String }
        struct Canonical: Decodable { let text: String; let valid: Bool }
        let documents: [Document]
        let canonical: [Canonical]
        struct Admissions: Decodable {
            struct Document: Decodable { let name: String; let valid: Bool; let acknowledgement: String }
            let original: InitialCompletionDocuments.CpmBinding
            let admission: String
            let documents: [Document]
        }
        struct RecoveryRecord: Decodable {
            let reference: String, provenance: String, receipt: String, projection: String, encoded: String
            let maximum_bytes: Int
        }
        struct RetainedResult: Decodable {
            struct Evidence: Decodable {
                let reference: [String: String]
                let result_canonical: String, provenance_canonical: String, result_digest: String, provenance_digest: String
            }
            let name: String, valid: Bool, reference: [String: String], original_provenance: String
            let evidence: Evidence
        }
        let retained_results: [RetainedResult]
        let recovery_record: RecoveryRecord
        let admissions: Admissions
    }
    private func fixtures() throws -> Fixtures {
        let url = try #require(Bundle(for: InitialCompletionBundleAnchor.self)
            .url(forResource: "InitialCompletionFixtures", withExtension: "json"))
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    @Test func retainedResultVectorsRequireFrozenSchemaOriginalFactsAndDigests() throws {
        let vectors = try fixtures().retained_results
        let acceptedCount = vectors.filter { $0.valid }.count
        #expect(vectors.count == 37 && acceptedCount == 14)
        for vector in vectors {
            func reference(_ fields: [String: String]) throws -> Data {
                try InitialAnalysisCanonical.encode(.object(fields.mapValues { .string($0) }))
            }
            let evidence = vector.evidence
            let result = Data(evidence.result_canonical.utf8), provenance = Data(evidence.provenance_canonical.utf8)
            let receivedReference = try reference(evidence.reference), expectedReference = try reference(vector.reference)
            let decoded = try? InitialRetainedResult(reference: receivedReference, result: result, provenance: provenance,
                resultDigest: evidence.result_digest, provenanceDigest: evidence.provenance_digest,
                expectedReference: expectedReference, originalProvenance: Data(vector.original_provenance.utf8))
            #expect((decoded != nil) == vector.valid, "Frozen result vector: \(vector.name)")
            if let decoded {
                #expect(decoded.reference == receivedReference && decoded.result == result && decoded.provenance == provenance)
                #expect(decoded.resultDigest == evidence.result_digest && decoded.provenanceDigest == evidence.provenance_digest)
            }
        }
    }

    @MainActor @Test func frozenResultCreatesOnlyAnUnownedUnsavedProjection() throws {
        let vectors = try fixtures().retained_results.filter(\.valid)
        let speciesID = "00000000-0000-4000-8000-000000000888"
        let timestamp = Date(timeIntervalSince1970: 12345), captured = Date(timeIntervalSince1970: 12000)
        let notes = "\u{FEFF}e\u{0301}/🦋"
        #expect(vectors.count == 14)
        for vector in vectors {
            let evidence = vector.evidence
            let reference = try InitialAnalysisCanonical.encode(.object(evidence.reference.mapValues { .string($0) }))
            let result = try InitialRetainedResult(reference: reference, result: Data(evidence.result_canonical.utf8),
                provenance: Data(evidence.provenance_canonical.utf8), resultDigest: evidence.result_digest,
                provenanceDigest: evidence.provenance_digest, expectedReference: reference,
                originalProvenance: Data(vector.original_provenance.utf8))
            let record = try LocalScanRecordFactory.makeInitialRecord(from: result, speciesID: speciesID,
                timestamp: timestamp, captureDate: captured, capturedMediaJSON: nil, coverImagePath: nil, fieldNotes: notes)
            #expect(record.id == vector.reference["scan_id"])
            #expect(record.timestamp == timestamp && record.captureDate == captured)
            #expect(record.fieldNotes.map { Data($0.utf8) } == Data(notes.utf8))
            #expect(record.mediaAuthorityRaw == "legacy" && record.sharedMediaConsumerID == nil)
            #expect(record.selectedAnalysisID == nil && record.analysisOwnerAccountID == nil && record.observationStateRevision == nil)
            #expect(record.analysisSelectionInitialized && !record.userConfirmedIdentification)
            let reasoning = vector.name == "exact_unicode_bytes" ? "\u{FEFF}e\u{0301} synthetic 🦋" : "Synthetic identification fixture."
            #expect(record.aiReasoning.map { Data($0.utf8) } == Data(reasoning.utf8))
            if let candidates = record.candidatesData {
                let raw = try #require(JSONSerialization.jsonObject(with: candidates) as? [[String: Any]])
                #expect(raw.first?["scientific_name"] as? String == "Danaus gilippus")
                #expect(raw.first?["confidence_score"] as? Double == 0.2)
                let display = try JSONDecoder().decode([IdentificationCandidate].self, from: candidates)
                #expect(display.first?.scientificName == "Danaus gilippus" && display.first?.confidenceScore == 0.2)
                let legacy = try JSONEncoder().encode(display)
                let reopened = try JSONDecoder().decode([IdentificationCandidate].self, from: legacy)
                #expect(reopened.first?.scientificName == display.first?.scientificName)
            }
            #expect(record.commonName == "Monarch Butterfly")
            if vector.name == "primary_unresolved_biological" || vector.name == "primary_non_biological" {
                #expect(record.scientificName == "Taxonomy Unavailable" && record.speciesId.isEmpty)
            } else {
                #expect(record.scientificName == "Danaus plexippus")
            }
            if vector.name.hasPrefix("primary_") {
                #expect(record.primaryIdentification?.value != nil)
                #expect(record.speciesId == (vector.name == "primary_species" ? speciesID : ""))
            }
            if vector.name.hasPrefix("decimal_") {
                let spelling = String(vector.name.dropFirst("decimal_".count))
                #expect(record.confidenceScore == Double(spelling))
            }
            struct Provenance: Decodable { let version: Int; let provider: String }
            let stored = try #require(record.identificationProvenanceData)
            let provenance = try JSONDecoder().decode(Provenance.self, from: stored)
            #expect([1, 2].contains(provenance.version) && ["openai", "gemini"].contains(provenance.provider))
            #expect(result.result == Data(evidence.result_canonical.utf8) && result.provenance == Data(evidence.provenance_canonical.utf8))
        }
    }

    @MainActor @Test func frozenProjectionPreservesRankedCandidatesAndPetForSavedBaseline() throws {
        let vector = try #require(fixtures().retained_results.first { $0.name == "primary_species" })
        var document = try #require(InitialAnalysisCanonical.parse(Data(vector.evidence.result_canonical.utf8)).object)
        var fields = try #require(document["data"]?.object)
        let primary: InitialAnalysisCanonical.Value = .object(["version": .integer(1), "resolution": .string("species"),
            "scientific_name": .string("Canis lupus familiaris"), "common_name": .string("Dog")])
        fields["primary_identification"] = primary
        fields["scientific_name"] = .string("Canis lupus familiaris"); fields["common_name"] = .string("Dog")
        fields["ai_reasoning"] = .string("Original retained reasoning")
        fields["candidates"] = .array([.object(["scientific_name": .string("Canis lupus"), "common_name": .string("Wolf"),
            "confidence_score": .string("0.2"), "taxon_rank": .string("species"), "distinguishing_feature": .string("Synthetic trait")])])
        fields["pet_identification"] = .object(["species_group": .string("dog"), "label": .string("Synthetic coat"),
            "label_type": .string("coat_pattern"), "confidence_score": .string("0.75"), "evidence": .array([.string("Synthetic pattern")])])
        document["data"] = .object(fields)
        let bytes = try InitialAnalysisCanonical.encode(.object(document))
        let reference = try InitialAnalysisCanonical.encode(.object(vector.reference.mapValues { .string($0) }))
        let provenance = Data(vector.original_provenance.utf8)
        let digest = SHA256.hash(data: Data("merian.initial-analysis.result.v1\n".utf8) + bytes).map { String(format: "%02x", $0) }.joined()
        let result = try InitialRetainedResult(reference: reference, result: bytes, provenance: provenance,
            resultDigest: digest, provenanceDigest: vector.evidence.provenance_digest, expectedReference: reference, originalProvenance: provenance)
        let speciesID = "00000000-0000-4000-8000-000000000888", analysisID = UUID()
        let record = try LocalScanRecordFactory.makeInitialRecord(from: result, speciesID: speciesID,
            timestamp: Date(timeIntervalSince1970: 1), captureDate: Date(timeIntervalSince1970: 1),
            capturedMediaJSON: nil, coverImagePath: nil, fieldNotes: nil)
        // Independent saved-server shapes use JSON numbers and retain rank.
        let candidate: [String: Any] = ["scientific_name": "Canis lupus", "common_name": "Wolf", "confidence_score": 0.2,
            "taxon_rank": "species", "distinguishing_feature": "Synthetic trait"]
        let pet: [String: Any] = ["species_group": "dog", "label": "Synthetic coat", "label_type": "coat_pattern",
            "confidence_score": 0.75, "evidence": ["Synthetic pattern"]]
        let candidatesData = try #require(record.candidatesData), petData = try #require(record.petIdentificationData)
        let raw = try #require(JSONSerialization.jsonObject(with: candidatesData) as? [[String: Any]])
        #expect(raw.first?["taxon_rank"] as? String == "species" && raw.first?["scientificName"] == nil)
        let rawPet = try #require(JSONSerialization.jsonObject(with: petData) as? [String: Any])
        #expect(rawPet["species_group"] as? String == "dog" && rawPet["confidenceScore"] == nil)
        #expect(try JSONDecoder().decode([IdentificationCandidate].self, from: candidatesData).first?.commonName == "Wolf")
        #expect(record.petIdentification?.label == "Synthetic coat" && record.petIdentification?.confidenceScore == 0.75)
        var saved: [String: Any] = ["ai_confidence_score": 0.87, "is_biological_subject": true,
            "ai_reasoning": "Original retained reasoning", "inference_tier": "flash", "species_id": speciesID,
            "primary_identification": try JSONSerialization.jsonObject(with: InitialAnalysisCanonical.encode(primary)),
            "identification_provenance": try JSONSerialization.jsonObject(with: provenance), "candidates": [candidate], "pet_identification": pet]
        func baseline() throws -> Data? {
            // Exercises the comparison consumer only; full V3 import remains a separate journey gate.
            let server = ObservationHistoryPage.Result(version: 3, photos: [], audio: nil, video: nil, analysisID: analysisID,
                completedAt: nil, importedAt: nil, bytes: try JSONSerialization.data(withJSONObject: ["result": saved]))
            return try SavedIdentificationDisplayBaseline.capture(AnalysisDisplaySnapshot(analysisID: analysisID, record: record), matching: server)
        }
        #expect(try baseline() != nil)
        var changed = candidate; changed.removeValue(forKey: "taxon_rank"); saved["candidates"] = [changed]
        #expect(try baseline() == nil)
        saved["candidates"] = [candidate]; var changedPet = pet; changedPet["confidence_score"] = 0.5; saved["pet_identification"] = changedPet
        #expect(try baseline() == nil)
        #expect(result.result == bytes && result.provenance == provenance)
    }

    @MainActor @Test func initialBaselinePinsDisplayAndSubmittedContextWithoutEnrollment() throws {
        let vector = try #require(fixtures().retained_results.first { $0.name == "primary_species" })
        let evidence = vector.evidence
        let reference = try InitialAnalysisCanonical.encode(.object(vector.reference.mapValues { .string($0) }))
        let result = try InitialRetainedResult(reference: reference, result: Data(evidence.result_canonical.utf8),
            provenance: Data(evidence.provenance_canonical.utf8), resultDigest: evidence.result_digest,
            provenanceDigest: evidence.provenance_digest, expectedReference: reference, originalProvenance: Data(vector.original_provenance.utf8))
        let record = try LocalScanRecordFactory.makeInitialRecord(from: result, speciesID: "",
            timestamp: Date(timeIntervalSince1970: 1), captureDate: Date(timeIntervalSince1970: 2),
            capturedMediaJSON: nil, coverImagePath: nil, fieldNotes: "\u{FEFF}e\u{0301}")
        record.observationContextsJSON = ["first", "second"]
        let baseline = try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: result)
        #expect(try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: result) == baseline)
        record.observationContextsJSON = ["second", "first"]
        #expect(try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: result) != baseline)
        record.observationContextsJSON = ["first", "second"]
        record.fieldNotes = "é"
        #expect(try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: result) != baseline)
        record.fieldNotes = "\u{FEFF}e\u{0301}"
        record.timestamp = Date(timeIntervalSince1970: 3)
        #expect(try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: result) != baseline)
        record.timestamp = Date(timeIntervalSince1970: 1)
        record.aiReasoning = "Later display"
        #expect(try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: result) != baseline)
        record.selectedAnalysisID = UUID().uuidString
        #expect(throws: (any Error).self) { try LocalScanRecordFactory.initialApplicationBaseline(record: record, result: result) }
        #expect(record.aiReasoning == "Later display" && record.selectedAnalysisID != nil)
        #expect(result.result == Data(evidence.result_canonical.utf8))
    }

    @MainActor @Test func frozenProvenanceStorageLimitAppliesAfterNumericProjection() throws {
        let all = try fixtures().retained_results
        let vector = try #require(all.first { $0.name == "gemini_modality_usage" })
        let primary = try #require(all.first { $0.name == "primary_species" })
        let primaryFields = try #require(InitialAnalysisCanonical.parse(Data(primary.evidence.result_canonical.utf8)).object?["data"]?.object)
        let tiny = "0." + String(repeating: "0", count: 323) + "5"
        func digest(_ domain: String, _ bytes: Data) -> String {
            SHA256.hash(data: Data("merian.initial-analysis.\(domain).v1\n".utf8) + bytes).map { String(format: "%02x", $0) }.joined()
        }
        for oversized in [false, true] {
            var document = try #require(InitialAnalysisCanonical.parse(Data(vector.evidence.result_canonical.utf8)).object)
            var fields = try #require(document["data"]?.object)
            var provenance = try #require(fields["identification_provenance"]?.object)
            for key in ["binding", "model", "variant", "operation", "prompt", "confidence", "safety"] {
                provenance[key] = .string(String(repeating: oversized ? "界" : "é", count: 80))
            }
            provenance["schema"] = .string("merian_identify_primary_v1")
            provenance["diagnostic_trigger"] = .string(tiny)
            provenance["prompt_diagnostic_trigger"] = .string(tiny)
            var generation = try #require(provenance["generation"]?.object)
            generation["temperature"] = .string(tiny)
            generation["seed"] = .integer(999999999); generation["top_k"] = .integer(999999999)
            generation["max_output_tokens"] = .integer(999999999); generation["thinking_budget"] = .integer(999999999)
            provenance["generation"] = .object(generation)
            fields["identification_provenance"] = .object(provenance)
            fields["primary_identification"] = primaryFields["primary_identification"]
            fields["candidates"] = .null
            document["data"] = .object(fields)
            let bytes = try InitialAnalysisCanonical.encode(.object(document))
            let original = try InitialAnalysisCanonical.encode(.object(provenance))
            #expect(original.count > 2048)
            let reference = try InitialAnalysisCanonical.encode(.object(vector.reference.mapValues { .string($0) }))
            let result = try InitialRetainedResult(reference: reference, result: bytes, provenance: original,
                resultDigest: digest("result", bytes), provenanceDigest: digest("result-provenance", original),
                expectedReference: reference, originalProvenance: original)
            if oversized {
                #expect(throws: InitialRetainedResult.ApplicationFailure.provenanceStorageLimit) {
                    try result.applicationProvenance()
                }
                #expect(throws: InitialRetainedResult.ApplicationFailure.provenanceStorageLimit) {
                    try LocalScanRecordFactory.makeInitialRecord(from: result, speciesID: "",
                        timestamp: Date(timeIntervalSince1970: 1), captureDate: Date(timeIntervalSince1970: 1),
                        capturedMediaJSON: nil, coverImagePath: nil, fieldNotes: nil)
                }
            } else {
                let projected = try result.applicationProvenance()
                #expect(projected.count <= 2048)
                let record = try LocalScanRecordFactory.makeInitialRecord(from: result, speciesID: "",
                    timestamp: Date(timeIntervalSince1970: 1), captureDate: Date(timeIntervalSince1970: 1),
                    capturedMediaJSON: nil, coverImagePath: nil, fieldNotes: nil)
                #expect(record.primaryIdentification?.value?.resolution == .species)
                let object = try #require(JSONSerialization.jsonObject(with: projected) as? [String: Any])
                #expect(object["diagnostic_trigger"] as? Double == Double.leastNonzeroMagnitude)
            }
            #expect(result.provenance == original)
        }
    }

    @Test func sharedCompletionVectors() throws {
        let fixtures = try fixtures()
        #expect(fixtures.documents.count >= 29)
        for vector in fixtures.documents {
            let r = Data(vector.receipt.utf8), p = Data(vector.projection.utf8)
            if vector.valid {
                let decoded: InitialCompletionDocuments
                do { decoded = try InitialCompletionDocuments(receipt: r, projection: p) }
                catch { Issue.record("Positive completion vector rejected: \(vector.name)"); continue }
                #expect(decoded.receipt == r, "\(vector.name)")
                #expect(decoded.projection == p, "\(vector.name)")
            } else {
                #expect(throws: (any Error).self, "\(vector.name)") {
                    _ = try InitialCompletionDocuments(receipt: r, projection: p)
                }
            }
        }
    }

    @Test func sharedOriginalAdmissionVectorsPreserveBytesAndRejectForeignFacts() throws {
        let vectors = try fixtures().admissions
        #expect(vectors.documents.count == 44)
        for vector in vectors.documents {
            let bytes = Data(vector.acknowledgement.utf8)
            if vector.valid {
                let value = try InitialCompletionDocuments.CpmAdmission(acknowledgement: bytes, original: vectors.original)
                #expect(value.acknowledgement == bytes)
                #expect(value.admission == Data(vectors.admission.utf8))
            } else {
                #expect(throws: (any Error).self, "\(vector.name)") {
                    _ = try InitialCompletionDocuments.CpmAdmission(acknowledgement: bytes, original: vectors.original)
                }
            }
        }
    }

    @Test func originalAdmissionRejectsChangedSavedBindings() throws {
        let vectors = try fixtures().admissions
        let firstPositive = vectors.documents.first { $0.valid }
        let positive = try #require(firstPositive)
        let binding = vectors.original
        let facts: [String: String] = [
            "owner_id": binding.ownerID, "scan_id": binding.scanID,
            "candidate_canonical": binding.candidateCanonical,
            "candidate_digest": binding.candidateDigest, "content_digest": binding.contentDigest,
            "assignment_digest": binding.assignmentDigest, "backend_generation": binding.backendGeneration,
            "backend_configuration_digest": binding.backendConfigurationDigest,
        ]
        for key in facts.keys.sorted() {
            var changed = facts
            if key == "candidate_canonical" { changed[key] = binding.candidateCanonical + " " }
            else if key.hasSuffix("digest") { changed[key] = String(repeating: "0", count: 64) }
            else { changed[key] = "00000000-0000-4000-8000-000000000999" }
            let original = try JSONDecoder().decode(InitialCompletionDocuments.CpmBinding.self,
                from: JSONSerialization.data(withJSONObject: changed))
            #expect(throws: (any Error).self, "\(key)") {
                _ = try InitialCompletionDocuments.CpmAdmission(
                    acknowledgement: Data(positive.acknowledgement.utf8), original: original)
            }
        }
    }

    @Test func recoveryRecordPreservesRestartFactsAndRejectsTampering() throws {
        let fixture = try fixtures(), vector = fixture.recovery_record
        let positive = fixture.admissions.documents.first { $0.valid }
        let acknowledgement = try #require(positive).acknowledgement
        let admission = try InitialCompletionDocuments.CpmAdmission(
            acknowledgement: Data(acknowledgement.utf8), original: fixture.admissions.original)
        let documents = try InitialCompletionDocuments(receipt: Data(vector.receipt.utf8), projection: Data(vector.projection.utf8))
        let value = try InitialCompletionDocuments.CpmRecoveryRecord(reference: Data(vector.reference.utf8),
            originalProvenance: Data(vector.provenance.utf8), documents: documents, admission: admission)
        #expect(value.bytes == Data(vector.encoded.utf8))
        #expect(try InitialCompletionDocuments.CpmRecoveryRecord.decode(value.bytes, admission: admission) == value)
        #expect(try InitialCompletionDocuments.CpmRecoveryRecord.maximumBytes == vector.maximum_bytes)
        #expect(value.reference == Data(vector.reference.utf8))
        #expect(value.originalProvenance == Data(vector.provenance.utf8))
        let parsed = try InitialAnalysisCanonical.parse(value.bytes).object
        let original = try #require(parsed)
        for key in ["admission_sha256", "result_digest", "provenance_digest", "state", "receipt_base64", "projection_base64", "provenance_base64"] {
            var changed = original
            changed[key] = .string(key.hasSuffix("digest") || key.hasSuffix("sha256") ? String(repeating: "0", count: 64) : "invalid")
            #expect(throws: (any Error).self, "\(key)") {
                _ = try InitialCompletionDocuments.CpmRecoveryRecord.decode(InitialAnalysisCanonical.encode(.object(changed)), admission: admission)
            }
        }
        for key in original.keys {
            var changed = original; changed.removeValue(forKey: key)
            #expect(throws: (any Error).self, "missing \(key)") {
                _ = try InitialCompletionDocuments.CpmRecoveryRecord.decode(InitialAnalysisCanonical.encode(.object(changed)), admission: admission)
            }
        }
        var extra = original; extra["extra"] = .null
        #expect(throws: (any Error).self) {
            _ = try InitialCompletionDocuments.CpmRecoveryRecord.decode(InitialAnalysisCanonical.encode(.object(extra)), admission: admission)
        }
        #expect(throws: (any Error).self) {
            _ = try InitialCompletionDocuments.CpmRecoveryRecord(reference: Data(vector.reference.utf8),
                originalProvenance: Data(repeating: 32, count: 65_537), documents: documents, admission: admission)
        }
        var changedReference = try #require(InitialAnalysisCanonical.parse(value.reference).object)
        changedReference["owner_id"] = .string("00000000-0000-4000-8000-000000000999")
        #expect(throws: (any Error).self) {
            _ = try InitialCompletionDocuments.CpmRecoveryRecord(reference: InitialAnalysisCanonical.encode(.object(changedReference)),
                originalProvenance: value.originalProvenance, documents: documents, admission: admission)
        }
    }

    @Test func sharedCanonicalVectors() throws {
        for vector in try fixtures().canonical {
            let data = Data(vector.text.utf8)
            if vector.valid {
                #expect(try InitialAnalysisCanonical.encode(InitialAnalysisCanonical.parse(data)) == data)
            } else {
                #expect(throws: (any Error).self) { _ = try InitialAnalysisCanonical.parse(data) }
            }
        }
    }

    @Test func normalizationIsNeverIdentity() throws {
        let composed = Data("\"é\"".utf8), decomposed = Data("\"e\u{301}\"".utf8)
        let bom = Data("\"\u{feff}Taxon\"".utf8)
        #expect(try InitialAnalysisCanonical.encode(InitialAnalysisCanonical.parse(bom)) == bom)
        #expect(composed != decomposed)
        #expect(try InitialAnalysisCanonical.encode(InitialAnalysisCanonical.parse(composed)) == composed)
        #expect(try InitialAnalysisCanonical.encode(InitialAnalysisCanonical.parse(decomposed)) == decomposed)
    }

    @Test func graphAndByteBounds() throws {
        let exactDepth = Data((String(repeating: "[", count: 12) + "0" + String(repeating: "]", count: 12)).utf8)
        #expect(try InitialAnalysisCanonical.encode(InitialAnalysisCanonical.parse(exactDepth)) == exactDepth)
        let array = InitialAnalysisCanonical.Value.array(Array(repeating: .integer(0), count: 512))
        let arrayBytes = try InitialAnalysisCanonical.encode(array)
        #expect(try InitialAnalysisCanonical.encode(InitialAnalysisCanonical.parse(arrayBytes)) == arrayBytes)
        for text in [String(repeating: "[", count: 13) + "0" + String(repeating: "]", count: 13),
                     "[" + Array(repeating: "0", count: 513).joined(separator: ",") + "]",
                     "\"" + String(repeating: "x", count: 1_048_576) + "\"",
                     "{" + (0..<129).map { "\"a\($0)\":0" }.sorted().joined(separator: ",") + "}"] {
            #expect(throws: (any Error).self) { _ = try InitialAnalysisCanonical.parse(Data(text.utf8)) }
        }
        let leaf = InitialAnalysisCanonical.Value.array(Array(repeating: .integer(0), count: 512))
        #expect(throws: (any Error).self) {
            _ = try InitialAnalysisCanonical.encode(.array(Array(repeating: leaf, count: 8)))
        }
    }

    @Test func malformedBytesAndNoncanonicalEscapes() {
        for bytes: [UInt8] in [[34, 0xc0, 0xaf, 34], [34, 0xed, 0xa0, 0x80, 34],
                               [34, 0xf4, 0x90, 0x80, 0x80, 34], [34, 0, 34], [34, 10, 34]] {
            #expect(throws: (any Error).self) { _ = try InitialAnalysisCanonical.parse(Data(bytes)) }
        }
        for text in [#""\ud83e\udd8b""#, #""\uFEFF""#, #""\u000B""#,
                     #""\u000a""#, #""\u00+1""#, "[0,]", "{\"a\":0,}", "01", "--1", "truefalse"] {
            #expect(throws: (any Error).self) { _ = try InitialAnalysisCanonical.parse(Data(text.utf8)) }
        }
    }
}
