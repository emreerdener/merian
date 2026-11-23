import Foundation
import SwiftData

/// Whole-store, read-only validation of accepted ordinary liabilities. Unlike
/// the per-original reader, this also rejects unanchored and foreign V70/V71
/// rows. It grants no queue, mutation, file access, or final-release authority.
@MainActor
enum SharedMediaOrdinaryStoreAudit {
    struct Snapshot: Equatable, Sendable {
        let header: SharedMediaNativeAppEligibility.Header
        let submissions: Int64
        let holds: Int64
        let metadataBytes: Int64
        let reservedBytes: Int64
        let capturePackages: [UUID: Int64]
    }

    /// Caller retains the native store fence. No inventory predicate is used:
    /// a corrupt scope field must not hide a row from the reverse audit.
    static func verify(context: ModelContext, profile: SharedMediaNativeAppProfile,
                       capture: SharedMediaCaptureArtifactInspection? = nil,
                       checkpoint: () throws -> Void = {}) throws -> Snapshot {
        try verify(context: context, profile: profile, capture: capture.map(SharedMediaCaptureAuditEvidence.ready),
            erasure: nil, checkpoint: checkpoint)
    }

    static func verifyForErasure(context: ModelContext, erasure: SharedMediaNativeErasureAuditScope,
                                 capture: SharedMediaCaptureAuditEvidence?, checkpoint: () throws -> Void) throws -> Snapshot {
        try erasure.requireCurrent(context)
        return try verify(context: context, profile: erasure.profile, capture: capture, erasure: erasure, checkpoint: checkpoint)
    }

    private static func verify(context: ModelContext, profile: SharedMediaNativeAppProfile,
                               capture: SharedMediaCaptureAuditEvidence?, erasure: SharedMediaNativeErasureAuditScope?,
                               checkpoint: () throws -> Void) throws -> Snapshot {
        func requireCapture() throws {
            if let capture {
                guard capture.profile == profile else { throw SharedMediaStorageFailure.conflict }
                try capture.requireCurrent(context)
            } else { try SharedMediaStorageLookup.requireNoUnqualifiedCaptureArtifacts(context) }
        }
        try requireCapture()
        let scope = SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        let expected = try erasure?.header ?? SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
        func check() throws {
            try Task.checkCancellation(); try checkpoint()
            try requireCapture()
            guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
            if let erasure { try erasure.requireCurrent(context) } else if
                try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope) != expected {
                throw SharedMediaStorageFailure.conflict
            }
        }
        var expectedHolds: Int64 = 0, metadata: Int64 = 0, reserved: Int64 = 0
        var captureParents: Int64 = 0, captureChildren: Int64 = 0
        var capturePackages: [UUID: Int64] = [:]
        let submissions = try visit(context, FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(
            sortBy: [SortDescriptor(\.cursorKey)]), checkpoint: check) { row in
            if row.formatRaw == SharedMediaCaptureSubmission.Format.v1.rawValue {
                guard let capture else { throw SharedMediaStorageFailure.closed }
                try capture.requireCurrent(context)
                let receipt = try SharedMediaCaptureSubmissionReceipt.auditRead(row, in: context)
                guard receipt.submission.profile == profile,
                      receipt.submission.rootBindingSHA256 == capture.inventory.ledger.rootBindingSHA256,
                      receipt.submission.inventoryRevision < expected.inventory.revision else { throw SharedMediaStorageFailure.conflict }
                if case .accepted(let acceptance) = receipt.state,
                   acceptance.inventoryRevision > expected.inventory.revision { throw SharedMediaStorageFailure.conflict }
                if let release = receipt.release,
                   (release.releasedRevision ?? release.inventoryRevision) > expected.inventory.revision {
                    throw SharedMediaStorageFailure.conflict
                }
                if case .reserved = receipt.state {
                    guard capturePackages[receipt.submission.scanID] == nil,
                          capturePackages.count < PhotoPreparationPolicy.maximumPackages else { throw SharedMediaStorageFailure.capacity }
                    let journal = try SharedMediaCaptureDraftJournalReceipt.matching(scanID: receipt.submission.scanID,
                        generation: receipt.submission.generation, context: context)
                    let journalBytes = try journal.map { try SharedMediaStoragePolicy.add($0.metadataBytes, $0.futureBytes) } ?? 0
                    capturePackages[receipt.submission.scanID] = try SharedMediaStoragePolicy.add(receipt.submission.packageBytes, journalBytes)
                }
                captureParents = try SharedMediaStoragePolicy.add(captureParents, 1)
                captureChildren = try SharedMediaStoragePolicy.add(captureChildren, Int64(receipt.artifacts.count))
                metadata = try SharedMediaStoragePolicy.add(metadata, receipt.metadataBytes)
                reserved = try SharedMediaStoragePolicy.add(reserved, receipt.reservedBytes)
                return
            }
            let receipt = try accepted(row, context: context, profile: profile)
            expectedHolds = try SharedMediaStoragePolicy.add(expectedHolds, Int64(receipt.holds.requests.count))
            metadata = try SharedMediaStoragePolicy.add(metadata, receipt.metadataBytes)
        }
        var lastAuditedAssetID: UUID?
        let holds = try visit(context, FetchDescriptor<SharedMediaOrdinaryTransferRecord>(
            sortBy: [SortDescriptor(\.sourceAssetID), SortDescriptor(\.cursorKey)]), checkpoint: check) { row in
            let generation = row.submissionGeneration
            var query = FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(predicate: #Predicate {
                $0.submissionGeneration == generation
            })
            query.fetchLimit = 2
            let parents = try context.fetch(query)
            guard parents.count == 1, let parent = parents.first else { throw SharedMediaStorageFailure.conflict }
            let receipt = try accepted(parent, context: context, profile: profile)
            guard receipt.holds.requests.contains(where: { $0.id == row.id }),
                  row.inventoryID == profile.inventoryID, row.inventoryGeneration == profile.generation,
                  row.ownerID == profile.ownerID else { throw SharedMediaStorageFailure.conflict }
            // This complete per-source audit binds the saved seal, acquisition,
            // lease, asset generation and all current P1 + ordinary counts.
            if lastAuditedAssetID != row.sourceAssetID {
                let original = try SharedMediaNativeOriginalAccounting.auditAccountingEvidence(
                    assetID: row.sourceAssetID, inventoryID: profile.inventoryID, context: context, capture: capture, checkpoint: check)
                guard original.ownerID == profile.ownerID, original.retirement == nil else {
                    throw SharedMediaStorageFailure.conflict
                }
                lastAuditedAssetID = row.sourceAssetID
            }
        }
        try check()
        guard holds == expectedHolds else { throw SharedMediaStorageFailure.conflict }
        // Every artifact belongs to an exact parent or a validated source-only
        // draft. Unknown orphans cannot hide in the physical-only audit.
        if captureParents > 0 {
            guard let capture else { throw SharedMediaStorageFailure.conflict }
            let sources = try SharedMediaCaptureDraftSourceRecovery.unboundInventory(context: context,
                profile: profile, rootBindingSHA256: capture.inventory.ledger.rootBindingSHA256, checkpoint: check)
            guard try SharedMediaStoragePolicy.add(captureChildren, sources.artifactCount) == capture.inventory.ledger.artifacts else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        return .init(header: expected, submissions: submissions, holds: holds, metadataBytes: metadata, reservedBytes: reserved, capturePackages: capturePackages)
    }

    private static func accepted(_ row: SharedMediaOrdinarySubmissionRecord, context: ModelContext,
                                 profile: SharedMediaNativeAppProfile) throws -> SharedMediaOrdinarySubmissionReceipt.Snapshot {
        let receipt = try SharedMediaOrdinarySubmissionReceipt.read(row, in: context)
        guard case .accepted = receipt.state, receipt.submission.profile == profile else {
            throw SharedMediaStorageFailure.conflict
        }
        return receipt
    }

    private static func visit<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>,
                                                  checkpoint: () throws -> Void, body: (T) throws -> Void) throws -> Int64 {
        var query = descriptor, offset = 0, total: Int64 = 0
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        while true {
            try checkpoint(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows { try checkpoint(); try body(row) }
            try checkpoint()
            total = try SharedMediaStoragePolicy.add(total, Int64(rows.count))
            if rows.count < SharedMediaStoragePolicy.pageSize { return total }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            offset = next
        }
    }
}
