#if DEBUG
import CryptoKit
import Foundation
import SwiftData

/// Calls the ordinary submission and completion owners. Running state, account,
/// entitlement and the response are explicit test seams, not dispatch evidence.
@MainActor enum InitialMediaHistoryUISubmission {
    struct Witness: Codable {
        let media: String
        let withText: Bool
        let scan: String
        let owner: UUID
        let generation: UUID
        let baseline: UUID
        let submitted: [SerializedMediaItem]
        let timestamp: Date
        let retained: [String: String]
        let inferenceFrames: [String]
        let originalClip: String?
        let proof: OrdinaryInferenceCompletion.Proof
    }

    static func create(media: String, withText: Bool, root: URL, container: ModelContainer,
                       di: AppDIContainer, progress: (String) -> Void) async throws -> Witness {
        guard UITestSeedCoordinator.initialMediaHistoryEnabled else { throw MerianError.invalidResponse }
        progress("initial signed-out lifecycle completion")
        let auth = SupabaseManager.shared
        guard let lifecycle = AuthSessionLifecycleLiveProvider.liveProviderForUITesting,
              try await lifecycle.waitForInitialSignedOutForTesting(),
              auth.currentUser == nil, auth.client.auth.currentSession == nil else {
            throw MerianError.invalidResponse
        }
        try Task.checkCancellation()
        let manager = OfflineQueueManager.shared, entitlement = EntitlementManager.shared
        guard entitlement.activeAccountID == nil, !entitlement.isVerifiedForCurrentLaunch,
              entitlement.inFlightCount == 0, manager.activeInferenceGenerations.isEmpty else { throw MerianError.invalidResponse }
        let oldAdmission = manager.captureLibraryAdmission, oldContext = manager.modelContext
        let oldOnline = manager.isOnline, oldCount = manager.unsyncedItemsCount
        let oldSubscription = RevenueCatManager.shared.isSubscribed, oldQuota = UsageManager.debugFreeScanLimitOverride
        let owner = PublicationConsentUIFixture.owner, generation = UUID()
        let context = ModelContext(container)
        var admitted: String?
        defer {
            if let id = admitted {
                manager.activeInferenceGenerations[id] = nil; manager.inferenceCompletionGenerations[id] = nil
                manager.inferenceDispatchDates[id] = nil; manager.deferredLiveUploadScanIds.remove(id)
            }
            manager.retiredInferenceGenerations.remove(generation)
            manager.captureLibraryAdmission = oldAdmission; manager.modelContext = oldContext
            manager.isOnline = oldOnline; manager.unsyncedItemsCount = oldCount
            entitlement.resetForTesting()
            RevenueCatManager.shared.isSubscribed = oldSubscription; UsageManager.debugFreeScanLimitOverride = oldQuota
        }
        manager.captureLibraryAdmission = { _ in true }; manager.modelContext = context; manager.isOnline = false
        UsageManager.debugFreeScanLimitOverride = true; entitlement.resetForTesting(userID: owner)
        RevenueCatManager.shared.isSubscribed = true
        let workspace = InitialMediaHistoryUIInput.workspace(di)
        defer { workspace.preFetchTask?.cancel(); di.inferenceEngine.cancelActiveRequest() }
        let beforeGeneration = seamFacts(context: context, owner: owner)
        let note = InitialMediaHistoryUIInput.note
        var frameHashes: [String] = [], originalClip: String?, expectedPlayback: String?
        var expectedPhotoDisplay: String?
        let expectedAudio: String?
        if media == "photo" {
            let image = try InitialMediaHistoryUIInput.photo()
            expectedAudio = nil
            frameHashes = [digest(image.compressedData)]
            expectedPhotoDisplay = digest(image.displayData)
            workspace.stagedCapture.images = [image]
            if withText { workspace.stagedCapture.observationContexts = [.init(context: note, addedAt: .distantPast)] }
            await workspace.submitStagedCapture(modelContext: context)
            let deadline = ContinuousClock.now + .seconds(15)
            while workspace.offlineToastMessage == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            guard workspace.offlineToastMessage != nil, workspace.stagedCapture.images.isEmpty else { throw MerianError.invalidResponse }
        } else if media == "audio" {
            let input = try await InitialMediaHistoryUIInput.audio(in: root)
            expectedAudio = try digest(Data(contentsOf: input))
            let accepted: Bool
            if withText {
                accepted = await workspace.submitNonVisualCapture(audioFileNames: [input.path], observationContexts: [note],
                    mediaTimeline: [.description(note), .audio(input.path)], modelContext: context)
            } else { accepted = await workspace.submitAudio(audioFileName: input.path, modelContext: context) }
            guard accepted else { throw MerianError.invalidResponse }
        } else {
            guard media == "video" else { throw MerianError.invalidResponse }
            let input = try await InitialMediaHistoryUIInput.video(in: root, progress: progress)
            progress("video: production preparation")
            originalClip = try digest(Data(contentsOf: input))
            let prepared = try await CaptureScanVideoMediaPreparer.prepare(.init(videoURL: input,
                duration: 1, composingCenter: 0.5, isProActive: true))
            guard let audio = prepared.audioFilePath else { throw MerianError.invalidResponse }
            expectedAudio = try digest(Data(contentsOf: URL.documentsDirectory.appendingPathComponent(audio)))
            expectedPlayback = try digest(Data(contentsOf: prepared.playback.fileURL))
            frameHashes = prepared.sampledFrames.map { digest($0.inferenceData) }
            guard frameHashes.count == 5 else { throw MerianError.invalidResponse }
            progress("video: ordinary submission")
            workspace.stagedCapture.videos = [CaptureWorkspaceViewModel.makeStagedVideo(prepared)]
            if withText { workspace.stagedCapture.observationContexts = [.init(context: note, addedAt: .distantPast)] }
            let payload = CaptureSubmissionPayload(nodes: workspace.stagedCapture.orderedNodes)
            let beforeSubmission = admissionFacts(context: context, owner: owner, payload: payload)
            await workspace.submitStagedCapture(modelContext: context)
            let deadline = ContinuousClock.now + .seconds(15)
            while workspace.offlineToastMessage == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            let toast: String
            switch workspace.offlineToastMessage?.title {
            case nil: toast = "absent"
            case "Unable to save capture. Please try again.": toast = "queue-rejected"
            case "Unable to check scan availability. Please try again.": toast = "admission-unavailable"
            case "Your capture is kept in this draft. Open Library or Profile to restore access before identifying.": toast = "library-blocked"
            case "Fixed-context replay requires one audio sample with no other staged items.": toast = "replay-blocked"
            case "No network connection. Queued for analysis.": toast = "queued-offline"
            default: toast = "other"
            }
            try writeAdmissionDiagnostic(root: root, value: ["beforeGeneration": beforeGeneration,
                "beforeSubmission": beforeSubmission, "afterSubmission": admissionFacts(context: context, owner: owner, payload: payload),
                "toast": toast, "stagedVideoCount": workspace.stagedCapture.videos.count,
                "queueWritePending": workspace.isQueueingStagedCapture,
                "fixtureQueueCount": try context.fetchCount(FetchDescriptor<OfflineQueuedScan>())])
            progress("video submission: " + toast)
            guard workspace.offlineToastMessage != nil, workspace.stagedCapture.videos.isEmpty else { throw MerianError.invalidResponse }
        }
        progress("submitted queue/media verification")
        let rows = try context.fetch(FetchDescriptor<OfflineQueuedScan>())
        guard rows.count == 1, let queue = rows.first,
              let extracted = try manager.extractedQueuedScanData(scanId: queue.id),
              extracted.capturedMediaItems.count == (withText ? 2 : 1),
              !withText || extracted.capturedMediaItems.first == .description(note) else {
            throw MerianError.invalidResponse
        }
        let audio = extracted.audioFilePaths ?? []
        if media == "photo" {
            let display = extracted.capturedMediaSnapshot.thumbnailImagePaths
            guard audio.isEmpty, (extracted.audioMediaItems ?? []).isEmpty,
                  (extracted.videoFilePaths ?? []).isEmpty,
                  let visual = extracted.visualMediaItems, visual.count == 1,
                  visual.first?.kind == .image, visual.first?.sourceIndex == 0,
                  try extracted.localImagePaths.map({ try digest(Data(contentsOf: ownedMedia($0))) }) == frameHashes,
                  display.count == 1, try digest(Data(contentsOf: ownedMedia(display[0]))) == expectedPhotoDisplay else {
                throw MerianError.invalidResponse
            }
        } else {
            guard audio.count == 1, try digest(Data(contentsOf: ownedMedia(audio[0]))) == expectedAudio,
                  extracted.audioMediaItems == [media == "video" ? .videoAudio(clipIndex: 0) : .audio(sourceIndex: 0)] else {
                throw MerianError.invalidResponse
            }
        }
        if media == "video" {
            guard extracted.visualMediaItems == (0..<5).map({ .videoFrame(clipIndex: 0, frameIndex: $0) }),
                  try extracted.localImagePaths.map({ try digest(Data(contentsOf: URL.documentsDirectory.appendingPathComponent($0))) }) == frameHashes,
                  let playback = extracted.videoFilePaths, playback.count == 1,
                  try digest(Data(contentsOf: URL.documentsDirectory.appendingPathComponent(playback[0]))) == expectedPlayback else {
                throw MerianError.invalidResponse
            }
        }
        let paths = Set(extracted.capturedMediaSnapshot.thumbnailImagePaths + audio + (extracted.videoFilePaths ?? []))
        let hashes = try Dictionary(uniqueKeysWithValues: paths.map { ($0, try digest(Data(contentsOf: ownedMedia($0)))) })
        let submitted = queue.serializedCapturedMediaItems, timestamp = queue.timestamp, id = queue.id
        admitted = id
        progress("original completion ownership")
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>()).filter { $0.kind == .scanIngestion }
        guard jobs.count == 1, let job = jobs.first, job.subjectId == id else { throw MerianError.invalidResponse }
        queue.queueState = .inferencing; job.status = .running
        job.metadataJSON = InferenceGenerationMetadataContract.setting(generation, in: job.metadataJSON)
        try context.save(); manager.activeInferenceGenerations[id] = generation
        guard await BackgroundDatabaseActor(modelContainer: container).activateBackgroundAccountWork(scanId: id,
            ownership: .init(ownerUserID: owner, generation: generation, phase: .inference)) else { throw MerianError.invalidResponse }
        let runtime = AuthRuntimeState(), session = AuthTransitionSession(userID: owner, isAnonymous: false)
        var acquired = 0, released = 0, published = 0, correctPublication = false
        let boundary = BackgroundAccountWorkLeaseBoundary(begin: { expected in
            guard expected == owner, runtime.transitionAllows(nil) else { throw CancellationError() }
            acquired += 1; return runtime.beginAccountWork(session: session)
        }, isCurrent: { runtime.accountWorkLeaseIsCurrent($0, publishedSession: session, sdkSession: session) },
        finish: { released += 1; runtime.finishAccountWork($0) })
        let response = Data("""
        {"success":true,"data":{"scan_id":"\(id)","is_biological_subject":true,
        "is_live_capture":true,"ecology_type":"wild","is_invasive":false,
        "scientific_name":"Synthetic audio species","common_name":"Synthetic audio",
        "confidence_score":0.75,"insight_data":{"hazard_type":"none","ai_reasoning":"Synthetic audio result."}}}
        """.utf8)
        let responseURL = root.appendingPathComponent("synthetic-response.json")
        try response.write(to: responseURL, options: .atomic)
        progress("ordinary terminal completion")
        await manager.processInferenceTerminalResult(scanId: id, generation: generation, ownerUserID: owner,
            taskIdentifier: 89292, resultFileURL: responseURL, statusCode: 200, functionRouteEvidence: nil,
            accountWork: boundary, publishCompletion: { scan, result, saved in
                published += 1
                correctPublication = scan == id && result.finalScanId == id && saved.capturedMediaItems == submitted
            })
        let fresh = ModelContext(container)
        guard acquired == 1, released == 1, published == 1, correctPublication,
              let record = try fresh.fetch(FetchDescriptor<LocalScanRecord>()).first,
              let proof = try OrdinaryInferenceCompletion.retained(for: record, owner: owner, context: fresh),
              proof.resultSHA256 == digest(response), proof.generation == generation else { throw MerianError.invalidResponse }
        return Witness(media: media, withText: withText, scan: id, owner: owner, generation: generation,
            baseline: UUID(), submitted: submitted, timestamp: timestamp, retained: hashes,
            inferenceFrames: frameHashes, originalClip: originalClip, proof: proof)
    }

    static func ownedMedia(_ path: String) throws -> URL {
        let root = URL.documentsDirectory.resolvingSymlinksInPath()
        let url = root.appendingPathComponent(path).standardizedFileURL
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains(".."),
              url.path.hasPrefix(root.path + "/"), url.resolvingSymlinksInPath() == url else { throw MerianError.invalidResponse }
        return url
    }
    private static func seamFacts(context: ModelContext, owner: UUID) -> [String: Bool] {
        let manager = OfflineQueueManager.shared
        return ["expectedContext": manager.modelContext === context,
            "expectedEntitlementOwner": EntitlementManager.shared.activeAccountID == owner,
            "subscription": RevenueCatManager.shared.isSubscribed, "online": manager.isOnline,
            "queueLibraryAdmitted": manager.captureLibraryAdmission(nil)]
    }
    private static func admissionFacts(context: ModelContext, owner: UUID, payload: CaptureSubmissionPayload) -> [String: Bool] {
        var value = seamFacts(context: context, owner: owner)
        let audio = payload.mediaTimeline.audioFilePaths, video = payload.mediaTimeline.videoFilePaths
        value["canonicalAudioPaths"] = audio.count == 1 && audio.allSatisfy(InferenceAudioPreparer.isCanonicalInferencePath)
        value["edgeCompatibleAudio"] = audio.count == 1 && audio.allSatisfy(InferenceAudioPreparer.isQueueEligibleInferenceAudioPath)
        let bytes = Int64(payload.inferenceImages.reduce(0) { $0 + $1.compressedData.count })
            + Int64(payload.displayImages.reduce(0) { $0 + $1.displayData.count })
            + OfflineQueueStoragePolicy.estimatedBytes(for: audio + video)
        value["storageAdmitted"] = OfflineQueueStoragePolicy.canAdmitNewPayload(estimatedBytes: bytes)
        return value
    }
    private static func writeAdmissionDiagnostic(root: URL, value: [String: Any]) throws {
        let file = root.appendingPathComponent("submission-diagnostic.json")
        guard file.resolvingSymlinksInPath() == file.standardizedFileURL else { throw MerianError.invalidResponse }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard data.count < 8192 else { throw MerianError.invalidResponse }
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
}
#endif
