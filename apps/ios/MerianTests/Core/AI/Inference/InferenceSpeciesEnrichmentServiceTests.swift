import Foundation
import Testing

@testable import Merian

@MainActor
private final class SpeciesEnrichmentFetchRecorder {
    var response = EnrichScanResponse(success: true, data: nil)
    var error: Error?
    private(set) var requests: [InferenceSpeciesEnrichmentService.Request] = []
    private(set) var scopes: [InferenceSpeciesEnrichmentService.Scope] = []

    func dependencies() -> InferenceSpeciesEnrichmentService.Dependencies {
        InferenceSpeciesEnrichmentService.Dependencies { [self] request, scope in
            requests.append(request)
            scopes.append(scope)
            if let error { throw error }
            return response
        }
    }
}

@MainActor
@Suite("Inference Species Enrichment Service")
struct InferenceSpeciesEnrichmentServiceTests {
    @Test func metadataRequestIsForwardedAndNormalized() async throws {
        let recorder = SpeciesEnrichmentFetchRecorder()
        recorder.response = try decodeResponse(
            """
            {
              "success": true,
              "data": {
                "habitat_description": "  Open fields and meadows  ",
                "gbif_taxon_key": 5137920,
                "taxonomy": {
                  "kingdom": "Animalia",
                  "phylum": "Arthropoda",
                  "class": "Insecta",
                  "order": "Lepidoptera",
                  "family": "Nymphalidae",
                  "genus": "Danaus"
                },
                "alternative_common_names": [
                  " Monarch, Milkweed butterfly ",
                  "monarch",
                  " "
                ]
              }
            }
            """
        )
        let service = InferenceSpeciesEnrichmentService(
            dependencies: recorder.dependencies()
        )
        let request = makeRequest()

        let patch = try #require(
            await service.fetchMetadata(for: request)
        )

        #expect(recorder.requests == [request])
        #expect(recorder.scopes == [.metadata])
        #expect(patch.habitatDescription == "Open fields and meadows")
        #expect(patch.gbifTaxonKey == 5_137_920)
        #expect(patch.taxonomy?.kingdom == "Animalia")
        #expect(patch.taxonomy?.phylum == "Arthropoda")
        #expect(patch.taxonomy?.className == "Insecta")
        #expect(patch.taxonomy?.order == "Lepidoptera")
        #expect(patch.taxonomy?.family == "Nymphalidae")
        #expect(patch.taxonomy?.genus == "Danaus")
        #expect(
            patch.alternativeCommonNames ==
                ["Monarch", "Milkweed butterfly"]
        )
        #expect(
            patch.persistedAlternativeCommonNames == [
                " Monarch, Milkweed butterfly ",
                "monarch",
                " "
            ]
        )

        let applied = patch.applying(to: makeSpeciesData())
        #expect(applied.habitatDescription == "Open fields and meadows")
        #expect(applied.gbifTaxonKey == 5_137_920)
        #expect(applied.taxonomy?.genus == "Danaus")
        #expect(
            applied.alternativeCommonNames ==
                ["Monarch", "Milkweed butterfly"]
        )
    }

    @Test func absentMetadataFieldsPreserveExistingPresentation() async throws {
        let recorder = SpeciesEnrichmentFetchRecorder()
        recorder.response = try decodeResponse(
            """
            {
              "success": true,
              "data": {
                "habitat_description": "  "
              }
            }
            """
        )
        let service = InferenceSpeciesEnrichmentService(
            dependencies: recorder.dependencies()
        )
        let existing = makeSpeciesData(
            habitatDescription: "Existing habitat",
            alternativeCommonNames: ["Existing name"]
        )

        let patch = try #require(
            await service.fetchMetadata(for: makeRequest())
        )
        let applied = patch.applying(to: existing)

        #expect(applied.habitatDescription == "Existing habitat")
        #expect(applied.alternativeCommonNames == ["Existing name"])
        #expect(patch.persistedAlternativeCommonNames == nil)
    }

    @Test func providedButEmptyNamesClearExistingPresentation() async throws {
        let recorder = SpeciesEnrichmentFetchRecorder()
        recorder.response = try decodeResponse(
            """
            {
              "success": true,
              "data": {
                "alternative_common_names": ["  "]
              }
            }
            """
        )
        let service = InferenceSpeciesEnrichmentService(
            dependencies: recorder.dependencies()
        )

        let patch = try #require(
            await service.fetchMetadata(for: makeRequest())
        )
        let applied = patch.applying(
            to: makeSpeciesData(alternativeCommonNames: ["Existing name"])
        )

        #expect(patch.alternativeCommonNames == nil)
        #expect(applied.alternativeCommonNames == nil)
        #expect(patch.persistedAlternativeCommonNames == ["  "])
    }

    @Test func lookalikeResponseMapsEveryPresentationField() async throws {
        let recorder = SpeciesEnrichmentFetchRecorder()
        recorder.response = try decodeResponse(
            """
            {
              "success": true,
              "data": {
                "similar_species": [{
                  "species_id": "candidate-id",
                  "scientific_name": "Danaus gilippus",
                  "common_name": "Queen, Queen butterfly",
                  "reference_image_url": "https://example.com/queen.jpg",
                  "iucn_red_list_status": "LC",
                  "reason": "Similar wing pattern",
                  "visual_traits": ["white-spotted forewings"],
                  "confidence": 0.86,
                  "source": "curated",
                  "review_status": "approved",
                  "is_bidirectional": true,
                  "sort_order": 2
                }]
              }
            }
            """
        )
        let service = InferenceSpeciesEnrichmentService(
            dependencies: recorder.dependencies()
        )

        let patch = try #require(
            await service.fetchLookalikes(for: makeRequest())
        )
        let entry = try #require(patch.entries.first)

        #expect(recorder.scopes == [.lookalikes])
        #expect(entry.speciesId == "candidate-id")
        #expect(entry.scientificName == "Danaus gilippus")
        #expect(entry.commonName == "Queen")
        #expect(entry.referenceImageUrl == "https://example.com/queen.jpg")
        #expect(entry.iucnRedListStatus == "LC")
        #expect(entry.similarityReason == "Similar wing pattern")
        #expect(entry.visualTraits == ["white-spotted forewings"])
        #expect(entry.similarityConfidence == 0.86)
        #expect(entry.relationshipSource == "curated")
        #expect(entry.reviewStatus == "approved")
        #expect(entry.isBidirectional == true)
        #expect(entry.sortOrder == 2)
        #expect(
            patch.applying(to: makeSpeciesData())
                .similarSpecies?.entries.first?.scientificName ==
                "Danaus gilippus"
        )
    }

    @Test func nilAndEmptyPayloadsProduceNoPatch() async throws {
        let recorder = SpeciesEnrichmentFetchRecorder()
        let service = InferenceSpeciesEnrichmentService(
            dependencies: recorder.dependencies()
        )

        #expect(try await service.fetchMetadata(for: makeRequest()) == nil)

        recorder.response = try decodeResponse(
            """
            {
              "success": true,
              "data": { "similar_species": [] }
            }
            """
        )
        #expect(try await service.fetchLookalikes(for: makeRequest()) == nil)
    }

    @Test func transportErrorsRemainAvailableToEnginePolicy() async {
        let recorder = SpeciesEnrichmentFetchRecorder()
        recorder.error = TestError.unavailable
        let service = InferenceSpeciesEnrichmentService(
            dependencies: recorder.dependencies()
        )

        do {
            _ = try await service.fetchMetadata(for: makeRequest())
            Issue.record("Expected the injected transport error")
        } catch TestError.unavailable {
            #expect(recorder.scopes == [.metadata])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeRequest() -> InferenceSpeciesEnrichmentService.Request {
        InferenceSpeciesEnrichmentService.Request(
            scanId: "00000000-0000-4000-8000-00000000e321",
            scientificName: "Danaus plexippus",
            confidenceScore: 0.94,
            inferenceTier: "pro"
        )
    }

    private func makeSpeciesData(
        habitatDescription: String? = nil,
        alternativeCommonNames: [String]? = nil
    ) -> SpeciesData {
        SpeciesData(
            scanId: "00000000-0000-4000-8000-00000000e321",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(
                aiReasoning: "Synthetic observation",
                hazardType: "none"
            ),
            confidenceScore: 0.94,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "terrestrial",
            habitatDescription: habitatDescription,
            inferenceTier: "pro",
            alternativeCommonNames: alternativeCommonNames
        )
    }

    private func decodeResponse(_ json: String) throws -> EnrichScanResponse {
        try JSONDecoder().decode(
            EnrichScanResponse.self,
            from: Data(json.utf8)
        )
    }

    private enum TestError: Error {
        case unavailable
    }
}
