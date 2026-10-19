import Foundation
import SwiftData

/// Complete database-side original/receipt joins under the caller's store fence.
/// This read-only audit grants no admission, file, writer or cleanup authority.
/// Namespace, hashes and projected metadata accounting remain separate checks.
@MainActor
enum SharedMediaNativeAcquisitionGraph {
    static func audit(context: ModelContext, inventoryID: UUID) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        try requireNativeInventory(inventory)
        let allowed: [any PersistentModel.Type] = [SharedMediaInventoryRecord.self,
            SharedMediaMembershipBootstrapRecord.self, SharedMediaPendingMembershipRecord.self,
            SharedMediaAcquisitionReceiptRecord.self, PhotoPreparationRecord.self, PhotoPreparationAsset.self,
            PhotoPreparationReference.self, PhotoPreparationLease.self, SharedMediaAllocationRecord.self,
            SharedMediaReferenceRecord.self, SharedMediaLeaseRecord.self, SharedMediaAssetReferenceCountRecord.self,
            SharedMediaDerivativePairRecord.self, SharedMediaDerivativeWorkRecord.self]
        for type in CurrentSchema.models where !allowed.contains(where: { ObjectIdentifier($0) == ObjectIdentifier(type) }) {
            guard try SharedMediaStorageLookup.count(context, type) == 0 else { throw SharedMediaStorageFailure.closed }
        }
        guard try context.fetchCount(FetchDescriptor<SharedMediaInventoryRecord>()) == 1 else { throw SharedMediaStorageFailure.conflict }
        try page(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)])) { row in
            _ = try receipt(row, inventory: inventory, context: context)
            if row.phaseRaw == "reserved" || row.phaseRaw == "held" {
                try uniqueFutureReference(row, context: context)
            }
        }
        // Physical rows have exactly one acquisition receipt or native intent.
        // Both domains receive complete forward validation below.
        try page(context, FetchDescriptor<SharedMediaAllocationRecord>(sortBy: [SortDescriptor(\.id)])) { row in
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: row.id, context: context) != nil { return }
            let value = try full(assetID: row.id, context: context)
            _ = try receipt(value, inventory: inventory, context: context)
        }
        try page(context, FetchDescriptor<SharedMediaLeaseRecord>(sortBy: [SortDescriptor(\.id)])) { row in
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: row.allocationID, context: context) != nil { return }
            let id = row.id
            let value = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
            guard value.assetID == row.allocationID else { throw SharedMediaStorageFailure.conflict }
            _ = try receipt(value, inventory: inventory, context: context)
        }
        try page(context, FetchDescriptor<PhotoPreparationLease>(sortBy: [SortDescriptor(\.id)])) { row in
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: row.assetID, context: context) != nil { return }
            let value = try full(assetID: row.assetID, context: context)
            guard value.id == row.id, ["reserved", "held"].contains(value.phaseRaw) else { throw SharedMediaStorageFailure.conflict }
        }
        try page(context, FetchDescriptor<PhotoPreparationAsset>(sortBy: [SortDescriptor(\.id)])) { row in
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: row.id, context: context) != nil { return }
            guard try full(assetID: row.id, context: context).phaseRaw == "completed" else { throw SharedMediaStorageFailure.conflict }
        }
        try page(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(sortBy: [SortDescriptor(\.id)])) { row in
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: row.id, context: context) != nil { return }
            guard try full(assetID: row.id, context: context).phaseRaw == "completed" else { throw SharedMediaStorageFailure.conflict }
        }
        try page(context, FetchDescriptor<PhotoPreparationReference>(sortBy: [SortDescriptor(\.id)])) { row in
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: row.assetID, context: context) != nil { return }
            guard try full(assetID: row.assetID, context: context).phaseRaw == "completed" else { throw SharedMediaStorageFailure.conflict }
        }
        try page(context, FetchDescriptor<SharedMediaReferenceRecord>(sortBy: [SortDescriptor(\.id)])) { row in
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: row.allocationID, context: context) != nil { return }
            guard try full(assetID: row.allocationID, context: context).phaseRaw == "completed" else { throw SharedMediaStorageFailure.conflict }
        }
        try page(context, FetchDescriptor<PhotoPreparationRecord>(sortBy: [SortDescriptor(\.id)])) { row in
            try package(row, context: context)
        }
        try SharedMediaNativePairPlanGraph.audit(context: context, inventory: inventory)
        let pending = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
        try pending.validateMembership(in: context, inventory: inventory)
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
    }

    /// Read the persisted request first. Exact caller matching is additional;
    /// fresh admission preconditions must never precede completed replay lookup.
    static func receipt(_ row: SharedMediaAcquisitionReceiptRecord, inventory: SharedMediaInventoryRecord,
                        context: ModelContext) throws -> SharedMediaAcquisitionReceipt {
        try requireNativeInventory(inventory)
        return try receiptFacts(row, inventory: inventory, context: context)
    }

    static func scopedReceipt(_ row: SharedMediaAcquisitionReceiptRecord, inventory: SharedMediaInventoryRecord,
                              context: ModelContext, format: SharedMediaNativeScopedFormat = .existingV1, checkpoint: () throws -> Void = {}) throws -> SharedMediaAcquisitionReceipt {
        try format.requireProfile(inventory)
        return try receiptFacts(row, inventory: inventory, context: context, checkpoint: checkpoint)
    }

    private static func receiptFacts(_ row: SharedMediaAcquisitionReceiptRecord, inventory: SharedMediaInventoryRecord,
                                     context: ModelContext, checkpoint: () throws -> Void = {}) throws -> SharedMediaAcquisitionReceipt {
        guard !context.hasChanges, row.inventoryID == inventory.id,
              row.inventoryGeneration == inventory.generation else { throw SharedMediaStorageFailure.conflict }
        let value = try SharedMediaAcquisitionReceipt.read(row)
        switch value {
        case .released:
            let id = row.id
            guard try context.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id })) == 0,
                  try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id })) == 0 else {
                throw SharedMediaStorageFailure.conflict
            }
        case .reserved(let request): try pending(request, held: false, inventory: inventory, context: context)
        case .held(let request): try pending(request, held: true, inventory: inventory, context: context)
        case .completed(let request, let result):
            let snapshot = try SharedMediaNativeOriginalAccounting.audit(assetID: request.assetID, inventoryID: inventory.id, context: context, checkpoint: checkpoint)
            let assetID = request.assetID, operationID = request.operationID
            let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
            let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
            let descriptor = snapshot.retirement?.proof.file ?? snapshot.physicalIdentity
            guard try full(assetID: assetID, context: context).id == operationID,
                  snapshot.assetGeneration == request.assetGeneration, snapshot.ownerID == request.ownerID,
                  snapshot.leaseID == operationID, snapshot.leaseEpoch == request.writerEpoch,
                  allocation.packageID == request.packageID, snapshot.fileToken == request.finalToken,
                  snapshot.byteCount == result.byteCount, snapshot.sha256 == result.sha256,
                  snapshot.contentType == result.contentType, descriptor == result.descriptor.file,
                  asset.acquisitionKindRaw == request.kind.rawValue,
                  inventory.revision >= result.inventoryRevision,
                  try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == operationID || $0.assetID == assetID })) == 0 else {
                throw SharedMediaStorageFailure.conflict
            }
            if let retiring = snapshot.retirement {
                guard retiring.proof == result.descriptor else { throw SharedMediaStorageFailure.conflict }
            }
            let referenceID = request.referenceID, packageID = request.packageID
            var original = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID }); original.fetchLimit = 2
            let originals = try context.fetch(original)
            guard originals.count <= 1 else { throw SharedMediaStorageFailure.conflict }
            if let ref = originals.first {
                guard ref.assetID == request.assetID, ref.packageID == packageID,
                      ref.ownerID == request.ownerID, ref.roleRaw == "original", ref.ordinal == request.ordinal,
                      ref.revision >= result.referenceRevision else { throw SharedMediaStorageFailure.conflict }
            }
            var origin = FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }); origin.fetchLimit = 2
            let origins = try context.fetch(origin)
            guard origins.count <= 1 else { throw SharedMediaStorageFailure.conflict }
            if let package = origins.first {
                guard package.ownerID == request.ownerID, package.draftGeneration == request.draftGeneration,
                      package.revision >= result.packageRevision else { throw SharedMediaStorageFailure.conflict }
                if package.accountingTierRaw == "pending" {
                    let member = try one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
                    guard member.revision >= result.membershipRevision else { throw SharedMediaStorageFailure.conflict }
                }
            }
            // The original logical reference and origin package can have been
            // removed. Surviving paired references are audited independently.
        }
        return value
    }

    private static func pending(_ request: SharedMediaAcquisitionIntent, held: Bool,
                                inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        let assetID = request.assetID, operationID = request.operationID, packageID = request.packageID
        let referenceID = request.referenceID
        let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        let lease = try one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.allocationID == assetID }))
        let work = try one(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.assetID == assetID }))
        let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let closing = allocation.stateRaw == "p1PendingCleanupV1"
        let closure = try work.terminalProof.map { try SharedMediaNativePendingClosure.decode($0, request: request) }
        guard closing == (closure != nil) else { throw SharedMediaStorageFailure.conflict }
        let minimumPackage: Int64
        switch request.packageExpectation {
        case .absent: minimumPackage = held ? 1 : 0
        case .revision(let value): minimumPackage = value + (held ? 2 : 1)
        }
        guard try full(assetID: assetID, context: context).id == operationID,
              inventory.revision >= (try SharedMediaStoragePolicy.add(request.expectedInventoryRevision, (held ? 2 : 1) + (closing ? 1 : 0))),
              allocation.inventoryID == inventory.id, allocation.accountID == request.ownerID,
              allocation.packageID == packageID, allocation.namespaceRaw == SharedMediaPhotoLedger.namespace,
              allocation.poolRaw == "durable", allocation.fileToken == request.finalToken,
              allocation.stateRaw == (closing ? "p1PendingCleanupV1" : (held ? "p1Held" : "p1Reserved")), allocation.materializedBytes == 0,
              allocation.reservedBytes == request.maximumBytes, allocation.physicalIdentity == nil,
              lease.id == operationID, lease.processEpoch == request.writerEpoch,
              lease.purposeRaw == "p1AcquireV1", lease.stateRaw == (closing ? "closedPendingCleanupV1" : (held ? "unknown" : "open")),
              work.id == operationID, work.packageID == packageID, work.ownerID == request.ownerID,
              work.processEpoch == request.writerEpoch, work.purposeRaw == "acquire",
              work.partialFileToken == request.partialToken, work.finalFileToken == request.finalToken,
              work.reservedByteCount == request.maximumBytes, work.allocatedByteCount == 0,
              work.sourceIdentity == nil,
              work.writerStateRaw == (closing ? "closedPendingCleanupV1" : (held ? "unknown" : "open")),
              package.ownerID == request.ownerID, package.draftGeneration == request.draftGeneration,
              package.accountingTierRaw == "pending", !package.retirementRequested,
              package.revision >= (try SharedMediaStoragePolicy.add(minimumPackage, closing ? 1 : 0)),
              (held || closing) ? package.phaseRaw == "needsAttention" : ["acquiring", "needsAttention"].contains(package.phaseRaw),
              try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID })) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID })) == 0,
              try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.allocationID == assetID })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private static func uniqueFutureReference(_ row: SharedMediaAcquisitionReceiptRecord, context: ModelContext) throws {
        guard let bytes = row.requestData else { throw SharedMediaStorageFailure.conflict }
        let request = try SharedMediaAcquisitionIntent.decode(bytes)
        try page(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)])) { other in
            guard other.id != row.id, let data = other.requestData else { return }
            let candidate = try SharedMediaAcquisitionIntent.decode(data)
            guard candidate.referenceID != request.referenceID else { throw SharedMediaStorageFailure.conflict }
        }
    }

    static func validatePresentation(_ presentation: [PhotoPreparationImagePresentation], package: PhotoPreparationRecord, context: ModelContext) throws {
        for photo in presentation {
            let id = photo.referenceID
            let ref = try one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id }))
            let edge = try one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id }))
            let assetID = ref.assetID
            let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
            guard ref.packageID == package.id, ref.ownerID == package.ownerID, ref.roleRaw == "original", ref.isLive,
                  asset.ownerID == package.ownerID, asset.cleanupStateRaw == "ready",
                  edge.allocationID == assetID, edge.accountID == package.ownerID, edge.stateRaw == "live",
                  edge.ownerID == id.uuidString.lowercased(), edge.roleRaw == SharedMediaPhotoLedger.namespace else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    static func scopedPendingPackage(_ row: PhotoPreparationRecord, inventory: SharedMediaInventoryRecord,
                                     context: ModelContext, format: SharedMediaNativeScopedFormat = .existingV1) throws {
        try format.requireProfile(inventory)
        guard row.accountingTierRaw == "pending" else { throw SharedMediaStorageFailure.conflict }
        try package(row, context: context, scopedInventory: inventory)
    }

    private static func package(_ row: PhotoPreparationRecord, context: ModelContext, scopedInventory: SharedMediaInventoryRecord? = nil) throws {
        let id = row.id
        guard row.draftID == id, row.contractVersion == PhotoPreparationPolicy.contract, row.revision >= 0,
              ["pending", "retained"].contains(row.accountingTierRaw),
              ["draftOwned", "acquiring", "needsAttention", "preparing", "preparedHeld"].contains(row.phaseRaw) else { throw SharedMediaStorageFailure.conflict }
        let envelope = try SharedMediaNativeDraftEnvelope.decode(row.supportingContextData)
        try validatePresentation(envelope.presentation, package: row, context: context)
        var refsQuery = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == id }); refsQuery.fetchLimit = 7
        var workQuery = FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.packageID == id }); workQuery.fetchLimit = 7
        let refs = try context.fetch(refsQuery), jobs = try context.fetch(workQuery)
        guard refs.count <= 6, jobs.count <= 6,
              !refs.isEmpty || !jobs.isEmpty || row.accountingTierRaw == "pending",
              row.accountingTierRaw == "pending" || jobs.isEmpty else { throw SharedMediaStorageFailure.conflict }
        var ordinals = Set<Int64>(), allocated: Int64 = 0
        for ref in refs {
            if ref.roleRaw == "original" {
                guard ordinals.insert(ref.ordinal).inserted else { throw SharedMediaStorageFailure.conflict }
            } else {
                guard try SharedMediaNativePairFileGraph.nativeWork(assetID: ref.assetID, context: context) != nil else { throw SharedMediaStorageFailure.conflict }
            }
            let assetID = ref.assetID
            let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
            allocated = try SharedMediaStoragePolicy.add(allocated, asset.byteCount)
        }
        var held = false, acquisitionJobs = 0
        for work in jobs {
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: work.assetID, context: context) != nil { continue }
            acquisitionJobs += 1
            let value = try SharedMediaAcquisitionReceipt.read(full(assetID: work.assetID, context: context))
            let intent: SharedMediaAcquisitionIntent
            switch value {
            case .reserved(let request): intent = request; held = held || work.writerStateRaw == "closedPendingCleanupV1"
            case .held(let request): intent = request; held = true
            default: throw SharedMediaStorageFailure.conflict
            }
            guard ordinals.insert(intent.ordinal).inserted else { throw SharedMediaStorageFailure.conflict }
        }
        guard ordinals.count <= 2 else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaNativePreparationGraph.validate(envelope, package: row, context: context, scopedInventory: scopedInventory)
        let activePairs = try context.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == id && $0.phaseRaw != "ready" }))
        guard activePairs <= 1 else { throw SharedMediaStorageFailure.conflict }
        let frozen: Bool
        if case .preparation(let value) = envelope { frozen = value.frozen != nil } else { frozen = false }
        let expectedPhase = frozen ? "preparedHeld" : envelope.attempt != nil ? "preparing" : activePairs > 0 ? "needsAttention"
            : held ? "needsAttention" : acquisitionJobs == 0 ? "draftOwned" : "acquiring"
        guard allocated == row.allocatedByteCount, row.phaseRaw == expectedPhase else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private static func requireNativeInventory(_ row: SharedMediaInventoryRecord) throws {
        guard row.revision >= 0, row.modeRaw == "nativeQualificationV1",
              row.phaseRaw == "readyNativeAccountingV1", row.cursor.isEmpty else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private static func full(assetID: UUID, context: ModelContext) throws -> SharedMediaAcquisitionReceiptRecord {
        let row = try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
        guard ["reserved", "held", "completed"].contains(row.phaseRaw) else { throw SharedMediaStorageFailure.conflict }
        return row
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }

    private static func page<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>,
                                               body: (T) throws -> Void) throws {
        var query = descriptor, offset = 0; query.fetchLimit = SharedMediaStoragePolicy.pageSize
        while true {
            query.fetchOffset = offset
            try Task.checkCancellation()
            let rows = try context.fetch(query)
            for row in rows { try body(row) }
            if rows.count < SharedMediaStoragePolicy.pageSize { return }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            offset = next
        }
    }
}
