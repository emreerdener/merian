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
        
        do {
            let downloadedImage = try await Task.detached(priority: .utility) { () -> UIImage? in
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 else { return nil }
                
                let decoded = try JSONDecoder().decode(WikiSummaryResponse.self, from: data)
                
                // Prefer thumbnail for lists, fallback to original if thumbnail doesn't exist.
                guard let imageUrlString = decoded.thumbnail?.source ?? decoded.originalimage?.source,
                      let imageUrl = URL(string: imageUrlString) else { return nil }
                
                var imageRequest = URLRequest(url: imageUrl)
                imageRequest.setValue("Merian/1.0", forHTTPHeaderField: "User-Agent")
                
                let (imageData, imageResponse) = try await URLSession.shared.data(for: imageRequest)
                guard let imageHttpRes = imageResponse as? HTTPURLResponse, imageHttpRes.statusCode == 200,
                      let img = UIImage(data: imageData) else { return nil }
                
                return img
            }.value
            
            if let downloadedImage {
                Self.memoryCache.setObject(downloadedImage, forKey: normalized as NSString)
                self.image = downloadedImage
            }
        } catch {
            MerianLog.general.debug("SimilarSpeciesImageFetcher failed for \(scientificName): \(error.localizedDescription)")
        }
    }
}
