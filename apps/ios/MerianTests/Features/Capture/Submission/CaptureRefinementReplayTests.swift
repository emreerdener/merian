import SwiftData
import XCTest

@testable import Merian

extension CaptureWorkspaceViewModelRefinementTests {
    func testEnrollmentBeforeOrDuringAdmissionPreservesLegacyDraftWithoutEnqueue() async throws {
        let queue = OfflineQueueManager.shared, previous = OfflineQueueManager.shared.modelContext
        let wasOnline = queue.isOnline
        defer { queue.modelContext = previous; queue.isOnline = wasOnline; ScanAdmissionManager.shared.resetForTesting() }
        queue.isOnline = true
        for visual in [false, true] {
            for before in [false, true] {
                let context = try makeModelContext()
                queue.modelContext = context
                let original = LocalScanRecord(speciesId: "refinement-fence", scientificName: "Danaus plexippus", commonName: "Monarch")
                context.insert(original); try context.save()
                let vm = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
                vm.baseRefinementContext = RefinementScanContext(record: original)
                let note = ObservationContext(freeText: "Additional evidence")
                vm.stagedCapture.observationContexts = [StagedObservationContext(context: note)]
                if visual { vm.commitPreparedStagedImages([makePreparedStagedImage()]) }
                let nodes = vm.stagedCapture.orderedNodes.map(\.id)
                let protect = {
                    _ = try ObservationHistoryEnrollmentIntent.stage(observationID: XCTUnwrap(UUID(uuidString: original.id)), ownerID: UUID(), context: context)
                    try context.save()
                }
                if before { try protect() }
                var previews = 0
                ScanAdmissionManager.shared.overridingPreview = { _ in
                    previews += 1
                    do { try protect() } catch { XCTFail("Unable to stage enrollment") }
                    return ScanAdmissionPreview(decision: .allowed, effectivePlan: "pro_paid", dailyLimit: nil, dailyRemaining: nil)
                }
                if visual {
                    await vm.submitStagedCapture(modelContext: context)
                } else {
                    let accepted = await vm.submitNonVisualCapture(audioFileNames: [], observationContexts: [note],
                        mediaTimeline: [.description(note)], modelContext: context, targetEradicationScanId: original.id)
                    XCTAssertFalse(accepted)
                }
                XCTAssertEqual(previews, before ? 0 : 1)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()), 0)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<LocalScanRecord>()), 1)
                XCTAssertEqual(vm.stagedCapture.orderedNodes.map(\.id), nodes)
                XCTAssertEqual(vm.baseRefinementContext?.scanId, original.id)
                XCTAssertNil(vm.pendingAnalyzeScanId)
            }
        }
    }

    func testNonvisualAdmissionCannotOutliveCanceledOrChangedRefinementTarget() async throws {
        let queue = OfflineQueueManager.shared, previous = OfflineQueueManager.shared.modelContext
        let wasOnline = queue.isOnline
        defer { queue.modelContext = previous; queue.isOnline = wasOnline; ScanAdmissionManager.shared.resetForTesting() }
        queue.isOnline = true
        for replace in [false, true] {
            let context = try makeModelContext()
            queue.modelContext = context
            let original = LocalScanRecord(speciesId: "refinement-fence", scientificName: "Danaus plexippus", commonName: "Monarch")
            context.insert(original); try context.save()
            let vm = CaptureWorkspaceViewModel(diContainer: .preview, preparedImageLoader: { _ in nil }, prewarmHeadersOnInit: false)
            vm.baseRefinementContext = RefinementScanContext(record: original)
            let note = ObservationContext(freeText: "Additional evidence")
            vm.stagedCapture.observationContexts = [StagedObservationContext(context: note)]
            let nodes = vm.stagedCapture.orderedNodes.map(\.id)
            var previews = 0
            ScanAdmissionManager.shared.overridingPreview = { _ in
                previews += 1
                vm.cancelRefinementStaging()
                if replace {
                    vm.baseRefinementContext = RefinementScanContext(record: LocalScanRecord(
                        speciesId: "different-source", scientificName: "Strix varia", commonName: "Barred Owl"))
                }
                return ScanAdmissionPreview(decision: .allowed, effectivePlan: "pro_paid", dailyLimit: nil, dailyRemaining: nil)
            }
            let accepted = await vm.submitNonVisualCapture(audioFileNames: [], observationContexts: [note],
                mediaTimeline: [.description(note)], modelContext: context, targetEradicationScanId: original.id)
            XCTAssertFalse(accepted)
            XCTAssertEqual(previews, 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()), 0)
            XCTAssertEqual(vm.stagedCapture.orderedNodes.map(\.id), nodes)
            XCTAssertNil(vm.pendingAnalyzeScanId)
        }
    }

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
            context.insert(original)
            try context.save()
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
