import Foundation
import SwiftData

// MARK: - Inference Processing Actor

/// Off-main-actor worker for CPU-bound inference tasks: base64 encoding and response parsing/persistence.
actor InferenceProcessingActor {
    static let shared = InferenceProcessingActor()

    /// Encodes image data payloads to base64 strings, preserving order.
    func encodeBase64(compressedDatas: [Data]) async -> [String] {
        compressedDatas.map { $0.base64EncodedString() }
    }

    /// Decodes the edge function response, persists the scan record, and returns the mapped data.
    func parseAndSave(
        resultData: Data,
        telemetry: CaptureTelemetry,
        modelContext: ModelContext?,
        compressedDatas: [Data]
    ) async throws -> (SpeciesData?, Bool) {
        let parsedWrapper: EdgeResponseWrapper
        do {
            parsedWrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: resultData)
        } catch let error as DecodingError {
            MerianLog.general.debug("AI JSON decoding error: \(error.localizedDescription, privacy: .private)")
            throw APIError.decodingFailed
        }

        let mappedData = SpeciesData(
            fromEdgeResponse: parsedWrapper.data,
            locationName: telemetry.locationName,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            gpsElevation: telemetry.gpsElevation,
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude
        )

        try Task.checkCancellation()

        var newDiscovery = false

        if mappedData.confidenceScore > 0.0, let container = modelContext?.container, !compressedDatas.isEmpty {
            let savedPaths = await FileIOActor.shared.writeTemporaryImages(imageDatas: compressedDatas)
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            newDiscovery = await dbActor.saveLiveScanRecord(mappedData: mappedData, localImagePaths: savedPaths)
        }

        return (mappedData, newDiscovery)
    }
}
