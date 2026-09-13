import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite("Inference Historical Record Projection")
struct InferenceHistoricalRecordProjectionTests {
    @Test func projectsPersistedPresentationAndDeferredContent() async throws {
        let lookalikes = [
            SimilarSpeciesEntry(
                scientificName: "Danaus gilippus",
                commonName: "Queen",
                referenceImageUrl: "https://example.com/queen.jpg",
                iucnRedListStatus: "LC"
            )
        ]
        let candidates = [
            IdentificationCandidate(
                scientificName: "Danaus erippus",
                commonName: "Southern Monarch",
                confidenceScore: 0.72,
                distinguishingFeature: "broader dark veins"
            )
        ]
        let petIdentification = PetIdentification(
            speciesGroup: "cat",
            label: "Domestic shorthair",
            labelType: "coat_type",
            confidenceScore: 0.84,
            evidence: ["short coat"]
        )
        let mediaItems: [SerializedMediaItem] = [
            .image(.documents("monarch.webp", sourceIndex: 0)),
            .audio(.documents("habitat.wav", sourceIndex: 1)),
            .description(
                ObservationContext(freeText: "Observed near milkweed")
            )
        ]
        let record = LocalScanRecord(
            id: "historical-complete",
            speciesId: "monarch-id",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            capturedMediaJSON: CapturedMediaSnapshot(
                items: mediaItems
            ).jsonString,
            hazardType: "poisonous",
            isBiological: true,
            isLiveCapture: false,
            isInvasive: true,
            invasiveStatusRegion: "Oceania",
            invasiveRationale: "Introduced population",
            invasiveConfidence: 0.88,
            ecologyType: "terrestrial",
            wikipediaUrl: "https://en.wikipedia.org/wiki/Monarch_butterfly",
            wikipediaOverview: "A migratory milkweed butterfly.",
            referenceImageUrl: "https://example.com/monarch.jpg",
            confidenceScore: 0.94,
            taxonomyKingdom: "Animalia",
            taxonomyPhylum: "Arthropoda",
            taxonomyClass: "Insecta",
            taxonomyOrder: "Lepidoptera",
            taxonomyFamily: "Nymphalidae",
            taxonomyGenus: "Danaus",
            locationName: "Prairie",
            weatherCondition: "Clear",
            weatherTemperatureF: 72,
            lookalikesData: try JSONEncoder().encode(lookalikes),
            candidatesData: try JSONEncoder().encode(candidates),
            iucnRedListStatus: "LC",
            gpsLatitude: 41.8,
            gpsLongitude: -87.6,
            gpsElevation: 181,
            zoomFactor: 2,
            aiReasoning: "Orange wings with black veins.",
            habitatDescription: "Open fields with milkweed.",
            gbifTaxonKey: 5_137_920,
            estimatedSizeCm: 9.5,
            lifeStage: "adult",
            reproductiveCondition: "unknown",
            sex: "female",
            sexConfidence: 0.7,
            sexEvidence: "wing venation",
            individualCount: 2,
            ecologicalInteractions: ["pollinating"],
            inferenceTier: "pro",
            userConfirmedIdentification: true,
            isFlagged: true,
            imageQualityScore: 92,
            alternativeCommonNames: ["Milkweed butterfly"],
            petIdentificationData: try JSONEncoder().encode(petIdentification)
        )

        let projection = InferenceHistoricalRecordProjection(
            record: record,
            resetLocalLookalikes: false
        )
        let species = projection.speciesData

        #expect(projection.scanId == "historical-complete")
        #expect(projection.displayedScientificName == "Danaus plexippus")
        #expect(projection.overrideScientificName == nil)
        #expect(projection.mediaSnapshot.items == mediaItems)
        #expect(
            projection.referenceImageURL ==
                "https://example.com/monarch.jpg"
        )
        #expect(projection.referenceURLs == ["https://example.com/monarch.jpg"])
        #expect(projection.gbifTaxonKey == 5_137_920)
        #expect(species.scanId == "historical-complete")
        #expect(species.presentationRole == .inferenceResult)
        #expect(species.commonName == "Monarch")
        #expect(species.scientificName == "Danaus plexippus")
        #expect(species.aiScientificName == "Danaus plexippus")
        #expect(species.confidenceScore == 0.94)
        #expect(species.blurScore == nil)
        #expect(species.insightData.aiReasoning == "Orange wings with black veins.")
        #expect(species.insightData.hazardType == "poisonous")
        #expect(
            species.wikipediaUrl ==
                "https://en.wikipedia.org/wiki/Monarch_butterfly"
        )
        #expect(
            species.wikipediaOverview ==
                "A migratory milkweed butterfly."
        )
        #expect(
            species.referenceImageUrl ==
                "https://example.com/monarch.jpg"
        )
        #expect(species.isBiological)
        #expect(!species.isLiveCapture)
        #expect(species.isInvasive)
        #expect(species.invasiveStatusRegion == "Oceania")
        #expect(species.invasiveRationale == "Introduced population")
        #expect(species.invasiveConfidence == 0.88)
        #expect(species.ecologyType == "terrestrial")
        #expect(species.taxonomy?.kingdom == "Animalia")
        #expect(species.taxonomy?.phylum == "Arthropoda")
        #expect(species.taxonomy?.className == "Insecta")
        #expect(species.taxonomy?.order == "Lepidoptera")
        #expect(species.taxonomy?.family == "Nymphalidae")
        #expect(species.taxonomy?.genus == "Danaus")
        #expect(!species.isNewDiscovery)
        #expect(!species.isNewToMerianDictionary)
        #expect(species.locationName == "Prairie")
        #expect(species.weatherCondition == "Clear")
        #expect(species.weatherTemperatureF == 72)
        #expect(species.gpsElevation == 181)
        #expect(species.gpsLatitude == 41.8)
        #expect(species.gpsLongitude == -87.6)
        #expect(species.colors == nil)
        #expect(species.groupTags == nil)
        #expect(species.iucnRedListStatus == "LC")
        #expect(species.zoomFactor == 2)
        #expect(species.estimatedSizeCm == 9.5)
        #expect(species.lifeStage == "adult")
        #expect(species.reproductiveCondition == "unknown")
        #expect(species.sex == "female")
        #expect(species.sexConfidence == 0.7)
        #expect(species.sexEvidence == "wing venation")
        #expect(species.individualCount == 2)
        #expect(species.ecologicalInteractions == ["pollinating"])
        #expect(species.aiReasoning == "Orange wings with black veins.")
        #expect(species.habitatDescription == "Open fields with milkweed.")
        #expect(species.gbifTaxonKey == 5_137_920)
        #expect(species.inferenceTier == "pro")
        #expect(species.alternativeCommonNames == ["Milkweed butterfly"])
        #expect(species.petIdentification == petIdentification)
        #expect(species.userConfirmedIdentification)
        #expect(species.isFlagged)
        #expect(species.imageQualityScore == 92)
        #expect(species.userIdentificationOverride == nil)
        #expect(!species.alternativesExhausted)
        #expect(species.similarSpecies == nil)
        #expect(species.candidates == nil)
        #expect(species.audioFilePaths == nil)
        #expect(species.videoFilePaths == nil)
        #expect(
            projection.hydrationPlan == .init(
                allowsSpeciesHydration: true,
                allowsReferenceImages: true,
                shouldResetLocalLookalikes: false,
                needsWikipedia: false,
                needsMetadata: false,
                needsLookalikes: false
            )
        )

        let decoded = await InferenceHistoricalRecordProjection
            .decodeDeferredContent(projection.deferredContent)
        #expect(decoded.similarSpecies?.entries.first?.commonName == "Queen")
        #expect(decoded.candidates?.first?.scientificName == "Danaus erippus")
    }

    @Test func activeOverrideOwnsDisplayIdentityAndSuppressesAIReasoning() {
        let record = LocalScanRecord(
            id: "historical-override",
            speciesId: "original-id",
            scientificName: "Procyon lotor",
            commonName: "White-nosed Coati",
            isBiological: true,
            wikipediaOverview: "A member of the raccoon family.",
            referenceImageUrl: "https://example.com/coati.jpg",
            taxonomyKingdom: "Animalia",
            taxonomyOrder: "Carnivora",
            aiReasoning: "The original image resembled a raccoon.",
            habitatDescription: "Woodlands.",
            gbifTaxonKey: 2_435_878,
            userIdentificationOverride: "Nasua narica"
        )

        let projection = InferenceHistoricalRecordProjection(
            record: record,
            resetLocalLookalikes: false
        )

        #expect(projection.displayedScientificName == "Nasua narica")
        #expect(projection.overrideScientificName == "Nasua narica")
        #expect(projection.speciesData.scientificName == "Nasua narica")
        #expect(projection.speciesData.aiScientificName == "Procyon lotor")
        #expect(projection.speciesData.userIdentificationOverride == "Nasua narica")
        #expect(projection.speciesData.insightData.aiReasoning.isEmpty)
        #expect(
            projection.speciesData.aiReasoning ==
                "The original image resembled a raccoon."
        )
    }

    @Test func humanAndUnresolvedRecordsSuppressSpeciesHydration() async throws {
        let staleCandidates = try JSONEncoder().encode([
            IdentificationCandidate(
                scientificName: "Turdus migratorius",
                confidenceScore: 0.75
            )
        ])
        let records = [
            LocalScanRecord(
                id: "historical-human",
                speciesId: "human-id",
                scientificName: "Homo sapiens",
                commonName: "Person",
                isBiological: true,
                referenceImageUrl: "https://example.com/person.jpg",
                candidatesData: staleCandidates,
                gbifTaxonKey: 1
            ),
            LocalScanRecord(
                id: "historical-unresolved",
                speciesId: "unresolved-id",
                scientificName:
                    LocalScanRecord.unresolvedBiologicalScientificName,
                commonName: LocalScanRecord.unresolvedBiologicalCommonName,
                isBiological: true,
                referenceImageUrl: "https://example.com/stale.jpg",
                candidatesData: staleCandidates,
                gbifTaxonKey: 2
            )
        ]

        for record in records {
            let projection = InferenceHistoricalRecordProjection(
                record: record,
                resetLocalLookalikes: true
            )
            let decoded = await InferenceHistoricalRecordProjection
                .decodeDeferredContent(projection.deferredContent)

            #expect(!projection.hydrationPlan.allowsSpeciesHydration)
            #expect(!projection.hydrationPlan.allowsReferenceImages)
            #expect(!projection.hydrationPlan.shouldResetLocalLookalikes)
            #expect(!projection.hydrationPlan.needsWikipedia)
            #expect(!projection.hydrationPlan.needsEnrichment)
            #expect(projection.speciesData.confidenceScore == 0)
            #expect(projection.speciesData.referenceImageUrl == nil)
            #expect(projection.speciesData.gbifTaxonKey == nil)
            #expect(projection.speciesData.taxonomy == nil)
            #expect(projection.speciesData.petIdentification == nil)
            #expect(decoded.similarSpecies == nil)
            #expect(decoded.candidates == nil)
        }
    }

    @Test func deferredDecodeOwnsValuesAfterRecordDeletion() async throws {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let candidates = [
            IdentificationCandidate(
                scientificName: "Bassariscus astutus",
                confidenceScore: 0.65
            )
        ]
        let record = LocalScanRecord(
            id: "historical-deleted",
            speciesId: "raccoon-id",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            isBiological: true,
            similarSpecies: ["Procyon cancrivorus"],
            candidatesData: try JSONEncoder().encode(candidates)
        )
        context.insert(record)
        try context.save()

        let projection = InferenceHistoricalRecordProjection(
            record: record,
            resetLocalLookalikes: false
        )
        context.delete(record)
        try context.save()
        #expect(
            try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 0
        )

        let decoded = await InferenceHistoricalRecordProjection
            .decodeDeferredContent(projection.deferredContent)

        #expect(projection.scanId == "historical-deleted")
        #expect(
            decoded.similarSpecies?.lookalikes == ["Procyon cancrivorus"]
        )
        #expect(
            decoded.candidates?.first?.scientificName ==
                "Bassariscus astutus"
        )
    }

    @Test func legacyLookalikesAndCandidatesDecodeWithoutRichData() async throws {
        let candidates = [
            IdentificationCandidate(
                scientificName: "Bassariscus astutus",
                confidenceScore: 0.65
            )
        ]
        let record = LocalScanRecord(
            id: "historical-legacy",
            speciesId: "raccoon-id",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            isBiological: true,
            similarSpecies: [
                "Procyon cancrivorus",
                "Bassariscus astutus"
            ],
            candidatesData: try JSONEncoder().encode(candidates)
        )

        let projection = InferenceHistoricalRecordProjection(
            record: record,
            resetLocalLookalikes: false
        )
        let decoded = await InferenceHistoricalRecordProjection
            .decodeDeferredContent(projection.deferredContent)

        #expect(projection.speciesData.similarSpecies == nil)
        #expect(projection.speciesData.candidates == nil)
        #expect(projection.hydrationPlan.needsLookalikes)
        #expect(
            decoded.similarSpecies?.lookalikes == [
                "Procyon cancrivorus",
                "Bassariscus astutus"
            ]
        )
        #expect(decoded.similarSpecies?.entries.first?.commonName == nil)
        #expect(decoded.candidates?.first?.scientificName == "Bassariscus astutus")
    }

    @Test func richCommonNameStateControlsLookalikeRefresh() throws {
        let richRecord = completeHydrationRecord(
            lookalikes: [
                SimilarSpeciesEntry(
                    scientificName: "Procyon cancrivorus",
                    commonName: "Crab-eating Raccoon",
                    referenceImageUrl: nil,
                    iucnRedListStatus: nil
                )
            ]
        )
        let unnamedRecord = completeHydrationRecord(
            lookalikes: [
                SimilarSpeciesEntry(
                    scientificName: "Procyon cancrivorus",
                    commonName: nil,
                    referenceImageUrl: nil,
                    iucnRedListStatus: nil
                )
            ]
        )

        let richProjection = InferenceHistoricalRecordProjection(
            record: richRecord,
            resetLocalLookalikes: false
        )
        let unnamedProjection = InferenceHistoricalRecordProjection(
            record: unnamedRecord,
            resetLocalLookalikes: false
        )

        #expect(!richProjection.hydrationPlan.needsLookalikes)
        #expect(unnamedProjection.hydrationPlan.needsLookalikes)
        #expect(!richProjection.hydrationPlan.needsMetadata)
        #expect(!unnamedProjection.hydrationPlan.needsMetadata)
    }

    @Test func resetAndMissingMetadataProduceIndependentHydrationScopes() async throws {
        let record = completeHydrationRecord(
            lookalikes: [
                SimilarSpeciesEntry(
                    scientificName: "Procyon cancrivorus",
                    commonName: "Crab-eating Raccoon",
                    referenceImageUrl: nil,
                    iucnRedListStatus: nil
                )
            ]
        )
        record.similarSpecies = ["Bassariscus astutus"]
        record.habitatDescription = " \n\t "
        record.referenceImageUrl = nil

        let projection = InferenceHistoricalRecordProjection(
            record: record,
            resetLocalLookalikes: true
        )
        let decoded = await InferenceHistoricalRecordProjection
            .decodeDeferredContent(projection.deferredContent)

        #expect(projection.hydrationPlan.shouldResetLocalLookalikes)
        #expect(projection.hydrationPlan.needsMetadata)
        #expect(projection.hydrationPlan.needsLookalikes)
        #expect(projection.hydrationPlan.needsWikipedia)
        #expect(projection.hydrationPlan.needsEnrichment)
        #expect(decoded.similarSpecies == nil)
    }

    @Test func malformedCandidatesFailSoftly() async {
        let record = completeHydrationRecord(lookalikes: [])
        record.candidatesData = Data("not-json".utf8)
        let projection = InferenceHistoricalRecordProjection(
            record: record,
            resetLocalLookalikes: false
        )

        let decoded = await InferenceHistoricalRecordProjection
            .decodeDeferredContent(projection.deferredContent)

        #expect(decoded.candidates == nil)
    }

    private func completeHydrationRecord(
        lookalikes: [SimilarSpeciesEntry]
    ) -> LocalScanRecord {
        LocalScanRecord(
            id: "complete-\(UUID().uuidString.lowercased())",
            speciesId: "raccoon-id",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            isBiological: true,
            wikipediaOverview: "A medium-sized mammal.",
            referenceImageUrl: "https://example.com/raccoon.jpg",
            taxonomyKingdom: "Animalia",
            taxonomyOrder: "Carnivora",
            taxonomyFamily: "Procyonidae",
            lookalikesData: try? JSONEncoder().encode(lookalikes),
            habitatDescription: "Woodlands and urban areas.",
            gbifTaxonKey: 2_433_697
        )
    }
}
