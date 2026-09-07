import Foundation
@testable import Merian
import Testing

@Suite("Media Upload Sync", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct MediaUploadSyncTests {
    @Test func uploadBatchSelectionSkipsBlockedHeadRowsAndPacksLaterWork() throws {
        let emptyRows = (0..<5).map { index in
            PendingScanPayload(
                id: "empty-\(index)",
                localImagePaths: [],
                localAudioPaths: [],
                localVideoPaths: []
            )
        }
        let fiveItems = PendingScanPayload(
            id: "five-items",
            localImagePaths: (0..<5).map { "image-\($0).webp" },
            localAudioPaths: [],
            localVideoPaths: []
        )
        let twoItems = PendingScanPayload(
            id: "two-items",
            localImagePaths: ["later-a.webp", "later-b.webp"],
            localAudioPaths: [],
            localVideoPaths: []
        )
        let oneItem = PendingScanPayload(
            id: "one-item",
            localImagePaths: ["later-fit.webp"],
            localAudioPaths: [],
            localVideoPaths: []
        )

        let selected = OfflineQueueManager.shared.selectUploadBatch(
            from: emptyRows + [fiveItems, twoItems, oneItem]
        )

        #expect(selected.map(\.id) == [fiveItems.id, oneItem.id])
        #expect(selected.flatMap(\.localUploadPaths).count == 6)

        let remoteURL = URL(string: "https://r2.invalid/upload")!
        let videoItem = ScanUploadItem(
            scanId: "video-policy",
            uploadIndex: 0,
            mediaKind: .video,
            localPath: "video.mp4",
            fileName: "video.mp4",
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            contentType: "video/mp4",
            objectKey: "staging/owner/video.mp4",
            sizeBytes: 128
        )
        let imageItem = ScanUploadItem(
            scanId: "image-policy",
            uploadIndex: 0,
            mediaKind: .image,
            localPath: "image.webp",
            fileName: "image.webp",
            fileURL: URL(fileURLWithPath: "/tmp/image.webp"),
            contentType: "image/webp",
            objectKey: "staging/owner/image.webp",
            sizeBytes: 64
        )
        let deferredVideoRequest =
            OfflineQueueManager.shared.queuedUploadRequest(
                remoteURL: remoteURL,
                item: videoItem,
                requiredHeaders: [
                    "Content-Type": "video/mp4",
                    "Content-Length": "128"
                ],
                scanContainsPlaybackVideo: true,
                allowsExpensiveVideoUpload: false
            )
        let forcedVideoRequest =
            OfflineQueueManager.shared.queuedUploadRequest(
                remoteURL: remoteURL,
                item: videoItem,
                requiredHeaders: [
                    "Content-Type": "video/mp4",
                    "Content-Length": "128"
                ],
                scanContainsPlaybackVideo: true,
                allowsExpensiveVideoUpload: true
            )
        let videoSiblingImageRequest =
            OfflineQueueManager.shared.queuedUploadRequest(
                remoteURL: remoteURL,
                item: imageItem,
                requiredHeaders: [
                    "Content-Type": "image/webp",
                    "Content-Length": "64"
                ],
                scanContainsPlaybackVideo: true,
                allowsExpensiveVideoUpload: false
            )
        let imageRequest =
            OfflineQueueManager.shared.queuedUploadRequest(
                remoteURL: remoteURL,
                item: imageItem,
                requiredHeaders: [
                    "Content-Type": "image/webp",
                    "Content-Length": "64"
                ],
                scanContainsPlaybackVideo: false,
                allowsExpensiveVideoUpload: false
            )

        #expect(!deferredVideoRequest.allowsConstrainedNetworkAccess)
        #expect(!deferredVideoRequest.allowsExpensiveNetworkAccess)
        #expect(!forcedVideoRequest.allowsConstrainedNetworkAccess)
        #expect(forcedVideoRequest.allowsExpensiveNetworkAccess)
        #expect(!videoSiblingImageRequest.allowsConstrainedNetworkAccess)
        #expect(!videoSiblingImageRequest.allowsExpensiveNetworkAccess)
        #expect(!imageRequest.allowsConstrainedNetworkAccess)
        #expect(imageRequest.allowsExpensiveNetworkAccess)
        #expect(deferredVideoRequest.value(forHTTPHeaderField: "Content-Type") == "video/mp4")
        #expect(deferredVideoRequest.value(forHTTPHeaderField: "Content-Length") == "128")
        #expect(imageRequest.value(forHTTPHeaderField: "Content-Type") == "image/webp")
        #expect(imageRequest.value(forHTTPHeaderField: "Content-Length") == "64")

        let uploadSyncSource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadSync.swift"
        )
        let uploadDispatchSource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/MediaUpload/OfflineQueueManager+UploadDispatch.swift"
        )
        let syncSource = uploadSyncSource + "\n" + uploadDispatchSource
        #expect(syncSource.contains(
            "var entriesByScanId: [String: [UploadDispatchEntry]]"
        ))
        let ownershipActivation = try #require(syncSource.range(
            of: "guard await queueActor.activateBackgroundAccountWork("
        ))
        let taskCreation = try #require(syncSource.range(
            of: "let task = session.uploadTask("
        ))
        let terminalLeaseRetention = try #require(syncSource.range(
            of: "guard retainBackgroundAccountWork("
        ))
        let firstResume = try #require(syncSource.range(
            of: "uploadTask.resume()"
        ))
        #expect(syncSource.contains("let durableOwnership = BackgroundAccountWorkOwnership("))
        #expect(syncSource.contains("var uploadTasks: [URLSessionUploadTask] = []"))
        #expect(syncSource.contains("uploadTasks.count == entries.count"))
        #expect(syncSource.contains("for uploadTask in uploadTasks"))
        #expect(ownershipActivation.lowerBound < taskCreation.lowerBound)
        #expect(terminalLeaseRetention.lowerBound < firstResume.lowerBound)
        #expect(syncSource.contains(
            "candidateScanIds: undispatchedScanIDs"
        ))
        #expect(syncSource.contains("finalPolicy.isOnline"))

        let managerSource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager.swift"
        )
        let replaySource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/InferenceReplay/OfflineQueueManager+InferenceReplay.swift"
        )
        let inferenceRecoverySource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceRecovery.swift"
        )
        let inferenceRetrySource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceRetry.swift"
        )
        let inferenceDispatchSource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceDispatch.swift"
        )
        let inferenceWatchdogSource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundInference/OfflineQueueManager+InferenceWatchdog.swift"
        )
        let inferencePipelineSource = [
            inferenceDispatchSource,
            inferenceRecoverySource,
            inferenceRetrySource,
            inferenceWatchdogSource
        ].joined(separator: "\n")
        let backgroundAccountWorkSource = try OfflineSyncTestSupport.loadRepositorySource(
            at: "apps/ios/Merian/Core/Data/OfflineSync/Services/BackgroundTransfer/OfflineQueueManager+BackgroundAccountWork.swift"
        )
        let normalizedInferencePipelineSource =
            OfflineSyncTestSupport.normalizedSource(inferencePipelineSource)
        let normalizedBackgroundAccountWorkSource =
            OfflineSyncTestSupport.normalizedSource(
                backgroundAccountWorkSource
            )
        #expect(normalizedBackgroundAccountWorkSource.contains(
            "func quiesceBackgroundAccountWorkForAuthTransition( sourceUserID: UUID? ) async -> Bool"
        ))
        #expect(normalizedBackgroundAccountWorkSource.contains(
            "guard let container = modelContext?.container else { return false }"
        ))
        #expect(normalizedBackgroundAccountWorkSource.contains(
            "guard !retirementFailed else { return false }"
        ))
        #expect(normalizedBackgroundAccountWorkSource.contains(
            "guard clock.now < deadline else { return false }"
        ))
        #expect(syncSource.components(
            separatedBy: "Set<String>(liveTasks.compactMap { task -> String? in"
        ).count == 4)
        #expect(replaySource.contains(
            "Set<String>(allTasks.compactMap { task -> String? in"
        ))
        #expect(managerSource.contains(
            "var allowsAutomaticNetworkWorkOnCurrentPath: Bool"
        ))
        #expect(inferencePipelineSource.components(
            separatedBy: "allowsAutomaticNetworkWorkOnCurrentPath"
        ).count == 19)
        #expect(normalizedInferencePipelineSource.components(
            separatedBy:
                "guard !Task.isCancelled, allowsAutomaticNetworkWorkOnCurrentPath, isServerIngestionPollCurrent("
        ).count == 6)
        #expect(normalizedInferencePipelineSource.contains(
            "guard allowsAutomaticNetworkWorkOnCurrentPath, isServerIngestionPollCurrent("
        ))
        #expect(normalizedInferencePipelineSource.contains(
            "let action = BackgroundInferencePolicy.scanStatusRecoveryAction( for: response ) guard allowsAutomaticNetworkWorkOnCurrentPath else {"
        ))
    }
}
