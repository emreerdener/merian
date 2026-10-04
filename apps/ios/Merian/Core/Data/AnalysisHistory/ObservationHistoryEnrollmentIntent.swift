import Foundation
import SwiftData

/// Caller owns the shared persistence transaction and save. Presence fails closed,
/// even when metadata is damaged. Explicit erasure retains an identity-only fence.
enum ObservationHistoryEnrollmentIntent {
    static let prefix = "observation-history-enrollment:"
    enum IntegrityError: Error { case invalidIntent }

    struct Receipt: Codable, Equatable {
        let version: Int
        let observationID: UUID
        let ownerID: UUID
        let intentID: UUID
    }

    static func jobID(_ scanID: String) -> String { prefix + scanID.lowercased() }

    static func holds(_ scanID: String, context: ModelContext) throws -> Bool {
        try context.fetchOfflineJob(id: jobID(scanID)) != nil
    }

    /// Read from a fresh context under the shared lock when deciding erasure or hydration.
    static func protects(_ scanID: String, context: ModelContext) throws -> Bool {
        if try holds(scanID, context: context) { return true }
        let lower = scanID.lowercased(), upper = scanID.uppercased()
        var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        query.fetchLimit = 2
        return try context.fetch(query).contains {
            $0.analysisOwnerAccountID != nil || $0.selectedAnalysisID != nil || $0.observationStateRevision != nil
        }
    }

    static func stage(observationID: UUID, ownerID: UUID, context: ModelContext) throws -> Receipt {
        if let job = try context.fetchOfflineJob(id: jobID(observationID.uuidString)) {
            return try restore(job, observationID: observationID, ownerID: ownerID)
        }
        let receipt = Receipt(version: 1, observationID: observationID, ownerID: ownerID, intentID: UUID())
        let data = try JSONEncoder().encode(receipt)
        context.insert(OfflineJobRecord(id: jobID(observationID.uuidString), kind: .future,
            subjectId: observationID.uuidString.lowercased(), status: .needsAttention,
            metadataJSON: String(decoding: data, as: UTF8.self)))
        return receipt
    }

    static func acknowledge(_ receipt: Receipt, context: ModelContext) throws {
        guard let job = try context.fetchOfflineJob(id: jobID(receipt.observationID.uuidString)),
              try restore(job, observationID: receipt.observationID, ownerID: receipt.ownerID) == receipt else {
            throw IntegrityError.invalidIntent
        }
        context.delete(job)
    }

    /// Erasure supersedes an active hold but retains a payload-free tombstone.
    /// A delayed page must not recreate the observation after cloud cleanup finishes.
    static func supersedeForExplicitDeletion(_ scanID: String, context: ModelContext) throws {
        guard try protects(scanID, context: ModelContext(context.container)) else { return }
        try ObservationHistorySelectionIntent.removeForDeletion(scanID, context: context)
        let job: OfflineJobRecord
        if let existing = try context.fetchOfflineJob(id: jobID(scanID)) { job = existing }
        else {
            job = OfflineJobRecord(id: jobID(scanID), kind: .future, subjectId: scanID.lowercased())
            context.insert(job)
        }
        job.kind = .future
        job.subjectId = scanID.lowercased()
        job.status = .cancelled
        job.metadataJSON = nil
        job.nextRunAt = nil
        job.lastErrorCode = nil
        job.lastErrorMessage = nil
        job.lastHTTPStatus = nil
        job.serverStatus = nil
        job.serverStage = nil
        job.serverRetryAfter = nil
        job.lastAttemptAt = nil
        job.attemptCount = 0
        job.approximateBytes = 0
        job.updatedAt = Date()
    }

    private static func restore(_ job: OfflineJobRecord, observationID: UUID, ownerID: UUID) throws -> Receipt {
        guard job.kindRaw == OfflineJobKind.future.rawValue, job.statusRaw == OfflineJobStatus.needsAttention.rawValue,
              job.subjectId == observationID.uuidString.lowercased(), job.nextRunAt == nil,
              let text = job.metadataJSON, text.utf8.count <= 4096 else { throw IntegrityError.invalidIntent }
        let data = Data(text.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["version", "observationID", "ownerID", "intentID"] else { throw IntegrityError.invalidIntent }
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        guard receipt.version == 1, receipt.observationID == observationID, receipt.ownerID == ownerID else {
            throw IntegrityError.invalidIntent
        }
        return receipt
    }
}
