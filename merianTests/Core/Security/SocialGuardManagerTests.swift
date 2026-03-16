import XCTest
@testable import Merian

@MainActor
final class SocialGuardManagerTests: XCTestCase {

    var socialGuard: SocialGuardManager!

    override func setUp() async throws {
        socialGuard = SocialGuardManager.shared
        // Reset state
        socialGuard.blockedUserIds.removeAll()
    }

    override func tearDown() async throws {
        socialGuard.blockedUserIds.removeAll()
        socialGuard = nil
    }

    func testInitialState() {
        XCTAssertTrue(socialGuard.blockedUserIds.isEmpty)
    }

    func testOptimisticBlockRevertsOnNetworkFailure() async {
        // We know that in a mocked/isolated runner WITHOUT live valid JWTs, 
        // the network callback `syncBlockWithBackend` will return false.
        // Therefore, the block should proactively insert, then revert.

        // Initial check
        XCTAssertTrue(socialGuard.blockedUserIds.isEmpty)

        // Block
        await socialGuard.blockUser(targetUserId: "mock-user-123")
        
        // Final assertion: It should be empty because the edge call fails natively.
        XCTAssertTrue(socialGuard.blockedUserIds.isEmpty)
    }
}
