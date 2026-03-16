import XCTest
@testable import Merian

@MainActor
final class SyncStateManagerTests: XCTestCase {

    var syncManager: SyncStateManager!

    override func setUp() async throws {
        syncManager = SyncStateManager.shared
        syncManager.completeSync()
    }

    override func tearDown() async throws {
        syncManager.completeSync()
        syncManager = nil
    }

    func testInitialState() {
        XCTAssertFalse(syncManager.isSyncing)
        XCTAssertEqual(syncManager.pendingUploadCount, 0)
    }

    func testBeginSyncUpdatesState() {
        syncManager.beginSync(itemCount: 5)
        
        XCTAssertTrue(syncManager.isSyncing)
        XCTAssertEqual(syncManager.pendingUploadCount, 5)
    }

    func testCompleteSyncResetsState() {
        syncManager.beginSync(itemCount: 3)
        syncManager.completeSync()
        
        XCTAssertFalse(syncManager.isSyncing)
        XCTAssertEqual(syncManager.pendingUploadCount, 0)
    }
}
