import Foundation
import Observation
import SwiftUI
import UIKit

private struct WikiThumbnail: Decodable {
    let source: String?
}

private struct WikiSummaryResponse: Decodable {
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
        let resolvedUrls = await Task.detached(priority: .utility) { () -> [String] in
            async let wikiUrl: String? = {
                guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)")
                else { return nil }
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                request.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")
                guard let (data, response) = try? await SimilarSpeciesImageFetcher.externalAPISession.data(for: request),
                      let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(WikiSummaryResponse.self, from: data)
                else { return nil }
                return decoded.thumbnail?.source ?? decoded.originalimage?.source
            }()

            async let gbifUrls: [String] = {
                guard let encoded = scientificName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "https://api.gbif.org/v1/occurrence/search?scientificName=\(encoded)&mediaType=StillImage&limit=5")
                else { return [] }
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                guard let (data, response) = try? await SimilarSpeciesImageFetcher.externalAPISession.data(for: request),
                      let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(FetcherGBIFMediaResponse.self, from: data),
                      let results = decoded.results
                else { return [] }
                
                return results.compactMap { $0.media?.first(where: { $0.type == "StillImage" })?.identifier }
            }()

            var urls: [String] = []
            if let w = await wikiUrl { urls.append(w) }
            urls.append(contentsOf: await gbifUrls)
            
            // Remove duplicates while keeping order
            var seen = Set<String>()
            return urls.filter { seen.insert($0).inserted }
        }.value
        
        if resolvedUrls.isEmpty { return false }
        
        // 2. Delegate uncompressed bitmap instantiation to Zero-OOM actor limits
        // We accumulate dynamically so the UI can update while remaining images continue downloading
        await withTaskGroup(of: UIImage?.self) { group in
            for urlString in resolvedUrls {
                group.addTask {
                    return await LocalImageLoader.shared.loadImage(fromPath: nil, fallbackUrl: urlString, maxDimension: 500)
                }
            }
            
            for await downloadedImage in group {
                if let downloadedImage = downloadedImage {
                    self.images.append(downloadedImage)
                }
            }
        }
        
        return !self.images.isEmpty
    }
}
