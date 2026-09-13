import SwiftData
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testRefinementThreeItemQueueReplayMatchesForegroundProjection() async throws {
        enableUnlimitedFreeScansForTest()
        defer { restoreFreeScanLimitForTest() }
        let queue = OfflineQueueManager.shared
        let originalContext = queue.modelContext
        let originalOnline = queue.isOnline
        let context = try makeModelContext()
        queue.modelContext = context
        queue.isOnline = false
        defer {
            cleanupQueuedScans(in: context)
            queue.modelContext = originalContext
            queue.isOnline = originalOnline
        }

        for addsAudio in [false, true] {
            let viewModel = CaptureWorkspaceViewModel(
                diContainer: .preview,
                preparedImageLoader: { _ in nil },
                prewarmHeadersOnInit: false
            )
            let original = LocalScanRecord(
                speciesId: "refinement-replay", scientificName: "Strix varia", commonName: "Barred Owl"
            )
            viewModel.baseRefinementContext = RefinementScanContext(record: original)
            viewModel.commitPreparedStagedImages([makePreparedStagedImage()])
            if addsAudio {
                let audioFile = try makeTempAudioFilename(prefix: "refinement-replay")
                viewModel.stagedCapture.audios.append(StagedAudio(filePath: audioFile))
            } else {
                viewModel.commitPreparedStagedImages([makePreparedStagedImage()])
            }
            var draft = ObservationContext(freeText: "Compare this additional evidence")
            XCTAssertTrue(viewModel.prepareActiveStagedSubmission(descriptionDraft: &draft))
            let payload = CaptureSubmissionPayload(nodes: viewModel.stagedCapture.orderedNodes)
            let foregroundProjection = payload.mediaTimeline.submissionMediaProjection
            XCTAssertEqual(viewModel.baseRefinementContext?.scanId, original.id)

            await viewModel.submitStagedCapture(modelContext: context)
            try await waitUntil {
                viewModel.offlineToastMessage?.title == "No network connection. Scan queued for later."
            }
            let queuedScans = try context.fetch(FetchDescriptor<OfflineQueuedScan>())
            XCTAssertEqual(queuedScans.count, 1)
            let queued = try XCTUnwrap(queuedScans.first)
            let replay = try queue.buildExtractedScanData(from: queued, container: context.container)
            XCTAssertEqual(queued.capturedMediaSnapshot.items.count, 3)
            XCTAssertEqual(replay.capturedMediaSnapshot.observationContexts,
                           foregroundProjection.observationContexts)
            XCTAssertEqual(replay.ownerMediaTimeline, foregroundProjection.ownerMediaTimeline)
            XCTAssertEqual(replay.audioMediaItems ?? [], foregroundProjection.audioMediaItems)
            let contextsJSON = try foregroundProjection.observationContexts.map {
                String(decoding: try JSONEncoder().encode($0), as: UTF8.self)
            }
            let body = try MerianNetworkClient.buildMultiModalRequestBody(
                base64ImageDatas: payload.inferenceImages.map { $0.compressedData.base64EncodedString() },
                audioBase64s: addsAudio ? [makeInferenceTestPCM16WAVData().base64EncodedString()] : [],
                visualMediaItems: payload.visualMediaItems,
                audioMediaItems: foregroundProjection.audioMediaItems,
                ownerMediaTimeline: foregroundProjection.ownerMediaTimeline,
                observationContextsJSON: contextsJSON,
                userId: Self.entitlementTestUserID.uuidString,
                mimeType: "image/png",
                telemetry: replay.telemetry,
                deviceLocale: "en",
                deviceTimeZone: "UTC",
                deviceRegion: nil,
                currentMonth: 9,
                timeOfDay: "12:00 PM",
                depthScaleText: nil,
                clientScanId: queued.id
            )
            let bodyJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let timelineJSON = try XCTUnwrap(bodyJSON["ownerMediaTimeline"] as? [[String: Any]])
            XCTAssertEqual(timelineJSON.count, 3)
            XCTAssertEqual(timelineJSON.compactMap { $0["kind"] as? String },
                           ["image", addsAudio ? "audio" : "image", "description"])
            XCTAssertEqual(timelineJSON[0]["sourceIndex"] as? Int, 0)
            XCTAssertEqual(timelineJSON[1]["sourceIndex"] as? Int, addsAudio ? 0 : 1)
            if addsAudio {
                XCTAssertEqual(timelineJSON[1]["audioInputIndex"] as? Int, 0)
            }
            XCTAssertEqual(timelineJSON[2]["contextIndex"] as? Int, 0)
            XCTAssertEqual(bodyJSON["observation_contexts"] as? [[String: String]],
                           [["freeText": "Compare this additional evidence"]])
            XCTAssertEqual((bodyJSON["imageBase64s"] as? [String])?.count, addsAudio ? 1 : 2)
            XCTAssertEqual((bodyJSON["audioBase64s"] as? [String])?.count ?? 0, addsAudio ? 1 : 0)
            XCTAssertFalse(queued.capturedMediaJSON?.contains("isRefinementSupplement") ?? true)
            XCTAssertTrue(viewModel.stagedCapture.isEmpty)
            cleanupQueuedScans(in: context)
        }
    }
}
