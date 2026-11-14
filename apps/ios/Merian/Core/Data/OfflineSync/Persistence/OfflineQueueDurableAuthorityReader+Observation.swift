import Foundation
import SwiftData

extension OfflineQueueDurableAuthorityReader {
    /// Exact local ordinary operation snapshot, not execution or completion authority.
    struct ObservationSnapshot: Sendable, Equatable {
        let scanID: UUID
        let queueID: String
        let queueTimestamp: Date
        let state: ScanQueueState
        let needsAttention: Bool
        let capturedMedia: String?
        let mediaSnapshot: CapturedMediaSnapshot
        let fieldNotes: String?
        let queueUpdatedAt: Date
        let jobUpdatedAt: Date
        let visualMedia: String?
        let inferencePaths: [String]?
        let stagedKeys: [String]?
        let queueAttempts: Int
        let jobID: String
        let jobCreatedAt: Date
        let jobStatus: OfflineJobStatus
        let jobAttempts: Int
        let metadata: String
    }

    static func observation(scanId: String, ownerID: UUID, from container: ModelContainer) throws -> ObservationSnapshot {
        let context = ModelContext(container); context.autosaveEnabled = false
        guard let scanID = UUID(uuidString: scanId),
              try SharedMediaLegacyQueueAccess.permits(context, scanID: scanId, requiresQueue: true, requiresEvidence: true) else {
            throw MerianError.invalidResponse
        }
        var descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        descriptor.fetchLimit = 2
        let rows = try context.fetch(descriptor)
        guard rows.count == 1, let scan = rows.first, scan.permitsOrdinaryInference,
              let state = ScanQueueState(rawValue: scan.scanStateRaw),
              let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: scanId)),
              job.kindRaw == OfflineJobKind.scanIngestion.rawValue,
              job.subjectId?.lowercased() == scanID.uuidString.lowercased(),
              let status = OfflineJobStatus(rawValue: job.statusRaw),
              [.pending, .running, .waiting, .needsAttention].contains(status),
              let metadata = job.metadataJSON,
              let funding = OfflineScanJobMetadataContract.unreleasedFundingForObservation(in: metadata),
              funding.accountId == ownerID, funding.scanId == scanID.uuidString.lowercased() else {
            throw MerianError.invalidResponse
        }
        let held = state == .failed && scan.queueNeedsAttention && status == .needsAttention
        guard held || [.pending, .uploading, .staged, .inferencing].contains(state) else {
            throw MerianError.invalidResponse
        }
        return .init(scanID: scanID, queueID: scan.id, queueTimestamp: scan.timestamp,
            state: state, needsAttention: scan.queueNeedsAttention, capturedMedia: scan.capturedMediaJSON,
            mediaSnapshot: scan.capturedMediaSnapshot, fieldNotes: scan.fieldNotes,
            queueUpdatedAt: scan.queueUpdatedAt, jobUpdatedAt: job.updatedAt, visualMedia: scan.visualMediaItemsJSON, inferencePaths: scan.inferenceImagePaths,
            stagedKeys: scan.stagedR2Keys, queueAttempts: scan.queueAttemptCount, jobID: job.id,
            jobCreatedAt: job.createdAt, jobStatus: status, jobAttempts: job.attemptCount, metadata: metadata)
    }
}
