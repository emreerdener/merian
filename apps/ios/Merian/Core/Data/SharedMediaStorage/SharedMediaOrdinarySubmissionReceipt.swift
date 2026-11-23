import Foundation
import SwiftData

/// Strict, bounded persisted correlation of V71 and all V70 members. This
/// describes historical receipt bytes only: queue postconditions, current
/// asset counts, file seals and registered-owner authority remain separate.
@MainActor
enum SharedMediaOrdinarySubmissionReceipt {
    enum State: Equatable, Sendable {
        case reserved
        case accepted(SharedMediaOrdinarySubmissionAcceptance)
    }
    struct Snapshot: Equatable, Sendable {
        let submission: SharedMediaOrdinarySubmission
        let holds: SharedMediaOrdinaryHoldCohort
        let state: State
        /// Complete V71 envelope plus each V70 envelope/digest exactly once.
        let metadataBytes: Int64
    }

    static func read(_ row: SharedMediaOrdinarySubmissionRecord, in context: ModelContext) throws -> Snapshot {
        guard !context.hasChanges, row.modelContext === context, let data = row.requestData else { throw SharedMediaStorageFailure.conflict }
        let submission = try SharedMediaOrdinarySubmission.decode(data, sha256: row.requestSHA256)
        try requireScalars(row, submission: submission)
        let scanID = submission.scanID, generation = submission.generation
        let ids = submission.members.map(\.holdID)
        var query = FetchDescriptor<SharedMediaOrdinaryTransferRecord>(predicate: #Predicate {
            ids.contains($0.id) || $0.recipientScanID == scanID || $0.submissionGeneration == generation
        })
        query.fetchLimit = SharedMediaOrdinaryHoldCohort.maximumHolds + 1
        let rows = try context.fetch(query)
        guard rows.count == ids.count, Set(rows.map(\.id)) == Set(ids) else { throw SharedMediaStorageFailure.conflict }
        var requests: [SharedMediaOrdinaryHoldRequest] = []
        var accepted: [UUID: SharedMediaOrdinaryHoldAcceptance] = [:]
        var bytes = Int64(data.count + 64)
        for hold in rows {
            let receipt = try SharedMediaOrdinaryHoldReceipt.read(hold)
            bytes = try SharedMediaStoragePolicy.add(bytes, receipt.metadataBytes)
            switch receipt.state {
            case .reserved(let request): requests.append(request)
            case .accepted(let request, let acceptance): requests.append(request); accepted[request.id] = acceptance
            }
        }
        let holds = try SharedMediaOrdinaryHoldCohort(requests)
        try submission.validate(holds: holds)
        let state: State
        switch row.phaseRaw {
        case "reserved":
            guard row.revision == 0, accepted.isEmpty, row.acceptanceData == nil, row.acceptanceSHA256 == nil else {
                throw SharedMediaStorageFailure.conflict
            }
            state = .reserved
        case "accepted":
            guard row.revision == 1, let acceptanceData = row.acceptanceData,
                  let acceptanceSHA256 = row.acceptanceSHA256 else { throw SharedMediaStorageFailure.conflict }
            try holds.requireAcceptances(accepted)
            let receipt = try SharedMediaOrdinarySubmissionAcceptance.decode(acceptanceData,
                sha256: acceptanceSHA256, submission: submission, holds: holds)
            bytes = try SharedMediaStoragePolicy.add(bytes, Int64(acceptanceData.count + 64))
            state = .accepted(receipt)
        default: throw SharedMediaStorageFailure.conflict
        }
        guard bytes <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        return .init(submission: submission, holds: holds, state: state, metadataBytes: bytes)
    }

    /// Recheck before inserting; SwiftData uniqueness may upsert instead of
    /// rejecting a collision. Absence is descriptive, not admission authority.
    /// Any existing malformed, erased or unequal identity remains a conflict.
    static func existing(_ submission: SharedMediaOrdinarySubmission, in context: ModelContext) throws -> Snapshot? {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let bytes = try submission.encoded()
        let scanID = submission.scanID, generation = submission.generation
        let identity = submission.identityKey, eventID = submission.eventID, jobID = submission.jobID
        let scanKey = [submission.profile.ownerID, scanID].map { $0.uuidString.lowercased() }.joined(separator: ":")
        var query = FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(predicate: #Predicate {
            $0.id == generation || $0.submissionGeneration == generation || $0.recipientScanID == scanID ||
                $0.identityKey == identity || $0.scanKey == scanKey || $0.eventID == eventID || $0.jobID == jobID
        })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        guard let row = rows.first else {
            let ids = submission.members.map(\.holdID)
            var holds = FetchDescriptor<SharedMediaOrdinaryTransferRecord>(predicate: #Predicate {
                ids.contains($0.id) || $0.recipientScanID == scanID || $0.submissionGeneration == generation
            })
            holds.fetchLimit = 1
            guard try context.fetch(holds).isEmpty else { throw SharedMediaStorageFailure.conflict }
            return nil
        }
        guard row.requestData == bytes else { throw SharedMediaStorageFailure.conflict }
        return try read(row, in: context)
    }

    private static func requireScalars(_ row: SharedMediaOrdinarySubmissionRecord,
                                       submission value: SharedMediaOrdinarySubmission) throws {
        guard row.schemaVersion == 1, row.id == value.generation,
              row.cursorKey == value.generation.uuidString.lowercased(), row.identityKey == value.identityKey,
              row.scanKey == [value.profile.ownerID, value.scanID].map({ $0.uuidString.lowercased() }).joined(separator: ":"),
              row.inventoryID == value.profile.inventoryID, row.inventoryGeneration == value.profile.generation,
              row.ownerID == value.profile.ownerID, row.recipientScanID == value.scanID,
              row.submissionGeneration == value.generation, row.jobID == value.jobID, row.eventID == value.eventID,
              row.writerEpoch == value.writerEpoch, row.formatRaw == value.format.rawValue,
              row.observationSHA256 == value.observation.sha256,
              row.retirementData == nil, row.retirementSHA256 == nil else { throw SharedMediaStorageFailure.conflict }
    }
}
