import Foundation
import SwiftData

/// Closed synchronous preparation of one native original transition. The
/// repository supplies its unchanged fences and owns the sole save boundary.
/// Contexts/models never escape. This helper grants no file or loader authority.
@MainActor
final class SharedMediaNativeAcquisitionMutation {
    private let context: ModelContext
    private let container: ModelContainer
    private var reservation = false
    private let inventory: SharedMediaInventoryRecord
    private let request: SharedMediaAcquisitionIntent
    private enum Authority {
        case qualification(SharedMediaNativeMutationAuthority), app(SharedMediaNativeAppAcquisitionWitness)
        var binding: SharedMediaNativeBinding { switch self { case .qualification(let value): value.binding; case .app(let value): value.authority.binding } }
        var ownerID: UUID { switch self { case .qualification(let value): value.ownerID; case .app(let value): value.authority.profile.ownerID } }
        var writerEpoch: UUID { switch self { case .qualification(let value): value.writerEpoch; case .app(let value): value.authority.writerEpoch } }
        @MainActor func validate(_ container: ModelContainer) throws {
            switch self { case .qualification(let value): try value.validate(); case .app(let value): try value.validate(container) }
        }
    }
    private let authority: Authority
    private var transition = ""
    private let before: Before
    private var appAfter: SharedMediaNativeAppMetadataFacts?
    private var prepared = false
    private var consumed = false

    private init(container: ModelContainer, request: SharedMediaAcquisitionIntent, authority: Authority) throws {
        try authority.validate(container)
        try request.validate()
        guard request.ownerID == authority.ownerID, request.writerEpoch == authority.writerEpoch else { throw SharedMediaStorageFailure.conflict }
        self.authority = authority; self.container = container
        self.request = request
        context = ModelContext(container); context.autosaveEnabled = false
        let inventoryID = request.inventoryID, ownerID = request.ownerID
        inventory = try Self.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard inventory.generation == request.inventoryGeneration else { throw SharedMediaStorageFailure.conflict }
        switch authority {
        case .qualification:
            guard try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.ownerID != ownerID })) == 0,
                  try context.fetchCount(FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.ownerID != ownerID })) == 0 else { throw SharedMediaStorageFailure.conflict }
            let expectedBinding = try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])
            guard !authority.binding.initializing, authority.binding.bytes == expectedBinding else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
        case .app(let witness):
            guard witness.request == request, try SharedMediaNativeAppEligibility.profile(inventory) == witness.authority.profile else { throw SharedMediaStorageFailure.conflict }
        }
        before = try Before(context: context, inventory: inventory, request: request)
    }

    static func reserve(container: ModelContainer, request: SharedMediaAcquisitionIntent, authority: SharedMediaNativeMutationAuthority,
                        availableBytes: Int64) throws -> SharedMediaNativeAcquisitionMutation {
        let value = try Self(container: container, request: request, authority: .qualification(authority))
        try value.reserve(availableBytes: availableBytes)
        return value
    }

    static func complete(container: ModelContainer, request: SharedMediaAcquisitionIntent, authority: SharedMediaNativeMutationAuthority,
                         proof: SharedMediaPhotoRetirementInspection) throws -> SharedMediaNativeAcquisitionMutation {
        let value = try Self(container: container, request: request, authority: .qualification(authority))
        try value.complete(proof: proof)
        return value
    }
    static func reserve(container: ModelContainer, witness: SharedMediaNativeAppAcquisitionWitness, availableBytes: Int64) throws -> SharedMediaNativeAcquisitionMutation {
        guard witness.authority.settlementRequest == nil else { throw SharedMediaStorageFailure.closed }
        let value = try Self(container: container, request: witness.request, authority: .app(witness))
        try value.reserve(availableBytes: availableBytes); return value
    }
    static func complete(container: ModelContainer, witness: SharedMediaNativeAppAcquisitionWitness, proof: SharedMediaPhotoRetirementInspection) throws -> SharedMediaNativeAcquisitionMutation {
        guard witness.authority.settlementRequest == nil else { throw SharedMediaStorageFailure.closed }
        let value = try Self(container: container, request: witness.request, authority: .app(witness))
        try value.complete(proof: proof); return value
    }
    private func complete(proof: SharedMediaPhotoRetirementInspection) throws {
        guard proof.binding == authority.binding.bytes, proof.epoch == authority.binding.epoch,
              proof.file.assetID == request.assetID, proof.file.generation == request.assetGeneration,
              proof.file.token == request.finalToken else { throw SharedMediaStorageFailure.conflict }
        let result = try SharedMediaAcquisitionResult(request: request, inventoryRevision: increment(inventory.revision),
            packageRevision: increment(package().revision), membershipRevision: increment(member().revision),
            byteCount: proof.file.byteCount, sha256: proof.file.sha256, contentType: proof.file.contentType, descriptor: proof.identity)
        try complete(result)
    }

    static func hold(container: ModelContainer, request: SharedMediaAcquisitionIntent, authority: SharedMediaNativeMutationAuthority) throws -> SharedMediaNativeAcquisitionMutation {
        let value = try Self(container: container, request: request, authority: .qualification(authority))
        try value.hold()
        return value
    }

    static func hold(container: ModelContainer, witness: SharedMediaNativeAppAcquisitionWitness) throws -> SharedMediaNativeAcquisitionMutation {
        guard witness.authority.settlementRequest == witness.request else { throw SharedMediaStorageFailure.closed }
        let value = try Self(container: container, request: witness.request, authority: .app(witness))
        try value.hold(); return value
    }

    /// One attempt only. A thrown save is not evidence that it did not commit;
    /// discard this context and resolve through fresh exact graph readback.
    func save() throws {
        guard prepared, !consumed else { throw SharedMediaStorageFailure.closed }
        consumed = true
        try authority.validate(container)
        if reservation {
            let fresh = ModelContext(container); fresh.autosaveEnabled = false
            let inventoryID = request.inventoryID
            if case .qualification = authority { try SharedMediaNativeAcquisitionGraph.audit(context: fresh, inventoryID: inventoryID) }
            if case .app = authority { try SharedMediaNativeAppAcquisitionIdentity.direct(request, context: fresh) }
            let current = try Self.one(fresh, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            guard current.revision == request.expectedInventoryRevision else { throw SharedMediaStorageFailure.stale }
            try requireNoUnfinished(fresh)
        }
        if case .app = authority { try poststate(final: true).validate(context: context, inventory: inventory) }
        do { try context.save() } catch { context.rollback(); throw error }
    }

    private func reserve(availableBytes: Int64) throws {
        try requireNoUnfinished(context)
        reservation = true; transition = "reserve"
        guard inventory.revision == request.expectedInventoryRevision else { throw SharedMediaStorageFailure.stale }
        try requireFreshIDs()
        if isApp { try SharedMediaNativePreparationGraph.requireIdleFiles(context, scopedInventory: inventory, allowSavedOriginalRetirements: true) }
        else {
            guard try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0,
                  try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.cleanupStateRaw != "ready" })) == 0 else { throw PhotoPreparationFailure.cleanupPending }
        }
        let packageID = request.packageID
        let existing = try Self.optional(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let package: PhotoPreparationRecord
        switch (request.packageExpectation, existing) {
        case (.absent, nil):
            package = PhotoPreparationRecord(id: packageID, ownerID: request.ownerID,
                contractVersion: PhotoPreparationPolicy.contract, draftID: packageID, draftGeneration: request.draftGeneration,
                revision: 0, phaseRaw: "acquiring", supportingContextData: before.contexts,
                allocatedByteCount: 0, retirementRequested: false)
            context.insert(package)
        case (.revision(let expected), .some(let row)):
            guard row.revision == expected, row.ownerID == request.ownerID, row.draftGeneration == request.draftGeneration,
                  row.accountingTierRaw == "pending", row.phaseRaw == "draftOwned", !row.retirementRequested else {
                throw SharedMediaStorageFailure.stale
            }
            package = row
            package.revision = try increment(package.revision); package.phaseRaw = "acquiring"
        default: throw SharedMediaStorageFailure.stale
        }
        var query = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == packageID && $0.roleRaw == "original" }); query.fetchLimit = 3
        let references = try context.fetch(query)
        guard references.count < 2, references.allSatisfy({ $0.isLive && $0.roleRaw == "original" && $0.ordinal != request.ordinal }) else {
            throw SharedMediaStorageFailure.capacity
        }
        context.insert(SharedMediaAcquisitionReceiptRecord(operationID: request.operationID, inventoryID: request.inventoryID,
            inventoryGeneration: request.inventoryGeneration, ownerID: request.ownerID, requestFingerprint: try request.fingerprint(),
            packageID: packageID, assetID: request.assetID, requestData: try request.encoded()))
        context.insert(SharedMediaAllocationRecord(id: request.assetID, inventoryID: request.inventoryID, accountID: request.ownerID,
            packageID: packageID, namespaceRaw: SharedMediaPhotoLedger.namespace, fileToken: request.finalToken, poolRaw: "durable",
            stateRaw: "p1Reserved", materializedBytes: 0, reservedBytes: request.maximumBytes, physicalIdentity: nil))
        context.insert(SharedMediaLeaseRecord(id: request.operationID, allocationID: request.assetID, processEpoch: request.writerEpoch,
            purposeRaw: "p1AcquireV1", stateRaw: "open"))
        context.insert(PhotoPreparationLease(id: request.operationID, packageID: packageID, assetID: request.assetID, ownerID: request.ownerID,
            processEpoch: request.writerEpoch, purposeRaw: "acquire", partialFileToken: request.partialToken, finalFileToken: request.finalToken,
            reservedByteCount: request.maximumBytes, allocatedByteCount: 0, writerStateRaw: "open", terminalProof: nil))
        inventory.revision = try increment(inventory.revision)
        _ = try updateMembership(package, creating: existing == nil)
        try validateCommon(phase: "acquiring", addedBytes: 0, membershipChanged: true)
        try validatePending(held: false)
        try finish(availableBytes: availableBytes)
    }

    private func complete(_ result: SharedMediaAcquisitionResult) throws {
        transition = "complete"
        let row = try receipt()
        guard case .reserved = try readReceipt(row) else {
            throw SharedMediaStorageFailure.conflict
        }
        try result.validate(request: request)
        let package = try package(), allocation = try allocation(), lease = try lease(), work = try work()
        let member = try member()
        guard result.inventoryRevision == (try increment(inventory.revision)),
              result.packageRevision == (try increment(package.revision)),
              result.membershipRevision == (try increment(member.revision)) else { throw SharedMediaStorageFailure.stale }
        context.insert(PhotoPreparationAsset(id: request.assetID, ownerID: request.ownerID, generation: request.assetGeneration,
            fileToken: request.finalToken, contentType: result.contentType, byteCount: result.byteCount, sha256: result.sha256,
            acquisitionKindRaw: request.kind.rawValue, cleanupStateRaw: "ready"))
        context.insert(PhotoPreparationReference(id: request.referenceID, packageID: request.packageID, assetID: request.assetID,
            ownerID: request.ownerID, roleRaw: "original", ordinal: request.ordinal, revision: 0, isLive: true))
        context.insert(SharedMediaReferenceRecord(id: request.referenceID, allocationID: request.assetID, accountID: request.ownerID,
            ownerID: request.referenceID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        context.insert(SharedMediaAssetReferenceCountRecord(assetID: request.assetID, assetGeneration: request.assetGeneration,
            inventoryID: request.inventoryID, inventoryGeneration: request.inventoryGeneration, ownerID: request.ownerID, liveCount: 1))
        allocation.stateRaw = "p1Materialized"; allocation.materializedBytes = result.byteCount
        allocation.reservedBytes = 0; allocation.physicalIdentity = result.descriptor.file
        lease.stateRaw = "closed"; context.delete(work)
        row.phaseRaw = "completed"; row.revision = 1; row.resultData = try result.encoded(request: request)
        package.allocatedByteCount = try SharedMediaStoragePolicy.add(package.allocatedByteCount, result.byteCount)
        package.phaseRaw = "draftOwned"; package.revision = result.packageRevision
        inventory.revision = result.inventoryRevision
        guard try updateMembership(package, creating: false).revision == result.membershipRevision else { throw SharedMediaStorageFailure.conflict }
        try validateCommon(phase: "draftOwned", addedBytes: result.byteCount, membershipChanged: true)
        try validateCompleted(result)
        try finish(availableBytes: nil)
    }

    private func hold() throws {
        transition = "hold"
        let row = try receipt()
        guard case .reserved = try readReceipt(row) else {
            throw SharedMediaStorageFailure.conflict
        }
        let package = try package(), allocation = try allocation(), lease = try lease(), work = try work()
        row.phaseRaw = "held"; row.revision = 1; allocation.stateRaw = "p1Held"
        lease.stateRaw = "unknown"; work.writerStateRaw = "unknown"
        package.phaseRaw = "needsAttention"; package.revision = try increment(package.revision)
        inventory.revision = try increment(inventory.revision)
        try validateCommon(phase: "needsAttention", addedBytes: 0, membershipChanged: false)
        try validatePending(held: true)
        try finish(availableBytes: nil)
    }

    private func finish(availableBytes: Int64?) throws {
        let budget: SharedMediaNativeAcquisitionBudget.Snapshot
        if isApp {
            budget = try SharedMediaNativeAcquisitionBudget.evaluateAcquisitionPoststate(context: context, inventory: inventory, proof: poststate(final: true))
        } else {
            let graph = try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
            try graph.validateMembership(in: context, inventory: inventory)
            budget = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        }
        if let availableBytes { try budget.totals.checkAvailable(availableBytes) }
        if isApp { appAfter = try SharedMediaNativeAppMetadataFacts.acquisitionPoststate(context, inventory: inventory, proof: poststate(final: true)) }
        prepared = true
    }
    func acknowledgeApp() throws -> SharedMediaNativeAppMetadataFacts {
        guard prepared, case .app(let witness) = authority, let appAfter,
              try witness.authority.header(container) == SharedMediaNativeAppMetadataFacts.successor(witness.expected) else { throw SharedMediaStorageFailure.stale }
        let fresh = ModelContext(container); fresh.autosaveEnabled = false
        guard try SharedMediaNativeAppMetadataFacts.capture(fresh, profile: witness.authority.profile) == appAfter else { throw SharedMediaStorageFailure.conflict }
        return appAfter
    }
    private var isApp: Bool { if case .app = authority { true } else { false } }
    private func readReceipt(_ row: SharedMediaAcquisitionReceiptRecord) throws -> SharedMediaAcquisitionReceipt {
        if isApp { return try SharedMediaNativeAcquisitionGraph.scopedReceipt(row, inventory: inventory, context: context, format: .appV2) }
        return try SharedMediaNativeAcquisitionGraph.receipt(row, inventory: inventory, context: context)
    }
    private func requireNoUnfinished(_ context: ModelContext) throws {
        guard isApp else { try SharedMediaNativePreparationGraph.requireNoUnfinished(context); return }
        try SharedMediaNativePreparationGraph.requireNoUnfinished(context, inventory: inventory, targetPackageID: request.packageID)
    }
    private func projection(final: Bool) throws -> SharedMediaPendingGraph {
        if isApp { return try SharedMediaPendingGraph.deriveAcquisitionPoststate(in: context, inventory: inventory, proof: poststate(final: final)) }
        return try SharedMediaPendingGraph.derive(in: context, inventory: inventory)
    }
    private func updateMembership(_ package: PhotoPreparationRecord, creating: Bool) throws -> SharedMediaPendingMembershipRecord {
        let bytes = try projection(final: false).membership(packageID: package.id).encoded()
        if creating {
            let row = SharedMediaPendingMembershipRecord(packageID: package.id, inventoryID: inventory.id,
                inventoryGeneration: inventory.generation, ownerID: package.ownerID, draftGeneration: package.draftGeneration, membersData: bytes)
            context.insert(row); return row
        }
        let row = try member(); row.membersData = bytes; row.revision = try increment(row.revision); return row
    }

    /// Only the owned transition's rows changed after the pristine full audit.
    /// Keep that auditor strict; these exact postconditions cover the dirty rows.
    private func validatePending(held: Bool) throws {
        let row = try receipt(), package = try package(), allocation = try allocation(), lease = try lease(), work = try work()
        let value = try SharedMediaAcquisitionReceipt.read(row, expected: request)
        guard value == (held ? .held(request) : .reserved(request)),
              allocation.id == request.assetID, allocation.accountID == request.ownerID, allocation.inventoryID == inventory.id,
              allocation.packageID == request.packageID, allocation.fileToken == request.finalToken,
              allocation.namespaceRaw == SharedMediaPhotoLedger.namespace, allocation.poolRaw == "durable",
              allocation.stateRaw == (held ? "p1Held" : "p1Reserved"), allocation.reservedBytes == request.maximumBytes,
              allocation.materializedBytes == 0, allocation.physicalIdentity == nil,
              lease.id == request.operationID, lease.allocationID == request.assetID, lease.processEpoch == request.writerEpoch, lease.purposeRaw == "p1AcquireV1",
              lease.stateRaw == (held ? "unknown" : "open"), work.id == request.operationID, work.assetID == request.assetID, work.ownerID == request.ownerID,
              work.packageID == request.packageID, work.processEpoch == request.writerEpoch, work.purposeRaw == "acquire",
              work.partialFileToken == request.partialToken, work.finalFileToken == request.finalToken,
              work.reservedByteCount == request.maximumBytes, work.allocatedByteCount == 0,
              work.writerStateRaw == (held ? "unknown" : "open"), work.terminalProof == nil, work.sourceIdentity == nil,
              package.phaseRaw == (held ? "needsAttention" : "acquiring") else { throw SharedMediaStorageFailure.conflict }
    }

    private func validateCompleted(_ result: SharedMediaAcquisitionResult) throws {
        let row = try receipt(), assetID = request.assetID, referenceID = request.referenceID, operationID = request.operationID
        let asset = try Self.one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        let ref = try Self.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID }))
        let edge = try Self.one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID }))
        let count = try Self.one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        let allocation = try allocation(), lease = try lease(), package = try package()
        guard try SharedMediaAcquisitionReceipt.read(row, expected: request) == .completed(request, result),
              asset.generation == request.assetGeneration, asset.ownerID == request.ownerID, asset.fileToken == request.finalToken,
              asset.byteCount == result.byteCount, asset.sha256 == result.sha256, asset.contentType == result.contentType,
              asset.acquisitionKindRaw == request.kind.rawValue, asset.cleanupStateRaw == "ready",
              ref.assetID == assetID, ref.packageID == request.packageID, ref.ownerID == request.ownerID,
              ref.isLive, ref.revision == 0, ref.ordinal == request.ordinal, ref.roleRaw == "original",
              edge.allocationID == assetID, edge.accountID == request.ownerID, edge.ownerID == referenceID.uuidString.lowercased(),
              edge.roleRaw == SharedMediaPhotoLedger.namespace, edge.stateRaw == "live", edge.revision == 0,
              count.assetGeneration == request.assetGeneration, count.inventoryID == inventory.id,
              count.inventoryGeneration == inventory.generation, count.ownerID == request.ownerID,
              count.liveCount == 1, count.revision == 0, count.retirementID == nil,
              allocation.id == request.assetID, allocation.inventoryID == inventory.id, allocation.accountID == request.ownerID,
              allocation.packageID == request.packageID, allocation.fileToken == request.finalToken,
              allocation.namespaceRaw == SharedMediaPhotoLedger.namespace, allocation.poolRaw == "durable",
              lease.id == request.operationID, lease.allocationID == request.assetID,
              lease.processEpoch == request.writerEpoch, lease.purposeRaw == "p1AcquireV1",
              allocation.stateRaw == "p1Materialized", allocation.materializedBytes == result.byteCount,
              allocation.reservedBytes == 0, allocation.physicalIdentity == result.descriptor.file,
              lease.stateRaw == "closed", package.phaseRaw == "draftOwned",
              try context.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == operationID })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    @MainActor private struct Before {
        let inventoryRevision: Int64
        let packageRevision: Int64?
        let allocatedBytes: Int64
        let contexts: Data
        let membershipRevision: Int64?
        let membershipBytes: Data?
        init(context: ModelContext, inventory: SharedMediaInventoryRecord, request: SharedMediaAcquisitionIntent) throws {
            let id = request.packageID
            let package = try SharedMediaNativeAcquisitionMutation.optional(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
            let member = try SharedMediaNativeAcquisitionMutation.optional(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
            inventoryRevision = inventory.revision; packageRevision = package?.revision
            allocatedBytes = package?.allocatedByteCount ?? 0
            contexts = try package?.supportingContextData ?? PhotoPreparationPolicy.encodeDraft(contexts: [])
            membershipRevision = member?.revision; membershipBytes = member?.membersData
        }
    }

    private func validateCommon(phase: String, addedBytes: Int64, membershipChanged: Bool) throws {
        let package = try package(), member = try member()
        let expectedPackageRevision = try before.packageRevision.map { try increment($0) } ?? 0
        let expectedMemberRevision = membershipChanged ? try before.membershipRevision.map { try increment($0) } ?? 0 : before.membershipRevision
        let expectedMembers = try projection(final: true).membership(packageID: request.packageID).encoded()
        guard inventory.id == request.inventoryID, inventory.generation == request.inventoryGeneration,
              inventory.revision == (try increment(before.inventoryRevision)),
              package.id == request.packageID, package.ownerID == request.ownerID, package.draftID == request.packageID,
              package.draftGeneration == request.draftGeneration, package.contractVersion == PhotoPreparationPolicy.contract,
              package.accountingTierRaw == "pending", !package.retirementRequested, package.phaseRaw == phase,
              package.revision == expectedPackageRevision, package.supportingContextData == before.contexts,
              package.allocatedByteCount == (try SharedMediaStoragePolicy.add(before.allocatedBytes, addedBytes)),
              member.id == request.packageID, member.ownerID == request.ownerID, member.inventoryID == request.inventoryID,
              member.inventoryGeneration == request.inventoryGeneration, member.draftGeneration == request.draftGeneration,
              member.revision == expectedMemberRevision, member.membersData == expectedMembers,
              membershipChanged || member.membersData == before.membershipBytes else { throw SharedMediaStorageFailure.conflict }
    }

    private func requireFreshIDs() throws {
        if isApp { try SharedMediaNativeAppAcquisitionIdentity.direct(request, context: context); return }
        let wanted = Set([request.operationID, request.assetID, request.referenceID])
        // Sharing references may differ from a completed receipt's original ID.
        for id in wanted {
            guard try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id })) == 0,
                  try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id })) == 0 else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize; var offset = 0
        while true {
            query.fetchOffset = offset; let rows = try context.fetch(query)
            for row in rows {
                let ids: Set<UUID>
                switch try SharedMediaAcquisitionReceipt.read(row) {
                case .reserved(let old), .held(let old), .completed(let old, _): ids = [old.operationID, old.assetID, old.referenceID]
                case .released(let old): ids = [old.operationID]
                }
                guard wanted.isDisjoint(with: ids) else { throw SharedMediaStorageFailure.conflict }
            }
            if rows.count < SharedMediaStoragePolicy.pageSize { return }
            let (next, overflow) = offset.addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
    }

    private func poststate(final: Bool) throws -> SharedMediaNativeAppAcquisitionPoststate {
        guard case .app(let witness) = authority else { throw SharedMediaStorageFailure.closed }
        return .init(profile: witness.authority.profile, packageID: request.packageID,
            overlay: before.membershipRevision == nil, final: final, context: context, facts: witness.facts) { [self] in
                guard try SharedMediaNativeAppEligibility.profile(inventory) == witness.authority.profile,
                      inventory.revision == (try increment(before.inventoryRevision)) else { throw SharedMediaStorageFailure.conflict }
                try validateWriteSet(final: final)
            }
    }
    /// Typed exact insert/update/delete sets. Insertions are not counted as
    /// updates even on runtimes that also report them in changedModelsArray.
    private func validateWriteSet(final: Bool) throws {
        let operation = request.operationID, asset = request.assetID, package = request.packageID, reference = request.referenceID
        func key(_ model: any PersistentModel) throws -> String {
            switch model {
            case let row as SharedMediaInventoryRecord: return "inventory:" + row.id.uuidString
            case let row as PhotoPreparationRecord: return "package:" + row.id.uuidString
            case let row as SharedMediaPendingMembershipRecord: return "member:" + row.id.uuidString
            case let row as SharedMediaAcquisitionReceiptRecord: return "receipt:" + row.id.uuidString
            case let row as SharedMediaAllocationRecord: return "allocation:" + row.id.uuidString
            case let row as SharedMediaLeaseRecord: return "lease:" + row.id.uuidString
            case let row as PhotoPreparationLease: return "work:" + row.id.uuidString
            case let row as PhotoPreparationAsset: return "asset:" + row.id.uuidString
            case let row as PhotoPreparationReference: return "reference:" + row.id.uuidString
            case let row as SharedMediaReferenceRecord: return "edge:" + row.id.uuidString
            case let row as SharedMediaAssetReferenceCountRecord: return "count:" + row.id.uuidString
            default: throw SharedMediaStorageFailure.conflict
            }
        }
        func keys(_ rows: [any PersistentModel]) throws -> Set<String> {
            let values = try rows.map(key)
            guard Set(values).count == values.count else { throw SharedMediaStorageFailure.conflict }; return Set(values)
        }
        func named(_ name: String, _ id: UUID) -> String { name + ":" + id.uuidString }
        var inserted: Set<String> = [], updated: Set<String> = [named("inventory", inventory.id)], deleted: Set<String> = []
        switch transition {
        case "reserve":
            inserted = [named("receipt", operation), named("allocation", asset), named("lease", operation), named("work", operation)]
            if before.packageRevision == nil { inserted.insert(named("package", package)) } else { updated.insert(named("package", package)) }
            if before.membershipRevision == nil { if final { inserted.insert(named("member", package)) } }
            else if final { updated.insert(named("member", package)) }
        case "complete":
            inserted = [named("asset", asset), named("reference", reference), named("edge", reference), named("count", asset)]
            updated.formUnion([named("receipt", operation), named("allocation", asset), named("lease", operation), named("package", package)])
            if final { updated.insert(named("member", package)) }
            deleted = [named("work", operation)]
        case "hold":
            updated.formUnion([named("receipt", operation), named("allocation", asset), named("lease", operation), named("work", operation), named("package", package)])
        default: throw SharedMediaStorageFailure.conflict
        }
        let actualInserted = try keys(context.insertedModelsArray), actualDeleted = try keys(context.deletedModelsArray)
        let actualUpdated = try keys(context.changedModelsArray).subtracting(actualInserted).subtracting(actualDeleted)
        guard actualInserted == inserted, actualUpdated == updated, actualDeleted == deleted else { throw SharedMediaStorageFailure.conflict }
    }

    private func receipt() throws -> SharedMediaAcquisitionReceiptRecord {
        let id = request.operationID
        let row = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        _ = try SharedMediaAcquisitionReceipt.read(row, expected: request); return row
    }
    private func package() throws -> PhotoPreparationRecord {
        let id = request.packageID
        return try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func allocation() throws -> SharedMediaAllocationRecord {
        let id = request.assetID
        return try Self.one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func lease() throws -> SharedMediaLeaseRecord {
        let id = request.operationID
        return try Self.one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func work() throws -> PhotoPreparationLease {
        let id = request.operationID
        return try Self.one(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id }))
    }
    private func member() throws -> SharedMediaPendingMembershipRecord {
        let id = request.packageID
        return try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func increment(_ value: Int64) throws -> Int64 { try SharedMediaStoragePolicy.add(value, 1) }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        guard let row = try optional(context, query) else { throw SharedMediaStorageFailure.conflict }; return row
    }
    private static func optional<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T? {
        var query = query; query.fetchLimit = 2; let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }; return rows.first
    }
}

enum SharedMediaNativeAcquisitionBoundary: Equatable, Sendable {
    case afterOriginalWrite, beforeReservationSave, afterReservationSave, beforeCompletionSave, afterCompletionSave
    case beforeHeldSave, afterHeldSave, beforeReadback
}

/// Value-only pinned reservation state across loader/file awaits. These values
/// grant no mutation or file authority; a changed graph must never be rebased
/// into a successful completion.
struct SharedMediaNativeReservedState: Equatable {
    let inventory: SharedMediaStorageSnapshot
    let packageRevision: Int64
    let allocatedBytes: Int64
    let contexts: Data
    let membershipRevision: Int64
    let membershipBytes: Data
    @MainActor init(inventory: SharedMediaStorageSnapshot, context: ModelContext, request: SharedMediaAcquisitionIntent) throws {
        context.autosaveEnabled = false
        let id = request.packageID
        var packages = FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == id }); packages.fetchLimit = 2
        var members = FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }); members.fetchLimit = 2
        let rows = try context.fetch(packages), memberships = try context.fetch(members)
        guard rows.count == 1, memberships.count == 1, let package = rows.first, let member = memberships.first else {
            throw SharedMediaStorageFailure.conflict
        }
        self.inventory = inventory; packageRevision = package.revision; allocatedBytes = package.allocatedByteCount
        contexts = package.supportingContextData; membershipRevision = member.revision; membershipBytes = member.membersData
    }
}

/// Only this typed transaction can mint a dirty acquisition projection. The
/// first-package overlay is exact and cannot become a general root-repair API.
@MainActor
struct SharedMediaNativeAppAcquisitionPoststate {
    let profile: SharedMediaNativeAppProfile
    let packageID: UUID
    let overlay: Bool
    let final: Bool
    private let contextID: ObjectIdentifier
    private let facts: SharedMediaNativeAppMetadataFacts
    private let check: () throws -> Void
    fileprivate init(profile: SharedMediaNativeAppProfile, packageID: UUID, overlay: Bool, final: Bool,
                     context: ModelContext, facts: SharedMediaNativeAppMetadataFacts, check: @escaping () throws -> Void) {
        self.profile = profile; self.packageID = packageID; self.overlay = overlay; self.final = final
        contextID = ObjectIdentifier(context); self.facts = facts; self.check = check
    }
    func validate(context: ModelContext, inventory: SharedMediaInventoryRecord) throws {
        guard ObjectIdentifier(context) == contextID, try SharedMediaNativeAppEligibility.profile(inventory) == profile else { throw SharedMediaStorageFailure.conflict }
        try check()
        try facts.validateAcquisition(context, packageID: packageID, hasMember: !overlay || final)
    }
    func receivingBytes(_ consumer: SharedMediaConsumerRecord) throws -> Int64 { try facts.receivingBytes(consumer) }
}
