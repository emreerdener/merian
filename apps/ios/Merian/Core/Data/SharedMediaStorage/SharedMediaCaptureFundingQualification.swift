import Foundation
import SwiftData

/// Descriptive funding custody, read while the native owner holds its existing
/// account/root operation. These values grant no upload or provider authority.
@MainActor
enum SharedMediaCaptureFundingQualification {
    struct Entry: Equatable, Sendable {
        let scanID: String
        let funding: ScanFundingReservation?
        let proof: String
        let terminal: Bool
    }

    /// Restore all accepted nonterminal admissions, including needs-attention
    /// jobs. A stopped retry is still a held reservation.
    static func restore(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                        files: SharedMediaCaptureArtifactFiles) throws {
        try files.check(); _ = try authority.header(container)
        guard EntitlementManager.shared.activeAccountID == authority.profile.ownerID else {
            throw SharedMediaStorageFailure.closed
        }
        let context = ModelContext(container); context.autosaveEnabled = false
        let capture = SharedMediaCaptureAcceptance.mediaAuthority
        var query = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.mediaAuthorityRaw == capture },
            sortBy: [SortDescriptor(\.id)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        var offset = 0
        while true {
            try Task.checkCancellation(); try files.check(); _ = try authority.header(container)
            query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows {
                let value = try entry(row.id, context: context, authority: authority, files: files)
                if !value.terminal, let funding = value.funding {
                    EntitlementManager.shared.restoreQualifiedCaptureFunding(funding)
                    if funding.source == .immediateFlash || funding.source == .deferredFlash {
                        UsageManager.shared.consumeScan(scanId: value.scanID)
                    } else {
                        // A resolution may have committed before its caller
                        // observed success. Cold restoration must reconcile
                        // the meter from that qualified durable reservation.
                        UsageManager.shared.refundScan(scanId: value.scanID)
                    }
                }
            }
            if rows.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
    }

    static func entries(_ ids: Set<String>, normalizing target: String? = nil, container: ModelContainer,
                        authority: SharedMediaNativeAppOperationAuthority,
                        files: SharedMediaCaptureArtifactFiles) throws -> [String: Entry] {
        guard ids.count <= 128 else { throw SharedMediaStorageFailure.capacity }
        try files.check(); _ = try authority.header(container)
        let context = ModelContext(container); context.autosaveEnabled = false
        var result: [String: Entry] = [:]
        for id in ids.sorted() {
            try Task.checkCancellation()
            result[id] = try entry(id, normalizingResolution: id == target, context: context, authority: authority, files: files)
        }
        try files.check(); _ = try authority.header(container)
        return result
    }

    private struct Identity: Codable {
        let ownerID: UUID
        let scanID: String
        let createdAt: Date
        let status: String
        let metadataSHA256: String?
    }

    private static func entry(_ id: String, normalizingResolution: Bool = false, context: ModelContext,
                              authority: SharedMediaNativeAppOperationAuthority,
                              files: SharedMediaCaptureArtifactFiles) throws -> Entry {
        guard let scanID = UUID(uuidString: id), scanID.uuidString.lowercased() == id,
              let job = try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: id)),
              job.kind == .scanIngestion, job.subjectId == id else { throw SharedMediaStorageFailure.conflict }
        let funding: ScanFundingReservation?
        let proofMetadata: String?
        if try SharedMediaLegacyQueueAccess.permits(context, scanID: id, requiresEvidence: true) {
            guard let legacy = try SharedMediaLegacyQueueAccess.fundingIdentity(context, scanID: id, reservation: nil) else {
                throw SharedMediaStorageFailure.conflict
            }
            funding = OfflineScanJobMetadataContract.funding(in: legacy.metadata)
            guard funding == nil || funding?.accountId == authority.profile.ownerID else { throw SharedMediaStorageFailure.conflict }
            proofMetadata = legacy.metadata
        } else {
            guard let raw = job.metadataJSON,
                  let initial = try OrdinaryInitialSubmissionIdentity.read(
                    OfflineScanJobMetadataContract.object(from: raw)[OrdinaryInitialEvidenceProof.expectationKey]),
                  initial.ownerID == authority.profile.ownerID, initial.scanID == scanID,
                  let saved = try SharedMediaCaptureSubmissionReceipt.auditMatching(scanID: scanID,
                    generation: initial.generation, in: context), case .accepted = saved.state,
                  saved.submission.profile == authority.profile,
                  saved.submission.rootBindingSHA256 == files.rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaCaptureQueueIdentity.require(saved.submission, in: context)
            funding = try SharedMediaCaptureFundingResolution.funding(raw, submission: saved.submission)
            if job.status == .complete {
                _ = try SharedMediaCaptureCompletedCustody.read(scanID: scanID, generation: initial.generation,
                    ownerID: authority.profile.ownerID, context: context)
                _ = try OrdinaryInferenceCompletion.retainedInitialCompletionSHA256(metadata: raw,
                    scanID: scanID, owner: authority.profile.ownerID)
                _ = try SharedMediaCaptureFundingReceipt.read(raw).settlement(ownerID: authority.profile.ownerID)
            }
            // Resolution is the only permitted funding mutation. Normalize it
            // to the immutable original so its own save does not invalidate the
            // custody proof. QueueIdentity has already checked its exact join.
            var fields = OfflineScanJobMetadataContract.object(from: raw)
            fields.removeValue(forKey: SharedMediaCaptureFundingResolution.key)
            guard let normalized = OfflineScanJobMetadataContract.json(from: fields),
                  let original = OfflineScanJobMetadataContract.settingFunding(
                    try saved.submission.context.metadata(plan: saved.submission.plan()).funding, in: normalized) else {
                throw SharedMediaStorageFailure.conflict
            }
            proofMetadata = normalizingResolution ? original : raw
        }
        let proof = try SharedMediaAcquisitionEncoding.digest(SharedMediaAcquisitionEncoding.encode(
            Identity(ownerID: authority.profile.ownerID, scanID: id, createdAt: job.createdAt,
                status: job.statusRaw, metadataSHA256: proofMetadata.map { SharedMediaAcquisitionEncoding.digest(Data($0.utf8)) }),
            maximum: 4096))
        return .init(scanID: id, funding: funding, proof: proof, terminal: job.status == .complete || job.status == .cancelled)
    }
}
