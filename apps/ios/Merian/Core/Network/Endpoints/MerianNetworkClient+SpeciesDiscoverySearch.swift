import Foundation

extension MerianNetworkClient {
    func searchSpecies(_ request: SpeciesSearchRequest) async throws -> SpeciesSearchResponse {
        let data = try await performAuthenticatedEncodedJSONPost(
            function: "species-discovery-search", body: request, timeoutInterval: 45
        )
        return try SpeciesSearchResponseValidator.decode(data, request: request)
    }
}
