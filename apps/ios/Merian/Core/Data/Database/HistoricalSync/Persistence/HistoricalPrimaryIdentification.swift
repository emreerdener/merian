import Foundation

/// Keeps immutable AI identity separate from mutable dictionary and review data.
/// Both paged history and single-scan recovery use the same checked projection.
enum HistoricalPrimaryIdentification {
    static func validate(_ response: HistoricalScanResponse) throws -> PrimaryIdentification? {
        let primary = response.primary_identification.map(PrimaryIdentification.init(dto:))
        guard PrimaryIdentificationProvenancePolicy.requiresSnapshot(response.identification_provenance) == (primary != nil) else {
            throw PrimaryIdentification.IntegrityError.missingRequiredSnapshot
        }
        guard let primary else {
            guard response.candidates?.allSatisfy({ $0.taxon_rank == nil }) ?? true else {
                throw PrimaryIdentification.IntegrityError.invalidSnapshot
            }
            return nil
        }
        guard let value = primary.value,
              response.is_biological_subject == (value.resolution != .nonBiological) else {
            throw PrimaryIdentification.IntegrityError.invalidSnapshot
        }
        if value.resolution == .species {
            guard (response.candidates?.count ?? 0) <= 2,
                  response.candidates?.allSatisfy({ $0.taxon_rank == "species" }) ?? true else {
                throw PrimaryIdentification.IntegrityError.invalidSnapshot
            }
        } else if response.species_dictionary != nil || response.candidates != nil || response.pet_identification != nil {
            throw PrimaryIdentification.IntegrityError.invalidSnapshot
        }
        return primary
    }

    static func validateMerge(_ response: HistoricalScanResponse, into record: LocalScanRecord) throws {
        let incoming = try validate(response)
        try PrimaryIdentificationPersistence.validateMerge(
            storedPrimary: record.primaryIdentificationData,
            storedProvenance: record.identificationProvenanceData,
            incomingPrimary: incoming,
            incomingProvenance: response.identification_provenance.map(IdentificationResultProvenance.init(dto:))
        )
    }

    @discardableResult
    static func merge(_ response: HistoricalScanResponse, into record: LocalScanRecord) throws -> Bool {
        try validateMerge(response, into: record)
        let bytes = try PrimaryIdentification.merging(
            stored: record.primaryIdentificationData,
            incoming: response.primary_identification.map(PrimaryIdentification.init(dto:))
        )
        var changed = bytes != record.primaryIdentificationData
        record.primaryIdentificationData = bytes
        guard let value = bytes.flatMap({ PrimaryIdentification(storedData: $0).value }) else { return changed }
        let scientificName = value.scientificName ?? LocalScanRecord.unresolvedBiologicalScientificName
        let commonName = value.commonName ?? value.scientificName ?? LocalScanRecord.unresolvedBiologicalCommonName
        if record.scientificName != scientificName || record.commonName != commonName {
            record.scientificName = scientificName
            record.commonName = commonName
            changed = true
        }
        if value.resolution != .species {
            // Old local caches or typed review state cannot add species effects.
            let staleStrings = [record.referenceImageUrl, record.wikipediaUrl,
                record.wikipediaOverview, record.habitatDescription, record.iucnRedListStatus,
                record.taxonomyKingdom, record.taxonomyPhylum, record.taxonomyClass,
                record.taxonomyOrder, record.taxonomyFamily, record.taxonomyGenus]
            changed = changed || !record.speciesId.isEmpty || staleStrings.contains(where: { $0 != nil }) ||
                record.gbifTaxonKey != nil || record.candidatesData != nil || record.petIdentificationData != nil ||
                record.lookalikesData != nil || record.similarSpecies != nil || record.alternativeCommonNames != nil
            record.speciesId = ""
            record.referenceImageUrl = nil
            record.wikipediaUrl = nil
            record.wikipediaOverview = nil
            record.habitatDescription = nil
            record.gbifTaxonKey = nil
            record.iucnRedListStatus = nil
            record.candidatesData = nil
            record.petIdentificationData = nil
            record.lookalikesData = nil
            record.similarSpecies = nil
            record.alternativeCommonNames = nil
            record.taxonomyKingdom = nil
            record.taxonomyPhylum = nil
            record.taxonomyClass = nil
            record.taxonomyOrder = nil
            record.taxonomyFamily = nil
            record.taxonomyGenus = nil
        }
        return changed
    }
}
