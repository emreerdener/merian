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
                    "description": "A medium-sized mammal native to North America.",
                    "is_poisonous": false,
                    "regional_status_rationale": "Least Concern"
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
        #expect(edgeResponse.insight_data?.is_poisonous == false)
        #expect(edgeResponse.insight_data?.description?.contains("mammal") == true)
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
            insightDescription: "A milkweed butterfly in the family Nymphalidae.",
            localImagePath: "monarch.jpg",
            semanticTags: ["butterfly", "insect"],
            isPoisonous: true,
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
            taxonomyGenus: "Danaus"
        )

        let engine = InferenceEngine()

        // Act
        engine.load(from: record)

        // Assert: Ensure engine parses the offline model locally into SpeciesData
        let resultingData = try #require(engine.speciesData, "SpeciesData should not be nil after loading")

        #expect(resultingData.commonName == "Monarch Butterfly")
        #expect(resultingData.scientificName == "Danaus plexippus")
        #expect(resultingData.confidenceScore == 0.99)
        #expect(resultingData.insightData.isPoisonous == true)
        #expect(resultingData.insightData.description.contains("Nymphalidae"))
        #expect(resultingData.taxonomy?.genus == "Danaus")

        // Assert image paths are stitched properly into activeImageDatas for the UI Carousel
        #expect(engine.activeImageDatas.count == 2, "Expected 2 total images (1 local, 1 extra)")
        #expect(engine.activeImageDatas[0] == "monarch.jpg")
        #expect(engine.activeImageDatas[1] == "monarch2.jpg")

        #expect(engine.isProcessing == false, "Processing state should return to false synchronously")
    }

    // MARK: - Premium Insights: EdgeResponse decoding

    @Test func testEdgeResponseDecodesProPremiumInsights() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "pro_scan_001",
                "is_biological_subject": true,
                "common_name": "Monarch Butterfly",
                "scientific_name": "Danaus plexippus",
                "confidence_score": 0.98,
                "insight_data": { "description": "A migratory butterfly.", "is_poisonous": false },
                "premium_insights": {
                    "ai_reasoning": "The orange and black wing pattern with white spots along the margins is diagnostic for Danaus plexippus.",
                    "habitat_description": "Open fields, meadows, and roadsides with milkweed.",
                    "global_distribution_regions": ["US-TX", "US-CA", "MX"]
                }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let premium = try #require(wrapper.data.premium_insights, "premium_insights must be present for Pro scans")

        #expect(premium.ai_reasoning?.contains("Danaus plexippus") == true)
        #expect(premium.habitat_description?.contains("milkweed") == true)
        #expect(premium.global_distribution_regions == ["US-TX", "US-CA", "MX"])
    }

    @Test func testEdgeResponsePremiumInsightsNilForFreeScans() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "scan_id": "free_scan_001",
                "is_biological_subject": true,
                "common_name": "Raccoon",
                "scientific_name": "Procyon lotor",
                "confidence_score": 0.91,
                "insight_data": { "description": "A medium-sized mammal.", "is_poisonous": false }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)

        #expect(wrapper.data.premium_insights == nil, "Free-tier scans must not include premium_insights")
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
                "insight_data": { "description": "A bioluminescent beetle.", "is_poisonous": false },
                "premium_insights": {
                    "ai_reasoning": "The characteristic light organ on the abdomen and flight pattern confirm Photinus pyralis.",
                    "habitat_description": "Warm temperate meadows and forest edges.",
                    "global_distribution_regions": ["US", "CA"]
                }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let speciesData = SpeciesData(fromEdgeResponse: wrapper.data, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)

        #expect(speciesData.aiReasoning?.contains("Photinus pyralis") == true)
        #expect(speciesData.habitatDescription?.contains("meadows") == true)
        #expect(speciesData.globalDistributionRegions == ["US", "CA"])
    }

    @Test func testSpeciesDataPremiumFieldsNilWhenPremiumInsightsMissing() throws {
        let jsonString = """
        {
            "success": true,
            "data": {
                "is_biological_subject": true,
                "common_name": "Raccoon",
                "insight_data": { "description": "A mammal.", "is_poisonous": false }
            }
        }
        """
        let data = jsonString.data(using: .utf8)!
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: data)
        let speciesData = SpeciesData(fromEdgeResponse: wrapper.data, locationName: nil, weatherCondition: nil, weatherTemperatureF: nil)

        #expect(speciesData.aiReasoning == nil)
        #expect(speciesData.habitatDescription == nil)
        #expect(speciesData.globalDistributionRegions == nil)
    }

    // MARK: - Premium Insights: load(from:) — V15 LocalScanRecord fields

    @Test func testLoadFromRecordWithPremiumInsights() throws {
        let regionsJson = "[\"US-TX\",\"MX\"]"
        let record = LocalScanRecord(
            speciesId: "species_v15",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            insightDescription: "The orange-black wing pattern is diagnostic.",
            aiReasoning: "The orange and black wing pattern with white marginal spots is diagnostic for Danaus plexippus.",
            habitatDescription: "Open fields and meadows with milkweed.",
            globalDistributionRegionsJson: regionsJson
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.aiReasoning?.contains("Danaus plexippus") == true)
        #expect(result.habitatDescription?.contains("milkweed") == true)
        #expect(result.globalDistributionRegions == ["US-TX", "MX"])
    }

    @Test func testLoadFromRecordWithMalformedDistributionJson() throws {
        let record = LocalScanRecord(
            speciesId: "species_malformed",
            scientificName: "Unknown",
            commonName: "Unknown",
            insightDescription: "Test",
            globalDistributionRegionsJson: "NOT_VALID_JSON"
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        // Malformed JSON must not crash; globalDistributionRegions should be nil
        #expect(result.globalDistributionRegions == nil)
    }

    @Test func testLoadFromRecordWithNilPremiumFields() throws {
        let record = LocalScanRecord(
            speciesId: "species_legacy",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            insightDescription: "A medium-sized mammal."
        )
        let engine = InferenceEngine()
        engine.load(from: record)

        let result = try #require(engine.speciesData)
        #expect(result.aiReasoning == nil)
        #expect(result.habitatDescription == nil)
        #expect(result.globalDistributionRegions == nil)
    }
}
