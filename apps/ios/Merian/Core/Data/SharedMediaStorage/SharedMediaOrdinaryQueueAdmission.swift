import Foundation
import SwiftData

/// Exact initial queue rows for the ordinary original owner. Construction and
/// readback grant no funding, save, file access or dispatch authority. The owner
/// must insert these rows in the same transaction as the complete hold cohort.
struct SharedMediaOrdinaryQueueAdmission: Sendable {
    static let mediaAuthority = "sharedOrdinaryInitialV1"
    let submission: SharedMediaOrdinarySubmission
    let metadata: OrdinaryInitialJobMetadata
    let timestamp: Date
    let telemetry: CaptureTelemetry
    let blurScore: Double?
    let preferredGoal: FieldTripPreferredGoal?
    let fieldNotes: String?
    let approximateBytes: Int64

    init(submission: SharedMediaOrdinarySubmission, funding: ScanFundingReservation,
         timestamp: Date, telemetry: CaptureTelemetry, blurScore: Double?,
         preferredGoal: FieldTripPreferredGoal?) throws {
        try submission.validate()
        guard timestamp.timeIntervalSince1970.isFinite,
              [telemetry.gpsLatitude, telemetry.gpsLongitude, telemetry.gpsElevation,
               telemetry.weatherTemperatureF, telemetry.zoomFactor.map(Double.init), blurScore]
                .allSatisfy({ $0?.isFinite != false }),
              telemetry.subjectDistanceInMeters?.isFinite != false else { throw SharedMediaStorageFailure.invalid }
        if let goal = preferredGoal {
            guard UUID(uuidString: goal.userFieldTripId) != nil, UUID(uuidString: goal.itemId) != nil else {
                throw SharedMediaStorageFailure.invalid
            }
        }
        self.submission = submission
        metadata = try .init(identity: .init(ownerID: submission.profile.ownerID,
            scanID: submission.scanID, generation: submission.generation), funding: funding)
        self.timestamp = timestamp; self.telemetry = telemetry; self.blurScore = blurScore; self.preferredGoal = preferredGoal
        let frozen = try SharedMediaNativeFrozenCohort.decode(submission.observation.bytes)
        fieldNotes = frozen.initialFieldNotes
        // This is scheduling weight only. Original accounting remains with the
        // asset owner; no Documents paths or duplicate physical charge are made.
        approximateBytes = try frozen.entries.reduce(Int64(0)) { total, entry in
            let intent = try SharedMediaNativeDerivativeIntent.decode(entry.intent.bytes)
            return try SharedMediaStoragePolicy.add(total, intent.preparation.original.byteCount)
        }
    }

    typealias Rows = SharedMediaInitialQueueAdmission.Rows

    private var queue: SharedMediaInitialQueueAdmission {
        .init(identity: metadata.identity, eventIdentity: submission.eventID, jobID: submission.jobID,
            mediaAuthority: Self.mediaAuthority, metadata: metadata, timestamp: timestamp,
            telemetry: telemetry, blurScore: blurScore, preferredGoal: preferredGoal,
            fieldNotes: fieldNotes, approximateBytes: approximateBytes)
    }
    @MainActor func makeRows() -> Rows { queue.makeRows() }
    @MainActor func requireSaved(in context: ModelContext) throws { try queue.requireSaved(in: context) }
    @MainActor func requireRows(_ rows: Rows) throws { try queue.requireRows(rows) }
    @MainActor func requireAbsent(in context: ModelContext) throws {
        try queue.requireAbsent(in: context)
        let recipient = submission.scanID
        var artifacts = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.recipientScanID == recipient })
        artifacts.fetchLimit = 1
        guard try context.fetch(artifacts).isEmpty else { throw SharedMediaStorageFailure.conflict }
    }
}
