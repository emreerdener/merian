import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite("Inference Hydration Persistence Service")
struct InferenceHydrationPersistenceTests {
    @Test func serviceForwardsExactAdmittedSnapshots() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        var recordedReference:
            InferenceHydrationPersistenceService.ReferenceSnapshot?
        var recordedMetadata:
            InferenceHydrationPersistenceService.MetadataSnapshot?
        var recordedLookalikes:
            InferenceHydrationPersistenceService.LookalikesSnapshot?
        let service = InferenceHydrationPersistenceService(
            dependencies: .init(
                persistReference: { snapshot, receivedContainer in
                    #expect(receivedContainer === container)
                    recordedReference = snapshot
                },
                persistMetadata: { snapshot, receivedContainer in
                    #expect(receivedContainer === container)
                    recordedMetadata = snapshot
                },
                persistLookalikes: { snapshot, receivedContainer in
                    #expect(receivedContainer === container)
                    recordedLookalikes = snapshot
                }
            )
        )
        let reference = InferenceHydrationPersistenceService
            .ReferenceSnapshot(
                scanId: "scan-id",
                extract: "Reference overview",
                url: "https://example.com/reference",
                imageUrl: "https://example.com/reference.jpg",
                expectedScientificName: "Danaus plexippus"
            )
        let taxonomy = TaxonomyData(
            kingdom: "Animalia",
            phylum: "Arthropoda",
            className: "Insecta",
            order: "Lepidoptera",
            family: "Nymphalidae",
            genus: "Danaus"
        )
        let metadata = InferenceHydrationPersistenceService.MetadataSnapshot(
            scanId: "scan-id",
            habitatDescription: "Open fields",
            gbifTaxonKey: 5_137_920,
            taxonomy: taxonomy,
            alternativeCommonNames: ["Milkweed butterfly"],
            expectedScientificName: "Danaus plexippus"
        )
        let lookalikeEntry = makeLookalike()
        let lookalikes = InferenceHydrationPersistenceService
            .LookalikesSnapshot(
                scanId: "scan-id",
                entries: [lookalikeEntry],
                expectedScientificName: "Danaus plexippus"
            )

        await service.persistReference(reference, in: container)
        await service.persistMetadata(metadata, in: container)
        await service.persistLookalikes(lookalikes, in: container)

        #expect(recordedReference == reference)
        #expect(recordedMetadata?.scanId == "scan-id")
        #expect(recordedMetadata?.habitatDescription == "Open fields")
        #expect(recordedMetadata?.gbifTaxonKey == 5_137_920)
        #expect(recordedMetadata?.taxonomy?.className == "Insecta")
        #expect(
            recordedMetadata?.alternativeCommonNames ==
                ["Milkweed butterfly"]
        )
        #expect(
            recordedMetadata?.expectedScientificName == "Danaus plexippus"
        )
        #expect(recordedLookalikes?.scanId == "scan-id")
        #expect(
            recordedLookalikes?.entries.first?.scientificName ==
                lookalikeEntry.scientificName
        )
        #expect(
            recordedLookalikes?.expectedScientificName ==
                "Danaus plexippus"
        )
    }

    @Test func liveAdapterPersistsReferenceAndMetadata() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "hydration_metadata_\(UUID().uuidString.lowercased())"
        context.insert(
            LocalScanRecord(
                id: scanId,
                speciesId: "species-id",
                scientificName: "Danaus plexippus",
                commonName: "Monarch",
                isBiological: true,
                isLiveCapture: false
            )
        )
        try context.save()

        let service = InferenceHydrationPersistenceService.live
        await service.persistReference(
            .init(
                scanId: scanId,
                extract: "A migratory milkweed butterfly.",
                url: "https://en.wikipedia.org/wiki/Monarch_butterfly",
                imageUrl: "https://example.com/monarch.jpg",
                expectedScientificName: "Danaus plexippus"
            ),
            in: container
        )
        await service.persistMetadata(
            .init(
                scanId: scanId,
                habitatDescription: "Open fields",
                gbifTaxonKey: 5_137_920,
                taxonomy: TaxonomyData(
                    kingdom: "Animalia",
                    phylum: "Arthropoda",
                    className: "Insecta",
                    order: "Lepidoptera",
                    family: "Nymphalidae",
                    genus: "Danaus"
                ),
                alternativeCommonNames: ["Milkweed butterfly"],
                expectedScientificName: "Danaus plexippus"
            ),
            in: container
        )

        try inspectScan(scanId, in: container) { persisted in
            #expect(
                persisted.wikipediaOverview ==
                    "A migratory milkweed butterfly."
            )
            #expect(
                persisted.wikipediaUrl ==
                    "https://en.wikipedia.org/wiki/Monarch_butterfly"
            )
            #expect(
                persisted.referenceImageUrl ==
                    "https://example.com/monarch.jpg"
            )
            #expect(persisted.habitatDescription == "Open fields")
            #expect(persisted.gbifTaxonKey == 5_137_920)
            #expect(persisted.taxonomyKingdom == "Animalia")
            #expect(persisted.taxonomyClass == "Insecta")
            #expect(persisted.taxonomyGenus == "Danaus")
            #expect(
                persisted.alternativeCommonNames == ["Milkweed butterfly"]
            )
        }
    }

    @Test func liveAdapterEncodesAndPersistsLookalikes() async throws {
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let context = ModelContext(container)
        let scanId = "hydration_persistence_\(UUID().uuidString.lowercased())"
        context.insert(
            LocalScanRecord(
                id: scanId,
                speciesId: "species-id",
                scientificName: "Danaus plexippus",
                commonName: "Monarch",
                isBiological: true,
                isLiveCapture: false
            )
        )
        try context.save()

        await InferenceHydrationPersistenceService.live.persistLookalikes(
            .init(
                scanId: scanId,
                entries: [makeLookalike()],
                expectedScientificName: "Danaus plexippus"
            ),
            in: container
        )

        try inspectScan(scanId, in: container) { persisted in
            let data = try #require(persisted.lookalikesData)
            let decoded = try JSONDecoder().decode(
                [SimilarSpeciesEntry].self,
                from: data
            )
            let entry = try #require(decoded.first)

            #expect(entry.speciesId == "candidate-id")
            #expect(entry.scientificName == "Danaus gilippus")
            #expect(entry.commonName == "Queen")
            #expect(entry.visualTraits == ["white-spotted forewings"])
        }
    }

    private func inspectScan(
        _ scanId: String,
        in container: ModelContainer,
        assertions: (LocalScanRecord) throws -> Void
    ) throws {
        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<LocalScanRecord>()
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.id == scanId)
        try assertions(persisted)
    }

    private func makeLookalike() -> SimilarSpeciesEntry {
        SimilarSpeciesEntry(
            scientificName: "Danaus gilippus",
            commonName: "Queen",
            referenceImageUrl: "https://example.com/queen.jpg",
            iucnRedListStatus: "LC",
            speciesId: "candidate-id",
            similarityReason: "Similar wing pattern",
            visualTraits: ["white-spotted forewings"],
            similarityConfidence: 0.86,
            relationshipSource: "curated",
            reviewStatus: "approved",
            isBidirectional: true,
            sortOrder: 2
        )
    }
}
