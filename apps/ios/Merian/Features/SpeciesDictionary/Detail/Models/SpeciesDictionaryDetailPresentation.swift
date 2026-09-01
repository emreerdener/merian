import Foundation

extension SpeciesDictionaryEntry {
    var effectiveContentQuality: SpeciesDictionaryContentQuality {
        if let contentQuality { return contentQuality }

        let signalCount = [
            !referenceImages.isEmpty,
            (wikipediaOverview?.trimmedNonEmptyValue?.count ?? 0) >= 60,
            habitatDescription?.trimmedNonEmptyValue != nil
                || gbifTaxonKey != nil,
            taxonomy?.hasMeaningfulContent == true
        ].filter { $0 }.count

        if signalCount == 4 { return .complete }
        if signalCount >= 2 { return .sparse }
        return .needsEnrichment
    }

    var taxonomyData: TaxonomyData? {
        SpeciesDictionaryTaxonomyPresentation.data(from: taxonomy)
    }

    var similarSpeciesData: SimilarSpecies? {
        let entries = similarSpecies.compactMap { item -> SimilarSpeciesEntry? in
            guard let scientificName = item.scientificName
                .trimmedNonEmptyValue else {
                return nil
            }
            return SimilarSpeciesEntry(
                scientificName: scientificName,
                commonName: item.commonName,
                referenceImageUrl: item.referenceImageUrl,
                iucnRedListStatus: item.iucnRedListStatus,
                speciesId: item.speciesId,
                similarityReason: item.reason,
                visualTraits: item.visualTraits,
                similarityConfidence: item.confidence,
                relationshipSource: item.source,
                reviewStatus: item.reviewStatus,
                isBidirectional: item.isBidirectional,
                sortOrder: item.sortOrder
            )
        }

        return entries.isEmpty ? nil : SimilarSpecies(entries: entries)
    }
}

extension SpeciesDictionaryContentQuality {
    var telemetryValue: String { rawValue }
}

extension SpeciesDictionaryTaxonomy {
    var hasMeaningfulContent: Bool {
        [
            kingdom,
            phylum,
            className,
            order,
            family,
            genus
        ].compactMap { $0?.trimmedNonEmptyValue }.count >= 2
    }
}

extension SpeciesDictionarySimilarSpecies: Identifiable {
    var id: String { speciesId ?? scientificName }
}

enum SpeciesDictionaryPresentation: Identifiable, Equatable {
    case gallery(MediaGalleryPresentation)
    case author(ExploreAuthorProfileRoute)
    case fieldChat(SpeciesDictionaryChatPresentation)
    case paywall

    var id: String {
        switch self {
        case .gallery(let presentation):
            "gallery-\(presentation.id)"
        case .author(let route):
            "author-\(route.id)"
        case .fieldChat(let presentation):
            "field-chat-\(presentation.id)"
        case .paywall:
            "paywall"
        }
    }

    var usesFullscreenCover: Bool {
        if case .gallery = self {
            return true
        }
        return false
    }
}

struct SpeciesDictionaryChatPresentation: Identifiable, Equatable {
    let id: String
    let displayName: String
    let scientificName: String
    let alternativeScientificNames: [String]
}

enum SpeciesDictionaryChatPresentationPolicy {
    enum Destination: Equatable {
        case fieldChat
        case paywall
    }

    static func canonicalSpeciesID(_ value: String?) -> String? {
        SpeciesDictionaryIdentity.canonicalSpeciesID(value)
    }

    static func destination(isProActive: Bool) -> Destination {
        isProActive ? .fieldChat : .paywall
    }

    static func canCommitAsyncPresentation(
        requestedSpeciesID: String,
        currentSpeciesID: String?,
        hasActivePresentation: Bool,
        isCancelled: Bool
    ) -> Bool {
        guard !isCancelled, !hasActivePresentation, let currentSpeciesID else {
            return false
        }
        return currentSpeciesID.caseInsensitiveCompare(requestedSpeciesID)
            == .orderedSame
    }
}

enum SpeciesDictionaryDetailFeedbackEffect: Equatable {
    case selection
    case sheet
    case error
}
