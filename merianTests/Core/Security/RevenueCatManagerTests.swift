import XCTest
@testable import Merian

@MainActor
final class RevenueCatManagerTests: XCTestCase {

    var revenueCatManager: RevenueCatManager!

    override func setUp() async throws {
        revenueCatManager = RevenueCatManager.shared
    }

    override func tearDown() async throws {
        revenueCatManager = nil
    }

    func testInitialStateIsCorrect() {
        // Assert starting default conditions
        XCTAssertFalse(revenueCatManager.isProActive)
        XCTAssertNil(revenueCatManager.currentOfferings)
        XCTAssertFalse(revenueCatManager.isFetchingOfferings)
    }
}
