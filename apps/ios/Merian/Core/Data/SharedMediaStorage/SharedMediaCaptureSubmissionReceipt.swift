import Foundation
import SwiftData

/// Canonical parent and ordered membership only. This reader grants no disk,
/// admission or release authority; physical inspection remains separately held.
@MainActor
enum SharedMediaCaptureSubmissionReceipt {
    enum State: Equatable, Sendable {
        case reserved
        case accepted(SharedMediaCaptureSubmissionAcceptance)
    }
    struct Snapshot: Equatable, Sendable {
        let submission: SharedMediaCaptureSubmission
        let artifacts: [SharedMediaCaptureArtifactLedger.Snapshot]
        let state: State
        let metadataBytes: Int64
        let reservedBytes: Int64
        var release: SharedMediaCaptureAcceptedRelease?
    }

    static func matching(scanID: UUID, generation: UUID, in context: ModelContext) throws -> Snapshot? {
        let saved = try auditMatching(scanID: scanID, generation: generation, in: context)
        guard saved?.release == nil else { throw SharedMediaStorageFailure.closed }
        return saved
    }

    static func auditMatching(scanID: UUID, generation: UUID, in context: ModelContext) throws -> Snapshot? {
        var query = FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(predicate: #Predicate {
            $0.recipientScanID == scanID || $0.submissionGeneration == generation || $0.id == generation
        })
        query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        guard let row = rows.first else { return nil }
        guard row.formatRaw == SharedMediaCaptureSubmission.Format.v1.rawValue else { throw SharedMediaStorageFailure.conflict }
        return try auditRead(row, in: context)
    }

    static func read(_ row: SharedMediaOrdinarySubmissionRecord, in context: ModelContext) throws -> Snapshot {
        let saved = try auditRead(row, in: context)
        guard saved.release == nil else { throw SharedMediaStorageFailure.closed }
        return saved
    }

    static func auditRead(_ row: SharedMediaOrdinarySubmissionRecord, in context: ModelContext) throws -> Snapshot {
        guard !context.hasChanges, row.modelContext === context, let data = row.requestData else {
            throw SharedMediaStorageFailure.conflict
        }
        let submission = try SharedMediaCaptureSubmission.decode(data, sha256: row.requestSHA256)
        try requireScalars(row, submission: submission)
        let scanID = submission.scanID, generation = submission.generation
        let ids = submission.members.map(\.artifactID)
        let query = FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate {
            ids.contains($0.id) || $0.recipientScanID == scanID || $0.submissionGeneration == generation
        })
        let rows = try SharedMediaCaptureArtifactCohort.activeRows(query, context: context, includeAcceptedRelease: true) { value in
                guard !ids.contains(value.request.id),
                      value.request.scanID == scanID, value.request.submissionGeneration == generation,
                      value.request.profile == submission.profile,
                      value.request.rootBindingSHA256 == submission.rootBindingSHA256,
                      !submission.members.contains(where: { $0.mediaID == value.request.mediaID }) else {
                    throw SharedMediaStorageFailure.conflict
                }
        }
        guard rows.count <= ids.count, Set(rows.map(\.id)).count == rows.count,
              Set(rows.map(\.id)).isSubset(of: Set(ids)) else { throw SharedMediaStorageFailure.conflict }
        var artifacts: [SharedMediaCaptureArtifactLedger.Snapshot] = []
        for member in submission.members {
            guard let row = rows.first(where: { $0.id == member.artifactID }) else { continue }
            let receipt = try SharedMediaCaptureArtifactLedger.auditReceipt(row)
            try submission.requireMember(receipt)
            artifacts.append(receipt)
        }
        // The capture ledger charges child receipts and physical bytes. Count
        // only this parent here so a complete audit never charges children twice.
        var metadata = Int64(data.count + 64)
        let state: State
        switch row.phaseRaw {
        case "reserved":
            guard row.revision == 0, row.acceptanceData == nil, row.acceptanceSHA256 == nil else {
                throw SharedMediaStorageFailure.conflict
            }
            state = .reserved
        case "accepted", "acceptedRetiring", "acceptedReleased":
            let steps: Int64 = row.phaseRaw == "acceptedReleased" ? 2 : row.phaseRaw == "acceptedRetiring" ? 1 : 0
            guard row.revision == 1 + steps, let accepted = row.acceptanceData, let digest = row.acceptanceSHA256 else {
                throw SharedMediaStorageFailure.conflict
            }
            state = .accepted(try SharedMediaCaptureSubmissionAcceptance.decode(accepted, sha256: digest,
                submission: submission, artifacts: artifacts))
            metadata = try SharedMediaStoragePolicy.add(metadata, Int64(accepted.count + 64))
        default: throw SharedMediaStorageFailure.conflict
        }
        let release: SharedMediaCaptureAcceptedRelease?
        if row.phaseRaw == "acceptedRetiring" || row.phaseRaw == "acceptedReleased" {
            guard case let .accepted(acceptance) = state, let data = row.retirementData,
                  let digest = row.retirementSHA256 else { throw SharedMediaStorageFailure.conflict }
            let saved = try SharedMediaCaptureAcceptedRelease.decode(data, sha256: digest,
                submission: submission, acceptance: acceptance, artifacts: artifacts)
            guard (saved.releasedRevision != nil) == (row.phaseRaw == "acceptedReleased") else { throw SharedMediaStorageFailure.conflict }
            for (member, artifact) in zip(saved.members, artifacts) {
                if let child = artifact.acceptedRelease {
                    guard child.parentIntentSHA256 == (try saved.intentSHA256), child.member == member,
                          child.inventoryRevision > saved.inventoryRevision else { throw SharedMediaStorageFailure.conflict }
                    if let finished = saved.releasedRevision {
                        guard let released = child.releasedRevision, finished > released else { throw SharedMediaStorageFailure.conflict }
                    }
                } else if saved.releasedRevision != nil { throw SharedMediaStorageFailure.conflict }
            }
            release = saved
            metadata = try SharedMediaStoragePolicy.add(metadata, Int64(data.count + 64))
        } else {
            guard row.retirementData == nil, row.retirementSHA256 == nil,
                  artifacts.allSatisfy({ $0.acceptedRelease == nil }) else { throw SharedMediaStorageFailure.conflict }
            release = nil
        }
        guard metadata <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        var serverChecksum: String?
        for remote in artifacts.compactMap(\.remoteStage) {
            guard case .accepted(let acceptance) = state, remote.inventoryRevision > acceptance.inventoryRevision,
                  serverChecksum == nil || serverChecksum == remote.serverRequestSHA256 else { throw SharedMediaStorageFailure.conflict }
            serverChecksum = remote.serverRequestSHA256
        }
        var reserved: Int64 = 0
        if case .reserved = state {
            reserved = Int64(SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes + 64)
            let present = Set(artifacts.map { $0.request.id })
            for member in submission.members where !present.contains(member.artifactID) {
                let input = try submission.artifact(mediaID: member.mediaID)
                // Until its own ledger row exists, reserve the exact media bytes
                // and bounded request/stage/descriptor metadata through the parent.
                let headroom = Int64(2 * SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes + 128 + 160
                    + SharedMediaCaptureRemoteStage.maximumBytes + 64)
                reserved = try SharedMediaStoragePolicy.add(reserved, SharedMediaStoragePolicy.add(input.byteCount, headroom))
            }
        }
        if let release, release.releasedRevision == nil {
            reserved = Int64(SharedMediaCaptureAcceptedRelease.maximumBytes + 64 - (row.retirementData?.count ?? 0) - 64)
            for artifact in artifacts where artifact.acceptedRelease == nil {
                reserved = try SharedMediaStoragePolicy.add(reserved, Int64(SharedMediaCaptureMemberRelease.maximumBytes + 64))
            }
        }
        return .init(submission: submission, artifacts: artifacts, state: state, metadataBytes: metadata, reservedBytes: reserved, release: release)
    }

    private static func requireScalars(_ row: SharedMediaOrdinarySubmissionRecord,
                                       submission value: SharedMediaCaptureSubmission) throws {
        guard row.schemaVersion == 1, row.id == value.generation,
              row.cursorKey == value.generation.uuidString.lowercased(), row.identityKey == value.identityKey,
              row.scanKey == [value.profile.ownerID, value.scanID].map({ $0.uuidString.lowercased() }).joined(separator: ":"),
              row.inventoryID == value.profile.inventoryID, row.inventoryGeneration == value.profile.generation,
              row.ownerID == value.profile.ownerID, row.recipientScanID == value.scanID,
              row.submissionGeneration == value.generation, row.jobID == value.jobID, row.eventID == value.eventID,
              row.writerEpoch == value.writerEpoch, row.formatRaw == value.format.rawValue,
              row.observationSHA256 == value.observation.sha256 else { throw SharedMediaStorageFailure.conflict }
    }
}
