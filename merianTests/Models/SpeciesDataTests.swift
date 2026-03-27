import Testing
@testable import Merian

struct SpeciesDataTests {

    @Test func testSpeciesDataInitialization() {
        // Arrange
        let insightData = InsightData(
            description: "A small, glowing beetle.",
            hazardType: "none",
            regionalStatusRationale: "Common in North America"
        )
        
        let taxonomyData = TaxonomyData(
            kingdom: "Animalia",
            phylum: "Arthropoda",
            className: "Insecta",
            order: "Coleoptera",
            family: "Lampyridae",
            genus: "Photinus"
        )
        
        // Act
        let species = SpeciesData(
            scanId: "scan_12345",
            commonName: "Firefly",
            scientificName: "Lampyridae",
            insightData: insightData,
            confidenceScore: 0.98,
            diagnosticComparison: nil,
            wikipediaUrl: "https://en.wikipedia.org/wiki/Firefly",
            wikipediaExtract: nil,
            referenceImageUrl: nil,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            taxonomy: taxonomyData
        )
        
        // Assert
        #expect(species.scanId == "scan_12345")
        #expect(species.commonName == "Firefly")
        #expect(species.scientificName == "Lampyridae")
        #expect(species.confidenceScore == 0.98)
        #expect(species.isBiological == true)
        #expect(species.isNewDiscovery == false, "Default or explicitly set state should be honored")
        
        #expect(species.insightData.hazardType == "none")
        #expect(species.taxonomy?.family == "Lampyridae")
    }
    
    @Test func testSpeciesDataMutability() {
        // Arrange
        let insightData = InsightData(
            description: "Default description",
            hazardType: "poisonous",
            regionalStatusRationale: nil
        )

        var species = SpeciesData(
            scanId: nil,
            commonName: "Unknown",
            scientificName: "Unknownidae",
            insightData: insightData,
            confidenceScore: 0.5,
            diagnosticComparison: nil,
            wikipediaUrl: nil,
            wikipediaExtract: nil,
            referenceImageUrl: nil,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: true,
            ecologyType: "Unknown",
            taxonomy: nil
        )

        // Act
        // Verify default state
        #expect(species.isNewDiscovery == false, "New discoveries default to false")

        // Mutate the explicitly var declared property
        species.isNewDiscovery = true

        // Assert
        #expect(species.isNewDiscovery == true, "isNewDiscovery should be fully mutable explicitly bridging state payloads")
    }

    // MARK: - Premium Insights: default nil state

    @Test func testPremiumFieldsDefaultToNilWhenOmitted() {
        let insightData = InsightData(description: "A beetle.", hazardType: "none", regionalStatusRationale: nil)
        let species = SpeciesData(
            commonName: "Firefly",
            scientificName: "Photinus pyralis",
            insightData: insightData,
            confidenceScore: 0.90
        )

        #expect(species.aiReasoning == nil, "aiReasoning must default to nil for non-Pro / legacy scans")
        #expect(species.habitatDescription == nil, "habitatDescription must default to nil")
        #expect(species.globalDistributionRegions == nil, "globalDistributionRegions must default to nil")
    }

    @Test func testPremiumFieldsMutability() {
        let insightData = InsightData(description: "A beetle.", hazardType: "none", regionalStatusRationale: nil)
        var species = SpeciesData(
            commonName: "Firefly",
            scientificName: "Photinus pyralis",
            insightData: insightData,
            confidenceScore: 0.90
        )

        species.aiReasoning = "The bioluminescent abdomen confirms Photinus pyralis."
        species.habitatDescription = "Warm temperate meadows near water."
        species.globalDistributionRegions = ["US-TX", "US-FL"]

        #expect(species.aiReasoning?.contains("Photinus pyralis") == true)
        #expect(species.habitatDescription?.contains("meadows") == true)
        #expect(species.globalDistributionRegions == ["US-TX", "US-FL"])
    }

    @Test func testPremiumFieldsRoundTripThroughInit() {
        let insightData = InsightData(description: "A monarch.", hazardType: "none", regionalStatusRationale: nil)
        let species = SpeciesData(
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            insightData: insightData,
            confidenceScore: 0.98,
            aiReasoning: "The orange-black wing pattern is diagnostic.",
            habitatDescription: "Open fields with milkweed.",
            globalDistributionRegions: ["US", "MX", "CA"]
        )

        #expect(species.aiReasoning == "The orange-black wing pattern is diagnostic.")
        #expect(species.habitatDescription == "Open fields with milkweed.")
        #expect(species.globalDistributionRegions == ["US", "MX", "CA"])
    }
}
