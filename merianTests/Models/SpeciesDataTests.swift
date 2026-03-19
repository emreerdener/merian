import Testing
@testable import Merian

struct SpeciesDataTests {

    @Test func testSpeciesDataInitialization() {
        // Arrange
        let insightData = InsightData(
            description: "A small, glowing beetle.",
            isPoisonous: false,
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
        
        #expect(species.insightData.isPoisonous == false)
        #expect(species.taxonomy?.family == "Lampyridae")
    }
    
    @Test func testSpeciesDataMutability() {
        // Arrange
        let insightData = InsightData(
            description: "Default description",
            isPoisonous: true,
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
}
