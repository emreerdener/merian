import Foundation
@testable import Merian
import Testing
import UIKit

struct LocalImageLoaderTests {
    private actor ConcurrencyProbe {
        private(set) var active = 0
        private(set) var maximum = 0

        func enter() {
            active += 1
            maximum = max(maximum, active)
        }

        func leave() {
            active -= 1
        }
    }

    @Test func asyncPermitPoolBoundsWorkWithoutBlockingWaits() async {
        let pool = AsyncPermitPool(limit: 2)
        let probe = ConcurrencyProbe()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    guard await pool.acquire() else { return }
                    await probe.enter()
                    try? await Task.sleep(for: .milliseconds(10))
                    await probe.leave()
                    await pool.release()
                }
            }
        }

        let maximum = await probe.maximum
        #expect(maximum == 2)
    }

    @Test func cancelledPermitWaiterDoesNotConsumeReleasedSlot() async {
        let pool = AsyncPermitPool(limit: 1)
        let initialPermit = await pool.acquire()
        #expect(initialPermit)

        let waiter = Task { await pool.acquire() }
        await Task.yield()
        waiter.cancel()
        let cancelledWaiterAcquired = await waiter.value
        #expect(!cancelledWaiterAcquired)

        await pool.release()
        let replacementPermit = await pool.acquire()
        #expect(replacementPermit)
        await pool.release()
    }
    
    @Test func testLocalImageLoader_ConcurrentDeduplication() async throws {
        let loader = LocalImageLoader.shared
        
        // We use a dummy payload URL that will just simulate a network flight
        let testUrlString = "https://example.com/dummy.jpg"
        
        // Clear caches to ensure cold start
        ImageCache.shared.clearCache()
        
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
