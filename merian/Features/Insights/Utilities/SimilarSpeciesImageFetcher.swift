import Foundation
import UIKit

@MainActor
final class SimilarSpeciesImageFetcher: ObservableObject {
    @Published var image: UIImage? = nil
    @Published var isLoading: Bool = false
    
    // In-memory cache to prevent re-fetching the same lookalike image repeatedly
    private static let memoryCache = NSCache<NSString, UIImage>()
    
    private struct WikiSummaryResponse: Decodable {
        let thumbnail: Thumbnail?
        let originalimage: Thumbnail?
        struct Thumbnail: Decodable {
            let source: String?
        }
    }
    
    private struct GBIFMediaResponse: Decodable {
        let results: [GBIFResult]?
        struct GBIFResult: Decodable {
            let media: [GBIFMedia]?
        }
        struct GBIFMedia: Decodable {
            let type: String?
            let identifier: String?
        }
    }
    
    func fetchImage(for scientificName: String) async {
        guard !scientificName.isEmpty else { return }
        
        let normalized = scientificName.replacingOccurrences(of: " ", with: "_")
        
        if let cachedImage = Self.memoryCache.object(forKey: normalized as NSString) {
            self.image = cachedImage
            return
        }
        
        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encoded)") else {
            return
        }
        
        self.isLoading = true
        defer { self.isLoading = false }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        request.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")
        
        let downloadedImage = await Task.detached(priority: .utility) { () -> UIImage? in
                // 1. Attempt Wikipedia
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                       let decoded = try? JSONDecoder().decode(WikiSummaryResponse.self, from: data),
                       let imageUrlString = decoded.thumbnail?.source ?? decoded.originalimage?.source,
                       let imageUrl = URL(string: imageUrlString) {
                        
                        var imageRequest = URLRequest(url: imageUrl)
                        imageRequest.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")
                        
                        let (imageData, imageResponse) = try await URLSession.shared.data(for: imageRequest)
                        if let imageHttpRes = imageResponse as? HTTPURLResponse, imageHttpRes.statusCode == 200,
                           let img = UIImage(data: imageData) {
                            return img
                        }
                    }
                } catch {
                    // Fail over cleanly
                }
                
                // 2. Fallback to GBIF Occurrence Search
                guard let gbifEncoded = scientificName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                      let gbifUrl = URL(string: "https://api.gbif.org/v1/occurrence/search?scientificName=\(gbifEncoded)&mediaType=StillImage&limit=1") else {
                    return nil
                }
                
                var gbifRequest = URLRequest(url: gbifUrl)
                gbifRequest.timeoutInterval = 6.0
                
                do {
                    let (data, response) = try await URLSession.shared.data(for: gbifRequest)
                    guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return nil }
                    
                    let decoded = try JSONDecoder().decode(GBIFMediaResponse.self, from: data)
                    guard let firstResult = decoded.results?.first,
                          let firstMedia = firstResult.media?.first(where: { $0.type == "StillImage" }),
                          let imageUrlString = firstMedia.identifier,
                          let imageUrl = URL(string: imageUrlString) else { return nil }
                    
                    var imageRequest = URLRequest(url: imageUrl)
                    imageRequest.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")
                    
                    let (imageData, imageResponse) = try await URLSession.shared.data(for: imageRequest)
                    guard let imageHttpRes = imageResponse as? HTTPURLResponse, imageHttpRes.statusCode == 200,
                          let img = UIImage(data: imageData) else { return nil }
                    
                    return img
                } catch {
                    return nil
                }
            }.value
            
        if let downloadedImage {
            Self.memoryCache.setObject(downloadedImage, forKey: normalized as NSString)
            self.image = downloadedImage
        }
    }
}
