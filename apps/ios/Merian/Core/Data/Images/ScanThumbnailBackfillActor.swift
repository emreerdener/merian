import Foundation
import SwiftData

private struct ThumbnailSpeciesDictionaryRow: Decodable {
    let scientific_name: String
    let reference_image_url: String?
    let wikipedia_url: String?
    let wikipedia_overview: String?
    let gbif_taxon_key: Int?
}

private struct ThumbnailBackfillPayload: Sendable {
    let referenceImageUrl: String
    let wikipediaUrl: String?
    let wikipediaOverview: String?
}

actor ScanThumbnailBackfillActor {
    static let shared = ScanThumbnailBackfillActor()

    private var inFlightScanIds: Set<String> = []
    private var recentSpeciesMisses: [String: TimeInterval] = [:]
    private let missCooldown: TimeInterval = 15 * 60
    private let perPassLimit = 12
    private let speciesReferenceService: SpeciesReferenceHydrationService

    init(
        speciesReferenceService: SpeciesReferenceHydrationService = .live
    ) {
        self.speciesReferenceService = speciesReferenceService
    }

    @discardableResult
    func backfill(
        records: [ScanThumbnailBackfillCandidate],
        modelContainer: ModelContainer
    ) async -> Set<String> {
        pruneExpiredMisses()

        let candidates = Array(
            records
                .filter { candidate in
                    !inFlightScanIds.contains(candidate.scanId) &&
                    recentSpeciesMisses[candidate.scientificName.lowercased()] == nil
                }
                .prefix(perPassLimit)
        )

        guard !candidates.isEmpty else { return [] }

        for candidate in candidates {
            inFlightScanIds.insert(candidate.scanId)
        }

        let dbActor = BackgroundDatabaseActor(modelContainer: modelContainer)
        let now = Date.now.timeIntervalSinceReferenceDate
        let cachedSpeciesByName = await fetchCachedSpeciesMap(
            scientificNames: candidates.map(\.scientificName)
        )

        var updatedScanIds: Set<String> = []
        await withTaskGroup(of: (ScanThumbnailBackfillCandidate, ThumbnailBackfillPayload?).self) { group in
            for candidate in candidates {
                let cachedSpecies = cachedSpeciesByName[candidate.scientificName.lowercased()]
                group.addTask { [candidate, cachedSpecies] in
                    let payload = await self.resolveBackfill(
                        for: candidate,
                        cachedSpecies: cachedSpecies
                    )
                    return (candidate, payload)
                }
            }

            for await (candidate, payload) in group {
                inFlightScanIds.remove(candidate.scanId)

                guard let payload else {
                    recentSpeciesMisses[candidate.scientificName.lowercased()] = now
                    continue
                }
                guard let referenceImageUrl = ExternalReferenceImagePolicy
                    .sanitizedURLList(payload.referenceImageUrl) else {
                    recentSpeciesMisses[candidate.scientificName.lowercased()] = now
                    continue
                }

                let didUpdate = await dbActor.updateScanWithWikipedia(
                    scanId: candidate.scanId,
                    extract: payload.wikipediaOverview,
                    url: payload.wikipediaUrl,
                    imageUrl: referenceImageUrl,
                    expectedScientificName: candidate.scientificName
                )
                guard didUpdate else { continue }

                updatedScanIds.insert(candidate.scanId)
                LocalImageLoader.shared.prefetch(
                    records: [(imagePath: nil, fallbackUrl: referenceImageUrl)],
                    maxDimension: 600
                )
            }
        }
        return updatedScanIds
    }

    private func resolveBackfill(
        for candidate: ScanThumbnailBackfillCandidate,
        cachedSpecies: ThumbnailSpeciesDictionaryRow?
    ) async -> ThumbnailBackfillPayload? {
        let cached = cachedSpecies
        let cachedUrls = cached?.reference_image_url.commaSeparatedUrls ?? []
        let cachedWikipediaUrl = cached?.wikipedia_url?.trimmedNonEmptyValue
        let cachedWikipediaOverview = cached?.wikipedia_overview?
            .trimmedNonEmptyValue
        let gbifKey = cached?.gbif_taxon_key ?? candidate.gbifTaxonKey

        if !cachedUrls.isEmpty {
            return ThumbnailBackfillPayload(
                referenceImageUrl: cachedUrls.joined(separator: ","),
                wikipediaUrl: cachedWikipediaUrl,
                wikipediaOverview: cachedWikipediaOverview
            )
        }

        let wikipediaReference = await fetchWikipediaReference(
            scientificName: candidate.scientificName
        )
        let gbifUrls = await fetchGBIFImageUrls(taxonKey: gbifKey)

        let mergedUrls = mergeUrls(
            primary: wikipediaReference?.imageURL,
            secondary: gbifUrls
        )

        guard !mergedUrls.isEmpty else { return nil }

        return ThumbnailBackfillPayload(
            referenceImageUrl: mergedUrls.joined(separator: ","),
            wikipediaUrl: cachedWikipediaUrl ?? wikipediaReference?.pageURL,
            wikipediaOverview: cachedWikipediaOverview ?? wikipediaReference?.overview
        )
    }

    private func fetchCachedSpeciesMap(scientificNames: [String]) async -> [String: ThumbnailSpeciesDictionaryRow] {
        let normalizedNames = Array(Set(scientificNames.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }))
        guard !normalizedNames.isEmpty else { return [:] }

        do {
            let rows: [ThumbnailSpeciesDictionaryRow] = try await SupabaseManager.shared.client
                .from("species_dictionary")
                .select("scientific_name, reference_image_url, wikipedia_url, wikipedia_overview, gbif_taxon_key")
                .in("scientific_name", values: normalizedNames)
                .execute()
                .value

            return Dictionary(
                rows.map { ($0.scientific_name.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            return [:]
        }
    }

    private func fetchWikipediaReference(
        scientificName: String
    ) async -> SpeciesWikipediaReference? {
        try? await speciesReferenceService.fetchWikipediaReference(
            for: scientificName
        )
    }

    private func fetchGBIFImageUrls(taxonKey: Int?) async -> [String] {
        guard let taxonKey else { return [] }
        return (try? await speciesReferenceService.fetchGBIFImageURLs(
            taxonKey: taxonKey
        )) ?? []
    }

    private func mergeUrls(primary: String?, secondary: [String]) -> [String] {
        var merged: [String] = []

        if let primary = primary?.trimmedNonEmptyValue {
            merged.append(primary)
        }

        for url in secondary {
            guard let trimmed = url.trimmedNonEmptyValue,
                  !merged.contains(trimmed) else {
                continue
            }
            merged.append(trimmed)
        }

        return Array(merged.prefix(5))
    }

    private func pruneExpiredMisses() {
        let cutoff = Date.now.timeIntervalSinceReferenceDate - missCooldown
        recentSpeciesMisses = recentSpeciesMisses.filter { $0.value > cutoff }
    }
}

private extension Optional where Wrapped == String {
    var commaSeparatedUrls: [String] {
        self?
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }
}
