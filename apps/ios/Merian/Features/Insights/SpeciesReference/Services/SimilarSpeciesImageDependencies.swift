import Foundation
import UIKit

struct SimilarSpeciesImageLoadOutput: Sendable {
    let images: [UIImage]
    let commonName: String?
}

struct SimilarSpeciesImageDependencies {
    let loadImages: @MainActor (
        _ scientificName: String
    ) async -> SimilarSpeciesImageLoadOutput

    init(
        loadImages: @escaping @MainActor (
            _ scientificName: String
        ) async -> SimilarSpeciesImageLoadOutput
    ) {
        self.loadImages = loadImages
    }

    static let live = Self { scientificName in
        await SimilarSpeciesImageService.live.loadImages(
            scientificName: scientificName
        )
    }
}

struct SimilarSpeciesImageService: Sendable {
    private struct WikiThumbnail: Decodable {
        let source: String?
    }

    private struct WikiSummaryResponse: Decodable {
        let title: String?
        let thumbnail: WikiThumbnail?
        let originalimage: WikiThumbnail?
    }

    private struct GBIFMedia: Decodable {
        let type: String?
        let identifier: String?
    }

    private struct GBIFResult: Decodable {
        let media: [GBIFMedia]?
    }

    private struct GBIFMediaResponse: Decodable {
        let results: [GBIFResult]?
    }

    private let session: URLSession
    private let loadImage: @Sendable (_ url: String) async -> UIImage?

    init(
        session: URLSession,
        loadImage: @escaping @Sendable (_ url: String) async -> UIImage?
    ) {
        self.session = session
        self.loadImage = loadImage
    }

    static let live: Self = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        return Self(
            session: session,
            loadImage: { url in
                await LocalImageLoader.shared.loadImage(
                    fromPath: nil,
                    fallbackUrl: url,
                    maxDimension: 500
                )
            }
        )
    }()

    func loadImages(scientificName: String) async -> SimilarSpeciesImageLoadOutput {
        async let wikipedia = fetchWikipedia(scientificName: scientificName)
        async let gbifURLs = fetchGBIFURLs(scientificName: scientificName)

        let wikipediaResult = await wikipedia
        var urls: [String] = []
        if let url = wikipediaResult.imageURL {
            urls.append(url)
        }
        urls.append(contentsOf: await gbifURLs)
        guard !Task.isCancelled else {
            return SimilarSpeciesImageLoadOutput(images: [], commonName: nil)
        }

        var seen = Set<String>()
        let candidates = urls.filter {
            ExternalReferenceImagePolicy.isAllowed($0) && seen.insert($0).inserted
        }
        let images = await loadCandidateImages(candidates)
        return SimilarSpeciesImageLoadOutput(
            images: images,
            commonName: wikipediaResult.title
        )
    }

    static func wikipediaRequest(scientificName: String) -> URLRequest? {
        let normalized = scientificName.replacingOccurrences(of: " ", with: "_")
        guard let encoded = normalized.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ),
        let url = URL(
            string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)"
        ) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func gbifRequest(scientificName: String) -> URLRequest? {
        guard let encoded = scientificName.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ),
        let url = URL(
            string: "https://api.gbif.org/v1/occurrence/search?scientificName=\(encoded)&mediaType=StillImage&limit=5"
        ) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        return request
    }

    static func orderedLoadedValues<Value>(
        from results: [(index: Int, value: Value?)]
    ) -> [Value] {
        results
            .sorted { $0.index < $1.index }
            .compactMap(\.value)
    }

    private func fetchWikipedia(
        scientificName: String
    ) async -> (title: String?, imageURL: String?) {
        guard let request = Self.wikipediaRequest(
            scientificName: scientificName
        ),
        let (data, response) = try? await session.data(for: request),
        let response = response as? HTTPURLResponse,
        response.statusCode == 200,
        let decoded = try? JSONDecoder().decode(
            WikiSummaryResponse.self,
            from: data
        ) else {
            return (nil, nil)
        }
        return (
            decoded.title,
            decoded.thumbnail?.source ?? decoded.originalimage?.source
        )
    }

    private func fetchGBIFURLs(scientificName: String) async -> [String] {
        guard let request = Self.gbifRequest(scientificName: scientificName),
              let (data, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let decoded = try? JSONDecoder().decode(
                  GBIFMediaResponse.self,
                  from: data
              ),
              let results = decoded.results else {
            return []
        }

        return results.compactMap { result in
            result.media?.first(where: { $0.type == "StillImage" })?.identifier
        }
    }

    private func loadCandidateImages(_ urls: [String]) async -> [UIImage] {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    guard !Task.isCancelled else { return (index, nil) }
                    return (index, await loadImage(url))
                }
            }

            var results: [(index: Int, value: UIImage?)] = []
            for await (index, image) in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return []
                }
                results.append((index, image))
            }
            return Self.orderedLoadedValues(from: results)
        }
    }
}
