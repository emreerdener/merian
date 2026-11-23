import Foundation
import SwiftData

/// Invocation-local read facts. Never a mutation, file, admission or release grant.
@MainActor
final class SharedMediaOrdinaryInspection {
    let profile: SharedMediaNativeAppProfile
    let snapshot: SharedMediaOrdinaryStoreAudit.Snapshot
    private let capture: SharedMediaCaptureArtifactInspection?
    private let containerID: ObjectIdentifier
    private enum Purpose { case ordinary, initialErasure }
    private let purpose: Purpose
    private var active = true

    private init(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                 snapshot: SharedMediaOrdinaryStoreAudit.Snapshot, capture: SharedMediaCaptureArtifactInspection? = nil,
                 purpose: Purpose = .ordinary) {
        self.containerID = ObjectIdentifier(container); self.profile = profile; self.snapshot = snapshot
        self.capture = capture; self.purpose = purpose
    }

    /// Returns only completed audit facts, never the special inspection. The
    /// scoped traversal must validate every receiving lifecycle before return;
    /// existing ordinary readers retain their advanced-receiving prohibition.
    static func auditInitialErasure(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                    capture: SharedMediaCaptureArtifactInspection?,
                                    header: @escaping () throws -> SharedMediaNativeAppEligibility.Header,
                                    betweenPages: @escaping () async throws -> Void) async throws -> SharedMediaNativeScopedSnapshot {
        let expected = try header()
        let check = { guard try header() == expected else { throw SharedMediaStorageFailure.stale } }
        let context = ModelContext(container); context.autosaveEnabled = false
        let snapshot = try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: profile,
            capture: capture, checkpoint: check)
        let inspection = Self(container: container, profile: profile, snapshot: snapshot, capture: capture, purpose: .initialErasure)
        defer { inspection.active = false }
        try inspection.requireCurrent(context)
        let result = try await SharedMediaNativeScopedAudit.runInitialErasureRead(container: container,
            profile: profile, header: header, betweenPages: betweenPages, ordinary: inspection)
        let fresh = ModelContext(container); fresh.autosaveEnabled = false
        try check(); try inspection.requireCurrent(fresh)
        guard try SharedMediaOrdinaryStoreAudit.verify(context: fresh, profile: profile,
            capture: capture, checkpoint: check) == snapshot else { throw SharedMediaStorageFailure.stale }
        return result
    }

    /// Explicit capture-aware read route. Default readers and every mutation
    /// route continue rejecting capture artifacts without this live scope.
    static func withVerifiedCapture<T>(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                       capture: SharedMediaCaptureArtifactInspection, checkpoint: () throws -> Void,
                                       body: (SharedMediaOrdinaryInspection) async throws -> T) async throws -> T {
        let context = ModelContext(container); context.autosaveEnabled = false
        try capture.requireCurrent(context)
        guard capture.profile == profile else { throw SharedMediaStorageFailure.conflict }
        let snapshot = try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: profile,
            capture: capture, checkpoint: checkpoint)
        let scope = Self(container: container, profile: profile, snapshot: snapshot, capture: capture)
        defer { scope.active = false }
        try scope.requireCurrent(context)
        let result = try await body(scope)
        let fresh = ModelContext(container); fresh.autosaveEnabled = false
        try checkpoint(); try scope.requireCurrent(fresh)
        guard try SharedMediaOrdinaryStoreAudit.verify(context: fresh, profile: profile,
            capture: capture, checkpoint: checkpoint) == snapshot else { throw SharedMediaStorageFailure.stale }
        return result
    }

    static func withVerified<T>(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                checkpoint: () throws -> Void,
                                body: (SharedMediaOrdinaryInspection?) async throws -> T) async throws -> T {
        let scope = try verified(container: container, profile: profile, checkpoint: checkpoint)
        defer { scope?.active = false }
        let result = try await body(scope)
        try checkpoint()
        if let scope {
            let context = ModelContext(container); context.autosaveEnabled = false
            try scope.requireCurrent(context)
            guard try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: profile,
                checkpoint: checkpoint) == scope.snapshot else { throw SharedMediaStorageFailure.stale }
        }
        return result
    }

    private static func verified(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                 checkpoint: () throws -> Void) throws -> SharedMediaOrdinaryInspection? {
        let context = ModelContext(container); context.autosaveEnabled = false
        try checkpoint()
        try SharedMediaStorageLookup.requireNoUnqualifiedCaptureArtifacts(context)
        if try context.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 0,
           try context.fetchCount(FetchDescriptor<SharedMediaOrdinaryTransferRecord>()) == 0 { return nil }
        let snapshot = try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: profile, checkpoint: checkpoint)
        let scope = Self(container: container, profile: profile, snapshot: snapshot)
        try scope.requireCurrent(context)
        return scope
    }

    /// Synchronous clean snapshot for an atomic owner's pre-save fence and
    /// post-save accounting. The inspection cannot escape or grant mutation.
    static func withVerifiedRead<T>(container: ModelContainer, profile: SharedMediaNativeAppProfile,
                                    checkpoint: () throws -> Void,
                                    body: (SharedMediaOrdinaryInspection?) throws -> T) throws -> T {
        let scope = try verified(container: container, profile: profile, checkpoint: checkpoint)
        defer { scope?.active = false }
        let result = try body(scope)
        try checkpoint()
        if let scope {
            let context = ModelContext(container); context.autosaveEnabled = false
            try scope.requireCurrent(context)
            guard try SharedMediaOrdinaryStoreAudit.verify(context: context, profile: profile,
                checkpoint: checkpoint) == scope.snapshot else { throw SharedMediaStorageFailure.stale }
        }
        return result
    }

    func requireCurrent(_ context: ModelContext) throws {
        try Task.checkCancellation()
        guard active, ObjectIdentifier(context.container) == containerID, !context.hasChanges,
              !context.container.mainContext.hasChanges else { throw SharedMediaStorageFailure.closed }
        if let capture { try capture.requireCurrent(context) } else {
            try SharedMediaStorageLookup.requireNoUnqualifiedCaptureArtifacts(context)
        }
        let scope = SharedMediaNativeScopeIdentity(inventoryID: profile.inventoryID, generation: profile.generation,
            ownerID: profile.ownerID, storeIdentity: profile.storeIdentity, rootBinding: try profile.rootIdentity)
        guard try SharedMediaNativeAppEligibility.snapshot(context: context, scope: scope) == snapshot.header else {
            throw SharedMediaStorageFailure.stale
        }
        if purpose == .initialErasure { return }
        // Advanced receiving lifecycles retain their own strict audits. They
        // cannot acquire an exemption through ordinary read inspection.
        let phase = FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.phaseRaw != "received" })
        let allocation = FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate {
            $0.allocationData != nil || $0.allocationSHA256 != nil
        })
        let admission = FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate {
            $0.initialAdmissionData != nil || $0.initialAdmissionSHA256 != nil
        })
        let completion = FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate {
            $0.initialCompletionData != nil || $0.initialCompletionSHA256 != nil
        })
        let release = FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate {
            $0.releaseStartData != nil || $0.releaseStartSHA256 != nil
        })
        for var query in [phase, allocation, admission, completion, release] {
            query.fetchLimit = 1
            guard try context.fetch(query).isEmpty else { throw SharedMediaStorageFailure.closed }
        }
    }

    func captureAllocation(_ id: UUID, context: ModelContext) throws {
        try requireCurrent(context)
        guard let capture else { throw SharedMediaStorageFailure.closed }
        try capture.allocation(id, context: context)
    }

    func original(_ assetID: UUID, inventoryID: UUID, context: ModelContext,
                  checkpoint: () throws -> Void = {}) throws -> SharedMediaNativeOriginalAccounting.Snapshot {
        try requireCurrent(context)
        guard inventoryID == profile.inventoryID else { throw SharedMediaStorageFailure.conflict }
        let result = try SharedMediaNativeOriginalAccounting.auditInspectedOrdinary(assetID: assetID,
            inventoryID: inventoryID, context: context, inspection: self, checkpoint: checkpoint)
        try requireCurrent(context)
        return result
    }

    /// Charge ordinary envelopes once, plus held sources outside the bounded
    /// pending graph. This does not introduce a retained-library package cap.
    func includeLiability(context: ModelContext, pendingAssets: Set<UUID>,
                          totals: inout SharedMediaStoragePolicy.Totals, checkpoint: () throws -> Void) throws {
        try requireCurrent(context)
        for (id, bytes) in snapshot.capturePackages { try totals.includePhotoPackage(id: id, bytes: bytes) }
        try capture?.includeLiability(context: context, totals: &totals)
        try totals.includePhotoPhysical(materialized: snapshot.metadataBytes, reserved: snapshot.reservedBytes)
        var query = FetchDescriptor<SharedMediaOrdinaryTransferRecord>(
            sortBy: [SortDescriptor(\.sourceAssetID), SortDescriptor(\.cursorKey)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        var offset = 0, previous: UUID?
        while true {
            try checkpoint(); try requireCurrent(context); query.fetchOffset = offset
            let rows = try context.fetch(query)
            for row in rows {
                try checkpoint(); try requireCurrent(context)
                let id = row.sourceAssetID
                if previous == id { continue }; previous = id
                if pendingAssets.contains(id) { continue }
                let source = try original(id, inventoryID: profile.inventoryID, context: context, checkpoint: checkpoint)
                let receipt = try SharedMediaNativePairPlanGraph.one(context,
                    FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == id }))
                guard case .completed(let request, let completion) = try SharedMediaAcquisitionReceipt.read(receipt) else {
                    throw SharedMediaStorageFailure.conflict
                }
                let metadata = try SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: completion)
                try totals.includePhotoPhysical(materialized: PhotoPreparationPolicy.add([source.byteCount, metadata,
                    Int64(source.physicalIdentity.utf8.count)]), reserved: 512 - Int64(source.physicalIdentity.utf8.count))
            }
            if rows.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
        try checkpoint(); try requireCurrent(context)
    }
}
