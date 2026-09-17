@testable import Merian
import Testing

struct SpeciesDataTests {
    @Test func testSpeciesDataInitialization() {
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

        #expect(species.scanId == "scan_12345")
        #expect(species.commonName == "Firefly")
        #expect(species.scientificName == "Lampyridae")
        #expect(species.confidenceScore == 0.98)
        #expect(species.isBiological == true)
        #expect(species.isNewDiscovery == false)
        #expect(species.hasResolvedBiologicalIdentification)
        #expect(species.insightData.hazardType == "none")
        #expect(species.taxonomy?.family == "Lampyridae")
    }

    @Test func testSpeciesDataMutability() {
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

        #expect(species.isNewDiscovery == false)
        species.isNewDiscovery = true
        #expect(species.isNewDiscovery == true)
    }

    @Test func humanOverrideKeepsHumanSafeguards() {
        for override in ["Homo sapien", "Human"] {
            let species = SpeciesData(
                commonName: "American Robin",
                scientificName: "Turdus migratorius",
                insightData: InsightData(
                    aiReasoning: "A bird.",
                    hazardType: "none"
                ),
                confidenceScore: 0.9,
                userIdentificationOverride: override
            )

            #expect(species.isHumanSubject)
            #expect(species.presentationScientificName == "Homo sapiens")
            #expect(species.shouldSuppressReferenceImages)
        }

        let historicalCommonName = SpeciesData(
            commonName: "Homo sapiens",
            scientificName: "Taxonomy Unavailable",
            insightData: InsightData(
                aiReasoning: "Legacy Human result.",
                hazardType: "none"
            ),
            confidenceScore: 0.9
        )
        #expect(historicalCommonName.isHumanSubject)
        #expect(historicalCommonName.shouldSuppressReferenceImages)
    }

    @Test(arguments: [
        "Taxonomy Unavailable",
        "unknown",
        "Unknown Subject",
        "Unidentified Wildlife",
        "No wildlife detected",
        "Inanimate Object",
        "Not Applicable",
        "N/A",
        "  UNKNOWN SUBJECT \n"
    ])
    func legacyPlaceholderNamesRemainUnresolved(_ placeholder: String) {
        let species = SpeciesData(
            commonName: placeholder,
            scientificName: placeholder,
            insightData: InsightData(
                aiReasoning: "Legacy placeholder.",
                hazardType: "none"
            ),
            confidenceScore: 0.99
        )

        #expect(!species.hasResolvedBiologicalIdentification)
        #expect(species.isUnresolvedBiologicalSubject)
        #expect(species.presentationConfidenceScore == nil)
        #expect(species.shouldSuppressReferenceImages)
    }

    @Test func historicalAudioPlaceholdersUseSafePresentationWithoutRewritingData() {
        let species = SpeciesData(
            commonName: "Unknown Subject",
            scientificName: "Taxonomy Unavailable",
            insightData: InsightData(
                aiReasoning: "Legacy audio result.",
                hazardType: "none"
            ),
            confidenceScore: 0.99,
            isBiological: true,
            audioFilePaths: ["legacy.wav"]
        )

        #expect(species.commonName == "Unknown Subject")
        #expect(species.scientificName == "Taxonomy Unavailable")
        #expect(
            species.subjectDisplayName(isAudioOnlyObservation: true) ==
                "Unidentified Wildlife"
        )
        #expect(species.presentationConfidenceScore == nil)

        let nonBiological = SpeciesData(
            commonName: "Unknown Subject",
            scientificName: "Taxonomy Unavailable",
            insightData: InsightData(
                aiReasoning: "Legacy non-biological audio result.",
                hazardType: "none"
            ),
            confidenceScore: 0.99,
            isBiological: false,
            audioFilePaths: ["legacy.wav"]
        )
        #expect(
            nonBiological.subjectDisplayName(isAudioOnlyObservation: true) ==
                "No wildlife detected"
        )
        #expect(
            nonBiological.subjectDisplayName(isAudioOnlyObservation: false) ==
                "Unknown Subject"
        )
    }

    @Test func testPremiumFieldsDefaultToNilWhenOmitted() {
        let species = SpeciesData(
            commonName: "Firefly",
            scientificName: "Photinus pyralis",
            insightData: InsightData(
                aiReasoning: "A beetle.",
                hazardType: "none"
            ),
            confidenceScore: 0.90
        )

        #expect(species.aiReasoning == nil)
        #expect(species.habitatDescription == nil)
    }

    @Test func testPremiumFieldsMutability() {
        var species = SpeciesData(
            commonName: "Firefly",
            scientificName: "Photinus pyralis",
            insightData: InsightData(
                aiReasoning: "A beetle.",
                hazardType: "none"
            ),
            confidenceScore: 0.90
        )

        species.aiReasoning = "The bioluminescent abdomen confirms Photinus pyralis."
        species.habitatDescription = "Warm temperate meadows near water."

        #expect(species.aiReasoning?.contains("Photinus pyralis") == true)
        #expect(species.habitatDescription?.contains("meadows") == true)
    }

    @Test func testPremiumFieldsRoundTripThroughInit() {
        let species = SpeciesData(
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            insightData: InsightData(
                aiReasoning: "A monarch.",
                hazardType: "none"
            ),
            confidenceScore: 0.98,
            aiReasoning: "The orange-black wing pattern is diagnostic.",
            habitatDescription: "  Open fields with milkweed.\n"
        )

        #expect(
            species.aiReasoning ==
                "The orange-black wing pattern is diagnostic."
        )
        #expect(species.habitatDescription == "Open fields with milkweed.")
    }

    @Test func testMemberwiseInitAIScientificNameFallsBackToScientificName() {
        let species = SpeciesData(
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(
                aiReasoning: "A raccoon.",
                hazardType: "none"
            ),
            confidenceScore: 0.92
        )

        #expect(species.aiScientificName == "Procyon lotor")
    }

    @Test func testMemberwiseInitAIScientificNameIsPreservedWhenExplicit() {
        let species = SpeciesData(
            commonName: "Crab-eating Raccoon",
            scientificName: "Procyon cancrivorus",
            insightData: InsightData(
                aiReasoning: "A raccoon.",
                hazardType: "none"
            ),
            confidenceScore: 0.92,
            aiScientificName: "Procyon lotor"
        )

        #expect(species.aiScientificName == "Procyon lotor")
        #expect(species.scientificName == "Procyon cancrivorus")
    }

    @Test func testReviewFieldDefaultsInMemberwiseInit() {
        let species = SpeciesData(
            commonName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            insightData: InsightData(
                aiReasoning: "A butterfly.",
                hazardType: "none"
            ),
            confidenceScore: 0.98
        )

        #expect(species.userIdentificationOverride == nil)
        #expect(species.userConfirmedIdentification == false)
    }
}
