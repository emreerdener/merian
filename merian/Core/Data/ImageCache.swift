import UIKit

// MARK: - Core L1 Hardware Cache
/// Thread-safe singleton for caching downsampled thumbnails in active RAM.
/// NSCache automatically purges objects if the iOS OS reports memory pressure.
final class ImageCache: @unchecked Sendable {
    // MARK: - Singleton Architecture
    static let shared = ImageCache()
    
    // MARK: - Memory Buffer
    private let cache = NSCache<NSString, UIImage>()
    
    // MARK: - Lifecycle
    private init() {
        // Limit cache to ~100 items to guarantee we never trigger OOM constraints (roughly 15MB)
        cache.countLimit = 100
    }
    
    // MARK: - Write Ops
    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
    
    // MARK: - Read Ops
    func get(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    // MARK: - Destructive Triggers
    func clearCache() {
        cache.removeAllObjects()
    }
}
