import Foundation
@testable import Merian
import SwiftData
import Testing
import UIKit

@MainActor
extension CaptureTerminalAcceptanceTests {
    enum TerminalMediaKind { case photo, audio, video }

    func initialMediaRetainsSubmittedBytesAndTextThroughCompletion(withText: Bool, kind: TerminalMediaKind) async throws {
        let video = kind == .video, photo = kind == .photo
        let manager = OfflineQueueManager.shared
        let oldAdmission = manager.captureLibraryAdmission
        let oldContext = manager.modelContext
        let oldOnline = manager.isOnline
        let oldCount = manager.unsyncedItemsCount
        let oldSubscription = RevenueCatManager.shared.isSubscribed
        let oldQuota = UsageManager.debugFreeScanLimitOverride
        manager.captureLibraryAdmission = { _ in true }
        UsageManager.debugFreeScanLimitOverride = true
        let ownerID = UUID()
        EntitlementManager.shared.resetForTesting(userID: ownerID)
        RevenueCatManager.shared.isSubscribed = true
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let outcome = ModelContainerBootstrapper.fixtureBootstrap {
            try PersistentStoreBootstrapSession.fixture(schema: schema,
                storeURL: root.appendingPathComponent("audio.sqlite"), anchor: root)
        }
        let container = try #require(outcome.container), startup = try #require(outcome.nativeReleaseAdmission)
        let context = ModelContext(container)
        manager.modelContext = context
        manager.isOnline = false
        let generation = UUID()
        var admittedScanID: String?
        var adoptedPaths: [String] = []
        var videoFixture: VideoAudioFixture?
        var preparedPlayback: URL?
        defer {
            if let id = admittedScanID {
                manager.inferenceStatusProbeTasks.cancel(id)
                manager.inferenceRetryTasks.cancel(id)
                manager.serverIngestionPollTasks.cancel(id)
                manager.foregroundInferenceRetirementTasks.cancel(id)
                manager.activeInferenceGenerations[id] = nil
                manager.inferenceCompletionGenerations[id] = nil
                manager.inferenceDispatchDates[id] = nil
                manager.deferredLiveUploadScanIds.remove(id)
            }
            manager.retiredInferenceGenerations.remove(generation)
            manager.captureLibraryAdmission = oldAdmission
            manager.modelContext = oldContext
            manager.isOnline = oldOnline
            manager.unsyncedItemsCount = oldCount
            RevenueCatManager.shared.isSubscribed = oldSubscription
            UsageManager.debugFreeScanLimitOverride = oldQuota
            EntitlementManager.shared.resetForTesting()
            SyncStateManager.shared.forceIdle()
            for path in adoptedPaths {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(path))
            }
            try? FileManager.default.removeItem(at: root.appendingPathComponent("source.wav"))
            videoFixture?.remove()
            if let preparedPlayback { try? FileManager.default.removeItem(at: preparedPlayback) }
            // Core Data can retain SQLite/WAL handles beyond ModelContainer scope.
            // Keep the unique store until test-process exit, as migration fixtures do.
        }
        let di = AppDIContainer.preview
        let workspace = makeWorkspace(di: di)
        defer { workspace.preFetchTask?.cancel(); di.inferenceEngine.cancelActiveRequest() }
        let input = root.appendingPathComponent("source.wav")
        var bytes = makeInferenceTestPCM16WAVData(sampleRate: 44_100, frameCount: 128, sampleAt: { Int16($0) })
        let note = ObservationContext(freeText: "  Calling e\u{301} 🐾\n")
        var frameBytes: [Data] = [], playbackBytes: Data?
        let accepted: Bool
        if photo {
            let image = try #require(UIImage(data: ObservationReanalysisProducerTests().image()))
            bytes = try #require(image.jpegData(compressionQuality: 0.8))
            workspace.stagedCapture.images = [StagedImage(compressedData: bytes, displayData: bytes,
                uiImage: image, original: IdentifiableImage(image: image))]
            if withText { workspace.stagedCapture.observationContexts = [.init(context: note, addedAt: .distantPast)] }
            await workspace.submitStagedCapture(modelContext: context)
            for _ in 0..<500 where workspace.offlineToastMessage == nil { try await Task.sleep(for: .milliseconds(10)) }
            accepted = workspace.offlineToastMessage != nil
            #expect(workspace.stagedCapture.images.isEmpty)
        } else if video {
            let fixture = try await VideoAudioFixture(channels: 1)
            videoFixture = fixture
            let prepared = try await CaptureScanVideoMediaPreparer.prepare(.init(videoURL: fixture.videoURL,
                duration: 1, composingCenter: 0.5, isProActive: true))
            preparedPlayback = prepared.playback.fileURL
            let audio = try #require(prepared.audioFilePath)
            adoptedPaths.append(audio)
            bytes = try Data(contentsOf: URL.documentsDirectory.appendingPathComponent(audio))
            playbackBytes = try Data(contentsOf: prepared.playback.fileURL)
            frameBytes = prepared.sampledFrames.map(\.inferenceData)
            try #require(frameBytes.count == 5)
            workspace.stagedCapture.videos = [CaptureWorkspaceViewModel.makeStagedVideo(prepared)]
            if withText {
                workspace.stagedCapture.observationContexts = [.init(context: note, addedAt: .distantPast)]
            }
            await workspace.submitStagedCapture(modelContext: context)
            for _ in 0..<500 where workspace.offlineToastMessage == nil {
                try await Task.sleep(for: .milliseconds(10))
            }
            accepted = workspace.offlineToastMessage != nil
            #expect(workspace.stagedCapture.videos.isEmpty)
        } else {
            try bytes.write(to: input)
            if withText {
                accepted = await workspace.submitNonVisualCapture(audioFileNames: [input.path], observationContexts: [note],
                    mediaTimeline: [.description(note), .audio(input.path)], modelContext: context)
            } else {
                accepted = await workspace.submitAudio(audioFileName: input.path, modelContext: context)
            }
        }
        try #require(accepted)
        #expect(!di.inferenceEngine.isProcessing)
        let queued = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let id = queued.id
        admittedScanID = id
        let route = queued.queuedScanContext()
        let submittedItems = queued.serializedCapturedMediaItems
        let snapshot = try manager.extractedQueuedScanData(scanId: id)
        let extracted = try #require(snapshot)
        let audioPaths = extracted.audioFilePaths ?? []
        adoptedPaths += extracted.localUploadPaths
        adoptedPaths += extracted.capturedMediaSnapshot.thumbnailImagePaths
        try #require(photo ? extracted.localImagePaths.count == 1 : audioPaths.count == 1)
        if photo {
            #expect(try Data(contentsOf: URL.documentsDirectory.appendingPathComponent(extracted.localImagePaths[0])) == bytes)
        }
        let durablePhoto = photo ? try #require(extracted.capturedMediaSnapshot.thumbnailImagePaths.first) : ""
        let savedURL = URL.documentsDirectory.appendingPathComponent(photo ? durablePhoto : audioPaths[0])
        let retainedPaths = extracted.capturedMediaSnapshot.thumbnailImagePaths + audioPaths + (extracted.videoFilePaths ?? [])
        let retainedBytes = try retainedPaths.map { try Data(contentsOf: URL.documentsDirectory.appendingPathComponent($0)) }
        if video {
            let playback = try #require(extracted.videoFilePaths?.first)
            #expect(try Data(contentsOf: URL.documentsDirectory.appendingPathComponent(playback)) == playbackBytes)
            #expect(extracted.visualMediaItems == (0..<5).map { .videoFrame(clipIndex: 0, frameIndex: $0) })
            #expect(try extracted.localImagePaths.map { try Data(contentsOf: URL.documentsDirectory.appendingPathComponent($0)) } == frameBytes)
            // The queue owns its adopted playback; a changed caller clip cannot replace it.
            try Data("later caller video".utf8).write(to: #require(videoFixture).videoURL)
            #expect(try Data(contentsOf: URL.documentsDirectory.appendingPathComponent(playback)) == playbackBytes)
        }
        #expect(savedURL.standardizedFileURL != input.standardizedFileURL)
        #expect(try Data(contentsOf: savedURL) == bytes)
        #expect(extracted.capturedMediaItems.count == (withText ? 2 : 1))
        if withText { #expect(extracted.capturedMediaItems.first == .description(note)) }
        #expect((extracted.audioMediaItems ?? []) == (photo ? [] : [video ? .videoAudio(clipIndex: 0) : .audio(sourceIndex: 0)]))
        // The original recording may already have been removed by submitAudio.
        // A later caller-side recording cannot replace the queue-owned input.
        try Data("later recording".utf8).write(to: input)
        #expect(try Data(contentsOf: savedURL) == bytes)
        queued.queueState = .inferencing
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.status = .running
        job.metadataJSON = InferenceGenerationMetadataContract.setting(generation, in: job.metadataJSON)
        try context.save()
        manager.activeInferenceGenerations[id] = generation
        let originalOwnership = BackgroundAccountWorkOwnership(ownerUserID: ownerID, generation: generation, phase: .inference)
        let activated = await BackgroundDatabaseActor(modelContainer: container).activateBackgroundAccountWork(
            scanId: id, ownership: originalOwnership)
        try #require(activated)
        let runtime = AuthRuntimeState()
        let session = AuthTransitionSession(userID: ownerID, isAnonymous: false)
        var leasesAcquired = 0, leasesReleased = 0
        let accountWork = BackgroundAccountWorkLeaseBoundary(
            begin: { owner in
                guard owner == ownerID, runtime.transitionAllows(nil) else { throw CancellationError() }
                leasesAcquired += 1
                return runtime.beginAccountWork(session: session)
            },
            isCurrent: { runtime.accountWorkLeaseIsCurrent($0, publishedSession: session, sdkSession: session) },
            finish: { leasesReleased += 1; runtime.finishAccountWork($0) })
        let response = Data("""
        {"success":true,"data":{"scan_id":"\(id)","is_biological_subject":true,
        "is_live_capture":true,"ecology_type":"wild","is_invasive":false,
        "scientific_name":"Synthetic audio species","common_name":"Synthetic audio",
        "confidence_score":0.75,"insight_data":{"hazard_type":"none","ai_reasoning":"Synthetic audio result."}}}
        """.utf8)
        let resultURL = root.appendingPathComponent("result.json")
        try response.write(to: resultURL)
        var publications = 0
        await manager.processInferenceTerminalResult(scanId: id, generation: generation,
            ownerUserID: ownerID, taskIdentifier: 89201,
            resultFileURL: resultURL, statusCode: 200, functionRouteEvidence: nil,
            accountWork: accountWork, publishCompletion: { scanID, result, saved in
                publications += 1
                #expect(scanID == id && result.finalScanId == id)
                #expect(saved.capturedMediaItems == submittedItems)
            })
        try #require(publications == 1)
        let fresh = ModelContext(container)
        let record = try #require(fresh.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try fresh.fetch(FetchDescriptor<OfflineJobRecord>()).first?.status == .complete)
        #expect(record.id == id)
        #expect(CapturedMediaSnapshot(jsonString: record.capturedMediaJSON).items == submittedItems)
        #expect(record.aiReasoning == "Synthetic audio result.")
        #expect(try Data(contentsOf: savedURL) == bytes)
        let insight = InsightSheetViewModel(inferenceEngine: di.inferenceEngine)
        insight.beginPresentationSession()
        #expect(insight.bindQueuedPresentationPreferringCompletedRecord(route, modelContext: fresh,
            inferenceEngine: di.inferenceEngine))
        #expect(insight.presentedLocalRecordScanId == id)
        insight.endPresentationSession()
        #expect(leasesAcquired == 1 && leasesReleased == 1)
        #expect(try OrdinaryInferenceCompletion.retained(for: record, owner: ownerID, context: fresh) != nil)
        let baselineID = try await enrollCompletedMedia(record: record, ownerID: ownerID,
            container: container, savedURL: savedURL, bytes: bytes, submittedItems: submittedItems, kind: kind, startup: startup)
        try response.write(to: resultURL)
        await manager.processInferenceTerminalResult(scanId: id, generation: generation,
            ownerUserID: ownerID, taskIdentifier: 89201,
            resultFileURL: resultURL, statusCode: 200, functionRouteEvidence: nil,
            accountWork: accountWork, publishCompletion: { _, _, _ in publications += 1 })
        #expect(publications == 1)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        #expect(try Data(contentsOf: savedURL) == bytes)
        let afterReplay = ModelContext(container)
        let enrolled = try #require(afterReplay.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(enrolled.selectedAnalysisID == baselineID.uuidString.lowercased())
        #expect(try afterReplay.fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 2)
        #expect(CapturedMediaSnapshot(jsonString: enrolled.capturedMediaJSON).items == submittedItems)
        #expect(try retainedPaths.map { try Data(contentsOf: URL.documentsDirectory.appendingPathComponent($0)) } == retainedBytes)
    }

    func enrollCompletedMedia(record: LocalScanRecord, ownerID: UUID, container: ModelContainer,
                                      savedURL: URL, bytes: Data, submittedItems: [SerializedMediaItem], kind: TerminalMediaKind,
                                      startup: NativeReleaseStartupAdmission) async throws -> UUID {
        let observation = try #require(UUID(uuidString: record.id))
        let baselineID = UUID()
        var state = try ObservationHistoryStateTests().fixture()
        state["owner_id"] = ownerID.uuidString.lowercased()
        state["observation_id"] = record.id
        state["selected_analysis_id"] = baselineID.uuidString.lowercased()
        var analysis = try #require(state["analysis"] as? [String: Any])
        let template = try #require(analysis["snapshot"] as? String)
        var snapshot = try #require(JSONSerialization.jsonObject(with: Data(template.utf8)) as? [String: Any])
        snapshot["analysis_id"] = baselineID.uuidString.lowercased()
        snapshot["observation_id"] = record.id
        var result = try #require(snapshot["result"] as? [String: Any])
        result["scan_id"] = record.id
        result["species_id"] = record.speciesId.lowercased()
        result["ai_reasoning"] = "Synthetic audio result."
        result["inference_tier"] = record.inferenceTier as Any? ?? NSNull()
        result["candidates"] = NSNull()
        snapshot["result"] = result
        // Synthetic server baseline bound to the completed fixture's observation.
        // Its V3 evidence declares original provider/media evidence unavailable.
        let snapshotBytes = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        analysis["snapshot"] = String(decoding: snapshotBytes, as: UTF8.self)
        state["analysis"] = analysis
        let stateBytes = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        let receipt = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "owner_id": ownerID.uuidString.lowercased(), "observation_id": record.id,
            "baseline_analysis_id": baselineID.uuidString.lowercased()] as [String: Any], options: [.sortedKeys])
        var enrollments = 0, reads = 0
        var cloud = ObservationHistoryCloudClient(begin: { expected in
            #expect(expected == ownerID)
            return AccountBoundWorkLease(id: UUID(), session: .init(userID: ownerID, isAnonymous: false))
        }, isCurrent: { _ in true }, finish: { _ in }, fetch: { _ in throw ObservationHistoryError.unavailable })
        cloud.enroll = { id in
            #expect(id == observation)
            enrollments += 1
            // The synthetic server has retained the baseline, but its first reply is lost.
            if enrollments == 1 { throw URLError(.networkConnectionLost) }
            return receipt
        }
        cloud.fetchState = { request in
            #expect(request.observation_id == observation.uuidString.lowercased())
            reads += 1
            if reads == 1 { throw URLError(.networkConnectionLost) }
            return stateBytes
        }
        let service = ObservationHistoryEnrollmentService(cloud: cloud)
        await #expect(throws: URLError.self) {
            try await service.enroll(observationID: record.id, expectedOwnerID: ownerID, container: container)
        }
        // A second attempt receives the same enrollment receipt, then loses the state read.
        await #expect(throws: URLError.self) {
            try await service.enroll(observationID: record.id, expectedOwnerID: ownerID, container: container)
        }
        #expect(try ObservationHistoryEnrollmentIntent.holds(record.id, context: ModelContext(container)))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalAnalysisRecord>()) == 0)
        #expect(try Data(contentsOf: savedURL) == bytes)
        let displayed = try ObservationHistoryEnrollmentService.baseline(observation: observation, container: container)
        let access = SavedIdentificationReanalysisAccess.prepared(cloud: cloud, enrollment: ObservationHistoryEnrollmentOwner(),
            currentOwner: { ownerID }, generation: { 1 }, sessionIsCurrent: { $0.userID == ownerID },
            containerIsCurrent: { $0 === container }, dispatch: { _ in Issue.record("Preparation cannot dispatch") })
        let request = try access.prepare(record.id, displayed, container)
        let action = try await request.resolve()
        let target = try action.resolve()
        #expect(target.analysisID == baselineID)
        #expect(enrollments == 3 && reads == 2)
        let fresh = ModelContext(container)
        let retained = try #require(fresh.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let baseline = try #require(fresh.fetch(FetchDescriptor<LocalAnalysisRecord>()).first)
        #expect(retained.selectedAnalysisID == baselineID.uuidString.lowercased())
        #expect(baseline.resultSnapshotData == snapshotBytes && baseline.snapshotVersion == 3)
        let association = try ObservationHistoryEnrollmentIntent.baseline(observationID: observation,
            ownerID: ownerID, context: fresh)
        #expect(association?.baselineAnalysisID == baselineID)
        #expect(association?.snapshotSHA256 == ObservationHistoryEnrollmentIntent.baselineDigest(snapshotBytes))
        #expect(CapturedMediaSnapshot(jsonString: retained.capturedMediaJSON).items == submittedItems)
        #expect(try Data(contentsOf: savedURL) == bytes)
        let source: ObservationReanalysisSource
        switch kind {
        case .photo: source = try .capture(observationID: observation, analysisID: baselineID, ownerID: ownerID, container: container)
        case .audio: source = try .captureForAudio(observationID: observation, analysisID: baselineID, ownerID: ownerID, container: container)
        case .video: source = try .captureForVideo(observationID: observation, analysisID: baselineID, ownerID: ownerID, container: container)
        }
        #expect(source.snapshot == snapshotBytes && source.audio == nil)
        let preview = try await ObservationHistoryPreviewService(cloud: cloud).preview(observationID: retained.id,
            analysisID: baselineID, container: container)
        #expect(preview.isSelected && preview.displayOrigin == .savedLocalProjection)
        if kind == .video {
            try await recoverVideoChild(source: source, container: container, cloud: cloud, withText: submittedItems.count > 1, startup: startup)
        } else if kind == .photo {
            try await recoverPhotoChild(source: source, container: container, cloud: cloud,
                baselineState: state, withText: submittedItems.count > 1)
        } else {
            try await recoverAudioChild(source: source, container: container, cloud: cloud,
                baselineState: state, withText: submittedItems.count > 1)
        }
        #expect(try Data(contentsOf: savedURL) == bytes)
        #expect(CapturedMediaSnapshot(jsonString: retained.capturedMediaJSON).items == submittedItems)
        return baselineID
    }

}
