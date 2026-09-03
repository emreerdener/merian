import Foundation

/// Species Dictionary request mapping and stateless catalog validation.
/// The client retains private transport and validated response-cache access.
extension MerianNetworkClient {
    func getSpeciesDictionary(scientificName: String) async throws -> SpeciesDictionaryEntry {
        try await performSpeciesDictionaryRequest(speciesId: nil, scientificName: scientificName)
    }

    func getSpeciesDictionary(speciesId: String, scientificName: String? = nil) async throws -> SpeciesDictionaryEntry {
        try await performSpeciesDictionaryRequest(speciesId: speciesId, scientificName: scientificName)
    }

    func getSpeciesDictionaryCatalog(
        category: SpeciesDictionaryCatalogCategory = .all,
        region: String? = nil,
        group: String? = nil,
        query: String? = nil,
        limit: Int = 40,
        cursor: SpeciesDictionaryCatalogCursor? = nil
    ) async throws -> SpeciesDictionaryCatalogResponse {
        try validateEndpointConfiguration("species-dictionary")
        var payload: [String: Any] = ["mode": "catalog", "limit": limit]
        if category != .all {
            payload["category"] = category.rawValue
        }
        if let region = region?.trimmedNonEmptyValue {
            payload["region"] = region
        }
        if let group = group?.trimmedNonEmptyValue {
            payload["group"] = group
        }
        if let query = query?.trimmedNonEmptyValue {
            payload["query"] = query
        }
        if let cursor {
            var cursorPayload: [String: Any] = [
                "scientific_name": cursor.scientificName,
                "species_id": cursor.speciesId
            ]
            if let createdAt = cursor.createdAt {
                cursorPayload["created_at"] = createdAt
            }
            payload["cursor"] = cursorPayload
        }

        let response = try await performAuthenticatedJSONPost(
            function: "species-dictionary",
            payload: payload,
            responseType: SpeciesDictionaryCatalogResponse.self
        )
        return try SpeciesDictionaryResponseValidator.catalog(response)
    }

    func getSpeciesDictionaryCatalog(
        query: String? = nil,
        limit: Int = 40,
        cursor: SpeciesDictionaryCatalogCursor? = nil
    ) async throws -> SpeciesDictionaryCatalogResponse {
        try await getSpeciesDictionaryCatalog(
            category: .all,
            region: nil,
            group: nil,
            query: query,
            limit: limit,
            cursor: cursor
        )
    }

    func getSpeciesDictionaryOverview(userRegion: String? = nil) async throws -> SpeciesDictionaryOverviewResponse {
        try validateEndpointConfiguration("species-dictionary")
        var payload: [String: Any] = [
            "mode": "overview",
            "cache_buster": UUID().uuidString
        ]
        if let userRegion = userRegion?.trimmedNonEmptyValue {
            payload["user_region"] = userRegion
        }

        let response = try await performAuthenticatedJSONPost(
            function: "species-dictionary",
            payload: payload,
            responseType: SpeciesDictionaryOverviewResponse.self
        )
        return try SpeciesDictionaryResponseValidator.overview(response)
    }

    func getSpeciesObservationStats(
        speciesId: String,
        scientificName: String
    ) async throws -> SpeciesObservationStatsEntry {
        try validateEndpointConfiguration("species-observation-stats")
        guard let requestedSpeciesId = SpeciesDictionaryIdentity.canonicalSpeciesID(speciesId),
              let requestedScientificName = SpeciesDictionaryIdentity.normalizedScientificName(scientificName) else {
            throw MerianError.invalidResponse
        }
        return try await performCachedSpeciesObservationStatsRequest(
            queryItems: [
                URLQueryItem(name: "species_id", value: requestedSpeciesId),
                URLQueryItem(name: "scientific_name", value: requestedScientificName)
            ],
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
    }

    private func performSpeciesDictionaryRequest(
        speciesId: String?,
        scientificName: String?
    ) async throws -> SpeciesDictionaryEntry {
        try validateEndpointConfiguration("species-dictionary")
        let requestedSpeciesId = SpeciesDictionaryIdentity.canonicalSpeciesID(speciesId)
        let requestedScientificName = SpeciesDictionaryIdentity.normalizedScientificName(scientificName)
        guard requestedSpeciesId != nil || requestedScientificName != nil else {
            throw MerianError.invalidResponse
        }
        var payload: [String: Any] = [:]
        if let speciesId = requestedSpeciesId {
            payload["species_id"] = speciesId
        }
        if let scientificName = requestedScientificName {
            payload["scientific_name"] = scientificName
        }
        return try await performCachedSpeciesDictionaryRequest(
            payload: payload,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
    }
}
