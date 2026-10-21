import Foundation
import SwiftData

/// Denial boundary for legacy helpers, not native admission or execution authority.
/// Call in the transaction context for admission, and in a fresh context after awaits.
enum SharedMediaLegacyQueueAccess {
    static let receivingKey = "native_receiving_v1"
    static let intentReceivingKey = "native_receiving_v2"
    private static func hasReceivingMarker(_ object: [String: Any]) -> Bool {
        object.keys.contains(receivingKey) || object.keys.contains(intentReceivingKey)
    }

    static func permitsMetadata(_ json: String?) -> Bool {
        guard let json else { return true }
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return !hasReceivingMarker(object)
    }

    static func permits(_ context: ModelContext, scanID: String,
                        requiresQueue: Bool = false, requiresEvidence: Bool = false) throws -> Bool {
        guard !scanID.isEmpty else { return false }
        let lower = scanID.lowercased(), upper = scanID.uppercased()
        let identities = [scanID, lower, upper]
        var queues = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate {
            $0.id == scanID || $0.id == lower || $0.id == upper
        })
        queues.fetchLimit = 2
        let rows = try context.fetch(queues)
        guard rows.count <= 1, !requiresQueue || rows.count == 1,
              rows.allSatisfy({ $0.permitsOrdinaryInference }) else { return false }

        var scans = FetchDescriptor<LocalScanRecord>(predicate: #Predicate {
            $0.id == scanID || $0.id == lower || $0.id == upper
        })
        scans.fetchLimit = 2
        let local = try context.fetch(scans)
        guard local.count <= 1,
              local.allSatisfy({ $0.mediaAuthorityRaw == "legacy" && $0.sharedMediaConsumerID == nil })
        else { return false }

        var consumers = FetchDescriptor<SharedMediaConsumerRecord>(predicate: #Predicate {
            identities.contains($0.originQueueID) || identities.contains($0.consumerID) ||
                identities.contains($0.observationID)
        })
        consumers.fetchLimit = 1
        guard try context.fetch(consumers).isEmpty else { return false }

        var analyses = FetchDescriptor<LocalAnalysisRecord>(predicate: #Predicate {
            (identities.contains($0.id) || identities.contains($0.observationID)) &&
            ($0.mediaAuthorityRaw != "legacy" || $0.sharedMediaConsumerID != nil)
        })
        analyses.fetchLimit = 1
        guard try context.fetch(analyses).isEmpty else { return false }

        let jobID = "scan-ingestion:" + scanID
        let lowerJob = "scan-ingestion:" + lower, upperJob = "scan-ingestion:" + upper
        var jobs = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
            $0.id == jobID || $0.id == lowerJob || $0.id == upperJob
        })
        jobs.fetchLimit = 2
        let jobRows = try context.fetch(jobs)
        guard !requiresEvidence || !rows.isEmpty || !local.isEmpty || !jobRows.isEmpty else { return false }
        return jobRows.count <= 1 && jobRows.allSatisfy {
            $0.kindRaw == OfflineJobKind.scanIngestion.rawValue &&
                $0.subjectId?.lowercased() == lower && permitsMetadata($0.metadataJSON)
        }
    }

    struct FundingIdentity: Equatable {
        let jobCreatedAt: Date
        let metadata: String?
        let reservation: ScanFundingReservation?
    }

    /// Metadata binds the existing generation and funding identity. Re-read after awaits.
    static func fundingIdentity(_ context: ModelContext, scanID: String,
                                reservation: ScanFundingReservation?) throws -> FundingIdentity? {
        guard try permits(context, scanID: scanID, requiresEvidence: true),
              let job = try context.fetchOfflineJob(id: "scan-ingestion:" + scanID) else { return nil }
        if let reservation,
           OfflineScanJobMetadataContract.funding(in: job.metadataJSON) != reservation { return nil }
        return FundingIdentity(jobCreatedAt: job.createdAt, metadata: job.metadataJSON, reservation: reservation)
    }

    static func permitsFresh(_ container: ModelContainer, scanID: String) -> Bool {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return (try? permits(context, scanID: scanID)) == true
    }

    /// Both views must agree while the caller holds ScanInferencePersistenceCoordinator.
    /// The transaction view includes unsaved admission; the fresh view rejects cached downgrades.
    static func permitsMutationAssumingScanLock(_ context: ModelContext, scanID: String) -> Bool {
        permitsFresh(context.container, scanID: scanID) && (try? permits(context, scanID: scanID)) == true
    }

    static func requireJobMutation(_ context: ModelContext, id: String,
                                   kind: OfflineJobKind, subjectID: String?, metadata: String?,
                                   existing: OfflineJobRecord?) throws {
        // A reserved marker cannot escape protection by changing the job kind or ID.
        for json in [metadata, existing?.metadataJSON].compactMap({ $0 }) {
            if let data = json.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               hasReceivingMarker(object) { throw SharedMediaStorageFailure.conflict }
        }
        let prefix = "scan-ingestion:"
        guard kind == .scanIngestion || existing?.kind == .scanIngestion || id.hasPrefix(prefix)
        else { return }
        guard permitsMetadata(metadata), permitsMetadata(existing?.metadataJSON),
              kind == .scanIngestion, id.hasPrefix(prefix),
              let subjectID, id == prefix + subjectID,
              existing == nil || (existing?.kind == .scanIngestion && existing?.subjectId == subjectID),
              permitsFresh(context.container, scanID: subjectID),
              try permits(context, scanID: subjectID, requiresQueue: true)
        else { throw SharedMediaStorageFailure.conflict }
    }
}
