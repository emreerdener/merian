import Foundation

struct SpeciesWikipediaReference: Sendable, Equatable {
    let overview: String?
    let pageURL: String
    let imageURL: String?
}

/// Owns the shared public Wikipedia mobile-sections and GBIF taxon-key
/// transport/parsing boundary used by inference and scan-thumbnail recovery.
///
/// Callers retain presentation identity, retry, scheduling, URL-admission, and
/// persistence policy. This service performs no observable or SwiftData
/// mutation.
struct SpeciesReferenceHydrationService: Sendable {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (
        Data,
        URLResponse
    )

    private struct WikiOriginalImage: Decodable {
        let source: String?
    }

    private struct WikiSection: Decodable {
        let title: String?
        let text: String?
    }

    private struct WikiLead: Decodable {
        let normalizedtitle: String?
        let originalimage: WikiOriginalImage?
    }

    private struct WikiRemainingSections: Decodable {
        let sections: [WikiSection]
    }

    private struct WikiMobileSectionsResponse: Decodable {
        let lead: WikiLead
        let remaining: WikiRemainingSections
    }

    private struct GBIFMediaResponse: Decodable {
        let results: [GBIFResult]?
    }

    private struct GBIFResult: Decodable {
        let media: [GBIFMedia]?
    }

    private struct GBIFMedia: Decodable {
        let type: String?
        let identifier: String?
    }

    private static let externalSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    static let live = SpeciesReferenceHydrationService { request in
        try await externalSession.data(for: request)
    }

    private let loadData: DataLoader

    init(loadData: @escaping DataLoader) {
        self.loadData = loadData
    }

    func fetchWikipediaReference(
        for species: String
    ) async throws -> SpeciesWikipediaReference? {
        let normalized = species.replacingOccurrences(of: " ", with: "_")
        guard let encoded = normalized.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ), let url = URL(
            string: "https://en.wikipedia.org/api/rest_v1/page/mobile-sections/\(encoded)"
        ) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await loadData(request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        return try await Task.detached(priority: .utility) {
            let decoded = try JSONDecoder().decode(
                WikiMobileSectionsResponse.self,
                from: data
            )
            let descriptionHTML = decoded.remaining.sections.first {
                $0.title?.caseInsensitiveCompare("Description") == .orderedSame
            }?.text
            let overview = descriptionHTML.flatMap(Self.normalizedHTMLText)

            let pageTitle = (decoded.lead.normalizedtitle ?? normalized)
                .replacingOccurrences(of: " ", with: "_")
            let encodedTitle = pageTitle.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? pageTitle
            return SpeciesWikipediaReference(
                overview: overview,
                pageURL: "https://en.wikipedia.org/wiki/\(encodedTitle)",
                imageURL: decoded.lead.originalimage?.source
            )
        }.value
    }

    func fetchGBIFImageURLs(taxonKey: Int) async throws -> [String] {
        guard let url = URL(
            string: "https://api.gbif.org/v1/occurrence/search?taxonKey=\(taxonKey)&mediaType=StillImage&limit=4"
        ) else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await loadData(request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }

        return try await Task.detached(priority: .utility) {
            let decoded = try JSONDecoder().decode(
                GBIFMediaResponse.self,
                from: data
            )
            var urls: [String] = []
            for result in decoded.results ?? [] {
                for media in result.media ?? [] {
                    if media.type == "StillImage", let identifier = media.identifier {
                        urls.append(identifier)
                        break
                    }
                }
            }
            return urls
        }.value
    }

    private nonisolated static func normalizedHTMLText(
        _ html: String
    ) -> String? {
        var result = html
            .replacingOccurrences(
                of: "<br>",
                with: "\n",
                options: .caseInsensitive
            )
            .replacingOccurrences(
                of: "<br/>",
                with: "\n",
                options: .caseInsensitive
            )
            .replacingOccurrences(
                of: "<br />",
                with: "\n",
                options: .caseInsensitive
            )
            .replacingOccurrences(
                of: "</p>",
                with: "\n",
                options: .caseInsensitive
            )
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
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
