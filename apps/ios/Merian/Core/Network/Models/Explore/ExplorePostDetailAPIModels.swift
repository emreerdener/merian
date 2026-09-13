import CoreLocation
import Foundation

struct ExplorePostDetailResponse: Decodable {
    let schemaVersion: Int?
    let data: ExplorePostDetail

    var effectiveSchemaVersion: Int { schemaVersion ?? 0 }
}

struct ExplorePostDetailMapPoint: Decodable, Equatable {
    let latitude: Double
    let longitude: Double
    let coordinateVisibility: ExploreCoordinateVisibility

    var coordinate: CLLocationCoordinate2D? {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ExplorePostDetail: Decodable {
    let postId: String
    var fieldNotes: String?
    var locationSharing: ExplorePostLocationSharing?
    let mapPoint: ExplorePostDetailMapPoint?
    let hashtags: [String]?
    let speciesDictionaryId: String?
    let alternativeCommonNames: [String]?
    let petIdentification: PetIdentification?
    let taxonomyKingdom: String?
    let taxonomyPhylum: String?
    let taxonomyClass: String?
    let taxonomyOrder: String?
    let taxonomyFamily: String?
    let taxonomyGenus: String?
    let aiReasoning: String?
    let habitatDescription: String?
    let gbifTaxonKey: Int?
    let iucnRedListStatus: String?
    let hazardType: String?
    let wikipediaUrl: String?
    let referenceImageUrl: String?
    let wikipediaOverview: String?
    let similarSpecies: [SimilarSpeciesEntry]?

    var visibleMapPoint: ExplorePostDetailMapPoint? {
        guard locationSharing == .open,
              let mapPoint,
              mapPoint.coordinate != nil else {
            return nil
        }

        return mapPoint
    }

    var taxonomyData: TaxonomyData? {
        let taxonomy = TaxonomyData(
            kingdom: taxonomyKingdom,
            phylum: taxonomyPhylum,
            className: taxonomyClass,
            order: taxonomyOrder,
            family: taxonomyFamily,
            genus: taxonomyGenus
        )

        let values = [
            taxonomy.kingdom,
            taxonomy.phylum,
            taxonomy.className,
            taxonomy.order,
            taxonomy.family,
            taxonomy.genus
        ]

        return values.contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ? taxonomy : nil
    }

    var hasHabitatDistributionContent: Bool {
        if let habitatDescription,
           !habitatDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        return gbifTaxonKey != nil
    }

    var hasOverviewContent: Bool {
        if let iucnRedListStatus,
           !iucnRedListStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if let wikipediaOverview,
           wikipediaOverview.trimmingCharacters(in: .whitespacesAndNewlines).count >= 60 {
            return true
        }

        return false
    }

    var referenceGalleryImages: [ExploreReferenceGalleryImage] {
        referenceGalleryImages(excluding: [])
    }

    func referenceGalleryImages(excluding mediaIdentifiers: [String]) -> [ExploreReferenceGalleryImage] {
        let rawUrls = ExternalReferenceImagePolicy.allowedURLStrings(from: referenceImageUrl)
        let visibleUrls = ReferenceImageDeduplicationPolicy.filteredReferenceURLs(
            rawUrls,
            excluding: mediaIdentifiers
        )
        let originalIndexes = Dictionary(
            rawUrls.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        var seen = Set<String>()

        return visibleUrls.compactMap { rawUrl in
            guard !rawUrl.isEmpty, seen.insert(rawUrl).inserted else { return nil }
            let index = originalIndexes[rawUrl] ?? 0

            return ExploreReferenceGalleryImage(
                id: rawUrl,
                url: rawUrl,
                source: referenceImageSource(for: rawUrl, index: index)
            )
        }
    }

    var similarSpeciesData: SimilarSpecies? {
        let entries = (similarSpecies ?? []).filter { entry in
            !entry.scientificName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return entries.isEmpty ? nil : SimilarSpecies(entries: entries)
    }

    var trimmedAiReasoning: String? {
        guard let aiReasoning else { return nil }
        let trimmed = aiReasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedFieldNotes: String? {
        guard let fieldNotes else { return nil }
        let trimmed = fieldNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func referenceImageSource(for urlString: String, index: Int) -> ExploreReferenceGalleryImage.Source {
        let host = URL(string: urlString)?.host?.lowercased() ?? ""
        if host == "media.merian.app" || host.hasSuffix(".merian.app") {
            return .merian
        }

        if host.contains("wikipedia") || host.contains("wikimedia") {
            return .wikipedia
        }

        if let wikipediaUrl,
           !wikipediaUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           index == 0 {
            return .wikipedia
        }

        return .gbif
    }
}

struct ExploreReferenceGalleryImage: Identifiable, Equatable {
    enum Source: Equatable {
        case wikipedia
        case gbif
        case merian

        var label: String {
            switch self {
            case .wikipedia:
                return "Wikipedia"
            case .gbif:
                return "GBIF"
            case .merian:
                return "Naturebook"
            }
        }

        var iconName: String {
            switch self {
            case .wikipedia:
                return "book.closed"
            case .gbif:
                return "globe.americas"
            case .merian:
                return "camera"
            }
        }

        var caption: String {
            switch self {
            case .wikipedia:
                return "Reference image"
            case .gbif:
                return "Field observation"
            case .merian:
                return "Naturebook observation"
            }
        }
    }

    let id: String
    let url: String
    let source: Source
}
