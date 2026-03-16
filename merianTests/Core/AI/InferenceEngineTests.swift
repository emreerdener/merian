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
        let wrapper = try decoder.decode(InferenceEngine.EdgeResponseWrapper.self, from: jsonData)
        
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
        let wrapper = try decoder.decode(InferenceEngine.EdgeResponseWrapper.self, from: jsonData)
        
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
}
