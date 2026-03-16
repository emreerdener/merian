import XCTest
@testable import Merian

final class ImageCacheTests: XCTestCase {

    var cache: ImageCache!

    override func setUp() {
        super.setUp()
        cache = ImageCache.shared
    }

    override func tearDown() {
        // Clear underlying NSCache logic by replacing dummy keys
        cache = nil
        super.tearDown()
    }

    func testCacheCanSetAndRetrieveImage() {
        let testImage = UIImage(systemName: "star")!
        let key = "testStarKey"

        // Value shouldn't exist initially
        XCTAssertNil(cache.get(forKey: key))
        
        // Cache and retrieve
        cache.set(testImage, forKey: key)
        let retrieved = cache.get(forKey: key)
        
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(testImage, retrieved)
    }

    func testCacheHandlesMissingKeys() {
        let missingKey = "iDoNotExist"
        XCTAssertNil(cache.get(forKey: missingKey))
    }
}
