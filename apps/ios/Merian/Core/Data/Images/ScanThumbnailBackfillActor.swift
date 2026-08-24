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

private struct ThumbnailWikipediaImage: Decodable {
    let source: String?
}

private struct ThumbnailWikipediaSection: Decodable {
    let title: String?
    let text: String?
}

private struct ThumbnailWikipediaLead: Decodable {
    let normalizedtitle: String?
    let originalimage: ThumbnailWikipediaImage?
}

private struct ThumbnailWikipediaRemaining: Decodable {
    let sections: [ThumbnailWikipediaSection]
}

private struct ThumbnailWikipediaSectionsResponse: Decodable {
    let lead: ThumbnailWikipediaLead
    let remaining: ThumbnailWikipediaRemaining
}

private struct ThumbnailWikipediaPayload: Sendable {
    let overview: String?
    let articleUrl: String?
    let imageUrl: String?
}

private struct ThumbnailGBIFMediaResponse: Decodable {
    let results: [ThumbnailGBIFResult]?
}

private struct ThumbnailGBIFResult: Decodable {
    let media: [ThumbnailGBIFMedia]?
}

private struct ThumbnailGBIFMedia: Decodable {
    let type: String?
    let identifier: String?
}

actor ScanThumbnailBackfillActor {
    static let shared = ScanThumbnailBackfillActor()

    private static let externalAPISession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.httpShouldSetCookies = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private var inFlightScanIds: Set<String> = []
    private var recentSpeciesMisses: [String: TimeInterval] = [:]
    private let missCooldown: TimeInterval = 15 * 60
    private let perPassLimit = 12

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
        let cachedWikipediaUrl = cached?.wikipedia_url?.trimmedNonEmpty
        let cachedWikipediaOverview = cached?.wikipedia_overview?.trimmedNonEmpty
        let gbifKey = cached?.gbif_taxon_key ?? candidate.gbifTaxonKey

        if !cachedUrls.isEmpty {
            return ThumbnailBackfillPayload(
                referenceImageUrl: cachedUrls.joined(separator: ","),
                wikipediaUrl: cachedWikipediaUrl,
                wikipediaOverview: cachedWikipediaOverview
            )
        }

        let wikiPayload = await fetchWikipediaPayload(scientificName: candidate.scientificName)
        let gbifUrls = await fetchGBIFImageUrls(taxonKey: gbifKey)

        let mergedUrls = mergeUrls(
            primary: wikiPayload?.imageUrl,
            secondary: gbifUrls
        )

        guard !mergedUrls.isEmpty else { return nil }

        return ThumbnailBackfillPayload(
            referenceImageUrl: mergedUrls.joined(separator: ","),
            wikipediaUrl: cachedWikipediaUrl ?? wikiPayload?.articleUrl,
            wikipediaOverview: cachedWikipediaOverview ?? wikiPayload?.overview
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

    private func fetchWikipediaPayload(scientificName: String) async -> ThumbnailWikipediaPayload? {
        let normalized = scientificName.replacingOccurrences(of: " ", with: "_")
        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/mobile-sections/\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8.0
        request.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await Self.externalAPISession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let decoded = try JSONDecoder().decode(ThumbnailWikipediaSectionsResponse.self, from: data)
            let descriptionHtml = decoded.remaining.sections.first {
                $0.title?.caseInsensitiveCompare("Description") == .orderedSame
            }?.text
            let overview = descriptionHtml.flatMap { Self.stripHTML($0) }
            let pageTitle = (decoded.lead.normalizedtitle ?? normalized).replacingOccurrences(of: " ", with: "_")
            let encodedTitle = pageTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pageTitle
            return ThumbnailWikipediaPayload(
                overview: overview,
                articleUrl: "https://en.wikipedia.org/wiki/\(encodedTitle)",
                imageUrl: decoded.lead.originalimage?.source?.trimmedNonEmpty
            )
        } catch {
            return nil
        }
    }

    private func fetchGBIFImageUrls(taxonKey: Int?) async -> [String] {
        guard let taxonKey,
              let url = URL(string: "https://api.gbif.org/v1/occurrence/search?taxonKey=\(taxonKey)&mediaType=StillImage&limit=4") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0

        do {
            let (data, response) = try await Self.externalAPISession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            let decoded = try JSONDecoder().decode(ThumbnailGBIFMediaResponse.self, from: data)
            var urls: [String] = []
            for result in decoded.results ?? [] {
                for mediaItem in result.media ?? [] {
                    if mediaItem.type == "StillImage", let identifier = mediaItem.identifier?.trimmedNonEmpty {
                        urls.append(identifier)
                        break
                    }
                }
            }
            return urls
        } catch {
            return []
        }
    }

    private func mergeUrls(primary: String?, secondary: [String]) -> [String] {
        var merged: [String] = []

        if let primary = primary?.trimmedNonEmpty {
            merged.append(primary)
        }

        for url in secondary {
            guard let trimmed = url.trimmedNonEmpty, !merged.contains(trimmed) else { continue }
            merged.append(trimmed)
        }

        return Array(merged.prefix(5))
    }

    private func pruneExpiredMisses() {
        let cutoff = Date.now.timeIntervalSinceReferenceDate - missCooldown
        recentSpeciesMisses = recentSpeciesMisses.filter { $0.value > cutoff }
    }

    private static func stripHTML(_ html: String) -> String? {
        var result = html
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")

        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
