import Testing
@testable import Merian

struct SpeciesDataTests {

    @Test func testSpeciesDataInitialization() {
        // Arrange
        let insightData = InsightData(
            aiReasoning: "A small, glowing beetle.",
            hazardType: "none"
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
            wikipediaUrl: "https://en.wikipedia.org/wiki/Firefly",
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
            aiReasoning: "Default description",
            hazardType: "poisonous"
        )

        var species = SpeciesData(
            scanId: nil,
            commonName: "Unknown",
            scientificName: "Unknownidae",
            insightData: insightData,
            confidenceScore: 0.5,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: true,
            ecologyType: "Unknown"
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
        let insightData = InsightData(aiReasoning: "A beetle.", hazardType: "none")
        let species = SpeciesData(
            commonName: "Firefly",
            scientificName: "Photinus pyralis",
            insightData: insightData,
            confidenceScore: 0.90
        )

        #expect(species.aiReasoning == nil, "aiReasoning must default to nil for non-Pro / legacy scans")
        #expect(species.habitatDescription == nil, "habitatDescription must default to nil")
    }

    @Test func testPremiumFieldsMutability() {
        let insightData = InsightData(aiReasoning: "A beetle.", hazardType: "none")
        var species = SpeciesData(
            commonName: "Firefly",
            scientificName: "Photinus pyralis",
            insightData: insightData,
            confidenceScore: 0.90
        )

        species.aiReasoning = "The bioluminescent abdomen confirms Photinus pyralis."
        species.habitatDescription = "Warm temperate meadows near water."

        #expect(species.aiReasoning?.contains("Photinus pyralis") == true)
        #expect(species.habitatDescription?.contains("meadows") == true)
    }

    @Test func testPremiumFieldsRoundTripThroughInit() {
        let insightData = InsightData(aiReasoning: "A monarch.", hazardType: "none")
        let species = SpeciesData(
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            insightData: insightData,
            confidenceScore: 0.98,
            aiReasoning: "The orange-black wing pattern is diagnostic.",
            habitatDescription: "Open fields with milkweed."
        )

        #expect(species.aiReasoning == "The orange-black wing pattern is diagnostic.")
        #expect(species.habitatDescription == "Open fields with milkweed.")
    }

    // MARK: - Similar Species: SimilarSpecies + SimilarSpeciesEntry

    @Test func testSimilarSpeciesBackwardsCompatAccessor() {
        // Arrange: three rich entries covering the common case from the join table
        let entries = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: "Crab-eating Raccoon", referenceImageUrl: "https://example.com/cancrivorus.jpg", iucnRedListStatus: "LC"),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: "Ringtail", referenceImageUrl: nil, iucnRedListStatus: "LC"),
            SimilarSpeciesEntry(scientificName: "Nasua nasua", commonName: "South American Coati", referenceImageUrl: nil, iucnRedListStatus: nil)
        ]
        let similar = SimilarSpecies(entries: entries)

        // Act
        let names = similar.lookalikes

        // Assert: backwards-compat accessor returns flat scientific name strings in order
        #expect(names.count == 3)
        #expect(names[0] == "Procyon cancrivorus")
        #expect(names[1] == "Bassariscus astutus")
        #expect(names[2] == "Nasua nasua")
    }

    @Test func testSimilarSpeciesEntriesWithPartialEnrichment() {
        // Arrange: historical records wrapped with nil enrichment (load(from:) path)
        let entries = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)
        ]
        let similar = SimilarSpecies(entries: entries)

        // Assert: partial entries are valid and accessible; nil fields don't crash
        #expect(similar.entries.count == 2)
        #expect(similar.entries[0].commonName == nil)
        #expect(similar.entries[0].referenceImageUrl == nil)
        #expect(similar.entries[0].iucnRedListStatus == nil)
        #expect(similar.lookalikes == ["Procyon cancrivorus", "Bassariscus astutus"])
    }

    @Test func testSimilarSpeciesMutability() {
        let insightData = InsightData(aiReasoning: "A procyonid.", hazardType: "none")
        var species = SpeciesData(
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: insightData,
            confidenceScore: 0.94
        )

        // Initial state: no lookalikes
        #expect(species.similarSpecies == nil)

        // Act: patch in similar species (mirrors fetchAndApplyEnrichment async path)
        species.similarSpecies = SimilarSpecies(entries: [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: "Crab-eating Raccoon", referenceImageUrl: nil, iucnRedListStatus: "LC")
        ])

        // Assert
        #expect(species.similarSpecies?.entries.count == 1)
        #expect(species.similarSpecies?.entries[0].scientificName == "Procyon cancrivorus")
        #expect(species.similarSpecies?.lookalikes == ["Procyon cancrivorus"])
    }
}
