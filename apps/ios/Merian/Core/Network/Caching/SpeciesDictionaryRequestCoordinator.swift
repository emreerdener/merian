import Foundation

/// Coordinates authenticated dictionary memo reads without exposing cache access
/// through the network client's endpoint API.
enum SpeciesDictionaryRequestCoordinator {
    /// Catalog, overview and detail share this fence around the transport await.
    static func performRequest<Value>(
        function: String,
        cache: SpeciesDictionaryResponseCache,
        expectedAuthUserID: UUID?,
        currentViewerID: () async throws -> UUID,
        operation: (UUID?) async throws -> Value
    ) async throws -> Value {
        let generation = function == "species-dictionary-for-viewer" ? cache.dictionaryGeneration : nil
        var viewerID = expectedAuthUserID
        if generation != nil, viewerID == nil { viewerID = try await currentViewerID() }
        let value = try await operation(viewerID)
        if let generation {
            let latestViewerID = try await currentViewerID()
            guard latestViewerID == viewerID, cache.dictionaryGeneration == generation else {
                throw CancellationError()
            }
            try Task.checkCancellation()
        }
        return value
    }

    static func loadEntry(
        cache: SpeciesDictionaryResponseCache,
        requestedSpeciesId: String?,
        requestedScientificName: String?,
        currentViewerID: () async throws -> UUID,
        loadResponse: (UUID) async throws -> SpeciesDictionaryResponse
    ) async throws -> SpeciesDictionaryEntry {
        let viewerID = try await currentViewerID()
        let generation = cache.dictionaryGeneration
        let scope = "\(viewerID.uuidString):\(generation)"
        try Task.checkCancellation()
        if let cached = cache.dictionaryEntry(
            speciesId: requestedSpeciesId,
            scientificName: requestedScientificName, scope: scope
        ) {
            try Task.checkCancellation()
            guard cache.dictionaryGeneration == generation else { throw CancellationError() }
            return cached
        }

        let response = try await loadResponse(viewerID)
        let entry = try SpeciesDictionaryResponseValidator.dictionaryEntry(
            response,
            requestedSpeciesId: requestedSpeciesId,
            requestedScientificName: requestedScientificName
        )
        let latestViewerID = try await currentViewerID()
        guard latestViewerID == viewerID,
              cache.dictionaryGeneration == generation else {
            throw CancellationError()
        }
        cache.storeDictionaryEntry(entry, scope: scope)
        return entry
    }
}
