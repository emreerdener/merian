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

    func testInitialStorageNotCriticallyLow() {
        // Assert starting default is false
        XCTAssertFalse(archiveManager.isStorageCriticallyLow)
    }

    func testPermissionsDefaults() {
        // We can't definitively predict the auth status in an isolated runner context, 
        // but it shouldn't crash reading it.
        let status = archiveManager.isAuthorized
        XCTAssertNotNil(status)
    }
}
