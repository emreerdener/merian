import Foundation
@testable import Merian
import SwiftData
import Testing
import UIKit

@MainActor
@Suite("Capture Terminal Acceptance", .serialized, .sharedProcessState(.offlineQueueManager))
struct CaptureTerminalAcceptanceTests {
    @Test func stagedVisualTerminalCompletionDrainsSignOutAndRejectsDuplicateCallbacks() async throws {
        let manager = OfflineQueueManager.shared
        let oldContext = manager.modelContext
        let oldOnline = manager.isOnline
        let oldCount = manager.unsyncedItemsCount
        let oldSubscription = RevenueCatManager.shared.isSubscribed
        let oldQuota = UsageManager.debugFreeScanLimitOverride
        UsageManager.debugFreeScanLimitOverride = true
        EntitlementManager.shared.resetForTesting(userID: UUID())
        RevenueCatManager.shared.isSubscribed = true
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, url: root.appendingPathComponent("capture.sqlite"))
        ])
        let context = ModelContext(container)
        manager.modelContext = context
        manager.isOnline = false
        var files: [String] = []
        var admittedScanId: String?
        let generation = UUID()
        let taskIdentifier = -91_001
        defer {
            if let scanId = admittedScanId {
                manager.inferenceStatusProbeTasks.cancel(scanId)
                manager.inferenceRetryTasks.cancel(scanId)
                manager.serverIngestionPollTasks.cancel(scanId)
                manager.foregroundInferenceRetirementTasks.cancel(scanId)
                manager.activeInferenceGenerations[scanId] = nil
                manager.inferenceCompletionGenerations[scanId] = nil
                manager.inferenceDispatchDates[scanId] = nil
                manager.deferredLiveUploadScanIds.remove(scanId)
            }
            manager.retiredInferenceGenerations.remove(generation)
            manager.backgroundAccountWorkLeases[taskIdentifier] = nil
            manager.inferenceTerminalTaskIdentifiers.remove(taskIdentifier)
            manager.modelContext = oldContext
            manager.isOnline = oldOnline
            manager.unsyncedItemsCount = oldCount
            RevenueCatManager.shared.isSubscribed = oldSubscription
            UsageManager.debugFreeScanLimitOverride = oldQuota
            EntitlementManager.shared.resetForTesting()
            SyncStateManager.shared.forceIdle()
            for path in files {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent(path))
            }
            try? FileManager.default.removeItem(at: root)
        }
        let di = AppDIContainer.preview
        let workspace = makeWorkspace(di: di)
        defer { workspace.preFetchTask?.cancel(); di.inferenceEngine.cancelActiveRequest() }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { renderer in
            UIColor.green.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let bytes = try #require(image.jpegData(compressionQuality: 0.8))
        workspace.stagedCapture.images = [StagedImage(
            compressedData: bytes, displayData: bytes, uiImage: image,
            original: IdentifiableImage(image: image)
        )]
        await workspace.submitStagedCapture(modelContext: context)
        for _ in 0..<500 where workspace.offlineToastMessage == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(workspace.offlineToastMessage != nil)
        #expect(workspace.stagedCapture.images.isEmpty)
        #expect(!di.inferenceEngine.isProcessing)
        let queued = try #require(context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let scanId = queued.id
        admittedScanId = scanId
        let route = queued.queuedScanContext()
        let extracted = try manager.extractedQueuedScanData(scanId: scanId)
        files = try #require(extracted).localImagePaths
        files += MediaJSONParser.imagePaths(jsonString: queued.capturedMediaJSON ?? "[]")
        queued.scanStateRaw = ScanQueueState.inferencing.rawValue
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.status = .running
        job.metadataJSON = InferenceGenerationMetadataContract.json(for: generation)
        try context.save()
        manager.activeInferenceGenerations[scanId] = generation

        let runtime = AuthRuntimeState()
        let source = AuthTransitionSession(userID: UUID(), isAnonymous: false)
        var acquired = 0
        var released = 0
        let accountWork = BackgroundAccountWorkLeaseBoundary(
            begin: { owner in
                guard owner == source.userID, runtime.transitionAllows(nil) else { throw CancellationError() }
                acquired += 1
                return runtime.beginAccountWork(session: source)
            },
            isCurrent: { runtime.accountWorkLeaseIsCurrent($0, publishedSession: source, sdkSession: source) },
            finish: { released += 1; runtime.finishAccountWork($0) }
        )
        let gate = CaptureTerminalDecodeGate()
        let finalization = BackgroundInferenceFinalizationService(dependencies: .init { request in
            await gate.wait()
            return try await InferenceResponsePreparationService.live.prepare(
                resultData: request.resultData, telemetry: request.telemetry,
                audioFilePaths: request.audioFilePaths, videoFilePaths: request.videoFilePaths,
                expectedScanId: request.expectedScanId
            )
        })
        let resultURL = root.appendingPathComponent("response.json")
        let duplicateURL = root.appendingPathComponent("duplicate.json")
        let response = Data("""
        {"success":true,"data":{"scan_id":"\(scanId)","is_biological_subject":true,
        "is_live_capture":true,"ecology_type":"wild","is_invasive":false,
        "scientific_name":"Danaus plexippus","common_name":"Monarch Butterfly",
        "confidence_score":0.98,"insight_data":{"hazard_type":"none","ai_reasoning":"Synthetic fixture."}}}
        """.utf8)
        try response.write(to: resultURL)
        try response.write(to: duplicateURL)
        var publications = 0
        let completion = Task { @MainActor in
            await manager.processInferenceTerminalResult(
                scanId: scanId, generation: generation, ownerUserID: source.userID,
                taskIdentifier: taskIdentifier, resultFileURL: resultURL, statusCode: 200,
                functionRouteEvidence: nil, accountWork: accountWork, finalizationService: finalization,
                publishCompletion: { _, result, _ in
                    publications += 1
                    #expect(result.finalScanId == scanId)
                    #expect((try? ModelContext(container).fetchCount(FetchDescriptor<OfflineQueuedScan>())) == 0)
                }
            )
        }
        for _ in 0..<500 {
            if await gate.started { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = await gate.started
        #expect(started)
        guard started else { await gate.release(); await completion.value; return }
        #expect(acquired == 1)
        #expect(released == 0)
        await manager.processInferenceTerminalResult(
            scanId: scanId, generation: generation, ownerUserID: source.userID,
            taskIdentifier: taskIdentifier, resultFileURL: duplicateURL, statusCode: 200,
            functionRouteEvidence: nil, accountWork: accountWork
        )
        await manager.processInferenceTerminalFailure(
            scanId: scanId, generation: generation, ownerUserID: source.userID,
            taskIdentifier: taskIdentifier, error: URLError(.cancelled), accountWork: accountWork
        )
        #expect(released == 0)
        #expect(!FileManager.default.fileExists(atPath: duplicateURL.path))
        #expect(manager.inferenceCompletionGenerations[scanId] == generation)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<LocalScanRecord>()) == 0)

        let transition = try #require(runtime.beginTransition(kind: .signOut, sourceSession: source))
        var drainStarted = false
        var signedOut = false
        let signOut = Task { @MainActor in
            await AuthLocalSignOutCoordinator().signOut(ownedBy: transition, dependencies: .init(
                state: .init(begin: { .init(awaitCancelledBootstrap: {}) }, finish: {}),
                transition: .init(
                    owns: { runtime.ownsTransition($0) },
                    awaitAccountWorkQuiescence: {
                        drainStarted = true
                        await runtime.awaitAccountWorkDrain()
                        return runtime.ownsTransition(transition)
                    },
                    updateForSessionInstallation: { _ in }, adoptSignedOutSession: { _ in }
                ),
                operations: .init(signOutSDKSession: { signedOut = true }, finishExternalSignOut: {}),
                diagnose: { _, _ in }
            ))
        }
        while !drainStarted { await Task.yield() }
        #expect(!signedOut)
        #expect(publications == 0)
        await gate.release()
        await completion.value
        await signOut.value
        #expect(signedOut)
        #expect(acquired == 1)
        #expect(released == 1)
        #expect(publications == 1)
        #expect(manager.backgroundAccountWorkLeases[taskIdentifier] == nil)
        #expect(!FileManager.default.fileExists(atPath: resultURL.path))
        let fresh = ModelContext(container)
        let records = try fresh.fetch(FetchDescriptor<LocalScanRecord>())
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.id == scanId)
        #expect(try fresh.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try fresh.fetch(FetchDescriptor<OfflineJobRecord>()).first?.status == .complete)
        let savedPaths = MediaJSONParser.imagePaths(jsonString: record.capturedMediaJSON ?? "[]")
        files += savedPaths
        #expect(savedPaths.count == 1)
        let savedPath = try #require(savedPaths.first)
        #expect(try Data(contentsOf: URL.documentsDirectory.appendingPathComponent(savedPath)) == bytes)
        let insight = InsightSheetViewModel(inferenceEngine: di.inferenceEngine)
        insight.beginPresentationSession()
        #expect(insight.bindQueuedPresentationPreferringCompletedRecord(
            route, modelContext: fresh, inferenceEngine: di.inferenceEngine
        ))
        #expect(insight.presentedLocalRecordScanId == scanId)
        insight.endPresentationSession()
    }

    private func makeWorkspace(di: AppDIContainer) -> CaptureWorkspaceViewModel {
        let base = CaptureWorkspaceDependencies.live(diContainer: di)
        let submission = CaptureSubmissionDependencies(
            context: .init(lastKnownLocation: { nil }, fetchDeferredContext: { _ in EnvironmentContext(location: nil) }),
            admission: .init(isOnline: { false }, canStartLocally: { _ in true }, preview: { _ in .unavailable }),
            deferredContext: .init(persistLocally: { _, _ in }, endpoint: .init(update: { _, _ in }), waitBeforeRetry: {})
        )
        return CaptureWorkspaceViewModel(diContainer: di, dependencies: .init(
            scan: base.scan, submission: submission, controls: base.controls,
            navigation: base.navigation, stagingToolbar: base.stagingToolbar,
            prepareImage: { _ in nil }, prepareHistoricalAudio: { _ in nil },
            externalImageImports: base.externalImageImports, downloadRefinementImage: { _ in nil },
            prewarmConnections: {}, sharedExplorePostId: { _ in nil }, captureGoalAccountId: { _ in nil },
            requestNotificationAuthorization: { _ in },
            feedback: .init(selection: { _ in }, sheet: { _ in }, medium: {}, error: {})
        ), prewarmHeadersOnInit: false)
    }
}

private actor CaptureTerminalDecodeGate {
    private(set) var started = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
