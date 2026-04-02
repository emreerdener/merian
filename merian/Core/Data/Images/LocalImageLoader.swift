import CoreImage
import Foundation
import SwiftUI

// MARK: - Core Image Processing Engine
/// Unifies APFS file rendering, sandbox extractions, and Cloudflare R2 loading autonomously handling physical cache networks natively.
actor LocalImageLoader {
    // MARK: - Singleton Architecture
    static let shared = LocalImageLoader()
    
    // MARK: - Thread-Safe Task Queues
    private var activeTasks: [String: Task<UIImage?, Never>] = [:]
    
    // Limits concurrent ImageIO decodes to prevent JetSam OOM on large grid layouts.
    private static let decodeSemaphore = DispatchSemaphore(value: 4)
    
    // MARK: - Asset Orchestration
    func loadImage(fromPath imagePath: String?, fallbackUrl: String? = nil, maxDimension: Int = 1024) async -> UIImage? {
        guard let baseKey = imagePath ?? fallbackUrl else {
            return nil
        }
        
        let cacheKey = "\(baseKey)_\(maxDimension)"
        
        // 1. RAM Cache Hit
        if let cached = ImageCache.shared.get(forKey: cacheKey) {
            return cached
        }
        
        // 2. Thundering Herd Request Coalescing
        if let existingTask = activeTasks[cacheKey] {
            return await existingTask.value
        }
        
        let fetchTask = Task.detached(priority: .userInitiated) { () -> UIImage? in
            // 3. Remote URL Execution (if 'imagePath' is actually a cloud URL payload directly)
            if let safePath = imagePath, safePath.starts(with: "http"), let remoteUrl = URL(string: safePath) {
                if let networkImage = await LocalImageLoader.fetchRemote(url: remoteUrl, cacheKey: cacheKey, maxSize: CGFloat(maxDimension)) {
                    return networkImage
                }
            }
            // 4. Local File Extraction directly off Main Thread
            else if let safePath = imagePath, !safePath.isEmpty, !safePath.starts(with: "http") {
                if let image = LocalImageLoader.loadLocal(path: safePath, cacheKey: cacheKey, maxSize: CGFloat(maxDimension)) {
                    return image
                }
            }

            // 5. Explicit Network Fallback explicitly routing legacy bounds
            if let fallbackUrlString = fallbackUrl {
                let urls = fallbackUrlString.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .compactMap { URL(string: $0) }

                for url in urls {
                    // We intentionally do NOT check `Task.isCancelled` here because this is a
                    // detached task serving multiple coalesced callers. We want it to finish caching.
                    if let networkImage = await LocalImageLoader.fetchRemote(url: url, cacheKey: cacheKey, maxSize: CGFloat(maxDimension)) {
                        return networkImage
                    }
                }
            }

            return nil
        }
        
        activeTasks[cacheKey] = fetchTask
        
        defer {
            if activeTasks[cacheKey] == fetchTask {
                activeTasks.removeValue(forKey: cacheKey)
            }
        }
        
        return await fetchTask.value
    }
    
    // MARK: - Prefetch API

    /// Warms the in-memory cache for a leading set of thumbnails before the grid renders.
    /// Results land in ImageCache so ScanThumbnail.task gets an immediate cache hit instead
    /// of starting a cold decode after the cell becomes visible.
    ///
    /// Uses .utility priority: runs immediately and freely on background threads without
    /// competing with the main render loop or camera capture (which runs on its own
    /// DispatchQueue entirely outside the Swift concurrency thread pool).
    /// Concurrency is capped at 4 to avoid thermal spikes on older devices.
    nonisolated func prefetch(
        records: [(imagePath: String?, fallbackUrl: String?)],
        maxDimension: Int
    ) {
        Task(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for record in records {
                    if inFlight >= 4 {
                        await group.next()
                        inFlight -= 1
                    }
                    group.addTask(priority: .utility) {
                        _ = await self.loadImage(
                            fromPath: record.imagePath,
                            fallbackUrl: record.fallbackUrl,
                            maxDimension: maxDimension
                        )
                    }
                    inFlight += 1
                }
            }
        }
    }

    // MARK: - Nonisolated Fetch Helpers
    // Static nonisolated functions so the Task.detached body above never re-enters the actor's
    // executor mid-operation. All I/O and CGImage work runs on the detached task's thread pool;
    // only the final ImageCache.shared.set call crosses into the cache (which is @unchecked Sendable).

    /// Decodes a local APFS file path into a UIImage without touching the actor's executor.
    private static nonisolated func loadLocal(path: String, cacheKey: String, maxSize: CGFloat) -> UIImage? {
        let filename = (path as NSString).lastPathComponent
        let url = URL.documentsDirectory.appendingPathComponent(filename)
        
        LocalImageLoader.decodeSemaphore.wait()
        defer { LocalImageLoader.decodeSemaphore.signal() }
        
        guard let cgImage = ImageDownsampler.shared.downsample(url: url, maxSize: maxSize) else { return nil }
        let image = UIImage(cgImage: cgImage)
        ImageCache.shared.set(image, forKey: cacheKey)
        return image
    }

    /// Downloads a remote URL, downsamples, and caches — entirely off the actor executor.
    static nonisolated func fetchRemote(url: URL, cacheKey: String, maxSize: CGFloat = 500) async -> UIImage? {
        if Task.isCancelled { return nil }
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            if Task.isCancelled { return nil }
            
            let thumbnail: UIImage? = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    LocalImageLoader.decodeSemaphore.wait()
                    defer { LocalImageLoader.decodeSemaphore.signal() }
                    
                    if let cgImage = ImageDownsampler.shared.downsample(url: tempURL, maxSize: maxSize) {
                        let result = UIImage(cgImage: cgImage)
                        ImageCache.shared.set(result, forKey: cacheKey)
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            return thumbnail
        } catch {
            return nil
        }
    }
}
