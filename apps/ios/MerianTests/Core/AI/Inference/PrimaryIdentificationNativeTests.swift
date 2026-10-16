import Foundation
import SwiftData
import Testing
@testable import Merian

/// Synthetic reserved-contract fixtures; no producer is admitted by these tests.
@MainActor
struct PrimaryIdentificationNativeTests {
    private func metadata() -> [String: Any] {
        ["version": 2, "provider": "openai", "binding": "synthetic_primary_v1",
         "model": "gpt-6-sol", "variant": "multimodal", "operation": "scan_identification",
         "policy_version": 1, "prompt": "synthetic_primary_v1", "schema": "merian_identify_primary_v1",
         "confidence": "openai_unqualified_v1", "diagnostic_trigger": NSNull(),
         "prompt_diagnostic_trigger": NSNull(), "safety": "openai_photo_moderation_v1", "timeout_ms": 90_000,
         "generation": ["max_output_tokens": 8_192, "reasoning_effort": "low", "image_detail": "high"]]
    }

    private func payload(_ resolution: PrimaryIdentification.Resolution = .genus, id: String = "primary-fixture") -> [String: Any] {
        let name: Any = resolution.isNamedBiologicalTaxon ? (resolution == .species ? "Examplea testus" : "Examplea") : NSNull()
        let primary: [String: Any] = ["version": 1, "resolution": resolution.rawValue,
            "scientific_name": name, "common_name": "Fixture subject"]
        return ["scan_id": id, "scientific_name": name, "common_name": "Fixture subject",
            "confidence_score": 0.0, "inference_tier": "flash",
            "is_biological_subject": resolution != .nonBiological,
            "is_new_to_merian_dictionary": false, "identification_provenance": metadata(),
            "primary_identification": primary]
    }

    private func edge(_ payload: [String: Any]) throws -> EdgeResponse {
        try JSONDecoder().decode(EdgeResponse.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    private func species(_ payload: [String: Any]) throws -> SpeciesData {
        SpeciesData(fromEdgeResponse: try edge(payload), locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)
    }

    private func historical(_ payload: [String: Any]) throws -> HistoricalScanResponse {
        var response = payload
        response["id"] = payload["scan_id"]
        response["timestamp"] = "2026-09-29T12:00:00Z"
        return try JSONDecoder().decode(HistoricalScanResponse.self, from: JSONSerialization.data(withJSONObject: response))
    }

    @Test(arguments: PrimaryIdentification.Resolution.allCases)
    func preparationHistoryAndReopenPreserveRank(resolution: PrimaryIdentification.Resolution) async throws {
        let value = payload(resolution)
        let bytes = try JSONSerialization.data(withJSONObject: ["success": true, "data": value])
        let prepared = try await InferenceResponsePreparationService.live.prepare(
            resultData: bytes, telemetry: nil, audioFilePaths: nil, videoFilePaths: nil, expectedScanId: nil)
        #expect(prepared.mappedData.requiresSavedRecord)
        #expect(prepared.mappedData.primaryIdentification?.value?.resolution == resolution)
        let context = try ScanRepositoryTestSupport.makeContext()
        let actor = HistoricalDatabaseActor(modelContainer: context.container)
        #expect(try await actor.reconcileScanPage(responses: [historical(value)]) == 1)
        let reopened = ModelContext(context.container)
        let record = try #require(reopened.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let projection = InferenceHistoricalRecordProjection(record: record, resetLocalLookalikes: false)
        #expect(projection.speciesData.primaryIdentification == prepared.mappedData.primaryIdentification)
        #expect(projection.speciesData.commonName == "Fixture subject")
        #expect(record.hasSpeciesLevelIdentification == (resolution == .species))
        #expect(projection.hydrationPlan.allowsSpeciesHydration == (resolution == .species))
        if resolution != .species {
            #expect(record.speciesId.isEmpty)
            #expect(!record.hasSpeciesRankForAchievements)
            #expect(projection.referenceImageURL == nil)
        }
    }

    @Test func contradictoryWireResultsFailBeforePersistence() throws {
        let mutations: [[String: Any]] = [
            ["scientific_name": "Differentia"], ["is_biological_subject": false],
            ["is_new_to_merian_dictionary": true], ["gbif_taxon_key": 42],
            ["reference_image_url": "https://example.com/reference.jpg"],
            ["candidates": [["scientific_name": "Examplea testus", "common_name": "Example",
                             "confidence_score": 0.8, "distinguishing_feature": "Fixture", "taxon_rank": "species"]]]
        ]
        for mutation in mutations {
            let data = try edge(payload().merging(mutation) { _, new in new })
            #expect(!PrimaryIdentificationResponseValidator.isValid(data))
        }
        var missing = payload(); missing.removeValue(forKey: "primary_identification")
        #expect(!PrimaryIdentificationResponseValidator.isValid(try edge(missing)))
        missing = payload(); missing.removeValue(forKey: "identification_provenance")
        #expect(!PrimaryIdentificationResponseValidator.isValid(try edge(missing)))
    }

    @Test func duplicateLiveCompletionPreservesOriginalAndReviewState() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let actor = BackgroundDatabaseActor(modelContainer: context.container)
        let original = try species(payload())
        #expect(await actor.saveNonVisualRecord(mappedData: original) != .notSaved)
        await actor.updateScanWithOverride(scanId: "primary-fixture", override: "Pending species",
            confirmed: false, newConfirmedSpeciesId: nil, userReviewState: .userOverridden)
        #expect(await actor.saveNonVisualRecord(mappedData: original) != .notSaved)
        #expect(await actor.saveNonVisualRecord(mappedData: try species(payload(.family))) == .notSaved)
        var legacy = payload(); legacy.removeValue(forKey: "primary_identification")
        legacy.removeValue(forKey: "identification_provenance"); legacy["confidence_score"] = 0.9
        #expect(await actor.saveNonVisualRecord(mappedData: try species(legacy)) == .notSaved)
        let record = try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(record.primaryIdentification?.value?.resolution == .genus)
        #expect(record.userIdentificationOverride == "Pending species")
        #expect(record.userReviewState == .userOverridden)
        #expect(record.scientificName == "Examplea")
    }

    @Test func offlineDuplicatesRejectConflictsAndAbsentRequiredSnapshot() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let actor = BackgroundDatabaseActor(modelContainer: context.container)
        let first = try species(payload())
        context.insert(OfflineQueuedScan(id: "primary-fixture", scanState: .inferencing))
        try context.save()
        #expect(await actor.saveNonVisualRecord(mappedData: first).wasSaved)
        var legacy = payload(); legacy.removeValue(forKey: "primary_identification")
        legacy.removeValue(forKey: "identification_provenance")
        for value in [try species(payload(.family)), try species(legacy)] {
            let result = await actor.persistOfflineScanResultAssumingPersistenceLock(
                mappedData: value, originalImagePaths: [], scanId: "primary-fixture",
                originalTimestamp: Date(), observationContextsJSON: nil, audioFilePaths: nil,
                videoFilePaths: nil, capturedMediaJSON: nil)
            #expect(!result.wasCleaned && result.speciesData == nil)
        }
        let identical = await actor.persistOfflineScanResultAssumingPersistenceLock(
            mappedData: first, originalImagePaths: [], scanId: "primary-fixture",
            originalTimestamp: Date(), observationContextsJSON: nil, audioFilePaths: nil,
            videoFilePaths: nil, capturedMediaJSON: nil)
        #expect(identical.wasCleaned)
        let saved = try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(saved.primaryIdentification?.value?.resolution == .genus)
    }

    @Test func broaderHistoryClearsSpeciesCachesAndNeverPromotesTypedReview() async throws {
        let context = try ScanRepositoryTestSupport.makeContext()
        let record = LocalScanRecord(id: "primary-fixture", speciesId: "legacy-species",
            scientificName: "Examplea testus", commonName: "Old species", confidenceScore: 0.99)
        record.taxonomyGenus = "Stalegenus"
        record.habitatDescription = "Stale habitat"
        record.wikipediaUrl = "https://example.com/stale"
        record.userIdentificationOverride = "Examplea testus"
        record.confirmedSpeciesId = "legacy-species"
        record.userConfirmedIdentification = true
        context.insert(record); try context.save()
        let actor = HistoricalDatabaseActor(modelContainer: context.container)
        _ = try await actor.reconcileScanPage(responses: [historical(payload(.family))])
        let saved = try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(saved.taxonomyGenus == nil && saved.habitatDescription == nil && saved.wikipediaUrl == nil)
        #expect(saved.scientificName == "Examplea")
        #expect(!saved.hasSpeciesLevelIdentification && !saved.hasSpeciesRankForAchievements)
        let projection = InferenceHistoricalRecordProjection(record: saved, resetLocalLookalikes: false)
        #expect(projection.speciesData.scientificName == "Examplea")
        #expect(projection.speciesData.primaryRankDescription != nil)
        #expect(projection.speciesData.taxonomy == nil)
        let stats = await SpeciesObservationStatsDatabaseActor(modelContainer: context.container)
            .fetchLocalStats(scientificName: "Examplea testus", speciesId: "legacy-species")
        #expect(stats.totalObservations == 0)
        let metadataActor = BackgroundDatabaseActor(modelContainer: context.container)
        #expect(await metadataActor.updateScanWithWikipedia(scanId: saved.id,
            extract: "Should not attach", url: "https://example.com/wrong", imageUrl: nil) == false)
        await metadataActor.updateScanWithEnrichment(scanId: saved.id, habitatDescription: "Wrong",
            gbifTaxonKey: 42, similarSpeciesJsonData: nil, taxonomy: nil)
        let checked = try #require(ModelContext(context.container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(checked.habitatDescription == nil && checked.gbifTaxonKey == nil)
    }

    @Test func damagedRequiredSnapshotCannotBecomeLegacyDuringHistoryMerge() throws {
        let record = LocalScanRecord(speciesId: "legacy", scientificName: "Examplea testus", commonName: "Example")
        record.identificationProvenanceData = try JSONSerialization.data(withJSONObject: metadata())
        #expect(record.primaryIdentification != nil && record.primaryIdentification?.value == nil)
        #expect(!record.hasSpeciesLevelIdentification)
        #expect(InferenceHistoricalRecordProjection(record: record, resetLocalLookalikes: false)
            .speciesData.presentationRole == .inferenceError)
        #expect(throws: PrimaryIdentification.IntegrityError.self) {
            try HistoricalPrimaryIdentification.validateMerge(historical(["scan_id": "fixture"]), into: record)
        }
    }
}
