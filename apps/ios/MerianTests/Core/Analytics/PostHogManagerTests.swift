@testable import Merian
import XCTest

@MainActor
final class PostHogManagerTests: XCTestCase {

    var postHogManager: PostHogManager!

    override func setUp() async throws {
        postHogManager = PostHogManager.shared
        postHogManager.reset()
    }

    override func tearDown() async throws {
        // Reset state so tests run deterministically
        postHogManager.reset()
        postHogManager = nil
    }

    func testManagerInitializationAndBindings() {
        XCTAssertNotNil(postHogManager)

        XCTAssertFalse(postHogManager.hasConsent)
        XCTAssertFalse(postHogManager.isCaptureEnabled)

        // Identity is rejected while analytics permission is absent.
        postHogManager.identifyUser(userId: "testing_bound_uuid")

        postHogManager.setConsentGranted(true, userId: "testing_bound_uuid")
        XCTAssertTrue(postHogManager.hasConsent)

        postHogManager.reset()
        XCTAssertFalse(postHogManager.hasConsent)
        XCTAssertFalse(postHogManager.isCaptureEnabled)
    }
}
