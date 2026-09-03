import Foundation
import Testing

@testable import Merian

@Suite("Species Observation Stats API Models")
struct SpeciesObservationStatsAPIModelsTests {
    @Test func testSpeciesObservationStatsResponseDecodesPublicCharts() throws {
        let data = Data("""
        {
            "schema_version": 2,
            "data": {
                "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                "scientific_name": "Danaus plexippus",
                "source": {
                    "provider": "inaturalist",
                    "scope": "global",
                    "inaturalist_taxon_id": 48662,
                    "fetched_at": "2026-05-17T12:00:00.000Z"
                },
                "status": "partial",
                "total_observations": 450448,
                "last_observation_date": "2026-05-17",
                "fetched_at": "2026-05-17T12:00:00.000Z",
                "provider_errors": ["life stage bucket unavailable"],
                "seasonality": [
                    { "month": 1, "count": 10 },
                    { "month": 2, "count": 20 }
                ],
                "history": [
                    { "year": 2026, "month": 5, "count": 40 }
                ],
                "life_stage": [
                    {
                        "key": "adult",
                        "label": "Adult",
                        "values": [{ "month": 8, "count": 100 }]
                    }
                ],
                "sex": [
                    {
                        "key": "female",
                        "label": "Female",
                        "values": [{ "month": 8, "count": 12 }]
                    }
                ]
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesObservationStatsResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 2)
        #expect(response.data.scientificName == "Danaus plexippus")
        #expect(response.data.status == .partial)
        #expect(response.data.totalObservations == 450448)
        #expect(response.data.source.inaturalistTaxonId == 48662)
        #expect(response.data.lifeStage.first?.label == "Adult")
    }
}
