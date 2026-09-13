extension InferenceSpeciesEnrichmentService {
    static let live = InferenceSpeciesEnrichmentService(
        dependencies: Dependencies { request, scope in
            try await MerianNetworkClient.shared.fetchEnrichment(
                scanId: request.scanId,
                scientificName: request.scientificName,
                confidenceScore: request.confidenceScore,
                inferenceTier: request.inferenceTier,
                scope: scope.rawValue
            )
        }
    )
}
