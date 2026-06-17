import XCTest
@testable import Merian

@MainActor
final class ArchiveManagerTests: XCTestCase {

    var archiveManager: ArchiveManager!

    override func setUp() async throws {
        archiveManager = ArchiveManager.shared
    }

    override func tearDown() async throws {
        archiveManager = nil
    }

    func testAvailableDiskSpaceIsPositive() {
        let space = archiveManager.getAvailableDiskSpace()
        // Running on any functional simulator or device should return > 0 available space
        XCTAssertGreaterThan(space, 0)
    }
}
