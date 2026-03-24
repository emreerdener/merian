import UIKit

// MARK: - Image Cache

/// Thread-safe in-memory cache for downsampled thumbnails.
///
/// Backed by `NSCache`, which automatically evicts entries under memory pressure.
/// Capped at 100 entries (~15 MB) to avoid contributing to memory warnings.
final class ImageCache: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = ImageCache()

    // MARK: - Storage

    private let cache = NSCache<NSString, UIImage>()

    // MARK: - Lifecycle

    private init() {
        cache.countLimit = 100
    }

    // MARK: - Access

    /// Stores an image in the cache under the given key.
    func set(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    /// Returns the cached image for the given key, or `nil` if not present.
    func get(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    /// Removes all cached images.
    func clearCache() {
        cache.removeAllObjects()
    }
}
