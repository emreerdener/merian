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
    }

    func parseAndSave(
        resultData: Data,
        telemetry: CaptureTelemetry,
        modelContext: ModelContext?,
        compressedDatas: [Data],
        displayDatas: [Data] = [],
        skipImageRequirement: Bool = false,
        observationContextsJSON: [String]? = nil,
        audioFilePaths: [String]? = nil // Added for V38 schema
    ) async throws -> ParseAndSaveResult {
        let parsedWrapper: EdgeResponseWrapper
        do {
            parsedWrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: resultData)
        } catch let error as DecodingError {
            MerianLog.general.debug("AI JSON decoding error: \(error.localizedDescription, privacy: .private)")
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

        try Task.checkCancellation()

        var newDiscovery = false
        var savedPaths: [String] = []

        if mappedData.confidenceScore > 0.0, let container = modelContext?.container,
           !compressedDatas.isEmpty || skipImageRequirement {
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            if !compressedDatas.isEmpty {
                // Standard image path: write display-quality images when available, fall back to
                // inference-quality (offline-queue reprocessing path with only 1024 px on disk).
                let datasToWrite = displayDatas.isEmpty ? compressedDatas : displayDatas
                savedPaths = await FileIOActor.shared.writeTemporaryImages(imageDatas: datasToWrite)
                newDiscovery = await dbActor.saveLiveScanRecord(
                    mappedData: mappedData,
                    localImagePaths: savedPaths,
                    observationContextsJSON: observationContextsJSON,
                    audioFilePaths: audioFilePaths
                )
            } else {
                // Describe path: no image data — save record with nil localImagePath.
                newDiscovery = await dbActor.saveDescribeRecord(
                    mappedData: mappedData,
                    observationContextsJSON: observationContextsJSON,
                    audioFilePaths: audioFilePaths
                )
            }
        }

        return ParseAndSaveResult(mappedData: mappedData, isNewDiscovery: newDiscovery, savedPaths: savedPaths)
    }
}
