import Testing

@testable import Merian

@Suite("Inference Identification Review Presentation")
struct InferenceReviewPresentationTests {
    @Test func overridePublishesCleanReplacementPlaceholder() {
        let original = makeSpeciesData()

        let action = IdentificationReviewPresentation.override(
            original,
            scientificName: "Procyon cancrivorus"
        )
        let updated = action.speciesData

        #expect(updated.scanId == original.scanId)
        #expect(updated.confidenceScore == original.confidenceScore)
        #expect(updated.scientificName == "Procyon cancrivorus")
        #expect(updated.commonName == "Procyon cancrivorus")
        #expect(updated.userIdentificationOverride == "Procyon cancrivorus")
        #expect(!updated.userConfirmedIdentification)
        #expect(!updated.isFlagged)
        #expect(!updated.alternativesExhausted)
        #expect(updated.insightData.aiReasoning.isEmpty)
        #expect(updated.insightData.hazardType == "none")
        expectSpeciesContextCleared(updated)
        #expect(action.referenceState == .empty)
    }

    @Test func confirmationChangesOnlyConfirmationPresentation() {
        let original = makeSpeciesData()

        let action = IdentificationReviewPresentation.confirmation(original)
        let updated = action.speciesData

        #expect(updated.userConfirmedIdentification)
        #expect(updated.userIdentificationOverride == nil)
        #expect(updated.commonName == original.commonName)
        #expect(updated.scientificName == original.scientificName)
        #expect(updated.wikipediaOverview == original.wikipediaOverview)
        #expect(action.referenceState == nil)
    }

    @Test func resetRestoresAIIdentityAndClearsOverrideContext() {
        var overridden = makeSpeciesData()
        overridden.userIdentificationOverride = "Procyon cancrivorus"
        overridden.userConfirmedIdentification = true

        let action = IdentificationReviewPresentation.reset(
            overridden,
            scientificName: "Procyon lotor",
            aiReasoning: "Original reasoning"
        )
        let updated = action.speciesData

        #expect(updated.userIdentificationOverride == nil)
        #expect(!updated.userConfirmedIdentification)
        #expect(!updated.isFlagged)
        #expect(!updated.alternativesExhausted)
        #expect(updated.scientificName == "Procyon lotor")
        #expect(updated.commonName == "Procyon lotor")
        #expect(updated.insightData.aiReasoning == "Original reasoning")
        #expect(updated.insightData.hazardType == "none")
        expectSpeciesContextCleared(updated)
        #expect(action.referenceState == .empty)
    }

    @Test func dictionaryResolutionNormalizesPresentationAndPersistence() {
        let record = InferenceSpeciesDictionaryRecord(
            id: "species-id",
            commonNames: ["fr": "raton laveur", "en": "crab-eating raccoon"],
            kingdom: "Animalia",
            phylum: "Chordata",
            className: "Mammalia",
            order: "Carnivora",
            family: "Procyonidae",
            genus: "Procyon",
            wikipediaOverview: "Overview",
            hazardType: nil,
            referenceImageURL:
                "https://example.com/a.jpg,http://example.com/rejected.jpg, https://example.com/b.jpg",
            wikipediaURL: "https://en.wikipedia.org/wiki/Procyon_cancrivorus",
            iucnRedListStatus: "LC",
            habitatDescription: "  Wetlands and forests  ",
            gbifTaxonKey: 2_439_905
        )

        let resolution = IdentificationReviewPresentation.dictionaryResolution(
            record: record,
            current: makeSpeciesData(),
            scientificName: "Procyon cancrivorus",
            restoringAIReasoning: "Restored reasoning",
            replacingSpeciesIdentity: true
        )
        let updated = resolution.action?.speciesData

        #expect(resolution.speciesID == "species-id")
        #expect(updated?.commonName == "Crab-Eating Raccoon")
        #expect(updated?.insightData.aiReasoning == "Restored reasoning")
        #expect(updated?.insightData.hazardType == "none")
        #expect(updated?.habitatDescription == "Wetlands and forests")
        #expect(updated?.referenceImageUrl ==
            "https://example.com/a.jpg,https://example.com/b.jpg")
        #expect(resolution.action?.referenceState == .loaded([
            "https://example.com/a.jpg",
            "https://example.com/b.jpg"
        ]))
        #expect(updated?.taxonomy?.family == "Procyonidae")
        #expect(updated?.gbifTaxonKey == 2_439_905)

        let patch = resolution.persistencePatch
        #expect(patch.commonName == "Crab-Eating Raccoon")
        #expect(patch.hazardType == "none")
        #expect(patch.habitatDescription == "Wetlands and forests")
        #expect(patch.referenceImageURL ==
            "https://example.com/a.jpg,https://example.com/b.jpg")
        #expect(patch.taxonomy?.genus == "Procyon")
        #expect(patch.replacingSpeciesIdentity)
    }

    @Test func dictionaryResolutionStillReturnsPersistenceWithoutLiveState() {
        let record = makeDictionaryRecord(commonNames: nil)

        let resolution = IdentificationReviewPresentation.dictionaryResolution(
            record: record,
            current: nil,
            scientificName: "Procyon cancrivorus",
            restoringAIReasoning: nil,
            replacingSpeciesIdentity: false
        )

        #expect(resolution.action == nil)
        #expect(resolution.speciesID == "species-id")
        #expect(resolution.persistencePatch.commonName == "Procyon Cancrivorus")
        #expect(!resolution.persistencePatch.replacingSpeciesIdentity)
    }

    private func expectSpeciesContextCleared(_ data: SpeciesData) {
        #expect(data.wikipediaOverview == nil)
        #expect(data.wikipediaUrl == nil)
        #expect(data.referenceImageUrl == nil)
        #expect(data.iucnRedListStatus == nil)
        #expect(data.habitatDescription == nil)
        #expect(data.gbifTaxonKey == nil)
        #expect(data.taxonomy == nil)
        #expect(data.alternativeCommonNames == nil)
        #expect(data.similarSpecies == nil)
    }

    private func makeSpeciesData() -> SpeciesData {
        SpeciesData(
            scanId: "scan-a",
            commonName: "Raccoon",
            scientificName: "Procyon lotor",
            insightData: InsightData(
                aiReasoning: "AI reasoning",
                hazardType: "allergenic"
            ),
            confidenceScore: 0.91,
            similarSpecies: SimilarSpecies(entries: []),
            wikipediaUrl: "https://en.wikipedia.org/wiki/Raccoon",
            wikipediaOverview: "Old overview",
            referenceImageUrl: "https://example.com/old.jpg",
            taxonomy: TaxonomyData(
                kingdom: "Animalia",
                phylum: "Chordata",
                className: "Mammalia",
                order: "Carnivora",
                family: "Procyonidae",
                genus: "Procyon"
            ),
            iucnRedListStatus: "LC",
            habitatDescription: "Old habitat",
            gbifTaxonKey: 5_211_749,
            alternativeCommonNames: ["Northern raccoon"],
            aiScientificName: "Procyon lotor",
            isFlagged: true,
            alternativesExhausted: true
        )
    }

    private func makeDictionaryRecord(
        commonNames: [String: String?]?
    ) -> InferenceSpeciesDictionaryRecord {
        InferenceSpeciesDictionaryRecord(
            id: "species-id",
            commonNames: commonNames,
            kingdom: nil,
            phylum: nil,
            className: nil,
            order: nil,
            family: nil,
            genus: nil,
            wikipediaOverview: nil,
            hazardType: nil,
            referenceImageURL: nil,
            wikipediaURL: nil,
            iucnRedListStatus: nil,
            habitatDescription: nil,
            gbifTaxonKey: nil
        )
    }
}
