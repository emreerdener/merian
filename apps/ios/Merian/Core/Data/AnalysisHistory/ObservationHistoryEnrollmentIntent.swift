import CryptoKit
import Foundation
import SwiftData

/// Caller owns the shared persistence transaction and save. Presence fails closed,
/// even when metadata is damaged. Explicit erasure retains an identity-only fence.
enum ObservationHistoryEnrollmentIntent {
    static let prefix = "observation-history-enrollment:"
    private static let baselinePrefix = "observation-history-baseline:"
    enum IntegrityError: Error { case invalidIntent }
    enum BaselineProvenance: String, Codable, Sendable { case serverRecovery }

    /// Historical server identity, never current selection or execution authority.
    struct BaselineAssociation: Codable, Equatable {
        let version: Int
        let observationID: UUID
        let ownerID: UUID
        let intentID: UUID?
        let baselineAnalysisID: UUID
        let snapshotSHA256: String
        let provenance: BaselineProvenance?
    }

    static func baselineJobID(_ scanID: String) -> String { baselinePrefix + scanID.lowercased() }

    /// A missing legacy association stays missing; never infer it from selection.
    static func baseline(observationID: UUID, ownerID: UUID, context: ModelContext) throws -> BaselineAssociation? {
        guard let job = try context.fetchOfflineJob(id: baselineJobID(observationID.uuidString)) else { return nil }
        guard job.kindRaw == OfflineJobKind.future.rawValue, job.statusRaw == OfflineJobStatus.complete.rawValue,
              job.subjectId == observationID.uuidString.lowercased(), job.nextRunAt == nil,
              let text = job.metadataJSON, text.utf8.count <= 4096 else { throw IntegrityError.invalidIntent }
        let data = Data(text.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrityError.invalidIntent
        }
        let value = try JSONDecoder().decode(BaselineAssociation.self, from: data)
        let common: Set<String> = ["version", "observationID", "ownerID", "baselineAnalysisID", "snapshotSHA256"]
        switch value.version {
        case 1:
            guard Set(object.keys) == common.union(["intentID"]), value.intentID != nil, value.provenance == nil else {
                throw IntegrityError.invalidIntent
            }
        case 2:
            guard Set(object.keys) == common.union(["provenance"]), value.intentID == nil, value.provenance == .serverRecovery else {
                throw IntegrityError.invalidIntent
            }
        default: throw IntegrityError.invalidIntent
        }
        guard value.observationID == observationID, value.ownerID == ownerID,
              value.baselineAnalysisID != observationID, value.baselineAnalysisID != ownerID,
              value.snapshotSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw IntegrityError.invalidIntent }
        return value
    }

    /// Hash exact validated V3 transport bytes, with a fixed domain separator.
    static func baselineDigest(_ bytes: Data) -> String {
        SHA256.hash(data: Data("merian.observation-history.enrollment-baseline.v1\n".utf8) + bytes)
            .map { String(format: "%02x", $0) }.joined()
    }

    struct Receipt: Codable, Equatable, Sendable {
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
        if try holds(scanID, context: context) || context.fetchOfflineJob(id: baselineJobID(scanID)) != nil { return true }
        let lower = scanID.lowercased(), upper = scanID.uppercased()
        var query = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == lower || $0.id == upper })
        query.fetchLimit = 2
        return try context.fetch(query).contains {
            $0.analysisOwnerAccountID != nil || $0.selectedAnalysisID != nil || $0.observationStateRevision != nil
        }
    }

    static func existing(observationID: UUID, ownerID: UUID, context: ModelContext) throws -> Receipt? {
        guard let job = try context.fetchOfflineJob(id: jobID(observationID.uuidString)) else { return nil }
        return try restore(job, observationID: observationID, ownerID: ownerID)
    }

    static func stage(observationID: UUID, ownerID: UUID, context: ModelContext) throws -> Receipt {
        guard try context.fetchOfflineJob(id: baselineJobID(observationID.uuidString)) == nil else { throw IntegrityError.invalidIntent }
        if let job = try context.fetchOfflineJob(id: jobID(observationID.uuidString)) {
            return try restore(job, observationID: observationID, ownerID: ownerID)
        }
        let receipt = Receipt(version: 1, observationID: observationID, ownerID: ownerID, intentID: UUID())
        let data = try JSONEncoder().encode(receipt)
        guard let metadataJSON = String(bytes: data, encoding: .utf8) else {
            throw IntegrityError.invalidIntent
        }
        context.insert(OfflineJobRecord(id: jobID(observationID.uuidString), kind: .future,
            subjectId: observationID.uuidString.lowercased(), status: .needsAttention,
            metadataJSON: metadataJSON))
        return receipt
    }

    static func acknowledge(_ receipt: Receipt, enrollment: ObservationHistoryEnrollment,
                            result: ObservationHistoryPage.Result, context: ModelContext) throws {
        guard let job = try context.fetchOfflineJob(id: jobID(receipt.observationID.uuidString)),
              try restore(job, observationID: receipt.observationID, ownerID: receipt.ownerID) == receipt else {
            throw IntegrityError.invalidIntent
        }
        guard result.version == 3, result.analysisID == enrollment.baselineAnalysisID,
              try context.fetchOfflineJob(id: baselineJobID(receipt.observationID.uuidString)) == nil else { throw IntegrityError.invalidIntent }
        let checked = try ObservationHistoryPage.snapshot(result.bytes, observationID: receipt.observationID.uuidString.lowercased(), ordinal: 1)
        guard checked.version == 3, checked.analysisID == enrollment.baselineAnalysisID else { throw IntegrityError.invalidIntent }
        let association = BaselineAssociation(version: 1, observationID: receipt.observationID, ownerID: receipt.ownerID,
            intentID: receipt.intentID, baselineAnalysisID: enrollment.baselineAnalysisID, snapshotSHA256: baselineDigest(result.bytes), provenance: nil)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(association)
        guard data.count <= 4096, let text = String(data: data, encoding: .utf8) else { throw IntegrityError.invalidIntent }
        context.insert(OfflineJobRecord(id: baselineJobID(receipt.observationID.uuidString), kind: .future,
            subjectId: receipt.observationID.uuidString.lowercased(), status: .complete, metadataJSON: text))
        context.delete(job)
    }

    /// Caller verifies exact existing local V3 bytes under the shared transaction.
    /// Never delete or repurpose an active enrollment intent to repair legacy data.
    static func recoverBaseline(_ recovered: ObservationHistoryBaselineRecovery, observationID: UUID,
                                ownerID: UUID, context: ModelContext) throws {
        guard try !holds(observationID.uuidString, context: context) else { throw IntegrityError.invalidIntent }
        if let existing = try baseline(observationID: observationID, ownerID: ownerID, context: context) {
            guard existing.baselineAnalysisID == recovered.enrollment.baselineAnalysisID,
                  existing.snapshotSHA256 == recovered.snapshotSHA256 else { throw IntegrityError.invalidIntent }
            return
        }
        let association = BaselineAssociation(version: 2, observationID: observationID, ownerID: ownerID,
            intentID: nil, baselineAnalysisID: recovered.enrollment.baselineAnalysisID,
            snapshotSHA256: recovered.snapshotSHA256, provenance: .serverRecovery)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(association)
        guard data.count <= 4096, let text = String(data: data, encoding: .utf8) else { throw IntegrityError.invalidIntent }
        context.insert(OfflineJobRecord(id: baselineJobID(observationID.uuidString), kind: .future,
            subjectId: observationID.uuidString.lowercased(), status: .complete, metadataJSON: text))
    }

    /// Erasure supersedes an active hold but retains a payload-free tombstone.
    /// A delayed page must not recreate the observation after cloud cleanup finishes.
    static func supersedeForExplicitDeletion(_ scanID: String, context: ModelContext) throws {
        guard try protects(scanID, context: ModelContext(context.container)) else { return }
        try ObservationHistorySelectionIntent.removeForDeletion(scanID, context: context)
        if let baseline = try context.fetchOfflineJob(id: baselineJobID(scanID)) { context.delete(baseline) }
        let job: OfflineJobRecord
        if let existing = try context.fetchOfflineJob(id: jobID(scanID)) {
            job = existing
        } else {
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
