import Foundation

/// Wire decoding remains in the authenticated client bridge. These checks
/// validate the schemas and identities accepted by Species Dictionary readers.
enum SpeciesDictionaryResponseValidator {
    static func catalog(_ response: SpeciesDictionaryCatalogResponse) throws -> SpeciesDictionaryCatalogResponse {
        guard response.schemaVersion == 1 else { throw MerianError.invalidResponse }
        return response
    }

    static func overview(_ response: SpeciesDictionaryOverviewResponse) throws -> SpeciesDictionaryOverviewResponse {
        guard response.schemaVersion == 1 else { throw MerianError.invalidResponse }
        return response
    }

    static func dictionaryEntry(
        _ response: SpeciesDictionaryResponse,
        requestedSpeciesId: String?,
        requestedScientificName: String?
    ) throws -> SpeciesDictionaryEntry {
        guard response.schemaVersion == 1,
              isValidDictionaryEntry(
                  response.data,
                  requestedSpeciesId: requestedSpeciesId,
                  requestedScientificName: requestedScientificName
              ) else {
            throw MerianError.invalidResponse
        }
        return response.data
    }

    static func observationStats(
        _ response: SpeciesObservationStatsResponse,
        requestedSpeciesId: String,
        requestedScientificName: String
    ) throws -> SpeciesObservationStatsEntry {
        guard response.effectiveSchemaVersion >= 2,
              SpeciesDictionaryIdentity.canonicalSpeciesID(response.data.speciesId) == requestedSpeciesId,
              SpeciesDictionaryIdentity.scientificNameCacheKey(response.data.scientificName) ==
                  SpeciesDictionaryIdentity.scientificNameCacheKey(requestedScientificName) else {
            throw MerianError.invalidResponse
        }
        return response.data
    }

    private static func isValidDictionaryEntry(
        _ entry: SpeciesDictionaryEntry,
        requestedSpeciesId: String?,
        requestedScientificName: String?
    ) -> Bool {
        let returnedSpeciesId = SpeciesDictionaryIdentity.canonicalSpeciesID(entry.id)
        let returnedScientificName = SpeciesDictionaryIdentity.scientificNameCacheKey(entry.scientificName)
        let requestedName = SpeciesDictionaryIdentity.scientificNameCacheKey(requestedScientificName)
        guard returnedScientificName != nil else { return false }

        if let requestedSpeciesId {
            if returnedSpeciesId == requestedSpeciesId {
                return true
            }
            return requestedName != nil
                && returnedScientificName == requestedName
                && returnedSpeciesId != nil
        }

        guard let requestedName, returnedScientificName == requestedName else {
            return false
        }
        return returnedSpeciesId != nil
            || entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .hasPrefix("external:")
    }
}
