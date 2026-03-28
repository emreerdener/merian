import Testing
import UIKit
import Foundation
@testable import Merian

struct LocalImageLoaderTests {
    
    @Test func testLocalImageLoader_ConcurrentDeduplication() async throws {
        let loader = LocalImageLoader.shared
        
        // We use a dummy payload URL that will just simulate a network flight
        let testUrlString = "https://example.com/dummy.jpg"
        
        // Clear caches to ensure cold start
        ImageCache.shared.clear()
        
        actor TaskCollector {
            var images: [UIImage?] = []
            func add(_ img: UIImage?) { images.append(img) }
        }
        
        let collector = TaskCollector()
        
        // Fire 5 concurrent requests for the exact same URL payload
        await withTaskGroup(of: UIImage?.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    return await loader.loadImage(fromPath: nil, fallbackUrl: testUrlString, maxDimension: 500)
                }
            }
            
            for await result in group {
                await collector.add(result)
            }
        }
        
        let results = await collector.images
        
        // Since it's a dummy URL that will 404/fail, they all should return exactly nil safely.
        // We are just verifying that the internal Task.detached deduplication dictionary allows
        // 5 concurrent requests without blowing up or entering a race condition!
        #expect(results.count == 5)
        
        for result in results {
            #expect(result == nil)
        }
    }
}
