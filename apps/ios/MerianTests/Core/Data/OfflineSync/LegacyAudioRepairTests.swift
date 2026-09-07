import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Legacy Audio Repair", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct LegacyAudioRepairTests {
    @Test func legacyStagedM4AIsUpgradedBeforeFreshUploadSigning() async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        defer {
            manager.modelContext = originalContext
            if originalContext != nil {
                manager.updateUnsyncedItemCount()
            }
        }
        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        let container = context.container
        let scanId = "legacy-staged-m4a-\(UUID().uuidString.lowercased())"
        let sourceName = "queued-legacy-\(UUID().uuidString.lowercased()).m4a"
        let sourceURL = URL.documentsDirectory.appendingPathComponent(sourceName)
        let outputName = "queued-audio-upgrade-\(UUID().uuidString.lowercased()).wav"
        let outputURL = URL.documentsDirectory.appendingPathComponent(outputName)
        try Data(repeating: 0x41, count: 512).write(to: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let scan = OfflineQueuedScan(
            id: scanId,
            capturedMediaJSON: MediaJSONParser.jsonString(from: [
                .audio(.documents(sourceName, sourceIndex: 0))
            ]),
            scanState: .staged,
            stagedR2Keys: ["staging/owner/\(scanId)_\(sourceName)"]
        )
        context.insert(scan)
        try context.save()

        let actor = BackgroundDatabaseActor(modelContainer: container)
        let result = await manager.repairLegacyQueuedAudio(
            scanIds: [scanId],
            dbActor: actor,
            audioPreparer: { requestedURL, requestedScanId in
                guard requestedURL.standardizedFileURL ==
                        sourceURL.standardizedFileURL,
                      requestedScanId == scanId else {
                    throw InferenceAudioPreparationError.sourceUnavailable
                }
                try makeInferenceTestPCM16WAVData(
                    sampleRate: 44_100,
                    channels: 1
                ).write(to: outputURL)
                return outputURL
            }
        )

        #expect(result.claimedScanIds == [scanId])
        #expect(result.repairedScanIds == [scanId])
        #expect(result.failedScanIds.isEmpty)

        let verificationContext = ModelContext(container)
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        let persisted = try #require(
            verificationContext.fetch(descriptor).first
        )
        #expect(persisted.queueState == .pending)
        #expect(persisted.stagedR2Keys == nil)
        #expect(persisted.capturedMediaSnapshot.audioPaths == [outputName])
        #expect(InferenceAudioPreparer.isCanonicalPreparedWAV(at: outputURL))
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))

        let payload = PendingScanPayload(
            id: scanId,
            localImagePaths: [],
            localAudioPaths: [outputName],
            localVideoPaths: []
        )
        let uploadItems = MediaStagingContract.uploadItems(
            for: payload,
            userId: "owner",
            documentsDirectory: .documentsDirectory
        )
        try MediaStagingContract.validateUploadBudget(uploadItems)
        #expect(uploadItems.first?.contentType == "audio/wav")
    }
}
