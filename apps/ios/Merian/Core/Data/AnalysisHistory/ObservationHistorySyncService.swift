import Foundation
import SwiftData

/// Prepared, deliberately not called by ordinary history sync or live completion.
/// Enrollment must already be acknowledged; this path cannot assign an owner.
@MainActor
struct ObservationHistorySyncService {
    var cloud = ObservationHistoryCloudClient.live

    struct Receipt: Equatable {
        let insertedCount: Int
        let nextBeforeOrdinal: Int?
        let analysisIDs: [UUID]
        let stateRevision: Int
    }

    func syncPage(observationID: String, beforeOrdinal: Int? = nil, limit: Int = 20,
                  container: ModelContainer) async throws -> Receipt {
        guard (1...20).contains(limit), beforeOrdinal.map({ (1...2_147_483_646).contains($0) }) ?? true else {
            throw ObservationHistoryError.invalidPage
        }
        let ownerID = try ConfirmedSpeciesReviewPersistence.transaction {
            let context = ModelContext(container)
            let scan = try Self.enrolledScan(observationID, context: context)
            guard let text = scan.analysisOwnerAccountID, let owner = UUID(uuidString: text) else {
                throw ObservationHistoryError.unavailable
            }
            return owner
        }
        let lease = try cloud.begin(ownerID)
        defer { cloud.finish(lease) }
        guard lease.session.userID == ownerID, cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        let request = ObservationHistoryPageRequest(observation_id: observationID.lowercased(), before_ordinal: beforeOrdinal, limit: limit)
        let data = try await cloud.fetch(request)
        try Task.checkCancellation()
        guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        let page = try ObservationHistoryPage.decode(data, request: request, ownerID: ownerID)
        return try ConfirmedSpeciesReviewPersistence.transaction {
            // No suspension between fresh reads, duplicate comparison and save.
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
                let scan = try Self.enrolledScan(observationID, context: context)
                guard scan.analysisOwnerAccountID == ownerID.uuidString.lowercased() else { throw ObservationHistoryError.accountChanged }
                let inserted = try Self.insert(page.results, into: scan, ownerID: ownerID, context: context)
                try Task.checkCancellation()
                guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
                if inserted > 0 { try context.save() }
                return Receipt(insertedCount: inserted, nextBeforeOrdinal: page.nextBeforeOrdinal,
                    analysisIDs: page.results.map(\.analysisID), stateRevision: page.revision)
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    /// Validate every duplicate before inserting; callers own rollback and save.
    static func insert(_ results: [ObservationHistoryPage.Result], into scan: LocalScanRecord,
                       ownerID: UUID, context: ModelContext) throws -> Int {
        var pending = [ObservationHistoryPage.Result]()
        for result in results {
            let id = result.analysisID.uuidString.lowercased()
            var query = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate { $0.id == id })
            query.fetchLimit = 1
            if let existing = try context.fetch(query).first {
                guard existing.ownerAccountID == ownerID.uuidString.lowercased(),
                      existing.observationID == scan.id, existing.snapshotVersion == result.version,
                      existing.completedAt == result.completedAt, existing.resultSnapshotData == result.bytes else {
                    throw ObservationHistoryError.resultConflict
                }
            } else { pending.append(result) }
        }
        for result in pending {
            let child = try LocalAnalysisRecord(analysisID: result.analysisID, observationID: scan.id,
                ownerAccountID: ownerID, completedAt: result.completedAt, snapshotVersion: result.version, resultSnapshotData: result.bytes)
            context.insert(child)
            if scan.analysisRecords == nil { scan.analysisRecords = [] }
            scan.analysisRecords?.append(child)
        }
        return pending.count
    }

    static func enrolledScan(_ observationID: String, context: ModelContext) throws -> LocalScanRecord {
        guard let id = UUID(uuidString: observationID) else { throw ObservationHistoryError.invalidPage }
        let lower = id.uuidString.lowercased(), upper = id.uuidString
        var deletions = FetchDescriptor<PendingCloudDeletionTask>(predicate: #Predicate { $0.scanId == lower || $0.scanId == upper })
        deletions.fetchLimit = 1
        guard try context.fetch(deletions).isEmpty else { throw ObservationHistoryError.deleted }
        var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        query.fetchLimit = 2
        let scans = try context.fetch(query)
        guard scans.count == 1, let scan = scans.first else { throw ObservationHistoryError.deleted }
        guard scan.analysisOwnerAccountID != nil, scan.selectedAnalysisID.flatMap(UUID.init(uuidString:)) != nil,
              let revision = scan.observationStateRevision, (0...2_147_483_646).contains(revision),
              scan.analysisSelectionInitialized else { throw ObservationHistoryError.unavailable }
        return scan
    }
}
