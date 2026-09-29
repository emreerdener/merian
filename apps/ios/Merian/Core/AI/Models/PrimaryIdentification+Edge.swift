import Foundation

extension PrimaryIdentification {
    init(dto: PrimaryIdentificationDTO) {
        // Encoding a generated DTO with only strings/integers cannot fail for a
        // valid wire value. Preserve an invalid sentinel if that ever changes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.init(storedData: (try? encoder.encode(dto)) ?? Data())
    }
}

enum PrimaryIdentificationProvenancePolicy {
    static func requiresSnapshot(_ provenance: IdentificationProvenanceDTO?) -> Bool {
        guard let provenance else { return false }
        switch provenance {
        case .v1(let value): return value.schema == "merian_identify_primary_v1"
        case .v2(let value): return value.schema == "merian_identify_primary_v1"
        }
    }
}

/// Semantic validation supplements the generated shape decoder. Foreground,
/// background and replay completion all use this boundary before persistence.
enum PrimaryIdentificationResponseValidator {
    static func isValid(_ data: EdgeResponse) -> Bool {
        let requiresPrimary = PrimaryIdentificationProvenancePolicy.requiresSnapshot(data.identification_provenance)
        guard requiresPrimary == (data.primary_identification != nil) else { return false }
        guard let dto = data.primary_identification else {
            return data.candidates?.allSatisfy { $0.taxon_rank == nil } ?? true
        }
        guard let primary = PrimaryIdentification(dto: dto).value,
              data.is_biological_subject == (primary.resolution != .nonBiological),
              data.scientific_name == primary.scientificName,
              data.common_name == primary.commonName else { return false }
        if primary.resolution == .species {
            return (data.candidates?.count ?? 0) <= 2 &&
                (data.candidates?.allSatisfy { $0.taxon_rank == "species" } ?? true)
        }
        return data.candidates == nil && data.pet_identification == nil &&
            data.is_new_to_merian_dictionary == false && data.gbif_taxon_key == nil &&
            data.reference_image_url == nil && data.wikipedia_url == nil &&
            data.wikipedia_overview == nil && data.species_insights == nil &&
            data.iucn_red_list_status == nil && data.alternative_common_names == nil &&
            (primary.resolution != .family || data.taxonomy?.genus == nil)
    }
}
