import SwiftUI

nonisolated func generateThumbnail(for url: URL, cacheKey: String) async -> UIImage? {
    if Task.isCancelled { return nil }
    
    return await Task.detached(priority: .userInitiated) {
        if Task.isCancelled { return nil }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 300
        ]
        
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            let fallback = UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 300, height: 300))
            if let fb = fallback { ImageCache.shared.set(fb, forKey: cacheKey) }
            return fallback
        }
        
        let img = UIImage(cgImage: cgImage)
        ImageCache.shared.set(img, forKey: cacheKey)
        return img
    }.value
}

nonisolated func fetchNetworkFallback(url: URL, cacheKey: String) async -> UIImage? {
    if Task.isCancelled { return nil }
    
    do {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }
        
        if Task.isCancelled { return nil }
        
        return await Task.detached(priority: .userInitiated) {
            if let cgImage = ImageDownsampler.downsample(data: data, maxSize: 500) {
                let thumbnail = UIImage(cgImage: cgImage)
                ImageCache.shared.set(thumbnail, forKey: cacheKey)
                return thumbnail
            } else {
                let fallback = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 500, height: 500))
                if let fb = fallback { ImageCache.shared.set(fb, forKey: cacheKey) }
                return fallback
            }
        }.value
    } catch {
        return nil
    }
}

/// Unifies APFS file rendering, sandbox extractions, and Cloudflare R2 loading autonomously handling physical cache networks natively.
actor LocalImageLoader {
    static let shared = LocalImageLoader()
    
    private var activeTasks: [String: Task<UIImage?, Never>] = [:]
    
    func loadImage(fromPath imagePath: String?, fallbackUrl: String? = nil, maxDimension: Int = 1024) async -> UIImage? {
        guard let cacheKey = imagePath ?? fallbackUrl else {
            return nil
        }
        
        // 1. RAM Cache Hit
        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            return cached
        }
        
        // 2. Thundering Herd Request Coalescing
        if let existingTask = activeTasks[cacheKey] {
            return await existingTask.value
        }
        
        let fetchTask = Task<UIImage?, Never> {
            // 3. Local File Extraction directly off Main Thread
            if let safePath = imagePath {
                let filename = (safePath as NSString).lastPathComponent
                let url = URL.documentsDirectory.appendingPathComponent(filename)
                
                if let decoded = await Task.detached(priority: .userInitiated, operation: { () -> UIImage? in
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maxDimension
                    ]
                    
                    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                        return nil
                    }
                    
                    return UIImage(cgImage: cgImage)
                }).value {
                    ImageCache.shared.set(decoded, forKey: cacheKey)
                    return decoded
                }
            }
            
            // 4. Network Fallback mapped securely via URLSession matching legacy Grid arrays
            if let fallbackUrlString = fallbackUrl, let url = URL(string: fallbackUrlString) {
                if let networkImage = await fetchNetworkFallback(url: url, cacheKey: cacheKey) {
                    return networkImage
                }
            }
            
            return nil
        }
        
        activeTasks[cacheKey] = fetchTask
        
        defer {
            activeTasks.removeValue(forKey: cacheKey)
        }
        
        return await fetchTask.value
    }
}
