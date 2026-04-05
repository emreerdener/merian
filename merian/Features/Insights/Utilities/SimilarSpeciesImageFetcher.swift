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
    var image: UIImage?
    var isLoading: Bool = false
    
    // Explicit network fallback strings that cache aggressively under OOM limits
    func fetchImage(for scientificName: String) async -> Bool {
        guard !scientificName.isEmpty else { return false }
        
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
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(WikiSummaryResponse.self, from: data)
                else { return nil }
                return decoded.thumbnail?.source ?? decoded.originalimage?.source
            }()

            async let gbifUrl: String? = {
                guard let encoded = scientificName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let url = URL(string: "https://api.gbif.org/v1/occurrence/search?scientificName=\(encoded)&mediaType=StillImage&limit=1")
                else { return nil }
                var request = URLRequest(url: url)
                request.timeoutInterval = 5.0
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(FetcherGBIFMediaResponse.self, from: data),
                      let firstMedia = decoded.results?.first?.media?.first(where: { $0.type == "StillImage" })
                else { return nil }
                return firstMedia.identifier
            }()

            return await [wikiUrl, gbifUrl].compactMap { $0 }
        }.value
        
        if resolvedUrls.isEmpty { return false }
        
        let fallbackUrlString = resolvedUrls.joined(separator: ",")
        
        // 2. Delegate uncompressed bitmap instantiation to Zero-OOM actor limits
        if let downloadedImage = await LocalImageLoader.shared.loadImage(fromPath: nil, fallbackUrl: fallbackUrlString, maxDimension: 500) {
            self.image = downloadedImage
            return true
        }
        
        return false
    }
}
