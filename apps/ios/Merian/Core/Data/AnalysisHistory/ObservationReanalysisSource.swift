import Foundation
import SwiftData

/// The identification the user opened, independent of later selection or review changes.
struct ObservationReanalysisSource: Equatable, Sendable {
    let ownerID: UUID
    let observationID: UUID
    let analysisID: UUID
    let snapshot: Data
    let photos: [ObservationHistoryPhotoReference]
    let evidence: [ObservationHistoryPhotoReference.Evidence]

    private init(ownerID: UUID, observationID: UUID, result: ObservationHistoryPage.Result) throws {
        // A decoded audio result is not an empty legacy source. Its durable audio
        // producer and request matcher must exist before Capture can reuse it.
        guard result.version != 4 else { throw ObservationHistoryError.unavailable }
        self.ownerID = ownerID; self.observationID = observationID; self.analysisID = result.analysisID
        self.snapshot = result.bytes; self.photos = result.photos
        if result.version == 2 {
            let envelope = try JSONSerialization.jsonObject(with: result.bytes) as? [String: Any]
            self.evidence = try ObservationHistoryPhotoReference.decodeEvidence(envelope?["evidence_manifest"],
                observationID: observationID, analysisID: result.analysisID)
        } else {
            // Legacy and imported results never borrow descriptions or media from the mutable observation.
            self.evidence = []
        }
    }

    /// Capture at entry. An explicit historical target need not be the selected identification.
    @MainActor
    static func capture(observationID: UUID, analysisID: UUID? = nil, ownerID: UUID, container: ModelContainer) throws -> Self {
        try ConfirmedSpeciesReviewPersistence.transaction {
            try read(observationID: observationID, analysisID: analysisID, ownerID: ownerID, context: ModelContext(container))
        }
    }

    @MainActor
    private static func read(observationID: UUID, analysisID: UUID?, ownerID: UUID, context: ModelContext) throws -> Self {
        let scan = try ObservationHistorySyncService.enrolledScan(observationID.uuidString, context: context)
        guard scan.analysisOwnerAccountID == ownerID.uuidString.lowercased(),
              !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else { throw ObservationHistoryError.unavailable }
        let sourceID = try analysisID ?? ObservationHistoryPage.uuid(scan.selectedAnalysisID)
        let id = sourceID.uuidString.lowercased()
        var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })
        query.fetchLimit = 1
        guard let record = try context.fetch(query).first, record.observationID == scan.id,
              record.ownerAccountID == scan.analysisOwnerAccountID,
              record.resultSnapshotData.count <= LocalAnalysisRecord.maximumSnapshotBytes else { throw ObservationHistoryError.unavailable }
        let envelope = try JSONSerialization.jsonObject(with: record.resultSnapshotData) as? [String: Any]
        let ordinal = try ObservationHistoryPage.integer(envelope?["ordinal"])
        let result = try ObservationHistoryPage.snapshot(record.resultSnapshotData, observationID: observationID.uuidString.lowercased(), ordinal: ordinal)
        guard result.analysisID == sourceID, result.version == record.snapshotVersion, result.completedAt == record.completedAt else {
            throw ObservationHistoryError.resultConflict
        }
        return try Self(ownerID: ownerID, observationID: observationID, result: result)
    }

    /// Caller already owns the shared persistence transaction; never acquire it recursively.
    @MainActor
    func validate(context: ModelContext) throws {
        let current = try Self.read(observationID: observationID, analysisID: analysisID, ownerID: ownerID, context: context)
        guard current == self else { throw ObservationHistoryError.resultConflict }
    }

    /// Called after suspended preparation and before persistence. Selection may have advanced.
    @MainActor
    func validate(container: ModelContainer) throws {
        let current = try Self.capture(observationID: observationID, analysisID: analysisID, ownerID: ownerID, container: container)
        guard current == self else { throw ObservationHistoryError.resultConflict }
    }
}
