import Foundation
import SwiftData

extension BackgroundDatabaseActor {
    /// Persists a visual live-inference result without changing its public
    /// capture-facing entry point.
    func saveLiveScanRecord(
        mappedData: SpeciesData,
        localImagePaths: [String],
        observationContextsJSON: [String]? = nil,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        persistenceFence: LiveInferencePersistenceFence? = nil
    ) async -> LiveInferencePersistenceResult {
        guard mappedData.confidenceScore > 0, !localImagePaths.isEmpty else {
            return .notSaved
        }
        return await persistLiveScanRecord(
            mappedData: mappedData,
            localImagePaths: localImagePaths,
            observationContextsJSON: observationContextsJSON,
            audioFilePaths: audioFilePaths,
            videoFilePaths: videoFilePaths,
            mediaTimeline: mediaTimeline,
            coverImagePath: localImagePaths.first,
            isLiveCapture: mappedData.isLiveCapture,
            persistenceFence: persistenceFence,
            operation: "live_visual"
        )
    }

    /// Persists a description-only, audio-only, or mixed non-visual result.
    func saveNonVisualRecord(
        mappedData: SpeciesData,
        observationContextsJSON: [String]? = nil,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        persistenceFence: LiveInferencePersistenceFence? = nil
    ) async -> LiveInferencePersistenceResult {
        guard mappedData.confidenceScore > 0 else { return .notSaved }
        return await persistLiveScanRecord(
            mappedData: mappedData,
            localImagePaths: [],
            observationContextsJSON: observationContextsJSON,
            audioFilePaths: audioFilePaths,
            videoFilePaths: videoFilePaths,
            mediaTimeline: mediaTimeline,
            coverImagePath: nil,
            isLiveCapture: false,
            persistenceFence: persistenceFence,
            operation: "live_nonvisual"
        )
    }

    private func persistLiveScanRecord(
        mappedData: SpeciesData,
        localImagePaths: [String],
        observationContextsJSON: [String]?,
        audioFilePaths: [String]?,
        videoFilePaths: [String]?,
        mediaTimeline: [CaptureSubmissionMediaItem]?,
        coverImagePath: String?,
        isLiveCapture: Bool,
        persistenceFence: LiveInferencePersistenceFence?,
        operation: String
    ) async -> LiveInferencePersistenceResult {
        guard livePersistenceFenceMatchesResult(
            persistenceFence,
            mappedScanId: mappedData.scanId
        ) else {
            return .notSaved
        }

        let recordId = mappedData.scanId ?? UUID().uuidString
        let persistenceScanId = persistenceFence?.scanId ?? recordId
        if let persistenceFence {
            await ScanInferencePersistenceCoordinator.shared.acquire(
                scanId: persistenceScanId
            )
            guard await livePersistenceFenceIsCurrentAssumingPersistenceLock(
                persistenceFence
            ) else {
                await ScanInferencePersistenceCoordinator.shared.release(
                    scanId: persistenceScanId
                )
                return .notSaved
            }
        }

        let result = await persistLiveScanRecordAssumingPersistenceLock(
            mappedData: mappedData,
            recordId: recordId,
            localImagePaths: localImagePaths,
            observationContextsJSON: observationContextsJSON,
            audioFilePaths: audioFilePaths,
            videoFilePaths: videoFilePaths,
            mediaTimeline: mediaTimeline,
            coverImagePath: coverImagePath,
            isLiveCapture: isLiveCapture,
            persistenceFence: persistenceFence,
            operation: operation
        )
        if persistenceFence != nil {
            await ScanInferencePersistenceCoordinator.shared.release(
                scanId: persistenceScanId
            )
        }
        return result
    }

    private func persistLiveScanRecordAssumingPersistenceLock(
        mappedData: SpeciesData,
        recordId: String,
        localImagePaths: [String],
        observationContextsJSON: [String]?,
        audioFilePaths: [String]?,
        videoFilePaths: [String]?,
        mediaTimeline: [CaptureSubmissionMediaItem]?,
        coverImagePath: String?,
        isLiveCapture: Bool,
        persistenceFence: LiveInferencePersistenceFence?,
        operation: String
    ) async -> LiveInferencePersistenceResult {
        await acquireScanFinalizationLock(
            scanId: recordId,
            operation: operation
        )
        let result = await persistLiveScanRecordAssumingFinalizationLock(
            mappedData: mappedData,
            recordId: recordId,
            localImagePaths: localImagePaths,
            observationContextsJSON: observationContextsJSON,
            audioFilePaths: audioFilePaths,
            videoFilePaths: videoFilePaths,
            mediaTimeline: mediaTimeline,
            coverImagePath: coverImagePath,
            isLiveCapture: isLiveCapture,
            persistenceFence: persistenceFence
        )
        await ScanFinalizationCoordinator.shared.release(scanId: recordId)
        return result
    }

    private func persistLiveScanRecordAssumingFinalizationLock(
        mappedData: SpeciesData,
        recordId: String,
        localImagePaths: [String],
        observationContextsJSON: [String]?,
        audioFilePaths: [String]?,
        videoFilePaths: [String]?,
        mediaTimeline: [CaptureSubmissionMediaItem]?,
        coverImagePath: String?,
        isLiveCapture: Bool,
        persistenceFence: LiveInferencePersistenceFence?
    ) async -> LiveInferencePersistenceResult {
        if let persistenceFence,
           !(await livePersistenceFenceIsCurrentAssumingPersistenceLock(
               persistenceFence
           )) {
            return .notSaved
        }

        do {
            let identity = try scanRecordSpeciesIdentity(
                for: mappedData.scientificName
            )
            let capturedMediaJSON = await CapturedMediaPersistenceService.live
                .makeCapturedMediaJSON(for: .init(
                    localImagePaths: localImagePaths,
                    observationContextsJSON: observationContextsJSON ?? [],
                    audioFilePaths: audioFilePaths ?? [],
                    videoFilePaths: videoFilePaths ?? [],
                    mediaTimeline: mediaTimeline
                ))

            if let persistenceFence,
               !(await livePersistenceFenceIsCurrentAssumingPersistenceLock(
                   persistenceFence
               )) {
                return .notSaved
            }

            try insertReplacingLocalScanRecord(
                mappedData: mappedData,
                recordId: recordId,
                speciesId: identity.speciesId,
                timestamp: Date(),
                captureDate: Date(),
                capturedMediaJSON: capturedMediaJSON,
                coverImagePath: coverImagePath,
                isLiveCapture: isLiveCapture,
                fieldNotes: try preservedScanRecordFieldNotes(scanId: recordId)
            )
            if persistenceFence != nil, Task.isCancelled {
                modelContext.rollback()
                return .notSaved
            }

            try modelContext.save()
            return LiveInferencePersistenceResult(
                wasSaved: true,
                isNewDiscovery: identity.isNewDiscovery
            )
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "persistLiveScanRecord: persistence failed: \(error, privacy: .private)"
            )
            return .notSaved
        }
    }

    private func livePersistenceFenceIsCurrentAssumingPersistenceLock(
        _ fence: LiveInferencePersistenceFence
    ) async -> Bool {
        guard !Task.isCancelled,
              liveInferenceGenerationIsCurrentAssumingPersistenceLock(
                  scanId: fence.scanId,
                  expectedGeneration: fence.generation
              ) else {
            return false
        }
        let isCurrentInMemory = await MainActor.run {
            OfflineQueueManager.shared.isForegroundInferenceAttemptCurrent(
                scanId: fence.scanId,
                generation: fence.generation
            )
        }
        return !Task.isCancelled && isCurrentInMemory &&
            liveInferenceGenerationIsCurrentAssumingPersistenceLock(
                scanId: fence.scanId,
                expectedGeneration: fence.generation
            )
    }

    private func livePersistenceFenceMatchesResult(
        _ fence: LiveInferencePersistenceFence?,
        mappedScanId: String?
    ) -> Bool {
        guard let fence else { return true }
        guard let mappedScanId else { return false }
        return mappedScanId.caseInsensitiveCompare(fence.scanId) == .orderedSame
    }
}
