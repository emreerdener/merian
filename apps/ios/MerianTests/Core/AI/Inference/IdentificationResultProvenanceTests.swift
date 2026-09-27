import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite("Identification result provenance")
struct IdentificationResultProvenanceTests {
    private func metadata(pro: Bool = false) -> [String: Any] {
        ["version": 1, "provider": "gemini", "binding": "gemini_baseline_v1",
         "model": pro ? "gemini-2.5-pro" : "gemini-2.5-flash",
         "variant": "multimodal", "operation": "scan_identification",
         "policy_version": 1, "prompt": "identify_vision_v1", "schema": "merian_identify_v1",
         "confidence": "gemini_identify_v1", "diagnostic_trigger": 0.99,
         "prompt_diagnostic_trigger": NSNull(), "safety": NSNull(), "timeout_ms": 90_000,
         "generation": ["temperature": 0.1, "seed": 42, "top_k": NSNull(),
                        "max_output_tokens": 8_192, "thinking_budget": pro ? 5_000 as Any : NSNull()]]
    }

    private func provenance(_ object: [String: Any]) throws -> IdentificationResultProvenance {
        let dto = try JSONDecoder().decode(IdentificationProvenanceDTO.self,
            from: JSONSerialization.data(withJSONObject: object))
        return IdentificationResultProvenance(dto: dto)
    }

    private func envelope(metadata: Any?) throws -> Data {
        var data: [String: Any] = ["scan_id": "00000000-0000-4000-8000-000000000052",
            "scientific_name": "Turdus migratorius", "common_name": "American Robin",
            "confidence_score": 0.999, "inference_tier": "flash", "is_biological_subject": true]
        if let metadata { data["identification_provenance"] = metadata }
        return try JSONSerialization.data(withJSONObject: ["success": true, "data": data])
    }

    @Test(arguments: [false, true])
    func knownGeminiConfigurationRetainsItsTierBands(pro: Bool) throws {
        let value = try provenance(metadata(pro: pro))
        #expect(InferenceConfidencePolicy.bands(forInferenceTier: pro ? "pro" : "flash", provenance: value) == (pro ? InferenceConfidencePolicy.pro : InferenceConfidencePolicy.flash))
        #expect(InferenceConfidencePolicy.bands(forInferenceTier: pro ? "flash" : "pro", provenance: value) == nil)
        #expect(InferenceConfidencePolicy.bands(forInferenceTier: nil, provenance: value) == nil)
        #expect(try provenance(metadata(pro: pro)).data == value.data)
    }

    @Test func requiredNullsSurviveStorageAndMissingKeysNeverQualify() throws {
        let value = try provenance(metadata())
        let encoded = try #require(JSONSerialization.jsonObject(with: value.data) as? [String: Any])
        #expect(encoded["safety"] is NSNull)
        #expect((encoded["generation"] as? [String: Any])?["thinking_budget"] is NSNull)
        for key in ["safety", "diagnostic_trigger", "prompt_diagnostic_trigger"] {
            var damaged = encoded; damaged.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: damaged)
            #expect(!IdentificationResultProvenance(storedData: data).supportsGeminiBands(forInferenceTier: "flash"))
        }
        var damaged = encoded
        var generation = try #require(encoded["generation"] as? [String: Any])
        generation.removeValue(forKey: "top_k"); damaged["generation"] = generation
        #expect(!IdentificationResultProvenance(storedData: try JSONSerialization.data(withJSONObject: damaged)).supportsGeminiBands(forInferenceTier: "flash"))
    }

    @Test(arguments: [false, true])
    func unexpectedMetadataKeysCannotInheritGeminiConfidence(nested: Bool) async throws {
        var object = metadata()
        if nested {
            var generation = try #require(object["generation"] as? [String: Any])
            generation["future_setting"] = 1
            object["generation"] = generation
        } else {
            object["future_setting"] = 1
        }
        let stored = IdentificationResultProvenance(storedData: try JSONSerialization.data(withJSONObject: object))
        #expect(!stored.supportsGeminiBands(forInferenceTier: "flash"))
        // Wire decoding must reject the extra field before DTO re-encoding could
        // erase it and accidentally turn future metadata into a known profile.
        await #expect(throws: MerianError.decodingFailed) {
            try await InferenceResponsePreparationService.live.prepare(
                resultData: envelope(metadata: object), telemetry: nil,
                audioFilePaths: nil, videoFilePaths: nil, expectedScanId: nil)
        }
    }

    @Test func existingAdmittedAudioExperimentRetainsProBandsOnly() throws {
        var object = metadata(pro: true)
        object["prompt"] = "identify_audio_uncertainty_experiment_v1"
        object["schema"] = "merian_audio_v2"
        object["confidence"] = "gemini_audio_v2"
        #expect(try provenance(object).supportsGeminiBands(forInferenceTier: "pro"))
        object["model"] = "gemini-2.5-flash"
        #expect(try !provenance(object).supportsGeminiBands(forInferenceTier: "flash"))
    }

    @Test func unknownConfigurationCannotUseLegacyConfidence() throws {
        let changes: [(String, Any)] = [("provider", "openai"), ("model", "future-model"),
            ("binding", "future_binding_v1"), ("prompt", "future_prompt_v1"),
            ("schema", "future_schema_v1"), ("confidence", "future_confidence_v1"),
            ("operation", "unknown"), ("variant", "unknown"), ("version", 2),
            ("policy_version", 2),
            ("diagnostic_trigger", 0.5)]
        for (key, value) in changes {
            var object = metadata(); object[key] = value
            #expect(InferenceConfidencePolicy.bands(forInferenceTier: "flash", provenance: try provenance(object)) == nil)
        }
        for bytes in [Data(), Data("{}".utf8), Data(repeating: 65, count: 2_049)] {
            #expect(InferenceConfidencePolicy.bands(forInferenceTier: "pro", provenance: IdentificationResultProvenance(storedData: bytes)) == nil)
        }
        #expect(InferenceConfidencePolicy.bands(forInferenceTier: "pro", provenance: nil) == InferenceConfidencePolicy.pro)
    }

    @Test func wirePreparationLocalPersistenceAndReopenShareProvenance() async throws {
        let prepared = try await InferenceResponsePreparationService.live.prepare(
            resultData: envelope(metadata: metadata()), telemetry: nil,
            audioFilePaths: nil, videoFilePaths: nil, expectedScanId: nil)
        let original = try #require(prepared.mappedData.identificationProvenance)
        let record = LocalScanRecordFactory.makeRecord(from: prepared.mappedData,
            recordId: "fixture", speciesId: "fixture-species", timestamp: Date(), captureDate: Date(),
            capturedMediaJSON: nil, coverImagePath: nil, isLiveCapture: true, fieldNotes: nil)
        #expect(record.identificationProvenanceData == original.data)
        let projection = InferenceHistoricalRecordProjection(record: record, resetLocalLookalikes: false)
        #expect(projection.speciesData.identificationProvenance == original)
        #expect(projection.speciesData.identificationConfidenceBands == InferenceConfidencePolicy.flash)
    }

    @Test func explicitNullOrMalformedWireMetadataIsRejectedWhileOmissionWorks() async throws {
        for value: Any in [NSNull(), [String: Any]() ] {
            await #expect(throws: MerianError.decodingFailed) {
                try await InferenceResponsePreparationService.live.prepare(
                    resultData: envelope(metadata: value), telemetry: nil,
                    audioFilePaths: nil, videoFilePaths: nil, expectedScanId: nil)
            }
        }
        let legacy = try await InferenceResponsePreparationService.live.prepare(
            resultData: envelope(metadata: nil), telemetry: nil,
            audioFilePaths: nil, videoFilePaths: nil, expectedScanId: nil)
        #expect(legacy.mappedData.identificationProvenance == nil)
        #expect(legacy.mappedData.identificationConfidenceBands == InferenceConfidencePolicy.flash)
    }

    @Test func unqualifiedScoresRemainReviewableWithoutMatchLabels() throws {
        var object = metadata(); object["provider"] = "openai"
        let value = try provenance(object)
        let badge = ConfidenceBadgePresentation.resolve(confidenceScore: 0.999,
            inferenceTier: "flash", provenance: value, hasUserOverride: false,
            isUserConfirmed: false, analyzingPhrase: nil)
        #expect(badge.label == "Needs review" && badge.isVisible)
        #expect(ConfidenceExplanationPresentation.headerTitle(confidenceScore: 0.999,
            inferenceTier: "flash", provenance: value, hasUserOverride: false,
            isUserConfirmed: false) == "Review identification")
        let candidate = IdentificationCandidate(scientificName: "Turdus merula",
            commonName: "Blackbird", confidenceScore: 0.1, distinguishingFeature: "dark plumage")
        #expect(CandidateReviewVisibilityPolicy.shouldShowCandidates(primaryConfidence: 0.999,
            inferenceTier: "flash", provenance: value, candidates: [candidate]))
        #expect(CandidateReviewVisibilityPolicy.shouldSurfaceForReviewCollection(primaryConfidence: 0.999,
            inferenceTier: "flash", provenance: value, candidates: []))
        #expect(!CandidateReviewVisibilityPolicy.shouldShowCandidates(primaryConfidence: 0.999,
            inferenceTier: "flash", provenance: value, candidates: [candidate], userConfirmedIdentification: true))
    }

    @Test func profileSummaryAndDetailDoNotRewardUnknownConfidence() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let legacy = LocalScanRecord(id: "legacy", speciesId: "legacy-species", scientificName: "Fixture legacy", commonName: "Legacy fixture", confidenceScore: 0.999)
        var object = metadata(); object["provider"] = "unknown"
        let unknown = LocalScanRecord(id: "unknown", speciesId: "unknown-species", scientificName: "Fixture unknown", commonName: "Unknown fixture", confidenceScore: 0.999, inferenceTier: "flash", identificationProvenanceData: try provenance(object).data)
        context.insert(legacy); context.insert(unknown); try context.save()
        let actor = ProfileDatabaseActor(modelContainer: context.container)
        let stats = await actor.calculateAll()
        #expect(stats.awards.first { $0.type == .perfectLens }?.currentCount == 1)
        let detail = await actor.calculateAchievementDetail(for: .perfectLens)
        #expect(detail?.contributions.map(\.scanID) == ["legacy"])
    }

    @Test func historicalSyncKeepsPresentProvenanceAcrossOmissionAndQuarantinesMalformedRows() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let actor = HistoricalDatabaseActor(modelContainer: context.container)
        var row: [String: Any] = ["id": "00000000-0000-4000-8000-000000000052",
            "timestamp": "2026-09-26T12:00:00.000Z", "inference_tier": "flash",
            "ai_confidence_score": 0.999, "is_biological_subject": true,
            "explore_posts": NSNull(), "identification_provenance": metadata()]
        let response = try JSONDecoder().decode(HistoricalScanResponse.self,
            from: JSONSerialization.data(withJSONObject: row))
        #expect(try await actor.reconcileScanPage(responses: [response]) == 1)
        let verification = ModelContext(context.container)
        let record = try #require(verification.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let stored = try #require(record.identificationProvenanceData)
        #expect(stored == (try provenance(metadata())).data)
        row.removeValue(forKey: "identification_provenance")
        let omitted = try JSONDecoder().decode(HistoricalScanResponse.self,
            from: JSONSerialization.data(withJSONObject: row))
        _ = try await actor.reconcileScanPage(responses: [omitted])
        let reopened = ModelContext(context.container)
        #expect(try reopened.fetch(FetchDescriptor<LocalScanRecord>()).first?.identificationProvenanceData == stored)
        row["identification_provenance"] = [:] as [String: Any]
        let page = try HistoricalScanPageDecoder.decode(JSONSerialization.data(withJSONObject: [row]))
        #expect(page.remoteRowCount == 1 && page.rejectedRowCount == 1 && page.responses.isEmpty)
    }
}
