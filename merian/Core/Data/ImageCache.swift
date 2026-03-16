import UIKit

/// Thread-safe singleton for caching downsampled thumbnails in active RAM.
/// NSCache automatically purges objects if the iOS OS reports memory pressure.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        // Limit cache to ~100 items to guarantee we never trigger OOM constraints (roughly 15MB)
        cache.countLimit = 100
    }
    
    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    func get(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}
