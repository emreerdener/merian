import Foundation
import SwiftUI
import CoreImage

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
            // 3. Remote URL Execution (if 'imagePath' is actually a cloud URL payload directly)
            if let safePath = imagePath, safePath.starts(with: "http"), let remoteUrl = URL(string: safePath) {
                if let networkImage = await fetchNetworkFallback(url: remoteUrl, cacheKey: cacheKey) {
                    return networkImage
                }
            } 
            // 4. Local File Extraction directly off Main Thread
            else if let safePath = imagePath, !safePath.isEmpty, !safePath.starts(with: "http") {
                let filename = (safePath as NSString).lastPathComponent
                let url = URL.documentsDirectory.appendingPathComponent(filename)
                
                if let decoded = await Task.detached(priority: .userInitiated, operation: { () -> UIImage? in
                    if let cgImage = ImageDownsampler.downsample(url: url, maxSize: CGFloat(maxDimension)) {
                        return UIImage(cgImage: cgImage)
                    }
                    
                    return nil
                }).value {
                    ImageCache.shared.set(decoded, forKey: cacheKey)
                    return decoded
                }
            }
            
            // 5. Explicit Network Fallback explicitly routing legacy bounds
            if let fallbackUrlString = fallbackUrl {
                let urls = fallbackUrlString.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .compactMap { URL(string: $0) }
                
                for url in urls {
                    if Task.isCancelled { return nil }
                    if let networkImage = await fetchNetworkFallback(url: url, cacheKey: cacheKey) {
                        return networkImage
                    }
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
    
    // Explicit network fallback natively isolated off Main Thread
    private nonisolated func fetchNetworkFallback(url: URL, cacheKey: String) async -> UIImage? {
        if Task.isCancelled { return nil }
        
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            if Task.isCancelled { return nil }
            
            return await Task.detached(priority: .userInitiated) {
                if let cgImage = ImageDownsampler.downsample(url: tempURL, maxSize: 500) {
                    let thumbnail = UIImage(cgImage: cgImage)
                    ImageCache.shared.set(thumbnail, forKey: cacheKey)
                    return thumbnail
                }
                
                return nil
            }.value
        } catch {
            return nil
        }
    }
}
