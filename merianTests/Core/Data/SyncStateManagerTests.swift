import XCTest
@testable import Merian

@MainActor
final class SyncStateManagerTests: XCTestCase {

    var syncManager: SyncStateManager!

    override func setUp() async throws {
        syncManager = SyncStateManager.shared
        syncManager.forceIdle()
    }

    override func tearDown() async throws {
        syncManager.forceIdle()
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

    func testCompleteUploadPhaseResetsWhenNoInferenceActive() {
        syncManager.beginSync(itemCount: 3)
        syncManager.completeUploadPhase()
        XCTAssertFalse(syncManager.isSyncing)
        XCTAssertEqual(syncManager.pendingUploadCount, 0)
    }

    func testCompleteSyncResetsWhenAllInferenceComplete() {
        syncManager.beginInferencing()
        syncManager.completeSync()
        XCTAssertFalse(syncManager.isSyncing)
    }

    func testCompleteSyncDoesNotGoIdleUntilAllPipelinesFinish() {
        syncManager.beginInferencing()
        syncManager.beginInferencing()
        syncManager.completeSync()
        XCTAssertTrue(syncManager.isSyncing) // one still in flight
        syncManager.completeSync()
        XCTAssertFalse(syncManager.isSyncing) // now both done
    }

    func testCompleteUploadPhaseDoesNotGoIdleWhenInferenceActive() {
        syncManager.beginInferencing()
        syncManager.completeUploadPhase()
        XCTAssertTrue(syncManager.isSyncing) // inference still in flight
    }

    func testForceIdleResetsImmediately() {
        syncManager.beginInferencing()
        syncManager.beginInferencing()
        syncManager.forceIdle()
        XCTAssertFalse(syncManager.isSyncing)
    }
}
