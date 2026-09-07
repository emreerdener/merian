import CoreGraphics
import Foundation
import SwiftData

extension OfflineQueueManager {
    /// Maps a queued scan record to a Sendable `ExtractedScanData` snapshot.
    /// Must be called while `scan` is accessible on the main actor.
    func buildExtractedScanData(from scan: OfflineQueuedScan, container: ModelContainer) -> ExtractedScanData {
        let preferredGoal = ModelContext(container)
            .preferredGoalHint(scanId: scan.id)
        let visualMediaItems: [IdentifyVisualMediaItem]? = scan.visualMediaItemsJSON.flatMap { json in
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode([IdentifyVisualMediaItem].self, from: data)
        }
        let firstImage = visualMediaItems?.first { $0.kind == .image }
        let shouldOmitQueueTimestamp = firstImage?.captureSource == .gallery
            && firstImage?.hasEmbeddedCaptureDate != true
        var telemetry = CaptureTelemetry(
            subjectDistanceInMeters: scan.subjectDistanceInMeters,
            gpsLatitude: scan.gpsLatitude,
            gpsLongitude: scan.gpsLongitude,
            gpsElevation: scan.gpsElevation,
            locationName: scan.locationName,
            weatherCondition: scan.weatherCondition,
            weatherTemperatureF: scan.weatherTemperatureF,
            timeOfDay: nil,
            timestamp: shouldOmitQueueTimestamp
                ? nil
                : DateUtilities.iso8601Formatter.string(from: scan.timestamp)
        )
        telemetry.zoomFactor = scan.zoomFactor.map { CGFloat($0) }

        return ExtractedScanData(
            telemetry: telemetry,
            r2Keys: scan.stagedR2Keys ?? [],
            container: container,
            originalTimestamp: scan.timestamp,
            capturedMediaItems: scan.serializedCapturedMediaItems,
            inferenceImagePaths: scan.inferenceImagePaths,
            visualMediaItemsJSON: scan.visualMediaItemsJSON,
            preferredGoal: preferredGoal
        )
    }
}
