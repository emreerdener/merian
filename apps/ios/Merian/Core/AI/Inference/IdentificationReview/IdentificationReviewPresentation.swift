import Foundation

/// Pure presentation mapping for interactive identification review.
///
/// `InferenceSpeciesPresentationCoordinator` applies these typed actions
/// synchronously through `InferencePresentationState`. This mapper never
/// performs persistence or transport.
enum IdentificationReviewPresentation {
    struct Action: Sendable {
        let speciesData: SpeciesData
        let referenceState: ReferenceState?
    }

    struct DictionaryResolution: Sendable {
        let action: Action?
        let speciesID: String
        let persistencePatch: IdentificationReviewSpeciesPatch
    }

    static func override(
        _ current: SpeciesData,
        scientificName: String
    ) -> Action {
        var updated = current
        updated.userIdentificationOverride = scientificName
        updated.scientificName = scientificName
        updated.commonName = scientificName
        updated.insightData = InsightData(aiReasoning: "", hazardType: "none")
        clearSpeciesContext(on: &updated)
        updated.userConfirmedIdentification = false
        updated.isFlagged = false
        updated.alternativesExhausted = false
        return Action(speciesData: updated, referenceState: .empty)
    }

    static func confirmation(_ current: SpeciesData) -> Action {
        var updated = current
        updated.userConfirmedIdentification = true
        return Action(speciesData: updated, referenceState: nil)
    }

    static func reset(
        _ current: SpeciesData,
        scientificName: String,
        aiReasoning: String
    ) -> Action {
        var updated = current
        updated.userIdentificationOverride = nil
        updated.userConfirmedIdentification = false
        updated.isFlagged = false
        updated.alternativesExhausted = false
        updated.scientificName = scientificName
        updated.commonName = scientificName
        updated.insightData = InsightData(
            aiReasoning: aiReasoning,
            hazardType: "none"
        )
        clearSpeciesContext(on: &updated)
        return Action(speciesData: updated, referenceState: .empty)
    }

    static func dictionaryResolution(
        record: InferenceSpeciesDictionaryRecord,
        current: SpeciesData?,
        scientificName: String,
        restoringAIReasoning: String?,
        replacingSpeciesIdentity: Bool
    ) -> DictionaryResolution {
        let commonName = resolvedCommonName(
            record.commonNames,
            fallback: scientificName
        )
        let taxonomy = TaxonomyData(
            kingdom: record.kingdom,
            phylum: record.phylum,
            className: record.className,
            order: record.order,
            family: record.family,
            genus: record.genus
        )
        let referenceImageURL = ExternalReferenceImagePolicy.sanitizedURLList(
            record.referenceImageURL
        )

        let referenceURLs = ExternalReferenceImagePolicy.allowedURLStrings(
            from: referenceImageURL
        )
        let referenceState: ReferenceState = referenceURLs.isEmpty
            ? .empty
            : .loaded(referenceURLs)
        let persistencePatch = IdentificationReviewSpeciesPatch(
            commonName: commonName,
            hazardType: record.hazardType ?? "none",
            wikipediaOverview: record.wikipediaOverview,
            wikipediaURL: record.wikipediaURL,
            referenceImageURL: referenceImageURL,
            iucnRedListStatus: record.iucnRedListStatus,
            habitatDescription: record.habitatDescription?
                .trimmedNonEmptyValue,
            gbifTaxonKey: record.gbifTaxonKey,
            taxonomy: taxonomy,
            replacingSpeciesIdentity: replacingSpeciesIdentity
        )
        let action = current.map { current in
            var updated = current
            updated.commonName = commonName
            updated.insightData = InsightData(
                aiReasoning: restoringAIReasoning ?? "",
                hazardType: record.hazardType ?? "none"
            )
            updated.taxonomy = taxonomy
            updated.iucnRedListStatus = record.iucnRedListStatus
            updated.habitatDescription = record.habitatDescription?
                .trimmedNonEmptyValue
            updated.gbifTaxonKey = record.gbifTaxonKey
            updated.referenceImageUrl = referenceImageURL
            updated.wikipediaOverview = record.wikipediaOverview
            updated.wikipediaUrl = record.wikipediaURL
            return Action(
                speciesData: updated,
                referenceState: referenceState
            )
        }
        return DictionaryResolution(
            action: action,
            speciesID: record.id,
            persistencePatch: persistencePatch
        )
    }

    private static func clearSpeciesContext(on speciesData: inout SpeciesData) {
        speciesData.wikipediaOverview = nil
        speciesData.wikipediaUrl = nil
        speciesData.referenceImageUrl = nil
        speciesData.iucnRedListStatus = nil
        speciesData.habitatDescription = nil
        speciesData.gbifTaxonKey = nil
        speciesData.taxonomy = nil
        speciesData.alternativeCommonNames = nil
        speciesData.similarSpecies = nil
    }

    private static func resolvedCommonName(
        _ names: [String: String?]?,
        fallback: String
    ) -> String {
        let resolvedName = names?["en"].flatMap { $0 }
            ?? names?.compactMap(\.value).first
            ?? fallback
        return resolvedName.capitalized
    }
}
