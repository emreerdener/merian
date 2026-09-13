import Foundation

/// Normalizes progressive `enrich-scan` responses for the inference
/// presentation and persistence boundaries.
///
/// `InferenceEngine` retains request admission, concurrency, retry, loading,
/// and stale-presentation policy. This service performs no observable or
/// SwiftData mutation.
struct InferenceSpeciesEnrichmentService: Sendable {
    enum Scope: String, Sendable {
        case metadata = "enrichment"
        case lookalikes
    }

    struct Request: Equatable, Sendable {
        let scanId: String
        let scientificName: String
        let confidenceScore: Double
        let inferenceTier: String
    }

    struct MetadataPatch: Sendable {
        let habitatDescription: String?
        let gbifTaxonKey: Int?
        let taxonomy: TaxonomyData?
        let alternativeCommonNames: [String]?
        let persistedAlternativeCommonNames: [String]?

        func applying(to speciesData: SpeciesData) -> SpeciesData {
            var updated = speciesData
            if let habitatDescription {
                updated.habitatDescription = habitatDescription
            }
            if let gbifTaxonKey {
                updated.gbifTaxonKey = gbifTaxonKey
            }
            if let taxonomy {
                updated.taxonomy = taxonomy
            }
            if persistedAlternativeCommonNames != nil {
                updated.alternativeCommonNames = alternativeCommonNames
            }
            return updated
        }
    }

    struct LookalikesPatch: Sendable {
        let entries: [SimilarSpeciesEntry]

        func applying(to speciesData: SpeciesData) -> SpeciesData {
            var updated = speciesData
            updated.similarSpecies = SimilarSpecies(entries: entries)
            return updated
        }
    }

    struct Dependencies: Sendable {
        let fetch: @MainActor @Sendable (
            _ request: Request,
            _ scope: Scope
        ) async throws -> EnrichScanResponse
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @MainActor
    func fetchMetadata(for request: Request) async throws -> MetadataPatch? {
        guard let data = try await dependencies.fetch(request, .metadata).data else {
            return nil
        }
        let taxonomy = data.taxonomy.map {
            TaxonomyData(
                kingdom: $0.kingdom,
                phylum: $0.phylum,
                className: $0.`class`,
                order: $0.order,
                family: $0.family,
                genus: $0.genus
            )
        }
        return MetadataPatch(
            habitatDescription: data.habitat_description?.trimmedNonEmptyValue,
            gbifTaxonKey: data.gbif_taxon_key,
            taxonomy: taxonomy,
            alternativeCommonNames: SpeciesData.sanitizeAlternativeNames(
                data.alternative_common_names
            ),
            persistedAlternativeCommonNames: data.alternative_common_names
        )
    }

    @MainActor
    func fetchLookalikes(
        for request: Request
    ) async throws -> LookalikesPatch? {
        guard let entries = try await dependencies
            .fetch(request, .lookalikes).data?.similar_species,
              !entries.isEmpty else {
            return nil
        }
        return LookalikesPatch(entries: entries.map(Self.mapLookalike))
    }

    private static func mapLookalike(
        _ entry: EnrichScanResponse.SimilarSpeciesEntry
    ) -> SimilarSpeciesEntry {
        let commonName = entry.common_name?
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SimilarSpeciesEntry(
            scientificName: entry.scientific_name,
            commonName: commonName,
            referenceImageUrl: entry.reference_image_url,
            iucnRedListStatus: entry.iucn_red_list_status,
            speciesId: entry.species_id,
            similarityReason: entry.reason,
            visualTraits: entry.visual_traits ?? [],
            similarityConfidence: entry.confidence,
            relationshipSource: entry.source,
            reviewStatus: entry.review_status,
            isBidirectional: entry.is_bidirectional,
            sortOrder: entry.sort_order
        )
    }
}
