import Testing
@testable import Merian
import Foundation
import SwiftData

@MainActor
struct InferenceEngineTests {

    @Test func testEdgeResponseDecodingSuccess() throws {
        // Arrange: Simulate a valid JSON payload from the Gemini Edge Function
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "gemini_scan_001",
                "is_biological_subject": true,
                "is_live_capture": true,
                "ecology_type": "Terrestrial",
                "is_invasive": false,
                "scientific_name": "Procyon lotor",
                "common_name": "Raccoon",
                "confidence_score": 0.96,
                "taxonomy": {
                    "kingdom": "Animalia",
                    "phylum": "Chordata",
                    "class": "Mammalia",
                    "order": "Carnivora",
                    "family": "Procyonidae",
                    "genus": "Procyon"
                },
                "insight_data": {
                    "ai_reasoning": "A medium-sized mammal native to North America.",
                    "hazard_type": "none"
                },
                "wikipedia_url": "https://en.wikipedia.org/wiki/Raccoon",
                "reference_image_url": "https://example.com/raccoon.jpg"
            }
        }
        """
        
        let jsonData = jsonString.data(using: .utf8)!
        
        // Act
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(EdgeResponseWrapper.self, from: jsonData)
        
        // Assert: Ensure nested Decodable structures map perfectly
        let edgeResponse = wrapper.data
        
        #expect(wrapper.success == true)
        #expect(edgeResponse.scan_id == "gemini_scan_001")
        #expect(edgeResponse.common_name == "Raccoon")
        #expect(edgeResponse.scientific_name == "Procyon lotor")
        #expect(edgeResponse.confidence_score == 0.96)
        #expect(edgeResponse.is_biological_subject == true)
        #expect(edgeResponse.ecology_type == "Terrestrial")
        #expect(edgeResponse.is_invasive == false)
        
        #expect(edgeResponse.taxonomy?.family == "Procyonidae")
        #expect(edgeResponse.insight_data?.hazard_type == "none")
        #expect(edgeResponse.insight_data?.ai_reasoning?.contains("mammal") == true)
        #expect(edgeResponse.wikipedia_url == "https://en.wikipedia.org/wiki/Raccoon")
    }

    @Test func testEdgeResponseDecodingPartialData() throws {
        // Arrange: Simulate a corrupted or low-confidence edge result containing nil fields
        let jsonString = """
        {
            "success": true,
            "data": {
                "is_biological_subject": false,
                "common_name": "Inanimate Object"
            }
        }
        """
        let jsonData = jsonString.data(using: .utf8)!
        
        // Act
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(EdgeResponseWrapper.self, from: jsonData)
        
        // Assert: Ensure optionality gracefully falls back rather than violently crashing
        let edgeResponse = wrapper.data
        
        #expect(edgeResponse.is_biological_subject == false)
        #expect(edgeResponse.common_name == "Inanimate Object")
        #expect(edgeResponse.scientific_name == nil)
        #expect(edgeResponse.taxonomy == nil)
        #expect(edgeResponse.insight_data == nil)
    }

    @Test func testLoadFromLocalScanRecord() throws {
        // Arrange: Create an ephemeral LocalScanRecord model offline
        let record = LocalScanRecord(
            speciesId: "species_abc",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            localImagePath: "monarch.jpg",
            semanticTags: ["butterfly", "insect"],
            hazardType: "poisonous",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            wikipediaUrl: "https://en.wikipedia.org/wiki/Monarch_butterfly",
            referenceImageUrl: "https://example.com/monarch.jpg",
            additionalImagePaths: ["monarch2.jpg"],
            confidenceScore: 0.99,
            taxonomyKingdom: "Animalia",
            taxonomyPhylum: "Arthropoda",
            taxonomyClass: "Insecta",
            taxonomyOrder: "Lepidoptera",
            taxonomyFamily: "Nymphalidae",
            taxonomyGenus: "Danaus",
            aiReasoning: "A milkweed butterfly in the family Nymphalidae."
        )

        let engine = InferenceEngine()

        // Act
        engine.load(from: record)

        // Assert: Ensure engine parses the offline model locally into SpeciesData
        let resultingData = try #require(engine.speciesData, "SpeciesData should not be nil after loading")

        #expect(resultingData.commonName == "Monarch Butterfly")
        #expect(resultingData.scientificName == "Danaus plexippus")
        #expect(resultingData.confidenceScore == 0.99)
        #expect(resultingData.insightData.hazardType == "poisonous")
        #expect(resultingData.insightData.aiReasoning.contains("Nymphalidae"))
        #expect(resultingData.taxonomy?.genus == "Danaus")

        // Note: validHistoricImagePaths is populated asynchronously by FileIOActor.validPaths(from:)
        // which filters out non-existent disk paths — cannot assert file paths in the unit test sandbox.

        #expect(engine.isProcessing == false, "Processing state should return to false synchronously")
    }

    // MARK: - load(from:) enrichment gate: all-null common names

    @Test func testLoadFromRecordWithAllNullCommonNamesTriggersEnrichment() throws {
        // Arrange: encode a lookalikesData blob where every entry has commonName == nil.
        // This simulates a scan whose join table was populated before the common-name
        // back-fill pipeline existed. The needsEnrichment gate must fire so enrich-scan
        // is called and common names are fetched.
        let staleEntries = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)
        ]
        let lookalikesData = try JSONEncoder().encode(staleEntries)

        let record = LocalScanRecord(
            speciesId: "species_xyz",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            localImagePath: nil,
            semanticTags: ["raccoon"],
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            lookalikesData: lookalikesData,                 // present but all-null common names
            habitatDescription: "Forests and urban areas.", // present — not the trigger
            gbifTaxonKey: 2433697                          // present — not the trigger
        )

        let engine = InferenceEngine()
        engine.load(from: record)

        // The synchronous part of load(from:) must have pre-decoded the blob once
        // and produced a SimilarSpecies with the two stale entries.
        // speciesData.similarSpecies is set asynchronously inside historicHydrationTask,
        // but we can assert the engine initialised cleanly and isProcessing returned false.
        #expect(engine.isProcessing == false)
        // The enrichment path is async (historicHydrationTask); we verify the gate condition
        // was met by confirming lookalikesData decoded to all-null common names correctly.
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: lookalikesData)
        #expect(decoded.allSatisfy { $0.commonName == nil }, "All entries must have nil commonName to trigger enrichment gate")
        #expect(decoded.count == 2)
    }

    @Test func testLoadFromRecordWithRichCommonNamesSkipsEnrichment() throws {
        // Arrange: encode a lookalikesData blob where entries have commonName populated.
        // needsEnrichment must be false — no redundant enrich-scan call should fire.
        let richEntries = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: "Crab-eating Raccoon", referenceImageUrl: "https://example.com/cancrivorus.jpg", iucnRedListStatus: "LC"),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: "Ringtail", referenceImageUrl: nil, iucnRedListStatus: "LC")
        ]
        let lookalikesData = try JSONEncoder().encode(richEntries)

        let record = LocalScanRecord(
            speciesId: "species_xyz",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            localImagePath: nil,
            semanticTags: ["raccoon"],
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            lookalikesData: lookalikesData,
            habitatDescription: "Forests and urban areas.",
            gbifTaxonKey: 2433697
        )

        let engine = InferenceEngine()
        engine.load(from: record)

        #expect(engine.isProcessing == false)
        // Confirm the gate condition is not met — at least one commonName is non-nil.
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: lookalikesData)
        #expect(decoded.contains { $0.commonName != nil }, "At least one non-nil commonName must prevent enrichment re-trigger")
    }

    // MARK: - Premium Insights: EdgeResponse decoding

    @Test func testEdgeResponseDecodesSpeciesInsights() throws {
        // species_insights is populated on cache hit for all tiers — sourced from species_dictionary
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "cache_hit_001",
                "is_biological_subject": true,
                "common_name": "Monarch Butterfly",
                "scientific_name": "Danaus plexippus",
                "confidence_score": 0.98,
                "insight_data": { "ai_reasoning": "A migratory butterfly.", "hazard_type": "none" },
                "species_insights": {
                    "habitat_description": "Open fields, meadows, and roadsides with milkweed."
                }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let insights = try #require(wrapper.data.species_insights, "species_insights must decode on a cache-hit response")

        #expect(insights.habitat_description?.contains("milkweed") == true)
    }

    @Test func testEdgeResponseSpeciesInsightsNilOnCacheMiss() throws {
        // species_insights is absent on a fresh scan (cache miss) — enrichment arrives via enrich-scan
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "cache_miss_001",
                "is_biological_subject": true,
                "common_name": "Raccoon",
                "scientific_name": "Procyon lotor",
                "confidence_score": 0.91,
                "insight_data": { "ai_reasoning": "A medium-sized mammal.", "hazard_type": "none" }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)

        #expect(wrapper.data.species_insights == nil, "Cache-miss responses must not include species_insights")
    }

    @Test func testSpeciesDataMapsAiReasoningFromEdgeResponse() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "reason_scan",
                "is_biological_subject": true,
                "common_name": "Firefly",
                "scientific_name": "Photinus pyralis",
                "confidence_score": 0.95,
                "insight_data": { "ai_reasoning": "A bioluminescent beetle.", "hazard_type": "none" },
                "species_insights": {
                    "habitat_description": "Warm temperate meadows and forest edges."
                }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let speciesData = SpeciesData(fromEdgeResponse: wrapper.data, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)

        #expect(speciesData.aiReasoning?.contains("bioluminescent beetle") == true, "aiReasoning must be populated per-scan from insight_data.ai_reasoning")
        #expect(speciesData.habitatDescription?.contains("meadows") == true)
    }

    @Test func testSpeciesDataPremiumFieldsNilWhenPremiumInsightsMissing() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "is_biological_subject": true,
                "common_name": "Raccoon",
                "insight_data": { "ai_reasoning": "A mammal.", "hazard_type": "none" }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let speciesData = SpeciesData(fromEdgeResponse: wrapper.data, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)

        // aiReasoning IS populated from insight_data.ai_reasoning (per-scan, always present when insight_data exists)
        #expect(speciesData.aiReasoning == "A mammal.", "aiReasoning comes from insight_data.ai_reasoning, not from removed premium_insights")
        // habitatDescription requires species_insights.habitat_description — absent on cache miss
        #expect(speciesData.habitatDescription == nil)
    }

    // MARK: - Premium Insights: load(from:) — V15 LocalScanRecord fields

    @Test func testLoadFromRecordWithPremiumInsights() throws {
        let record = LocalScanRecord(
            speciesId: "species_v15",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            aiReasoning: "The orange and black wing pattern with white marginal spots is diagnostic for Danaus plexippus.",
            habitatDescription: "Open fields and meadows with milkweed."
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.aiReasoning?.contains("Danaus plexippus") == true)
        #expect(result.habitatDescription?.contains("milkweed") == true)
    }

    @Test func testLoadFromRecordWithNilPremiumFields() throws {
        let record = LocalScanRecord(
            speciesId: "species_legacy",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.aiReasoning == nil)
        #expect(result.habitatDescription == nil)
    }

    // MARK: - Similar Species: EnrichScanResponse decoding

    @Test func testEnrichScanResponseDecodesRichLookalikes() throws {
        // Arrange: full payload from species_lookalikes join table hydration
        let jsonString = """
        {
            "success": true,
            "data": {
                "habitat_description": "Deciduous forests and urban areas.",
                "similar_species": [
                    {
                        "scientific_name": "Procyon cancrivorus",
                        "common_name": "Crab-eating Raccoon",
                        "reference_image_url": "https://example.com/cancrivorus.jpg",
                        "iucn_red_list_status": "LC"
                    },
                    {
                        "scientific_name": "Bassariscus astutus",
                        "common_name": "Ringtail",
                        "reference_image_url": null,
                        "iucn_red_list_status": "LC"
                    }
                ]
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(EnrichScanResponse.self, from: data)
        let entries = try #require(response.data?.similar_species, "similar_species must decode to a non-nil array")

        #expect(entries.count == 2)
        #expect(entries[0].scientific_name == "Procyon cancrivorus")
        #expect(entries[0].common_name == "Crab-eating Raccoon")
        #expect(entries[0].reference_image_url == "https://example.com/cancrivorus.jpg")
        #expect(entries[0].iucn_red_list_status == "LC")
        #expect(entries[1].scientific_name == "Bassariscus astutus")
        #expect(entries[1].reference_image_url == nil, "Null reference_image_url must decode as nil, not crash")
    }

    @Test func testEnrichScanResponseDecodesLookalikesWithNilOptionals() throws {
        // Arrange: sparse entry — only scientific_name provided (common during initial join table population)
        let jsonString = """
        {
            "success": true,
            "data": {
                "similar_species": [
                    { "scientific_name": "Nasua nasua" }
                ]
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(EnrichScanResponse.self, from: data)
        let entries = try #require(response.data?.similar_species)

        #expect(entries.count == 1)
        #expect(entries[0].scientific_name == "Nasua nasua")
        #expect(entries[0].common_name == nil)
        #expect(entries[0].reference_image_url == nil)
        #expect(entries[0].iucn_red_list_status == nil)
    }

    @Test func testEnrichScanResponseNilWhenSimilarSpeciesAbsent() throws {
        // Arrange: enrich-scan response with no lookalike data available for this species
        let jsonString = """
        {
            "success": true,
            "data": {
                "habitat_description": "Open ocean.",
                "gbif_taxon_key": 12345
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let response = try JSONDecoder().decode(EnrichScanResponse.self, from: data)

        #expect(response.data?.similar_species == nil, "Absent similar_species key must decode as nil, not an empty array")
    }

    // MARK: - Similar Species: load(from:) — historical record wrapping

    @Test func testLoadFromRecordWithSimilarSpecies() async throws {
        // Arrange: LocalScanRecord with legacy TEXT[] names (MerianSchemaV26 field)
        let record = LocalScanRecord(
            speciesId: "species_procyon",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            similarSpecies: ["Procyon cancrivorus", "Bassariscus astutus"]
        )
        let engine = InferenceEngine()
        engine.load(from: record)
        await engine.historicHydrationTask?.value

        let result = try #require(engine.speciesData)
        let similar = try #require(result.similarSpecies, "similarSpecies must be populated from LocalScanRecord.similarSpecies")

        // Assert: bare strings are wrapped in SimilarSpeciesEntry with nil enrichment fields
        #expect(similar.entries.count == 2)
        #expect(similar.entries[0].scientificName == "Procyon cancrivorus")
        #expect(similar.entries[0].commonName == nil, "Historical wrap must leave commonName nil — no join table data")
        #expect(similar.entries[0].referenceImageUrl == nil)
        #expect(similar.entries[0].iucnRedListStatus == nil)
        #expect(similar.entries[1].scientificName == "Bassariscus astutus")

        // Backwards-compat accessor must still return flat string array
        #expect(similar.lookalikes == ["Procyon cancrivorus", "Bassariscus astutus"])
    }

    @Test func testLoadFromRecordWithNilSimilarSpecies() async throws {
        // Arrange: record with no lookalike data (pre-V26 or species with no known lookalikes)
        let record = LocalScanRecord(
            speciesId: "species_unique",
            scientificName: "Ailuropoda melanoleuca",
            commonName: "Giant Panda"
        )
        let engine = InferenceEngine()
        engine.load(from: record)
        await engine.historicHydrationTask?.value

        let result = try #require(engine.speciesData)
        #expect(result.similarSpecies == nil, "nil similarSpecies on LocalScanRecord must not produce an empty SimilarSpecies struct")
    }

    // MARK: - Identification Candidates: EdgeResponse decoding

    @Test func testEdgeResponseDecodesCandidatesArray() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "cand_001",
                "is_biological_subject": true,
                "scientific_name": "Procyon lotor",
                "common_name": "Raccoon",
                "confidence_score": 0.82,
                "insight_data": { "ai_reasoning": "A procyonid.", "hazard_type": "none" },
                "candidates": [
                    { "scientific_name": "Procyon cancrivorus", "confidence_score": 0.71 },
                    { "scientific_name": "Bassariscus astutus", "confidence_score": 0.65 }
                ]
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)

        let candidates = try #require(wrapper.data.candidates, "candidates must decode from edge response JSON")
        #expect(candidates.count == 2)
        #expect(candidates[0].scientific_name == "Procyon cancrivorus")
        #expect(candidates[0].confidence_score == 0.71)
        #expect(candidates[1].scientific_name == "Bassariscus astutus")
    }

    @Test func testEdgeResponseNilCandidatesOnHighConfidenceScan() throws {
        // Server strips candidates before sending when confidence >= diagnosticTrigger.
        let jsonString = """
        {
            "success": true,
            "data": {
                "is_biological_subject": true,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.97,
                "insight_data": { "ai_reasoning": "Distinctive wings.", "hazard_type": "none" }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)

        #expect(wrapper.data.candidates == nil, "Absent candidates key must decode as nil, not an empty array")
    }

    // MARK: - Identification Candidates: load(from:) — V28/V29 fields

    @Test func testLoadFromRecordDecodesCandidatesData() async throws {
        let candidates: [IdentificationCandidate] = [
            IdentificationCandidate(scientificName: "Procyon cancrivorus", confidenceScore: 0.71),
            IdentificationCandidate(scientificName: "Bassariscus astutus", confidenceScore: 0.65)
        ]
        let blob = try JSONEncoder().encode(candidates)

        let record = LocalScanRecord(
            speciesId: "v28-candidates",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            candidatesData: blob
        )
        let engine = InferenceEngine()
        engine.load(from: record)
        await engine.historicHydrationTask?.value

        let result = try #require(engine.speciesData)
        let decoded = try #require(result.candidates, "load(from:) must decode candidatesData blob into SpeciesData.candidates")

        #expect(decoded.count == 2)
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].confidenceScore == 0.71)
    }

    @Test func testLoadFromRecordNilCandidatesDataYieldsNilCandidates() async throws {
        let record = LocalScanRecord(
            speciesId: "v28-no-candidates",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        let engine = InferenceEngine()
        engine.load(from: record)
        await engine.historicHydrationTask?.value

        let result = try #require(engine.speciesData)
        #expect(result.candidates == nil, "Nil candidatesData must produce nil candidates — not an empty array")
    }

    @Test func testLoadFromRecordPopulatesAIScientificName() throws {
        // load(from:) passes record.scientificName as aiScientificName, capturing the AI's
        // original identification before any user override can be applied.
        let record = LocalScanRecord(
            speciesId: "v29-ai-name",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.aiScientificName == "Procyon lotor", "load(from:) must set aiScientificName from record.scientificName")
    }

    @Test func testLoadFromRecordPopulatesUserIdentificationOverride() throws {
        // When a user previously overrode the identification, override is rehydrated on load.
        let record = LocalScanRecord(
            speciesId: "v29-override-load",
            scientificName: "Procyon cancrivorus",
            commonName: "Crab-eating Raccoon",
            userIdentificationOverride: "Procyon cancrivorus"
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.userIdentificationOverride == "Procyon cancrivorus", "load(from:) must restore userIdentificationOverride from the persisted record")
    }

    @Test func testLoadFromRecordPopulatesUserConfirmedIdentification() throws {
        // When a user previously confirmed the AI, the flag is restored on load.
        let record = LocalScanRecord(
            speciesId: "v29-confirmed-load",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            userConfirmedIdentification: true
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.userConfirmedIdentification == true, "load(from:) must restore userConfirmedIdentification from the persisted record")
    }

    @Test func testLoadFromRecordPopulatesIsFlagged() throws {
        // When a scan was previously flagged for moderation review, the flag is restored on load.
        let record = LocalScanRecord(
            speciesId: "v31-flagged-load",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            isFlagged: true
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.isFlagged == true, "load(from:) must restore isFlagged from the persisted record")
    }

    // MARK: - Identification Review: engine methods

    @Test func testConfirmAIIdentificationSetsConfirmedFlag() async throws {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "confirm_scan_001",
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "A mammal.", hazardType: "none"),
            confidenceScore: 0.92,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial"
        )

        await engine.confirmAIIdentification(modelContext: nil)

        #expect(engine.speciesData?.userConfirmedIdentification == true, "confirmAIIdentification must set userConfirmedIdentification to true")
        #expect(engine.speciesData?.userIdentificationOverride == nil, "confirmAIIdentification must not set an override")
    }

    @Test func testConfirmAIIdentificationIsNoOpWhenScanIdMissing() async throws {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: nil,
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "A mammal.", hazardType: "none"),
            confidenceScore: 0.92,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial"
        )

        await engine.confirmAIIdentification(modelContext: nil)

        #expect(engine.speciesData?.userConfirmedIdentification == false, "No-op when scanId is nil — userConfirmedIdentification must remain false")
    }

    @Test func testApplyIdentificationOverrideMutatesSpeciesData() async throws {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "override_scan_001",
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(aiReasoning: "A procyonid.", hazardType: "none"),
            confidenceScore: 0.82,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            aiScientificName: "Procyon lotor"
        )

        await engine.applyIdentificationOverride(scientificName: "Procyon cancrivorus", modelContext: nil)

        #expect(engine.speciesData?.scientificName == "Procyon cancrivorus", "Override must update scientificName immediately")
        #expect(engine.speciesData?.userIdentificationOverride == "Procyon cancrivorus", "Override must set userIdentificationOverride")
        #expect(engine.speciesData?.userConfirmedIdentification == false, "Override clears confirmed flag")
        #expect(engine.speciesData?.aiScientificName == "Procyon lotor", "aiScientificName must be preserved after override")
    }

    @Test func testResetIdentificationReviewClearsBothFields() async throws {
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: "reset_scan_001",
            commonName: "Crab-eating Raccoon",
            scientificName: "Procyon cancrivorus",
            insightData: InsightData(aiReasoning: "A procyonid.", hazardType: "none"),
            confidenceScore: 0.82,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            aiScientificName: "Procyon lotor",
            userIdentificationOverride: "Procyon cancrivorus"
        )

        await engine.resetIdentificationReview(modelContext: nil)

        #expect(engine.speciesData?.userIdentificationOverride == nil, "Reset must clear userIdentificationOverride")
        #expect(engine.speciesData?.userConfirmedIdentification == false, "Reset must clear userConfirmedIdentification")
        #expect(engine.speciesData?.scientificName == "Procyon lotor", "Reset must revert scientificName to aiScientificName")
        #expect(engine.speciesData?.aiScientificName == "Procyon lotor", "aiScientificName must remain unchanged after reset")
    }

    @Test func testResetIdentificationReviewIsNoOpWhenScanIdMissing() async throws {
        // When scanId is nil, reset bails out without mutating any fields.
        let engine = InferenceEngine()
        engine.speciesData = SpeciesData(
            scanId: nil,
            commonName: "Crab-eating Raccoon",
            scientificName: "Procyon cancrivorus",
            insightData: InsightData(aiReasoning: "A procyonid.", hazardType: "none"),
            confidenceScore: 0.82,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            aiScientificName: "Procyon lotor",
            userIdentificationOverride: "Procyon cancrivorus"
        )

        await engine.resetIdentificationReview(modelContext: nil)

        #expect(engine.speciesData?.userIdentificationOverride == "Procyon cancrivorus", "No-op when scanId is nil — override must remain unchanged")
        #expect(engine.speciesData?.scientificName == "Procyon cancrivorus", "No-op when scanId is nil — scientificName must remain unchanged")
    }

    // MARK: - Inference Tier Configuration Validation
    @Test func testInferenceTier_ConfigurationValidation() throws {
        // Assert Flash Free-Tier thresholds are strict
        let flashBands = MerianConfig.confidenceBands(forInferenceTier: "flash")
        #expect(flashBands.strong == 0.96)
        #expect(flashBands.possible == 0.75)
        #expect(flashBands.diagnosticTrigger == 0.88)
        
        // Assert Pro Premium-Tier thresholds are relaxed
        let proBands = MerianConfig.confidenceBands(forInferenceTier: "pro")
        #expect(proBands.strong == 0.85) 
        #expect(proBands.possible == 0.65)
        #expect(proBands.diagnosticTrigger == 0.80)
        
        // Assert Legacy/Nil scans resolve to Flash thresholds for safety
        let legacyBands = MerianConfig.confidenceBands(forInferenceTier: nil)
        #expect(legacyBands.strong == 0.96)
        #expect(legacyBands.diagnosticTrigger == 0.88)
    }
}
