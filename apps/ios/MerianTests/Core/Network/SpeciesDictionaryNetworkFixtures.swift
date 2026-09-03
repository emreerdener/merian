import Foundation

@testable import Merian

/// Synthetic wire and value fixtures shared by network-owned Dictionary suites.
enum SpeciesDictionaryNetworkFixtures {
    static let speciesID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let alternateID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    static let scientificName = "Testus floridus"

    static let dictionaryJSON = #"""
    {"schema_version":1,"data":{
      "id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","scientific_name":"Testus floridus","common_name":"Test Flower",
      "alternative_common_names":[],"group_tags":[],"reference_images":[],"similar_species":[]
    }}
    """#
    static let catalogJSON = #"{"schema_version":1,"data":[],"next_cursor":null}"#
    static let overviewJSON = #"{"schema_version":1,"data":{"categories":[],"regions":[]}}"#
    static let statsJSON = #"""
    {"schema_version":2,"data":{
      "species_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","scientific_name":"Testus floridus",
      "source":{"provider":"inaturalist","scope":"global","fetched_at":"2026-06-01T00:00:00Z"},
      "status":"fresh","total_observations":12,"fetched_at":"2026-06-01T00:00:00Z",
      "provider_errors":[],"seasonality":[],"history":[],"life_stage":[]
    }}
    """#

    static func dictionaryEntry(
        id: String = speciesID,
        scientificName: String = scientificName,
        commonName: String = "Test Flower"
    ) -> SpeciesDictionaryEntry {
        SpeciesDictionaryEntry(
            id: id, scientificName: scientificName, commonName: commonName, contentQuality: .complete,
            alternativeCommonNames: [], taxonomy: nil, hazardType: nil, iucnRedListStatus: nil,
            wikipediaUrl: nil, wikipediaOverview: nil, habitatDescription: nil, gbifTaxonKey: nil,
            groupTags: [], referenceImages: [], similarSpecies: []
        )
    }

    static func statsEntry(
        id: String? = speciesID,
        scientificName: String = scientificName,
        status: SpeciesObservationStatsStatus = .fresh
    ) -> SpeciesObservationStatsEntry {
        SpeciesObservationStatsEntry(
            speciesId: id,
            scientificName: scientificName,
            source: SpeciesObservationStatsSource(
                provider: "inaturalist", scope: "global", inaturalistTaxonId: nil, fetchedAt: "2026-06-01T00:00:00Z"
            ),
            status: status,
            totalObservations: 12,
            lastObservationDate: nil,
            fetchedAt: "2026-06-01T00:00:00Z",
            providerErrors: [],
            seasonality: [],
            history: [],
            lifeStage: []
        )
    }

    static func decode<Response: Decodable>(_ type: Response.Type, json: String) throws -> Response {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: Data(json.utf8))
    }
}
