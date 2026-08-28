import Combine
import SwiftData
import XCTest

@testable import Merian

@MainActor
private final class ScansLibraryActionRecorder {
    var sharedScanIDs: [String] = []
    var savedScanIDs: [String] = []
    var exploreShareScanIDs: [String] = []
    var storedPostIDs: [(postID: String, scanID: String)] = []
    var shareEvents: [(scanID: String, postID: String?)] = []
    var selectionFeedbackCount = 0
    var mediumFeedbackCount = 0
    var successFeedbackCount = 0
    var errorFeedbackCount = 0
    var actionOrder: [String] = []
    var saveResult = MediaSaveResult()
    var explorePostID = "post-1"
    var shouldFailExploreShare = false
}

private enum ScansLibraryActionTestError: Error {
    case failed
}

@MainActor
final class ScansLibraryActionsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var eventPublisher: AppEventPublisher!
    private var recorder: ScansLibraryActionRecorder!
    private var manager: ScansManager!

    override func setUp() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: LocalScanRecord.self,
            ScanCollection.self,
            OfflineQueuedScan.self,
            configurations: configuration
        )
        context = ModelContext(container)
        eventPublisher = AppEventPublisher()
        recorder = ScansLibraryActionRecorder()
        manager = ScansManager(dependencies: makeDependencies())
    }

    override func tearDown() async throws {
        manager = nil
        recorder = nil
        eventPublisher = nil
        context = nil
        container = nil
    }

    func testFeedbackActionsUseInjectedDependencies() {
        manager.triggerSelectionFeedback()
        manager.triggerMediumFeedback()

        XCTAssertEqual(recorder.selectionFeedbackCount, 1)
        XCTAssertEqual(recorder.mediumFeedbackCount, 1)
    }

    func testBatchShareUsesInjectedExporter() async throws {
        let scan = try makeEligibleScan()

        await manager.batchShare(scans: [scan])

        XCTAssertEqual(recorder.sharedScanIDs, [scan.id])
        XCTAssertFalse(manager.isDownloading)
    }

    func testBatchSaveSuccessClearsSelectionAndReportsSavedMedia() async throws {
        let scan = try makeEligibleScan()
        var saveResult = MediaSaveResult()
        saveResult.record(.photo, success: true)
        recorder.saveResult = saveResult
        manager.isSelectionMode = true
        manager.selectedScans = [scan.id]

        await manager.batchSaveMedia(scans: [scan])

        XCTAssertEqual(recorder.savedScanIDs, [scan.id])
        XCTAssertFalse(manager.isDownloading)
        XCTAssertFalse(manager.isSelectionMode)
        XCTAssertTrue(manager.selectedScans.isEmpty)
        XCTAssertEqual(recorder.successFeedbackCount, 1)
        XCTAssertEqual(recorder.errorFeedbackCount, 0)
        XCTAssertEqual(manager.toastMessage?.title, "Saved 1 photo to your camera roll.")
        XCTAssertEqual(manager.toastMessage?.severity, .success)
    }

    func testBatchSaveFailureClearsSelectionAndReportsExistingErrorCopy() async throws {
        let scan = try makeEligibleScan()
        manager.isSelectionMode = true
        manager.selectedScans = [scan.id]

        await manager.batchSaveMedia(scans: [scan])

        XCTAssertFalse(manager.isDownloading)
        XCTAssertFalse(manager.isSelectionMode)
        XCTAssertTrue(manager.selectedScans.isEmpty)
        XCTAssertEqual(recorder.successFeedbackCount, 0)
        XCTAssertEqual(recorder.errorFeedbackCount, 1)
        XCTAssertEqual(manager.toastMessage?.title, "No photos or videos could be saved")
        XCTAssertEqual(manager.toastMessage?.severity, .error)
    }

    func testExploreShareSuccessCommitsLocalStateEventAndFeedbackInOrder() async throws {
        let scan = try makeEligibleScan()
        recorder.explorePostID = "post-\(scan.id)"

        await manager.shareToExplore(scanId: scan.id, modelContext: context)

        XCTAssertEqual(recorder.exploreShareScanIDs, [scan.id])
        XCTAssertEqual(recorder.storedPostIDs.count, 1)
        XCTAssertEqual(recorder.storedPostIDs.first?.postID, recorder.explorePostID)
        XCTAssertEqual(recorder.storedPostIDs.first?.scanID, scan.id)
        XCTAssertEqual(recorder.shareEvents.count, 1)
        XCTAssertEqual(recorder.shareEvents.first?.scanID, scan.id)
        XCTAssertEqual(recorder.shareEvents.first?.postID, recorder.explorePostID)
        XCTAssertEqual(recorder.successFeedbackCount, 1)
        XCTAssertEqual(recorder.errorFeedbackCount, 0)
        XCTAssertEqual(
            recorder.actionOrder,
            ["endpoint", "store-share-state", "send-event", "success-feedback"]
        )
        XCTAssertEqual(manager.toastMessage?.title, "Shared to Explore")
        XCTAssertEqual(manager.toastMessage?.severity, .success)
    }

    func testExploreShareFailureDoesNotCommitLocalPublicationState() async throws {
        let scan = try makeEligibleScan()
        recorder.shouldFailExploreShare = true

        await manager.shareToExplore(scanId: scan.id, modelContext: context)

        XCTAssertEqual(recorder.exploreShareScanIDs, [scan.id])
        XCTAssertTrue(recorder.storedPostIDs.isEmpty)
        XCTAssertTrue(recorder.shareEvents.isEmpty)
        XCTAssertEqual(recorder.successFeedbackCount, 0)
        XCTAssertEqual(recorder.errorFeedbackCount, 1)
        XCTAssertEqual(recorder.actionOrder, ["endpoint", "error-feedback"])
        XCTAssertEqual(manager.toastMessage?.title, "Couldn’t share to Explore")
        XCTAssertEqual(manager.toastMessage?.body, "Try again.")
        XCTAssertEqual(manager.toastMessage?.severity, .error)
    }

    func testMissingExploreScanDoesNotCallEndpoint() async {
        await manager.shareToExplore(scanId: "missing", modelContext: context)

        XCTAssertTrue(recorder.exploreShareScanIDs.isEmpty)
        XCTAssertTrue(recorder.storedPostIDs.isEmpty)
        XCTAssertEqual(recorder.errorFeedbackCount, 1)
        XCTAssertEqual(manager.toastMessage?.title, "This scan is no longer available.")
        XCTAssertEqual(manager.toastMessage?.severity, .warning)
    }

    func testIneligibleExploreScanDoesNotCallEndpoint() async throws {
        let scan = LocalScanRecord(
            id: UUID().uuidString,
            speciesId: UUID().uuidString,
            scientificName: LocalScanRecord.unresolvedBiologicalScientificName,
            commonName: LocalScanRecord.unresolvedBiologicalCommonName,
            isBiological: true
        )
        context.insert(scan)
        try context.save()

        await manager.shareToExplore(scanId: scan.id, modelContext: context)

        XCTAssertTrue(recorder.exploreShareScanIDs.isEmpty)
        XCTAssertTrue(recorder.storedPostIDs.isEmpty)
        XCTAssertEqual(recorder.errorFeedbackCount, 1)
        XCTAssertEqual(
            manager.toastMessage?.title,
            "Reanalyze this scan before sharing to Explore."
        )
        XCTAssertEqual(manager.toastMessage?.severity, .warning)
    }

    private func makeEligibleScan() throws -> LocalScanRecord {
        let scan = LocalScanRecord(
            id: UUID().uuidString,
            speciesId: UUID().uuidString,
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            semanticTags: ["butterfly"],
            hazardType: "none",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            confidenceScore: 0.99,
            taxonomyKingdom: "Animalia",
            taxonomyClass: "Insecta",
            inferenceTier: "pro"
        )
        context.insert(scan)
        try context.save()
        return scan
    }

    private func makeDependencies() -> ScansLibraryDependencies {
        ScansLibraryDependencies(
            events: eventPublisher.publisher,
            sharedPostID: { _ in nil },
            batchShare: { [recorder] scans in
                recorder?.sharedScanIDs = scans.map(\.id)
            },
            batchSaveMedia: { [recorder] scans in
                recorder?.savedScanIDs = scans.map(\.id)
                return recorder?.saveResult ?? MediaSaveResult()
            },
            shareToExplore: { [recorder] scan in
                recorder?.actionOrder.append("endpoint")
                recorder?.exploreShareScanIDs.append(scan.id)
                if recorder?.shouldFailExploreShare == true {
                    throw ScansLibraryActionTestError.failed
                }
                return recorder?.explorePostID ?? "post-1"
            },
            storeSharedPostID: { [recorder] postID, scanID in
                recorder?.actionOrder.append("store-share-state")
                recorder?.storedPostIDs.append((postID, scanID))
            },
            sendExploreShareChanged: { [recorder] scanID, postID in
                recorder?.actionOrder.append("send-event")
                recorder?.shareEvents.append((scanID, postID))
            },
            triggerSelectionFeedback: { [recorder] in
                recorder?.selectionFeedbackCount += 1
            },
            triggerMediumFeedback: { [recorder] in
                recorder?.mediumFeedbackCount += 1
            },
            triggerLightFeedback: {},
            triggerSuccessFeedback: { [recorder] in
                recorder?.actionOrder.append("success-feedback")
                recorder?.successFeedbackCount += 1
            },
            triggerErrorFeedback: { [recorder] in
                recorder?.actionOrder.append("error-feedback")
                recorder?.errorFeedbackCount += 1
            },
            exploreShareErrorMessage: { _ in
                "Couldn’t share to Explore\nTry again."
            }
        )
    }
}
