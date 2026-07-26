@testable import Merian
import XCTest

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
        syncManager.beginSync(itemCount: 5, generation: UUID())
        XCTAssertTrue(syncManager.isSyncing)
        XCTAssertEqual(syncManager.pendingUploadCount, 5)
    }

    func testCompleteUploadPhaseResetsWhenNoInferenceActive() {
        let generation = UUID()
        syncManager.beginSync(itemCount: 3, generation: generation)
        syncManager.completeUploadPhase(generation: generation)
        XCTAssertFalse(syncManager.isSyncing)
        XCTAssertEqual(syncManager.pendingUploadCount, 0)
    }

    func testCompleteSyncResetsWhenAllInferenceComplete() {
        let generation = UUID()
        syncManager.beginInferencing(generation: generation)
        syncManager.completeSync(generation: generation)
        XCTAssertFalse(syncManager.isSyncing)
    }

    func testCompleteSyncDoesNotGoIdleUntilAllPipelinesFinish() {
        let firstGeneration = UUID()
        let secondGeneration = UUID()
        syncManager.beginInferencing(generation: firstGeneration)
        syncManager.beginInferencing(generation: secondGeneration)
        syncManager.completeSync(generation: firstGeneration)
        XCTAssertTrue(syncManager.isSyncing) // one still in flight
        syncManager.completeSync(generation: secondGeneration)
        XCTAssertFalse(syncManager.isSyncing) // now both done
    }

    func testCompleteUploadPhaseDoesNotGoIdleWhenInferenceActive() {
        let uploadGeneration = UUID()
        let inferenceGeneration = UUID()
        syncManager.beginSync(itemCount: 1, generation: uploadGeneration)
        syncManager.beginInferencing(generation: inferenceGeneration)
        syncManager.completeUploadPhase(generation: uploadGeneration)
        XCTAssertTrue(syncManager.isSyncing) // inference still in flight
    }

    func testForceIdleResetsImmediately() {
        syncManager.beginInferencing(generation: UUID())
        syncManager.beginInferencing(generation: UUID())
        syncManager.forceIdle()
        XCTAssertFalse(syncManager.isSyncing)
    }

    func testStaleUploadCompletionCannotClearReplacementBatch() {
        let staleGeneration = UUID()
        let currentGeneration = UUID()
        syncManager.beginSync(itemCount: 2, generation: staleGeneration)
        syncManager.beginSync(itemCount: 7, generation: currentGeneration)

        syncManager.completeUploadPhase(generation: staleGeneration)

        XCTAssertTrue(syncManager.isSyncing)
        XCTAssertEqual(syncManager.pendingUploadCount, 7)
        syncManager.completeUploadPhase(generation: currentGeneration)
        XCTAssertFalse(syncManager.isSyncing)
    }

    func testLateInferenceCompletionAfterForceIdleCannotDecrementNewWork() {
        let staleGeneration = UUID()
        let currentGeneration = UUID()
        syncManager.beginInferencing(generation: staleGeneration)
        syncManager.forceIdle()
        syncManager.beginInferencing(generation: currentGeneration)

        syncManager.completeSync(generation: staleGeneration)

        XCTAssertTrue(syncManager.isSyncing)
        XCTAssertEqual(syncManager.phase, .inferencing)
        syncManager.completeSync(generation: currentGeneration)
        XCTAssertFalse(syncManager.isSyncing)
    }

    func testLateFinalizingTransitionCannotAdvanceReplacementWork() {
        let staleGeneration = UUID()
        let currentGeneration = UUID()
        syncManager.beginInferencing(generation: staleGeneration)
        syncManager.forceIdle()
        syncManager.beginInferencing(generation: currentGeneration)

        syncManager.beginFinalizing(generation: staleGeneration)

        XCTAssertEqual(syncManager.phase, .inferencing)
        syncManager.beginFinalizing(generation: currentGeneration)
        XCTAssertEqual(syncManager.phase, .finalizing)
    }

    func testGenerationTaskRegistryUsesCompareBeforeClear() {
        let registry = GenerationTaskRegistry<String>()
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstToken = registry.replace(
            for: "scan-a",
            ownerGeneration: firstOwner
        ) { _ in Task {} }
        let secondToken = registry.replace(
            for: "scan-a",
            ownerGeneration: secondOwner
        ) { _ in Task {} }

        XCTAssertFalse(
            registry.clearIfCurrent("scan-a", token: firstToken)
        )
        registry.cancel("scan-a", ifOwnedBy: firstOwner)
        XCTAssertFalse(registry.isOwned("scan-a", by: firstOwner))
        XCTAssertTrue(registry.isOwned("scan-a", by: secondOwner))
        XCTAssertTrue(
            registry.isCurrent(
                "scan-a",
                token: secondToken,
                ownerGeneration: secondOwner
            )
        )

        registry.cancelAll()
        XCTAssertEqual(registry.count, 0)
    }
}
