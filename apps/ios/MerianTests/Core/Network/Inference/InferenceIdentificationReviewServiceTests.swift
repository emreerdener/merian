import Foundation
import Testing

@testable import Merian

@MainActor
@Suite("Inference Identification Review Service")
struct InferenceReviewServiceTests {
    @Test func dictionaryRecordDecodesThePostgRESTProjection() throws {
        let data = Data(
            """
            {
              "id": "species-id",
              "common_names": {"en": "Monarch", "fr": null},
              "kingdom": "Animalia",
              "phylum": "Arthropoda",
              "class": "Insecta",
              "order": "Lepidoptera",
              "family": "Nymphalidae",
              "genus": "Danaus",
              "wikipedia_overview": "A migratory butterfly.",
              "hazard_type": "none",
              "reference_image_url": "https://example.com/monarch.webp",
              "wikipedia_url": "https://example.com/monarch",
              "iucn_red_list_status": "LC",
              "habitat_description": "Open fields",
              "gbif_taxon_key": 5131911
            }
            """.utf8
        )

        let record = try JSONDecoder().decode(
            InferenceSpeciesDictionaryRecord.self,
            from: data
        )

        #expect(record.id == "species-id")
        let commonNames = try #require(record.commonNames)
        #expect(commonNames["en"] == "Monarch")
        #expect(commonNames.keys.contains("fr"))
        #expect(commonNames.compactMapValues { $0 }["fr"] == nil)
        #expect(record.className == "Insecta")
        #expect(record.gbifTaxonKey == 5_131_911)
    }

    @Test func reviewMutationEncodesExplicitNullsForClearedValues() throws {
        let mutation = InferenceIdentificationReviewMutation(
            scanID: "scan-id",
            override: nil,
            confirmed: false,
            confirmedSpeciesID: nil,
            userReviewState: "unreviewed"
        )

        let object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(mutation)
            ) as? [String: Any]
        )

        #expect(object["p_scan_id"] as? String == "scan-id")
        #expect(object["p_override"] is NSNull)
        #expect(object["p_confirmed"] as? Bool == false)
        #expect(object["p_confirmed_species_id"] is NSNull)
        #expect(object["p_user_review_state"] as? String == "unreviewed")
    }

    @Test func injectedHandlersReceiveTypedInputsAndReturnTypedValues() async throws {
        let expectedRecord = InferenceSpeciesDictionaryRecord(
            id: "species-id",
            commonNames: ["en": "Monarch"],
            kingdom: "Animalia",
            phylum: nil,
            className: nil,
            order: nil,
            family: nil,
            genus: "Danaus",
            wikipediaOverview: nil,
            hazardType: "none",
            referenceImageURL: nil,
            wikipediaURL: nil,
            iucnRedListStatus: nil,
            habitatDescription: nil,
            gbifTaxonKey: nil
        )
        let mutation = InferenceIdentificationReviewMutation(
            scanID: "scan-id",
            override: "Danaus plexippus",
            confirmed: true,
            confirmedSpeciesID: "species-id",
            userReviewState: "confirmed"
        )
        var loadedNames: [String] = []
        var loadedIDNames: [String] = []
        var syncedMutations: [InferenceIdentificationReviewMutation] = []
        let service = InferenceIdentificationReviewService(
            loadSpecies: { scientificName in
                loadedNames.append(scientificName)
                return expectedRecord
            },
            loadSpeciesID: { scientificName in
                loadedIDNames.append(scientificName)
                return expectedRecord.id
            },
            syncReview: { mutation in
                syncedMutations.append(mutation)
            }
        )

        #expect(try await service.loadSpecies(
            scientificName: "Danaus plexippus"
        ) == expectedRecord)
        #expect(try await service.loadSpeciesID(
            scientificName: "Danaus plexippus"
        ) == expectedRecord.id)
        try await service.syncReview(mutation)

        #expect(loadedNames == ["Danaus plexippus"])
        #expect(loadedIDNames == ["Danaus plexippus"])
        #expect(syncedMutations == [mutation])
    }
}
