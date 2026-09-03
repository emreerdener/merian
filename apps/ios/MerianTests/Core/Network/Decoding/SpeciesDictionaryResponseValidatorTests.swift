import Foundation
import Testing

@testable import Merian

@Suite("Species Dictionary Response Validation")
struct SpeciesDictionaryResponseValidatorTests {
    private typealias Fixtures = SpeciesDictionaryNetworkFixtures
    private typealias Validator = SpeciesDictionaryResponseValidator

    @Test func catalogAndOverviewRequireExactlySchemaOne() throws {
        let overview = try Fixtures.decode(SpeciesDictionaryOverviewResponse.self, json: Fixtures.overviewJSON).data
        for schema: Int? in [nil, 0, 1, 2, 99] {
            let catalogResponse = SpeciesDictionaryCatalogResponse(schemaVersion: schema, data: [], nextCursor: nil)
            let overviewResponse = SpeciesDictionaryOverviewResponse(schemaVersion: schema, data: overview)
            if schema == 1 {
                #expect(try Validator.catalog(catalogResponse).schemaVersion == 1)
                #expect(try Validator.overview(overviewResponse).schemaVersion == 1)
            } else {
                #expect(throws: MerianError.invalidResponse) { try Validator.catalog(catalogResponse) }
                #expect(throws: MerianError.invalidResponse) { try Validator.overview(overviewResponse) }
            }
        }
    }

    @Test func dictionaryRequiresSchemaOneAndANonemptyBoundedReturnedName() throws {
        for schema: Int? in [nil, 0, 1, 2, 99] {
            let response = SpeciesDictionaryResponse(schemaVersion: schema, data: Fixtures.dictionaryEntry())
            if schema == 1 {
                #expect(try Validator.dictionaryEntry(
                    response, requestedSpeciesId: Fixtures.speciesID, requestedScientificName: nil
                ) == response.data)
            } else {
                #expect(throws: MerianError.invalidResponse) {
                    try Validator.dictionaryEntry(response, requestedSpeciesId: Fixtures.speciesID, requestedScientificName: nil)
                }
            }
        }
        for name in ["", " \n\t ", String(repeating: "x", count: 161)] {
            #expect(throws: MerianError.invalidResponse) {
                try validateDictionary(Fixtures.dictionaryEntry(scientificName: name), requestedID: Fixtures.speciesID)
            }
        }
        let bounded = Fixtures.dictionaryEntry(scientificName: String(repeating: "é", count: 160))
        #expect(try validateDictionary(bounded, requestedID: Fixtures.speciesID) == bounded)
    }

    @Test func matchingCanonicalIDWinsOverASuppliedDifferentName() throws {
        let entry = Fixtures.dictionaryEntry(
            id: " \(Fixtures.speciesID.uppercased()) ", scientificName: "  Renamed   testus  "
        )
        #expect(try validateDictionary(entry, requestedID: Fixtures.speciesID, requestedName: "Old testus") == entry)
    }

    @Test func staleIDRecoveryRequiresTheRequestedNameAndAReturnedCanonicalID() throws {
        let entry = Fixtures.dictionaryEntry(id: Fixtures.alternateID, scientificName: " TESTUS \n floridus ")
        #expect(try validateDictionary(
            entry, requestedID: Fixtures.speciesID, requestedName: Fixtures.scientificName
        ) == entry)

        for name: String? in [nil, "Wrong testus", " ", String(repeating: "x", count: 161)] {
            #expect(throws: MerianError.invalidResponse) {
                try validateDictionary(entry, requestedID: Fixtures.speciesID, requestedName: name)
            }
        }
        for id in ["external:testus%20floridus", "not-a-uuid", ""] {
            #expect(throws: MerianError.invalidResponse) {
                try validateDictionary(
                    Fixtures.dictionaryEntry(id: id),
                    requestedID: Fixtures.speciesID, requestedName: Fixtures.scientificName
                )
            }
        }
    }

    @Test func nameOnlyAcceptsCanonicalOrExternalIdentityButNotArbitraryIDs() throws {
        for id in [Fixtures.speciesID, "external:testus%20floridus", "  EXTERNAL:testus  "] {
            let entry = Fixtures.dictionaryEntry(id: id)
            #expect(try validateDictionary(entry, requestedName: " TESTUS \n FLORIDUS ") == entry)
        }
        for id in ["not-a-uuid", "", "public:testus"] {
            #expect(throws: MerianError.invalidResponse) {
                try validateDictionary(Fixtures.dictionaryEntry(id: id), requestedName: Fixtures.scientificName)
            }
        }
        for name: String? in [nil, "Wrong testus", " "] {
            #expect(throws: MerianError.invalidResponse) {
                try validateDictionary(Fixtures.dictionaryEntry(), requestedName: name)
            }
        }
    }

    @Test func statsAllowsNewerSchemasAndUnknownStatusesWithoutWeakeningIdentityChecks() throws {
        let entry = Fixtures.statsEntry(
            id: " \(Fixtures.speciesID.uppercased()) ",
            scientificName: " TESTUS \n floridus ",
            status: .unknown("future_status")
        )
        for schema: Int? in [nil, 0, 1, 2, 3, 99] {
            let response = SpeciesObservationStatsResponse(schemaVersion: schema, data: entry)
            if let schema, schema >= 2 {
                #expect(try Validator.observationStats(
                    response, requestedSpeciesId: Fixtures.speciesID, requestedScientificName: Fixtures.scientificName
                ) == entry)
            } else {
                #expect(throws: MerianError.invalidResponse) {
                    try Validator.observationStats(
                        response, requestedSpeciesId: Fixtures.speciesID, requestedScientificName: Fixtures.scientificName
                    )
                }
            }
        }
    }

    @Test func statsRequiresBothCanonicalIDAndMatchingNormalizedName() {
        for id: String? in [nil, "", "external:testus", Fixtures.alternateID] {
            #expect(throws: MerianError.invalidResponse) {
                try validateStats(Fixtures.statsEntry(id: id))
            }
        }
        for name in ["", " \n ", "Different testus", String(repeating: "x", count: 161)] {
            #expect(throws: MerianError.invalidResponse) {
                try validateStats(Fixtures.statsEntry(scientificName: name))
            }
        }
    }

    private func validateDictionary(
        _ entry: SpeciesDictionaryEntry, requestedID: String? = nil, requestedName: String? = nil
    ) throws -> SpeciesDictionaryEntry {
        try Validator.dictionaryEntry(
            SpeciesDictionaryResponse(schemaVersion: 1, data: entry),
            requestedSpeciesId: requestedID, requestedScientificName: requestedName
        )
    }

    private func validateStats(_ entry: SpeciesObservationStatsEntry) throws -> SpeciesObservationStatsEntry {
        try Validator.observationStats(
            SpeciesObservationStatsResponse(schemaVersion: 2, data: entry),
            requestedSpeciesId: Fixtures.speciesID, requestedScientificName: Fixtures.scientificName
        )
    }
}
