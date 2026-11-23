import Foundation

/// Constructs uninserted legacy capture records after the manager's admission
/// checks. It owns field mapping only; it cannot persist or dispatch work.
@MainActor
struct CaptureQueueInitialRecords {
    enum Mode {
        case visual
        case nonVisual(hasUploadableMedia: Bool)
    }
    private let queuedMessage: String
    let scan: OfflineQueuedScan
    let goalHint: ActiveOfflineQueuedScanGoalHint?
    let jobMetadata: String?

    init(scanId: String, timestamp: Date, capturedMediaJSON: String?,
         initialFieldNotes: String?, inferenceImagePaths: [String],
         visualMediaItemsJSON: String?, preferredGoal: FieldTripPreferredGoal?,
         telemetry: CaptureTelemetry, blurScore: Double?, funding: ScanFundingReservation,
         foregroundInferenceGeneration: UUID?, mode: Mode = .visual) {
        let visual: Bool, state: ScanQueueState
        switch mode {
        case .visual:
            visual = true; state = .pending; queuedMessage = "Queued scan for upload."
        case .nonVisual(let hasUploadableMedia):
            visual = false; state = hasUploadableMedia ? .pending : .staged
            queuedMessage = "Queued non-visual scan for sync."
        }
        scan = OfflineQueuedScan(
            id: scanId,
            timestamp: timestamp,
            capturedMediaJSON: capturedMediaJSON,
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude,
            gpsElevation: telemetry.gpsElevation,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            blurScore: blurScore,
            subjectDistanceInMeters: visual ? telemetry.subjectDistanceInMeters : nil,
            locationName: telemetry.locationName,
            isFlashFired: nil,
            cameraPitchDegrees: nil,
            compassHeading: nil,
            relativeHumidity: nil,
            uvIndex: nil,
            zoomFactor: telemetry.zoomFactor.map { Double($0) },
            scanState: state,
            stagedR2Keys: visual ? nil : [],
            inferenceImagePaths: inferenceImagePaths.isEmpty ? nil : inferenceImagePaths,
            visualMediaItemsJSON: visualMediaItemsJSON
        )
        scan.fieldNotes = initialFieldNotes
        if let capturedMediaJSON,
           let items = MediaJSONParser.serializedItems(jsonString: capturedMediaJSON) {
            scan.replaceCapturedMedia(with: items)
        }

        goalHint = preferredGoal.map {
            ActiveOfflineQueuedScanGoalHint(scanId: scanId,
                userFieldTripId: $0.userFieldTripId, itemId: $0.itemId)
        }
        jobMetadata = OfflineScanJobMetadataContract.json(
            generation: foregroundInferenceGeneration, funding: funding)
    }

    func queuedEvent(jobID: String) -> OfflineQueueEvent {
        OfflineQueueEvent(jobId: jobID, scanId: scan.id, kind: .queued,
                          message: queuedMessage)
    }
}
