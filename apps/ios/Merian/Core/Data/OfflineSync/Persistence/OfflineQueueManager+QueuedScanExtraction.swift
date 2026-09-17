import CoreGraphics
import Foundation
import SwiftData

enum QueuedScanExtractionError: Error {
    case missingModelContext
}

extension OfflineQueuedScan {
    /// Resolves one live SwiftData row into the detached value routed through
    /// Scans and Insights. Call before deleting or detaching the receiver.
    @MainActor
    func queuedScanContext() -> QueuedScanContext {
        let capturedMediaItems = serializedCapturedMediaItems
        return QueuedScanContext(
            id: id,
            capturedMediaItems: capturedMediaItems,
            queueState: queueState,
            timestamp: timestamp,
            locationName: locationName,
            weatherTemperatureF: weatherTemperatureF,
            weatherCondition: weatherCondition,
            gpsElevation: gpsElevation,
            gpsLatitude: gpsLatitude,
            gpsLongitude: gpsLongitude,
            queueAttemptCount: queueAttemptCount,
            queueNextRetryAt: queueNextRetryAt,
            queueLastErrorCode: queueLastErrorCode,
            queueLastErrorMessage: queueLastErrorMessage,
            queueNeedsAttention: queueNeedsAttention,
            approximateQueuedBytes: OfflineQueueStoragePolicy.queuedMediaBytes(
                mediaItems: capturedMediaItems,
                inferenceImagePaths: inferenceImagePaths
            ),
            visualMediaItemsJSON: visualMediaItemsJSON
        )
    }
}

extension OfflineQueueManager {
    /// Reads and maps one queued scan while preserving the distinction between
    /// an absent row and an unavailable persistence boundary.
    func extractedQueuedScanData(
        scanId: String
    ) throws -> ExtractedScanData? {
        guard let context = modelContext else {
            throw QueuedScanExtractionError.missingModelContext
        }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        descriptor.fetchLimit = 1
        guard let scan = try context.fetch(descriptor).first else { return nil }
        return try buildExtractedScanData(
            from: scan,
            container: context.container
        )
    }

    /// Maps a queued scan record to a Sendable `ExtractedScanData` snapshot.
    /// Must be called while `scan` is accessible on the main actor.
    func buildExtractedScanData(
        from scan: OfflineQueuedScan,
        container: ModelContainer
    ) throws -> ExtractedScanData {
        let preferredGoal = try ModelContext(container)
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
