import SwiftData
import XCTest

@testable import Merian

@MainActor
final class NonBiologicalScansViewModelTests: XCTestCase {
    func testPresentationCopyAndCorrectionRouteRemainStable() {
        XCTAssertEqual(
            NonBiologicalScansPresentation.navigationTitle,
            "Non-biological"
        )
        XCTAssertEqual(
            NonBiologicalScansPresentation.emptyIconName,
            "photo.on.rectangle.angled"
        )
        XCTAssertEqual(NonBiologicalScansPresentation.emptyTitle, "Empty")
        XCTAssertEqual(
            NonBiologicalScansPresentation.emptyMessage,
            "This collection is currently empty. " +
                "Non-biological items are automatically purged here after 30 days."
        )
        XCTAssertEqual(
            NonBiologicalScansPresentation.retentionMessage,
            "Items in this collection are permanently deleted after 30 days " +
                "to free up space."
        )
        XCTAssertEqual(
            NonBiologicalScansPresentation.reanalysisAction,
            "Reanalyze as biological"
        )
        XCTAssertEqual(
            NonBiologicalScansPresentation.clearingProgress,
            "Clearing scans..."
        )
        XCTAssertEqual(
            NonBiologicalScansPresentation.deleteAllAction,
            "Delete all"
        )
        XCTAssertEqual(NonBiologicalScansPresentation.cancelAction, "Cancel")
        XCTAssertEqual(
            NonBiologicalScansPresentation.deleteAllMessage,
            "This action cannot be undone."
        )
        XCTAssertEqual(
            NonBiologicalScansPresentation.singleDeleteSuccess,
            "Scan deleted"
        )
        XCTAssertEqual(
            NonBiologicalScansPresentation.clearSuccess,
            "Scans cleared"
        )
        XCTAssertEqual(
            NonBiologicalScansPresentation.clearFailure,
            "Couldn't clear scans"
        )
        XCTAssertEqual(
            NonBiologicalScansPresentation.reanalysisStarted,
            "Reanalysis started"
        )
        XCTAssertEqual(
            NonBiologicalCorrectionReanalysis.confirmationTitle,
            "Reanalyze identification?"
        )
        XCTAssertEqual(
            NonBiologicalCorrectionReanalysis.confirmationMessage,
            "This identification was marked as non-biological. " +
                "Reanalysis will look for a biological subject using the original capture."
        )
        XCTAssertEqual(
            NonBiologicalCorrectionReanalysis.primaryAction,
            "Reanalyze"
        )
        XCTAssertEqual(
            NonBiologicalCorrectionReanalysis.secondaryAction,
            "Cancel"
        )

        let scanID = UUID().uuidString
        let route = NonBiologicalCorrectionReanalysis.refinementRoute(
            scanId: scanID
        )
        guard case let .refinement(
            routedScanID,
            initialDescription,
            entryPoint
        ) = route else {
            XCTFail("Correction should request a refinement route")
            return
        }

        XCTAssertEqual(routedScanID, scanID)
        XCTAssertNil(initialDescription)
        XCTAssertEqual(entryPoint, .nonBiologicalCorrection)
    }

    func testRefreshFiltersFromShellOwnedOrderAndTracksEligibilityChanges() {
        let newestNonBiological = makeRecord(
            id: "newest-non-biological",
            timestamp: Date(timeIntervalSinceReferenceDate: 30),
            isBiological: false
        )
        let biological = makeRecord(
            id: "biological",
            timestamp: Date(timeIntervalSinceReferenceDate: 20),
            isBiological: true
        )
        let oldestNonBiological = makeRecord(
            id: "oldest-non-biological",
            timestamp: Date(timeIntervalSinceReferenceDate: 10),
            isBiological: false
        )
        let source = [
            newestNonBiological,
            biological,
            oldestNonBiological
        ]
        let viewModel = NonBiologicalScansViewModel(
            scans: source,
            dependencies: NonBiologicalDependencies()
        )

        XCTAssertEqual(
            viewModel.scans.map(\.id),
            [newestNonBiological.id, oldestNonBiological.id]
        )
        XCTAssertEqual(
            viewModel.clearAllConfirmationTitle,
            "Delete 2 non-biological scans?"
        )

        let before = viewModel.refreshIdentity(scans: source)
        oldestNonBiological.isBiological = true
        let after = viewModel.refreshIdentity(scans: source)
        viewModel.refresh(scans: source)

        XCTAssertNotEqual(before, after)
        XCTAssertEqual(viewModel.scans.map(\.id), [newestNonBiological.id])
    }

    func testErasureSnapshotCapturesEveryMediaKindInStableOrder() {
        let media = CapturedMediaSnapshot(items: [
            .image(.documents("image.webp")),
            .image(.remoteURL("https://media.example/image.webp")),
            .audio(.documents("audio.wav")),
            .video(StoredVideoMediaReference(.documents("video.mp4")))
        ])
        let scan = makeRecord(
            id: "mixed-media",
            timestamp: Date(timeIntervalSinceReferenceDate: 1),
            isBiological: false,
            capturedMediaJSON: media.jsonString
        )

        let snapshot = NonBiologicalScanErasureSnapshot(scan: scan)

        XCTAssertEqual(snapshot.id, scan.id)
        XCTAssertEqual(
            snapshot.mediaPaths,
            [
                "image.webp",
                "https://media.example/image.webp",
                "audio.wav",
                "video.mp4"
            ]
        )
    }

    func testClearAllCommitsFilesThenPublishesFeedbackAndSync() async throws {
        let container = try makeContainer()
        let recorder = NonBiologicalEffectsRecorder()
        let scan = makeRecord(
            id: "delete-me",
            timestamp: Date(timeIntervalSinceReferenceDate: 1),
            isBiological: false,
            capturedMediaJSON: CapturedMediaSnapshot(items: [
                .image(.documents("delete-me.webp"))
            ]).jsonString
        )
        let viewModel = NonBiologicalScansViewModel(
            scans: [scan],
            dependencies: NonBiologicalDependencies(
                deleteRecords: { snapshots, _ in
                    recorder.effects.append("database")
                    recorder.snapshots = snapshots
                    return ["delete-me.webp"]
                },
                deleteFiles: { paths in
                    recorder.effects.append("files")
                    recorder.deletedPaths = paths
                },
                sendLibraryChanged: {
                    recorder.effects.append("event")
                },
                enqueueDeletionSync: {
                    recorder.effects.append("sync")
                },
                triggerSuccessFeedback: {
                    recorder.effects.append("success")
                },
                triggerErrorFeedback: {
                    recorder.effects.append("error")
                }
            )
        )

        let didDelete = await viewModel.clearAll(in: container)

        XCTAssertTrue(didDelete)
        XCTAssertFalse(viewModel.isClearingAll)
        XCTAssertEqual(recorder.snapshots.map(\.id), [scan.id])
        XCTAssertEqual(
            recorder.snapshots.first?.mediaPaths,
            ["delete-me.webp"]
        )
        XCTAssertEqual(recorder.deletedPaths, ["delete-me.webp"])
        XCTAssertEqual(
            recorder.effects,
            ["database", "files", "event", "success", "sync"]
        )
        XCTAssertEqual(viewModel.toastMessage?.title, "Scans cleared")
        XCTAssertEqual(viewModel.toastMessage?.severity, .success)
    }

    func testClearAllFailureRestoresInteractionAndSuppressesCommitEffects() async throws {
        let container = try makeContainer()
        let recorder = NonBiologicalEffectsRecorder()
        let scan = makeRecord(
            id: "keep-me",
            timestamp: Date(timeIntervalSinceReferenceDate: 1),
            isBiological: false
        )
        let viewModel = NonBiologicalScansViewModel(
            scans: [scan],
            dependencies: NonBiologicalDependencies(
                deleteRecords: { _, _ in
                    recorder.effects.append("database")
                    throw NonBiologicalExpectedError.deleteFailed
                },
                deleteFiles: { _ in
                    recorder.effects.append("files")
                },
                sendLibraryChanged: {
                    recorder.effects.append("event")
                },
                enqueueDeletionSync: {
                    recorder.effects.append("sync")
                },
                triggerSuccessFeedback: {
                    recorder.effects.append("success")
                },
                triggerErrorFeedback: {
                    recorder.effects.append("error")
                }
            )
        )

        let didDelete = await viewModel.clearAll(in: container)

        XCTAssertFalse(didDelete)
        XCTAssertFalse(viewModel.isClearingAll)
        XCTAssertEqual(recorder.effects, ["database", "error"])
        XCTAssertEqual(viewModel.toastMessage?.title, "Couldn't clear scans")
        XCTAssertEqual(viewModel.toastMessage?.severity, .error)
    }

    func testOverlappingClearAllKeepsOneDeletionOwner() async throws {
        let container = try makeContainer()
        let gate = NonBiologicalDeletionGate()
        let recorder = NonBiologicalEffectsRecorder()
        let viewModel = NonBiologicalScansViewModel(
            scans: [
                makeRecord(
                    id: "single-owner",
                    timestamp: Date(timeIntervalSinceReferenceDate: 1),
                    isBiological: false
                )
            ],
            dependencies: NonBiologicalDependencies(
                deleteRecords: { _, _ in
                    recorder.effects.append("database")
                    return try await gate.wait()
                },
                deleteFiles: { _ in
                    recorder.effects.append("files")
                },
                sendLibraryChanged: {
                    recorder.effects.append("event")
                },
                enqueueDeletionSync: {
                    recorder.effects.append("sync")
                },
                triggerSuccessFeedback: {
                    recorder.effects.append("success")
                }
            )
        )

        let firstTask = Task {
            await viewModel.clearAll(in: container)
        }
        for _ in 0..<20 where !gate.didStart {
            await Task.yield()
        }
        XCTAssertTrue(gate.didStart)
        XCTAssertTrue(viewModel.isClearingAll)

        let overlappingResult = await viewModel.clearAll(in: container)
        XCTAssertFalse(overlappingResult)
        XCTAssertEqual(recorder.effects, ["database"])

        gate.succeed()
        let firstResult = await firstTask.value
        XCTAssertTrue(firstResult)
        XCTAssertEqual(
            recorder.effects,
            ["database", "files", "event", "success", "sync"]
        )
    }

    func testPurgeReanalysisAndSingleDeleteUseInjectedEffects() async throws {
        let container = try makeContainer()
        let recorder = NonBiologicalEffectsRecorder()
        let scanID = "reanalyze-me"
        let viewModel = NonBiologicalScansViewModel(
            dependencies: NonBiologicalDependencies(
                purgeExpired: { _ in
                    recorder.effects.append("purge")
                },
                requestRoute: { route in
                    recorder.route = route
                    recorder.effects.append("route")
                },
                triggerSelectionFeedback: {
                    recorder.effects.append("selection")
                }
            )
        )

        await viewModel.purgeExpired(in: container)
        viewModel.requestReanalysis(scanID: scanID)

        XCTAssertEqual(recorder.effects, ["purge", "route", "selection"])
        guard case let .refinement(
            routedScanID,
            initialDescription,
            entryPoint
        ) = recorder.route else {
            XCTFail("Reanalysis should use the typed refinement route")
            return
        }
        XCTAssertEqual(routedScanID, scanID)
        XCTAssertNil(initialDescription)
        XCTAssertEqual(entryPoint, .nonBiologicalCorrection)
        XCTAssertEqual(viewModel.toastMessage?.title, "Reanalysis started")
        XCTAssertEqual(viewModel.toastMessage?.severity, .information)

        viewModel.didDeleteSingleScan()
        XCTAssertEqual(viewModel.toastMessage?.title, "Scan deleted")
        XCTAssertEqual(viewModel.toastMessage?.severity, .success)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private func makeRecord(
        id: String,
        timestamp: Date,
        isBiological: Bool,
        capturedMediaJSON: String? = nil
    ) -> LocalScanRecord {
        LocalScanRecord(
            id: id,
            speciesId: "species-\(id)",
            scientificName: "Species \(id)",
            commonName: "Species \(id)",
            timestamp: timestamp,
            capturedMediaJSON: capturedMediaJSON,
            isBiological: isBiological
        )
    }
}

private enum NonBiologicalExpectedError: Error {
    case deleteFailed
}

@MainActor
private final class NonBiologicalEffectsRecorder {
    var effects: [String] = []
    var snapshots: [NonBiologicalScanErasureSnapshot] = []
    var deletedPaths: [String] = []
    var route: AppRoute?
}

@MainActor
private final class NonBiologicalDeletionGate {
    private var continuation: CheckedContinuation<[String], Error>?
    private(set) var didStart = false

    func wait() async throws -> [String] {
        didStart = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func succeed() {
        continuation?.resume(returning: [])
        continuation = nil
    }
}
