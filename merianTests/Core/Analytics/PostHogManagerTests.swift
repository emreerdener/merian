import XCTest
@testable import Merian

@MainActor
final class PostHogManagerTests: XCTestCase {

    var postHogManager: PostHogManager!

    override func setUp() async throws {
        postHogManager = PostHogManager.shared
    }

    override func tearDown() async throws {
        // Reset state so tests run deterministically
        postHogManager.reset()
        postHogManager = nil
    }

    func testManagerInitializationAndBindings() {
        XCTAssertNotNil(postHogManager)
        
        // Ensure manual bind limits execute directly without breaking boundaries
        postHogManager.identifyUser(userId: "testing_bound_uuid")
        
        // Assert we can wipe that same boundary
        postHogManager.reset()
    }
}
