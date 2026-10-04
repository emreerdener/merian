import Foundation
import SwiftData

/// Require each result's own retained evidence, authority and recoverable
/// display. Never capture the outgoing identification as the target.
@MainActor
enum ObservationHistorySelectionProjection {
    struct Retained {
        let authority: ObservationHistoryAuthority
        let reviewRevision: Int
        let observationRevision: Int
    }

    static func retainedAuthority(scan: LocalScanRecord, context: ModelContext) throws -> ObservationHistoryAuthority {
        guard let id = scan.selectedAnalysisID.flatMap(UUID.init(uuidString:)) else { throw ObservationHistoryError.unavailable }
        let retained = try retained(id, scan: scan, context: context)
        guard retained.observationRevision == scan.observationStateRevision else {
            throw ObservationHistoryStateSyncService.AdmissionError.selectionProjectionRequired
        }
        return retained.authority
    }

    static func retained(_ id: UUID, scan: LocalScanRecord, context: ModelContext) throws -> Retained {
        let key = id.uuidString.lowercased()
        var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == key })
        query.fetchLimit = 1
        guard let result = try context.fetch(query).first,
              result.ownerAccountID == scan.analysisOwnerAccountID, result.observationID == scan.id,
              let state = result.state, state.id == key,
              state.ownerAccountID == result.ownerAccountID, state.observationID == scan.id,
              state.observationStateRevision > 0, state.observationStateRevision <= (scan.observationStateRevision ?? 0),
              state.reviewRevision >= 0, state.reviewRevision <= state.observationStateRevision,
              state.reviewSnapshotData.count <= 32_768, let display = state.displaySnapshotData else {
            throw ObservationHistoryStateSyncService.AdmissionError.selectionProjectionRequired
        }
        guard result.resultSnapshotData.count <= LocalAnalysisRecord.maximumSnapshotBytes else { throw ObservationHistoryError.invalidSnapshot }
        let envelope = try JSONSerialization.jsonObject(with: result.resultSnapshotData) as? [String: Any]
        let ordinal = try ObservationHistoryPage.integer(envelope?["ordinal"])
        let saved = try ObservationHistoryPage.snapshot(result.resultSnapshotData, observationID: scan.id.lowercased(), ordinal: ordinal)
        guard saved.analysisID == id, saved.version == result.snapshotVersion, saved.completedAt == result.completedAt else {
            throw ObservationHistoryError.resultConflict
        }
        _ = try ObservationHistoryDisplayProjection.restore(display, matching: saved)
        return Retained(authority: try ObservationHistoryAuthority.decode(JSONSerialization.jsonObject(with: state.reviewSnapshotData)),
            reviewRevision: state.reviewRevision, observationRevision: state.observationStateRevision)
    }
}
