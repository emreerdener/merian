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
