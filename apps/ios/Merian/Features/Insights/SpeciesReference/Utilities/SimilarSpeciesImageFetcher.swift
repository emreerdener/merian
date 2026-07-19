import Foundation
import Observation
import SwiftUI
import UIKit

private struct WikiThumbnail: Decodable {
    let source: String?
}

private struct WikiSummaryResponse: Decodable {
    let title: String?
    let thumbnail: WikiThumbnail?
    let originalimage: WikiThumbnail?
}

private struct FetcherGBIFMedia: Decodable {
    let type: String?
    let identifier: String?
}

private struct FetcherGBIFResult: Decodable {
    let media: [FetcherGBIFMedia]?
}

private struct FetcherGBIFMediaResponse: Decodable {
    let results: [FetcherGBIFResult]?
}

@MainActor
@Observable
final class SimilarSpeciesImageFetcher {
    var images: [UIImage] = []
    var commonName: String?
    var isLoading: Bool = false

    // Isolated session for Wikipedia and GBIF external API metadata calls.
    // Timeout is deliberately short (10 s) — these are best-effort enrichment fetches
    // and should never stall the InsightSheet layout.
    private static let externalAPISession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    nonisolated static func orderedLoadedValues<Value>(
        from results: [(index: Int, value: Value?)]
    ) -> [Value] {
        results
            .sorted { $0.index < $1.index }
            .compactMap { $0.value }
    }

    // Explicit network fallback strings that cache aggressively under OOM limits
    func fetchImage(for scientificName: String) async -> Bool {
        guard !scientificName.isEmpty else { return false }
        
        self.images.removeAll()
        
        // Ensure SwiftUI bindings track layout transitions
        self.isLoading = true
        defer { self.isLoading = false }
        
        let normalized = scientificName.replacingOccurrences(of: " ", with: "_")
        
        // 1. Resolve remote URLs concurrently off the main thread.
        //    Wikipedia and GBIF run in parallel — previously sequential, which meant
        //    an 11s worst-case wait (5s wiki + 6s GBIF) before the placeholder appeared.
        let fetchOutput = await Task.detached(priority: .utility) { () -> (urls: [String], commonName: String?) in
            async let wikiResult: (String?, String?)? = {
                guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
                else { return nil }
                var request = URLRequest(url: url)
                request.timeoutInterval = 10.0
                request.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")
                guard let (data, response) = try? await SimilarSpeciesImageFetcher.externalAPISession.data(for: request),
                      let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(WikiSummaryResponse.self, from: data)
                else { return nil }
                return (decoded.title, decoded.thumbnail?.source ?? decoded.originalimage?.source)
            }()

            async let gbifUrls: [String] = {
                guard let encoded = scientificName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "https://api.gbif.org/v1/occurrence/search?scientificName=\(encoded)&mediaType=StillImage&limit=5")
                else { return [] }
                var request = URLRequest(url: url)
                request.timeoutInterval = 10.0
                guard let (data, response) = try? await SimilarSpeciesImageFetcher.externalAPISession.data(for: request),
                      let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(FetcherGBIFMediaResponse.self, from: data),
                      let results = decoded.results
                else { return [] }
                
                return results.compactMap { $0.media?.first(where: { $0.type == "StillImage" })?.identifier }
            }()

            var urls: [String] = []
            let wr = await wikiResult
            if let w = wr?.1 { urls.append(w) }
            urls.append(contentsOf: await gbifUrls)
            
            // Remove duplicates while keeping order
            var seen = Set<String>()
            let deduped = urls.filter {
                ExternalReferenceImagePolicy.isAllowed($0) && seen.insert($0).inserted
            }
            return (urls: deduped, commonName: wr?.0)
        }.value
        
        let resolvedUrls = fetchOutput.urls
        if let fallbackName = fetchOutput.commonName, fallbackName.lowercased() != scientificName.lowercased() {
             self.commonName = fallbackName
        }
        
        if resolvedUrls.isEmpty { return false }
        
        // 2. Delegate uncompressed bitmap instantiation to Zero-OOM actor limits.
        // Preserve source order after concurrent downloads so filtering the first URL
        // deterministically promotes the next GBIF/Wikipedia result.
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, urlString) in resolvedUrls.enumerated() {
                group.addTask {
                    let image = await LocalImageLoader.shared.loadImage(
                        fromPath: nil,
                        fallbackUrl: urlString,
                        maxDimension: 500
                    )
                    return (index, image)
                }
            }

            var downloadedImages: [(index: Int, value: UIImage?)] = []
            for await (index, downloadedImage) in group {
                downloadedImages.append((index, downloadedImage))
            }
            self.images = Self.orderedLoadedValues(from: downloadedImages)
        }
        
        return !self.images.isEmpty
    }
}
