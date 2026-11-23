import Foundation

/// The queue's existing durable context, captured once before media writes.
/// No live sensor, goal selection, debug profile or new funding claim is read
/// when a reserved observation resumes after interruption.
/// Account privacy and locale retain the ordinary request policy: resolved at
/// dispatch, then frozen by the server's first successful ingestion admission.
struct SharedMediaCaptureSubmissionContext: Codable, Equatable, Sendable {
    let timestamp: Date
    let subjectDistanceInMeters: Float?
    let gpsLatitude: Double?
    let gpsLongitude: Double?
    let gpsElevation: Double?
    let locationName: String?
    let weatherCondition: String?
    let weatherTemperatureF: Double?
    let zoomFactor: Double?
    let blurScore: Double?
    let preferredGoal: FieldTripPreferredGoal?
    let initialFieldNotes: String?
    let jobMetadataJSON: String

    init(plan: CaptureInitialEvidencePlan, funding: ScanFundingReservation,
         timestamp: Date, telemetry: CaptureTelemetry, blurScore: Double?,
         preferredGoal: FieldTripPreferredGoal?) throws {
        self.timestamp = timestamp
        subjectDistanceInMeters = telemetry.subjectDistanceInMeters
        gpsLatitude = telemetry.gpsLatitude; gpsLongitude = telemetry.gpsLongitude
        gpsElevation = telemetry.gpsElevation; locationName = telemetry.locationName
        weatherCondition = telemetry.weatherCondition; weatherTemperatureF = telemetry.weatherTemperatureF
        zoomFactor = telemetry.zoomFactor.map(Double.init)
        self.blurScore = blurScore; self.preferredGoal = preferredGoal
        initialFieldNotes = Self.notes(plan)
        jobMetadataJSON = try OrdinaryInitialJobMetadata(identity: .init(ownerID: plan.ownerID,
            scanID: plan.scanID, generation: plan.generation), funding: funding).json
        try validate(plan: plan)
    }

    func metadata(plan: CaptureInitialEvidencePlan) throws -> OrdinaryInitialJobMetadata {
        guard let funding = OfflineScanJobMetadataContract.unreleasedFundingForObservation(in: jobMetadataJSON) else {
            throw SharedMediaStorageFailure.conflict
        }
        let value = try OrdinaryInitialJobMetadata(identity: .init(ownerID: plan.ownerID,
            scanID: plan.scanID, generation: plan.generation), funding: funding)
        try value.requireInitialReadback(jobMetadataJSON)
        return value
    }

    func validate(plan: CaptureInitialEvidencePlan) throws {
        guard timestamp.timeIntervalSince1970.isFinite,
              [gpsLatitude, gpsLongitude, gpsElevation, weatherTemperatureF, zoomFactor, blurScore]
                .allSatisfy({ $0?.isFinite != false }), subjectDistanceInMeters?.isFinite != false,
              initialFieldNotes == Self.notes(plan) else { throw SharedMediaStorageFailure.invalid }
        if let goal = preferredGoal {
            guard UUID(uuidString: goal.userFieldTripId) != nil, UUID(uuidString: goal.itemId) != nil else {
                throw SharedMediaStorageFailure.invalid
            }
        }
        _ = try SharedMediaAcquisitionEncoding.encode(self, maximum: Int(PhotoPreparationPolicy.metadata))
        _ = try metadata(plan: plan)
    }

    /// Matches the existing queue's reconstructed telemetry subset. Fields that
    /// the queue never persisted remain absent, including simulator profiles.
    var telemetry: CaptureTelemetry {
        .init(subjectDistanceInMeters: subjectDistanceInMeters, gpsLatitude: gpsLatitude,
            gpsLongitude: gpsLongitude, gpsElevation: gpsElevation, locationName: locationName,
            weatherCondition: weatherCondition, weatherTemperatureF: weatherTemperatureF,
            timeOfDay: nil, timestamp: DateUtilities.iso8601Formatter.string(from: timestamp),
            zoomFactor: zoomFactor.map { CGFloat($0) }, estimatedSizeCm: nil)
    }

    private static func notes(_ plan: CaptureInitialEvidencePlan) -> String? {
        InitialFieldNotesSeed.make(contexts: plan.items.compactMap { node in
            if case .description(let text) = node { return ObservationContext(freeText: text) }; return nil
        })
    }
}
