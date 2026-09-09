import Foundation
import SwiftData

extension BackgroundDatabaseActor {
    /// Validates the durable generation while the caller holds
    /// `ScanInferencePersistenceCoordinator` for `scanId`.
    ///
    /// Adoption exists only for an inference task already in flight during the
    /// generation rollout. A non-`nil` generation is never replaced.
    func validateOrAdoptInferenceGenerationAssumingPersistenceLock(
        scanId: String,
        expectedGeneration: UUID
    ) -> Bool {
        let inferencingRaw = ScanQueueState.inferencing.rawValue
        var scanDescriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate {
                $0.id == scanId && $0.scanStateRaw == inferencingRaw
            }
        )
        scanDescriptor.fetchLimit = 1
        do {
            guard try modelContext.fetch(scanDescriptor).first != nil else {
                return false
            }
        } catch {
            MerianLog.data.error(
                "validateOrAdoptInferenceGeneration: scan lookup failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return false
        }

        let jobId = OfflineQueueManager.scanIngestionJobId(scanId: scanId)
        let job: OfflineJobRecord?
        do {
            job = try modelContext.fetchOfflineJob(id: jobId)
        } catch {
            MerianLog.data.error(
                "validateOrAdoptInferenceGeneration: job lookup failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return false
        }
        guard let job else { return false }
        if InferenceGenerationMetadataContract.matches(
            expectedGeneration,
            in: job.metadataJSON
        ) {
            return true
        }
        guard InferenceGenerationMetadataContract.generation(
            in: job.metadataJSON
        ) == nil else {
            return false
        }

        job.metadataJSON = InferenceGenerationMetadataContract.setting(
            expectedGeneration,
            in: job.metadataJSON
        )
        job.updatedAt = Date()
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "validateOrAdoptInferenceGeneration: save failed scanId=\(scanId, privacy: .private) error=\(error, privacy: .private)"
            )
            return false
        }
    }

    /// Persists a prepared background inference result while the caller holds
    /// the scan's inference-persistence lock.
    ///
    /// Queue deletion remains on the main actor so its save reliably refreshes
    /// presented SwiftData queries.
    func persistOfflineScanResultAssumingPersistenceLock(
        mappedData initialMappedData: SpeciesData,
        originalImagePaths: [String],
        scanId: String,
        originalTimestamp: Date,
        observationContextsJSON: [String]?,
        audioFilePaths: [String]?,
        videoFilePaths: [String]?,
        capturedMediaJSON: String?
    ) async -> OfflineScanProcessingResult {
        guard !Task.isCancelled else { return .notProcessed }
        guard initialMappedData.confidenceScore > 0 else {
            do {
                try modelContext.save()
                return OfflineScanProcessingResult(
                    resolvedSpeciesName: nil,
                    isNewDiscovery: false,
                    finalScanId: nil,
                    speciesData: nil,
                    wasCleaned: true
                )
            } catch {
                modelContext.rollback()
                MerianLog.data.error(
                    "persistOfflineScanResult: terminal save failed; rolling back error=\(error, privacy: .private)"
                )
                return .notProcessed
            }
        }

        let recordId = initialMappedData.scanId ?? scanId
        await acquireScanFinalizationLock(
            scanId: recordId,
            operation: "offline"
        )
        let result = await persistOfflineScanResultAssumingFinalizationLock(
            mappedData: initialMappedData,
            originalImagePaths: originalImagePaths,
            recordId: recordId,
            originalTimestamp: originalTimestamp,
            observationContextsJSON: observationContextsJSON,
            audioFilePaths: audioFilePaths,
            videoFilePaths: videoFilePaths,
            capturedMediaJSON: capturedMediaJSON
        )
        await ScanFinalizationCoordinator.shared.release(scanId: recordId)
        return result
    }

    private func persistOfflineScanResultAssumingFinalizationLock(
        mappedData initialMappedData: SpeciesData,
        originalImagePaths: [String],
        recordId: String,
        originalTimestamp: Date,
        observationContextsJSON: [String]?,
        audioFilePaths: [String]?,
        videoFilePaths: [String]?,
        capturedMediaJSON: String?
    ) async -> OfflineScanProcessingResult {
        guard !Task.isCancelled else { return .notProcessed }

        do {
            var mappedData = initialMappedData
            let shouldInsertRecord = try localScanRecord(id: recordId) == nil
            let identity = try scanRecordSpeciesIdentity(
                for: mappedData.scientificName
            )
            let isNewDiscovery = shouldInsertRecord && identity.isNewDiscovery
            if isNewDiscovery {
                mappedData.isNewDiscovery = true
            }

            if shouldInsertRecord {
                try await insertOfflineScanRecordIfMissing(
                    mappedData: mappedData,
                    recordId: recordId,
                    speciesId: identity.speciesId,
                    discoveryTimestamp: originalTimestamp,
                    originalImagePaths: originalImagePaths,
                    observationContextsJSON: observationContextsJSON,
                    audioFilePaths: audioFilePaths,
                    videoFilePaths: videoFilePaths,
                    capturedMediaJSON: capturedMediaJSON
                )
            }
            try Task.checkCancellation()
            try modelContext.save()

            return OfflineScanProcessingResult(
                resolvedSpeciesName: mappedData.commonName,
                isNewDiscovery: isNewDiscovery,
                finalScanId: recordId,
                speciesData: mappedData,
                wasCleaned: true
            )
        } catch is CancellationError {
            modelContext.rollback()
            return .notProcessed
        } catch {
            modelContext.rollback()
            MerianLog.data.error(
                "persistOfflineScanResult: persistence failed; rolling back error=\(error, privacy: .private)"
            )
            return .notProcessed
        }
    }
}
