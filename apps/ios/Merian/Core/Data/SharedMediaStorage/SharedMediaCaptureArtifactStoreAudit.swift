import Foundation
import SwiftData

/// Complete, bounded-page capture ledger accounting. A saved snapshot is not a
/// file capability or an exemption for mutation, replay or final release.
@MainActor
enum SharedMediaCaptureArtifactStoreAudit {
    struct Snapshot: Equatable, Sendable {
        let header: SharedMediaNativeAppEligibility.Header
        let rootBindingSHA256: String
        let artifacts: Int64
        let metadataBytes: Int64
        let futureMetadataReservationBytes: Int64
        let materializedBytes: Int64
        let reservedBytes: Int64
    }

    /// The registered-root owner supplies its verified binding and retains the
    /// store fence. Never filter artifact rows by owner or inventory: corrupt
    /// scope fields must not hide liabilities from this reverse audit.
    static func verify(context: ModelContext, profile: SharedMediaNativeAppProfile,
                       rootBindingSHA256: String, checkpoint: () throws -> Void = {},
                       inspectArtifact: (SharedMediaCaptureArtifactLedger.Snapshot) throws -> Void = { _ in }) throws -> Snapshot {
        try verify(context: context, profile: profile, rootBindingSHA256: rootBindingSHA256,
            erasure: nil, checkpoint: checkpoint, inspectArtifact: inspectArtifact)
    }

    static func verifyForErasure(context: ModelContext, erasure: SharedMediaNativeErasureAuditScope,
                                 rootBindingSHA256: String, checkpoint: () throws -> Void,
                                 inspectArtifact: (SharedMediaCaptureArtifactLedger.Snapshot) throws -> Void) throws -> Snapshot {
        try erasure.requireCurrent(context)
        return try verify(context: context, profile: erasure.profile, rootBindingSHA256: rootBindingSHA256,
            erasure: erasure, checkpoint: checkpoint, inspectArtifact: inspectArtifact)
    }

    private static func verify(context: ModelContext, profile: SharedMediaNativeAppProfile, rootBindingSHA256: String,
                               erasure: SharedMediaNativeErasureAuditScope?, checkpoint: () throws -> Void,
                               inspectArtifact: (SharedMediaCaptureArtifactLedger.Snapshot) throws -> Void) throws -> Snapshot {
        guard SharedMediaAcquisitionEncoding.isHash(rootBindingSHA256) else { throw SharedMediaStorageFailure.conflict }
        let scope = SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        let expected = try erasure?.header ?? SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope)
        func check() throws {
            try Task.checkCancellation(); try checkpoint()
            guard !context.hasChanges, !context.container.mainContext.hasChanges else { throw SharedMediaStorageFailure.stale }
            if let erasure { try erasure.requireCurrent(context) } else if
                try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope) != expected {
                throw SharedMediaStorageFailure.stale
            }
        }
        func artifact(_ id: UUID) throws -> SharedMediaCaptureArtifactLedger.Snapshot {
            try check()
            if let erasure {
                return try SharedMediaCaptureArtifactLedger.auditErasureRead(id: id, profile: profile,
                    rootBindingSHA256: rootBindingSHA256, context: context, erasure: erasure)
            }
            return try SharedMediaCaptureArtifactLedger.auditRead(id: id, profile: profile,
                rootBindingSHA256: rootBindingSHA256, context: context)
        }
        var metadata: Int64 = 0, futureMetadata: Int64 = 0, materialized: Int64 = 0, reserved: Int64 = 0
        let count = try visit(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(
            sortBy: [SortDescriptor(\.cursorKey)]), checkpoint: check) { row in
            let value = try artifact(row.id)
            try inspectArtifact(value)
            try check()
            try requireNoPhotoAlias(value.request, context: context)
            if value.remoteStage != nil {
                guard let parent = try SharedMediaCaptureSubmissionReceipt.auditMatching(scanID: value.request.scanID,
                    generation: value.request.submissionGeneration, in: context), case .accepted = parent.state,
                      parent.artifacts.contains(value) else { throw SharedMediaStorageFailure.conflict }
            }
            let identityBytes = Int64((value.stage?.finalIdentity ?? value.stage?.partialIdentity)?.utf8.count ?? 0)
            metadata = try SharedMediaStoragePolicy.add(metadata, SharedMediaStoragePolicy.add(value.metadataBytes, identityBytes))
            if let retirement = value.retirement {
                if retirement.version == 2 { try SharedMediaCaptureAbortedPreparation.requireRetirement(value, context: context) }
                if retirement.releasedRevision == nil {
                    let saved = Int64(row.retirementData.map { $0.count + 64 } ?? 0)
                    futureMetadata = try SharedMediaStoragePolicy.add(futureMetadata,
                        Int64(SharedMediaCaptureArtifactRetirement.maximumBytes + 64) - saved)
                }
            } else if value.remoteStage == nil {
                futureMetadata = try SharedMediaStoragePolicy.add(futureMetadata, Int64(SharedMediaCaptureRemoteStage.maximumBytes + 64))
            }
            if let release = value.acceptedRelease, release.releasedRevision == nil {
                let saved = Int64(row.retirementData.map { $0.count + 64 } ?? 0)
                futureMetadata = try SharedMediaStoragePolicy.add(futureMetadata,
                    Int64(SharedMediaCaptureMemberRelease.maximumBytes + 64) - saved)
            }
            if value.releasedRevision != nil { return }
            if value.phase == .ready {
                materialized = try SharedMediaStoragePolicy.add(materialized, value.request.byteCount)
            } else {
                reserved = try SharedMediaStoragePolicy.add(reserved, value.request.byteCount)
                // A writing receipt still grows when it gains its completed
                // descriptor. Reserve the remaining bounded envelope and the
                // allocation's duplicated descriptor before materialization.
                let stageBytes = Int64(row.stageReceiptData.map { $0.count + 64 } ?? 0)
                let headroom = Int64(SharedMediaCaptureArtifactRequest.maximumEnvelopeBytes + 64 + 160)
                futureMetadata = try SharedMediaStoragePolicy.add(futureMetadata, headroom - stageBytes - identityBytes)
            }
        }
        let journals = try SharedMediaCaptureDraftJournalReceipt.inventory(context: context, profile: profile,
            rootBindingSHA256: rootBindingSHA256, checkpoint: check)
        metadata = try SharedMediaStoragePolicy.add(metadata, journals.metadata)
        futureMetadata = try SharedMediaStoragePolicy.add(futureMetadata, journals.future)
        let namespace = SharedMediaCaptureRootJournal.namespace
        let allocationCount = try visit(context, FetchDescriptor<SharedMediaAllocationRecord>(
            predicate: #Predicate { $0.namespaceRaw == namespace }, sortBy: [SortDescriptor(\.id)]), checkpoint: check) { row in
            let id = row.id
            let parent = try one(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.allocationID == id }))
            _ = try artifact(parent.id)
        }
        var referenceCount: Int64 = 0, leaseCount: Int64 = 0
        // Inspect all generic edges, including mislabelled and orphaned ones.
        // Non-capture allocations remain subject to their existing full audit.
        _ = try visit(context, FetchDescriptor<SharedMediaReferenceRecord>(sortBy: [SortDescriptor(\.id)]), checkpoint: check) { row in
            let id = row.allocationID
            let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
            if allocation.namespaceRaw == namespace {
                let parent = try one(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.allocationID == id }))
                guard try artifact(parent.id).request.referenceID == row.id else { throw SharedMediaStorageFailure.conflict }
                referenceCount = try SharedMediaStoragePolicy.add(referenceCount, 1)
            } else if row.roleRaw == namespace { throw SharedMediaStorageFailure.conflict }
        }
        _ = try visit(context, FetchDescriptor<SharedMediaLeaseRecord>(sortBy: [SortDescriptor(\.id)]), checkpoint: check) { row in
            let id = row.allocationID
            let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
            if allocation.namespaceRaw == namespace {
                let parent = try one(context, FetchDescriptor<SharedMediaOrdinaryArtifactRecord>(predicate: #Predicate { $0.allocationID == id }))
                guard try artifact(parent.id).request.leaseID == row.id else { throw SharedMediaStorageFailure.conflict }
                leaseCount = try SharedMediaStoragePolicy.add(leaseCount, 1)
            } else if row.purposeRaw == SharedMediaCaptureArtifactLedger.leasePurpose { throw SharedMediaStorageFailure.conflict }
        }
        try check()
        guard count == allocationCount, count == referenceCount, count == leaseCount else { throw SharedMediaStorageFailure.conflict }
        return .init(header: expected, rootBindingSHA256: rootBindingSHA256, artifacts: count,
            metadataBytes: metadata, futureMetadataReservationBytes: futureMetadata,
            materializedBytes: materialized, reservedBytes: reserved)
    }

    private static func requireNoPhotoAlias(_ request: SharedMediaCaptureArtifactRequest, context: ModelContext) throws {
        let asset = request.allocationID, lease = request.leaseID, reference = request.referenceID
        try absent(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == asset }))
        try absent(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset }))
        try absent(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == asset || $0.id == lease }))
        try absent(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.assetID == asset || $0.id == lease }))
        try absent(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == asset || $0.id == reference }))
        try absent(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate {
            $0.assetID == asset || $0.referenceID == reference || $0.leaseID == lease
        }))
    }

    private static func absent<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws {
        var query = descriptor; query.fetchLimit = 1
        guard try context.fetch(query).isEmpty else { throw SharedMediaStorageFailure.conflict }
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }

    private static func visit<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>,
                                                  checkpoint: () throws -> Void, body: (T) throws -> Void) throws -> Int64 {
        var query = descriptor, offset = 0, count: Int64 = 0
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        while true {
            try checkpoint(); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows { try checkpoint(); try body(row) }
            try checkpoint()
            count = try SharedMediaStoragePolicy.add(count, Int64(rows.count))
            if rows.count < SharedMediaStoragePolicy.pageSize { return count }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
    }
}
