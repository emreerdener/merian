import Foundation
import SwiftData

// MARK: - Inference Processing Actor

/// Off-main-actor worker for CPU-bound inference tasks: base64 encoding and response parsing/persistence.
actor InferenceProcessingActor {
    static let shared = InferenceProcessingActor()

    /// Encodes image data payloads to base64 strings, preserving order.
    /// Multi-image scans are encoded concurrently across worker threads to overlap CPU time.
    func encodeBase64(compressedDatas: [Data]) async -> [String] {
        guard compressedDatas.count > 1 else {
            return compressedDatas.map { $0.base64EncodedString() }
        }
        var results = [String](repeating: "", count: compressedDatas.count)
        await withTaskGroup(of: (Int, String).self) { group in
            for (i, data) in compressedDatas.enumerated() {
                group.addTask(priority: .userInitiated) { (i, data.base64EncodedString()) }
            }
            for await (i, encoded) in group {
                results[i] = encoded
            }
        }
        return results
    }

    /// Decodes the edge function response, persists the scan record, and returns the mapped data.
    ///
    /// Returns the saved local image paths alongside the result so the caller can populate
    /// `InferenceEngine.validHistoricImagePaths` before clearing `activeLiveCaptureDatas`,
    /// ensuring the carousel always has the user's image available immediately after inference.
    ///
    /// - Parameters:
    ///   - compressedDatas: 1024 px inference-quality images (used for base64 encoding only).
    ///   - displayDatas: 2048 px display-quality images written to disk. When non-empty these
    ///     are written instead of `compressedDatas` so the insight sheet and scan library
    ///     render at full display quality. Falls back to `compressedDatas` when empty
    ///     (e.g. offline-queue reprocessing path where only inference-quality data is stored).
    struct ParseAndSaveResult {
        let mappedData: SpeciesData?
        let isNewDiscovery: Bool
        let savedPaths: [String]
        /// True when the provider response reached a durable terminal state: either a
        /// `LocalScanRecord` was saved, or a valid confidence-zero response requires no
        /// record. False means persistence was rejected or failed and the queued job must
        /// remain available for recovery.
        let didCompletePersistence: Bool
    }

    func parseAndSave(
        resultData: Data,
        telemetry: CaptureTelemetry,
        modelContext: ModelContext?,
        compressedDatas: [Data],
        displayDatas: [Data] = [],
        skipImageRequirement: Bool = false,
        observationContextsJSON: [String]? = nil,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        persistenceFence: LiveInferencePersistenceFence? = nil
    ) async throws -> ParseAndSaveResult {
        let parseStartedAt = CFAbsoluteTimeGetCurrent()
        let parsedWrapper: EdgeResponseWrapper
        do {
            parsedWrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: resultData)
        } catch let error as DecodingError {
            MerianLog.general.debug("AI JSON decoding error: \(error.localizedDescription, privacy: .private)")
            throw MerianError.decodingFailed
        }
        guard IdentifySuccessEnvelopeValidator.isUsable(parsedWrapper) else {
            MerianLog.general.debug(
                "AI response decoded but failed the client success boundary."
            )
            throw MerianError.decodingFailed
        }

        var mappedData = SpeciesData(
            fromEdgeResponse: parsedWrapper.data,
            locationName: telemetry.locationName,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            gpsElevation: telemetry.gpsElevation,
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude
        )
        mappedData.zoomFactor = telemetry.zoomFactor.map { Double($0) }
        mappedData.audioFilePaths = audioFilePaths
        mappedData.videoFilePaths = videoFilePaths
        MerianLog.general.debug(
            "[⏱ BENCH] Response parsing: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - parseStartedAt), privacy: .public)s bytes=\(resultData.count, privacy: .public)"
        )

        try Task.checkCancellation()

        var newDiscovery = false
        var savedPaths: [String] = []
        let responseMatchesFence = persistenceFence.map { fence in
            mappedData.scanId?.caseInsensitiveCompare(fence.scanId)
                == .orderedSame
        } ?? true
        // Confidence-zero is a valid terminal provider response. It intentionally creates no
        // LocalScanRecord, matching the background retry path, but must not trigger another
        // paid provider call merely because there was nothing to persist. A queue-backed
        // response must still echo the exact scan ID before that no-record result is trusted.
        var didCompletePersistence =
            mappedData.confidenceScore <= 0.0 && responseMatchesFence

        let persistenceStartedAt = CFAbsoluteTimeGetCurrent()
        if mappedData.confidenceScore > 0.0, let container = modelContext?.container,
           !compressedDatas.isEmpty || skipImageRequirement {
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            if !compressedDatas.isEmpty {
                // Standard image path: write display-quality images when available, fall back to
                // inference-quality (offline-queue reprocessing path with only 1024 px on disk).
                let datasToWrite = displayDatas.isEmpty ? compressedDatas : displayDatas
                savedPaths = await FileIOActor.shared.writeTemporaryImages(imageDatas: datasToWrite)
                let persistenceResult = await dbActor.saveLiveScanRecord(
                    mappedData: mappedData,
                    localImagePaths: savedPaths,
                    observationContextsJSON: observationContextsJSON,
                    audioFilePaths: audioFilePaths,
                    videoFilePaths: videoFilePaths,
                    mediaTimeline: mediaTimeline,
                    persistenceFence: persistenceFence
                )
                didCompletePersistence = persistenceResult.wasSaved
                newDiscovery = persistenceResult.isNewDiscovery
                if !didCompletePersistence {
                    await FileIOActor.shared.deleteImages(at: savedPaths)
                    savedPaths = []
                }
            } else {
                // Non-visual path: no image data — save record with no local image path.
                let persistenceResult = await dbActor.saveNonVisualRecord(
                    mappedData: mappedData,
                    observationContextsJSON: observationContextsJSON,
                    audioFilePaths: audioFilePaths,
                    videoFilePaths: videoFilePaths,
                    mediaTimeline: mediaTimeline,
                    persistenceFence: persistenceFence
                )
                didCompletePersistence = persistenceResult.wasSaved
                newDiscovery = persistenceResult.isNewDiscovery
            }
        }
        MerianLog.general.debug(
            "[⏱ BENCH] Result persistence: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - persistenceStartedAt), privacy: .public)s"
        )

        return ParseAndSaveResult(
            mappedData: mappedData,
            isNewDiscovery: newDiscovery,
            savedPaths: savedPaths,
            didCompletePersistence: didCompletePersistence
        )
    }
}
