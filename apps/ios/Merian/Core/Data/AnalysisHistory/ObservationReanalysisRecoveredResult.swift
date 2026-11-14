import Foundation
import SwiftData

/// Read-only display confirmation after retained work exits. Task exit alone
/// cannot attest success, and this reader never selects or repairs a result.
@MainActor
enum ObservationReanalysisRecoveredResult {
    static func contains(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                         isCurrent: () -> Bool,
                         decode: (Data) throws -> ObservationHistoryPage.Result) throws -> Bool {
        try ConfirmedSpeciesReviewPersistence.transaction {
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            let context = ModelContext(container)
            let parent = try ObservationHistorySyncService.enrolledScan(identity.observationID.uuidString, context: context)
            guard parent.analysisOwnerAccountID == identity.ownerID.uuidString.lowercased() else { throw ObservationHistoryError.accountChanged }
            let lower = identity.analysisID.uuidString.lowercased(), upper = identity.analysisID.uuidString
            guard try context.fetch(FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })).isEmpty,
                  try context.fetch(FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })).isEmpty else {
                throw ObservationHistoryError.unavailable
            }
            let records = try context.fetch(FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper }))
            guard !records.isEmpty else { return false }
            guard records.count == 1, let record = records.first, record.id == lower,
                  record.ownerAccountID == identity.ownerID.uuidString.lowercased(), record.observationID == parent.id else {
                throw ObservationHistoryError.resultConflict
            }
            // The caller binds its original immutable typed media request.
            let result = try decode(record.resultSnapshotData)
            guard result.analysisID == identity.analysisID, result.version == record.snapshotVersion,
                  result.completedAt == record.completedAt, isCurrent() else { throw ObservationHistoryError.resultConflict }
            return true
        }
    }
}
