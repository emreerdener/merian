import Foundation
import SwiftData

/// Only this joint ledger may authorize admission alongside closed, detached
/// P1 work. The standalone repository cannot manufacture this permit.
struct SharedMediaInboxReservationPermit {
    let intent: PhotoPreparationIntent
    fileprivate init(_ intent: PhotoPreparationIntent) { self.intent = intent }
}

@MainActor
final class SharedMediaInboxHandoffLedger {
    static let holdRole = "inboxHandoffV1"
    private let joint: SharedMediaPhotoTransaction
    private let inventory: SharedMediaInventoryRecord
    private let binding: SharedMediaPhotoBinding
    private var context: ModelContext { joint.context }

    init(joint: SharedMediaPhotoTransaction, inventory: SharedMediaInventoryRecord, binding: SharedMediaPhotoBinding) {
        self.joint = joint; self.inventory = inventory; self.binding = binding
    }

    func all() throws -> [SharedMediaInboxHandoff] { try rows().map(Self.value) }

    func saved(_ request: SharedMediaInboxHandoffRequest) throws -> SharedMediaInboxHandoff? {
        try request.validate()
        guard inventory.generation == request.inventoryGeneration else { throw SharedMediaStorageFailure.stale }
        guard let row = try rows().first(where: { $0.id == request.id }) else { return nil }
        guard Self.request(row) == request else { throw SharedMediaStorageFailure.conflict }
        return Self.value(row)
    }

    func prepare(_ source: SharedMediaInboxSource, ownerID: UUID, packageID: UUID,
                 draftGeneration: UUID, ordinal: Int64) throws -> SharedMediaInboxHandoffRequest {
        guard source.phase == "ready", source.writerState == "closed", let digest = source.sha256,
              try rows().allSatisfy({ Self.value($0).detached }) else { throw SharedMediaStorageFailure.inUse }
        let request = SharedMediaInboxHandoffRequest(id: UUID(), nonce: UUID(), source: source.handle,
            inventoryGeneration: inventory.generation, expectedInventoryRevision: inventory.revision,
            ownerID: ownerID, packageID: packageID, draftGeneration: draftGeneration,
            assetID: UUID(), assetGeneration: UUID(), referenceID: UUID(), leaseID: UUID(), sourceHoldID: UUID(),
            ordinal: ordinal, byteCount: source.expectedBytes, sha256: digest)
        try request.validate(); return request
    }

    func reserve(_ request: SharedMediaInboxHandoffRequest) throws -> SharedMediaInboxHandoff {
        if let prior = try saved(request) { return prior }
        guard inventory.revision == request.expectedInventoryRevision,
              try rows().count < 8, try rows().allSatisfy({ Self.value($0).detached }) else { throw SharedMediaStorageFailure.stale }
        let source = try sourceRow(request)
        guard source.phaseRaw == "ready", source.writerStateRaw == "closed", source.retirementID == nil,
              try fetch(SharedMediaInboxSourceRecord.self, 8).allSatisfy({ $0.writerStateRaw == "closed" && $0.retirementID == nil }),
              try fetch(SharedMediaReferenceRecord.self, 144).allSatisfy({ $0.id != request.sourceHoldID }) else { throw SharedMediaStorageFailure.inUse }
        let intent = request.intent(epoch: binding.epoch)
        try PhotoPreparationRepository.reserveInbox(.init(intent), joint: joint)
        let row = SharedMediaInboxHandoffRecord(id: request.id, nonce: request.nonce, sourceID: request.source.id,
            sourceGeneration: request.source.generation, sourceRevision: request.source.revision,
            inventoryGeneration: request.inventoryGeneration, expectedInventoryRevision: request.expectedInventoryRevision,
            ownerID: request.ownerID, packageID: request.packageID, draftGeneration: request.draftGeneration,
            assetID: request.assetID, assetGeneration: request.assetGeneration, referenceID: request.referenceID,
            leaseID: request.leaseID, sourceHoldID: request.sourceHoldID, ordinal: request.ordinal,
            byteCount: request.byteCount, sha256: request.sha256, writerEpoch: binding.epoch)
        context.insert(row)
        context.insert(SharedMediaReferenceRecord(id: request.sourceHoldID, allocationID: source.id,
            accountID: nil, ownerID: request.id.uuidString.lowercased(), roleRaw: Self.holdRole, stateRaw: "held", revision: 0))
        context.insert(SharedMediaAllocationRecord(id: intent.assetID, inventoryID: inventory.id,
            accountID: intent.ownerID, packageID: intent.packageID, namespaceRaw: SharedMediaPhotoLedger.namespace,
            fileToken: intent.fileToken, poolRaw: "durable", stateRaw: "p1InboxReserved", materializedBytes: 0,
            reservedBytes: request.byteCount, physicalIdentity: nil))
        context.insert(SharedMediaLeaseRecord(id: intent.leaseID, allocationID: intent.assetID,
            processEpoch: binding.epoch, purposeRaw: "p1AcquireV1", stateRaw: "open"))
        return Self.value(row)
    }

    func partial(_ proof: SharedMediaInboxDestinationPartial) throws -> SharedMediaInboxHandoff {
        let row = try exact(proof.handoff)
        guard proof.binding == binding.bytes, proof.epoch == binding.epoch,
              row.phaseRaw == "reserved", row.writerStateRaw == "open", row.writerEpoch == binding.epoch,
              proof.identity.bytes == 0 else { throw SharedMediaStorageFailure.conflict }
        row.partialDevice = proof.identity.device; row.partialInode = proof.identity.inode; row.phaseRaw = "writing"
        return Self.value(row)
    }

    func complete(_ proof: SharedMediaInboxDestinationCompletion) throws -> SharedMediaInboxHandoff {
        let row = try exact(proof.handoff), request = Self.request(row)
        guard proof.binding == binding.bytes, proof.epoch == binding.epoch,
              ["writing", "completed"].contains(row.phaseRaw),
              proof.identity.device == row.partialDevice, proof.identity.inode == row.partialInode,
              proof.file.byteCount == row.byteCount, proof.file.sha256 == row.sha256,
              proof.file.assetID == row.assetID, proof.file.generation == row.assetGeneration,
              proof.file.token == request.intent(epoch: row.writerEpoch).fileToken else { throw SharedMediaStorageFailure.conflict }
        if row.phaseRaw == "completed" {
            guard row.finalIdentity == proof.identity.exact else { throw SharedMediaStorageFailure.conflict }
            return Self.value(row)
        }
        _ = try PhotoPreparationRepository.commit(request.intent(epoch: row.writerEpoch), file: proof.file, joint: joint)
        let allocation = try allocation(row), lease = try sharedLease(row)
        allocation.stateRaw = "p1Materialized"; allocation.materializedBytes = row.byteCount
        allocation.reservedBytes = 0; allocation.physicalIdentity = proof.identity.exact; lease.stateRaw = "closed"
        context.insert(SharedMediaReferenceRecord(id: row.referenceID, allocationID: row.assetID,
            accountID: row.ownerID, ownerID: row.referenceID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace,
            stateRaw: "live", revision: 0))
        row.phaseRaw = "completed"; row.writerStateRaw = "closed"; row.finalIdentity = proof.identity.exact
        return Self.value(row)
    }

    func close(_ proof: SharedMediaInboxDestinationClosure) throws -> SharedMediaInboxHandoff {
        let row = try exact(proof.handoff)
        guard proof.binding == binding.bytes, proof.epoch == binding.epoch,
              row.phaseRaw != "sourceRetiring", !Self.value(row).detached else { throw SharedMediaStorageFailure.conflict }
        row.writerStateRaw = "closed"
        if !Self.value(row).completed {
            let allocation = try allocation(row), work = try work(row), lease = try sharedLease(row)
            guard proof.occupied >= 0, proof.occupied <= row.byteCount else { throw SharedMediaStorageFailure.conflict }
            allocation.stateRaw = "p1InboxHeld"; allocation.materializedBytes = proof.occupied
            allocation.reservedBytes = row.byteCount - proof.occupied
            work.writerStateRaw = "closedInboxHeld"; lease.stateRaw = "closed"
        }
        return Self.value(row)
    }

    func abandon(_ proof: SharedMediaInboxDestinationClosure) throws {
        let row = try exact(proof.handoff)
        guard proof.binding == binding.bytes, proof.epoch == binding.epoch, row.writerStateRaw == "closed",
              row.phaseRaw != "sourceRetiring", !Self.value(row).detached else { throw SharedMediaStorageFailure.inUse }
        let source = try sourceRow(Self.request(row))
        guard source.retirementID == nil else { throw SharedMediaStorageFailure.inUse }
        let lease = try work(row)
        context.delete(try hold(row))
        if Self.value(row).completed { context.delete(lease); context.delete(row) }
        else {
            row.phaseRaw = "detached"
            lease.allocatedByteCount = 0; lease.sourceIdentity = nil
            lease.writerStateRaw = "closedNeedsAttention"; lease.terminalProof = "sourceOwnerAcceptedReturn"
            try allocation(row).stateRaw = "p1InboxDetached"
        }
    }

    func requireNoHold(sourceID: UUID) throws {
        guard try rows().allSatisfy({ $0.sourceID != sourceID || Self.value($0).detached }) else { throw SharedMediaStorageFailure.inUse }
    }

    func pinRetirement(_ request: SharedMediaInboxHandoffRequest) throws {
        guard let state = try saved(request), state.phase == "completed" else { throw SharedMediaStorageFailure.inUse }
        let row = try exact(state)
        _ = try sourceRow(request)
        // validate() proves the exact live destination reference and retained
        // source lease. Its retained row prevents destination retirement.
        _ = try validate()
        row.phaseRaw = "sourceRetiring"
    }

    func releaseSource(_ sourceID: UUID) throws {
        let active = try rows().filter { $0.sourceID == sourceID && !Self.value($0).detached }
        guard active.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        guard let row = active.first else { return }
        guard row.phaseRaw == "sourceRetiring", row.writerStateRaw == "closed" else { throw SharedMediaStorageFailure.inUse }
        context.delete(try work(row)); context.delete(try hold(row)); context.delete(row)
    }

    func retireDetached(_ proof: SharedMediaInboxDestinationInspection) throws -> SharedMediaInboxHandoff {
        let row = try exact(proof.handoff)
        guard proof.binding == binding.bytes, proof.epoch == binding.epoch,
              row.phaseRaw == "detached", row.writerStateRaw == "closed" else { throw SharedMediaStorageFailure.conflict }
        let allocation = try allocation(row)
        allocation.physicalIdentity = try proof.identity.encoded(); allocation.stateRaw = "p1InboxRetiring"
        row.phaseRaw = "detachedRetiring"
        return Self.value(row)
    }

    func detachedRetirement(_ request: SharedMediaInboxHandoffRequest) throws -> (SharedMediaInboxHandoff, SharedMediaInboxDestinationRetirementIdentity) {
        guard let state = try saved(request), state.phase == "detachedRetiring", state.writerState == "closed",
              let identity = try allocation(exact(state)).physicalIdentity else { throw SharedMediaStorageFailure.inUse }
        return try (state, .decode(identity))
    }

    func releaseDetached(_ proof: SharedMediaInboxDestinationRelease) throws {
        let intent = proof.retirement, row = try exact(intent.handoff)
        guard intent.binding == binding.bytes, intent.epoch == binding.epoch,
              try detachedRetirement(intent.handoff.request).1 == intent.identity else { throw SharedMediaStorageFailure.conflict }
        let p = try package(row)
        context.delete(try allocation(row)); context.delete(try work(row)); context.delete(try sharedLease(row)); context.delete(row)
        let hasReference = try fetch(PhotoPreparationReference.self, 128).contains { $0.packageID == p.id }
        let otherWork = try fetch(PhotoPreparationLease.self, 96).contains { $0.packageID == p.id && $0.id != row.leaseID }
        if !hasReference && !otherWork { context.delete(p) }
        else {
            p.phaseRaw = otherWork ? "needsAttention" : "draftOwned"
            p.revision = try SharedMediaStoragePolicy.add(p.revision, 1)
        }
    }

    /// Prove both sides of every additional edge before any joint save. Detached
    /// rows retain immutable request provenance, never authority over a source.
    func validate() throws -> (active: Int64, abandoned: Int64) {
        let rows = try rows(), states = rows.map(Self.value)
        let edges = try fetch(SharedMediaReferenceRecord.self, 144)
        let allWork = try fetch(PhotoPreparationLease.self, 96)
        let allocations = try fetch(SharedMediaAllocationRecord.self, 104)
        let active = states.filter { !$0.detached }
        guard active.count <= 1,
              Set(rows.map(\.id)).count == rows.count, Set(rows.map(\.nonce)).count == rows.count,
              Set(rows.map(\.assetID)).count == rows.count, Set(rows.map(\.leaseID)).count == rows.count,
              Set(rows.map(\.sourceHoldID)).count == rows.count,
              edges.filter({ $0.roleRaw == Self.holdRole }).count == active.count,
              allocations.filter({ $0.stateRaw.hasPrefix("p1Inbox") }).count == states.filter({ !$0.completed }).count,
              allWork.count == rows.count else { throw SharedMediaStorageFailure.conflict }
        var abandoned: Int64 = 0
        for row in rows {
            let state = Self.value(row), request = state.request
            try request.validate()
            guard row.inventoryGeneration == inventory.generation, row.expectedInventoryRevision <= inventory.revision,
                  ["reserved", "writing", "completed", "sourceRetiring", "detached", "detachedRetiring"].contains(row.phaseRaw),
                  ["open", "closed"].contains(row.writerStateRaw),
                  (row.partialDevice == nil) == (row.partialInode == nil),
                  row.phaseRaw != "reserved" || row.partialInode == nil,
                  !state.completed || (row.partialInode != nil && row.finalIdentity != nil && row.writerStateRaw == "closed"),
                  !state.detached || row.writerStateRaw == "closed" else { throw SharedMediaStorageFailure.conflict }
            let a = try allocation(row), lease = try work(row), shared = try sharedLease(row), p = try package(row)
            let intent = request.intent(epoch: row.writerEpoch)
            guard p.ownerID == row.ownerID, p.draftGeneration == row.draftGeneration,
                  a.accountID == row.ownerID, a.packageID == row.packageID, a.inventoryID == inventory.id,
                  a.namespaceRaw == SharedMediaPhotoLedger.namespace, a.fileToken == intent.fileToken,
                  lease.ownerID == row.ownerID, lease.assetID == row.assetID, lease.packageID == row.packageID,
                  lease.processEpoch == row.writerEpoch, lease.purposeRaw == "acquire",
                  lease.finalFileToken == intent.fileToken, lease.partialFileToken == intent.fileToken + ".partial",
                  shared.allocationID == row.assetID, shared.processEpoch == row.writerEpoch,
                  shared.purposeRaw == "p1AcquireV1", shared.stateRaw == row.writerStateRaw else { throw SharedMediaStorageFailure.conflict }
            if state.detached {
                guard !edges.contains(where: { $0.id == row.sourceHoldID }),
                      lease.allocatedByteCount == 0, lease.sourceIdentity == nil,
                      lease.writerStateRaw == "closedNeedsAttention", lease.terminalProof == "sourceOwnerAcceptedReturn" else { throw SharedMediaStorageFailure.conflict }
                abandoned = try SharedMediaStoragePolicy.add(abandoned, row.byteCount)
            } else {
                let source = try sourceRow(request), hold = try hold(row)
                guard source.writerStateRaw == "closed", source.finalIdentity != nil,
                      source.phaseRaw == (row.phaseRaw == "sourceRetiring" ? "retiring" : "ready"),
                      hold.allocationID == source.id, hold.accountID == nil, hold.ownerID == row.id.uuidString.lowercased(),
                      hold.roleRaw == Self.holdRole, hold.stateRaw == "held", hold.revision == 0,
                      lease.sourceIdentity == source.id.uuidString.lowercased(), lease.allocatedByteCount == row.byteCount else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
            if state.completed {
                guard lease.reservedByteCount == 0, lease.writerStateRaw == "closedSourceRetained",
                      lease.terminalProof == "destinationCommittedSourceStillOwned", a.stateRaw == "p1Materialized",
                      a.materializedBytes == row.byteCount, a.reservedBytes == 0, a.physicalIdentity == row.finalIdentity,
                      let asset = try fetch(PhotoPreparationAsset.self, 96).first(where: { $0.id == row.assetID }),
                      asset.generation == row.assetGeneration, asset.byteCount == row.byteCount, asset.sha256 == row.sha256,
                      let edge = try fetch(PhotoPreparationReference.self, 128).first(where: { $0.id == row.referenceID }),
                      edge.assetID == row.assetID, edge.packageID == row.packageID, edge.ownerID == row.ownerID,
                      edge.ordinal == row.ordinal, edge.isLive, edge.revision == 0 else { throw SharedMediaStorageFailure.conflict }
            } else {
                let retiring = row.phaseRaw == "detachedRetiring"
                let expected = retiring ? "p1InboxRetiring" : (state.detached ? "p1InboxDetached" : (row.writerStateRaw == "open" ? "p1InboxReserved" : "p1InboxHeld"))
                guard a.stateRaw == expected, (a.physicalIdentity != nil) == retiring, lease.reservedByteCount == row.byteCount,
                      try SharedMediaStoragePolicy.add(a.materializedBytes, a.reservedBytes) == row.byteCount,
                      row.partialInode != nil || a.materializedBytes == 0,
                      state.detached || (lease.terminalProof == nil && lease.writerStateRaw == (row.writerStateRaw == "open" ? "open" : "closedInboxHeld")) else {
                    throw SharedMediaStorageFailure.conflict
                }
                if let identity = a.physicalIdentity { _ = try SharedMediaInboxDestinationRetirementIdentity.decode(identity) }
            }
        }
        return (active.first?.request.byteCount ?? 0, abandoned)
    }

    func rows() throws -> [SharedMediaInboxHandoffRecord] { try fetch(SharedMediaInboxHandoffRecord.self, 8) }
    func exact(_ state: SharedMediaInboxHandoff) throws -> SharedMediaInboxHandoffRecord {
        guard let row = try rows().first(where: { $0.id == state.request.id }), Self.value(row) == state else { throw SharedMediaStorageFailure.stale }
        return row
    }
    func sourceRow(_ request: SharedMediaInboxHandoffRequest) throws -> SharedMediaInboxSourceRecord {
        guard let row = try fetch(SharedMediaInboxSourceRecord.self, 8).first(where: { $0.id == request.source.id }),
              row.generation == request.source.generation,
              row.revision == (try SharedMediaStoragePolicy.add(request.source.revision, row.phaseRaw == "retiring" ? 1 : 0)),
              row.byteCount == request.byteCount, row.sha256 == request.sha256 else { throw SharedMediaStorageFailure.stale }
        return row
    }
    func allocation(_ row: SharedMediaInboxHandoffRecord) throws -> SharedMediaAllocationRecord {
        guard let value = try fetch(SharedMediaAllocationRecord.self, 104).first(where: { $0.id == row.assetID }) else { throw SharedMediaStorageFailure.conflict }; return value
    }
    func work(_ row: SharedMediaInboxHandoffRecord) throws -> PhotoPreparationLease {
        guard let value = try fetch(PhotoPreparationLease.self, 96).first(where: { $0.id == row.leaseID }) else { throw SharedMediaStorageFailure.conflict }; return value
    }
    func sharedLease(_ row: SharedMediaInboxHandoffRecord) throws -> SharedMediaLeaseRecord {
        guard let value = try fetch(SharedMediaLeaseRecord.self, 104).first(where: { $0.id == row.leaseID }) else { throw SharedMediaStorageFailure.conflict }; return value
    }
    func package(_ row: SharedMediaInboxHandoffRecord) throws -> PhotoPreparationRecord {
        guard let value = try fetch(PhotoPreparationRecord.self, 4).first(where: { $0.id == row.packageID }) else { throw SharedMediaStorageFailure.conflict }; return value
    }
    func hold(_ row: SharedMediaInboxHandoffRecord) throws -> SharedMediaReferenceRecord {
        guard let value = try fetch(SharedMediaReferenceRecord.self, 144).first(where: { $0.id == row.sourceHoldID }) else { throw SharedMediaStorageFailure.conflict }; return value
    }
    func fetch<T: PersistentModel>(_ type: T.Type, _ maximum: Int) throws -> [T] {
        var query = FetchDescriptor<T>(); query.fetchLimit = maximum + 1
        let rows = try context.fetch(query)
        guard rows.count <= maximum else { throw SharedMediaStorageFailure.conflict }; return rows
    }
    static func request(_ r: SharedMediaInboxHandoffRecord) -> SharedMediaInboxHandoffRequest {
        .init(id: r.id, nonce: r.nonce, source: .init(id: r.sourceID, generation: r.sourceGeneration, revision: r.sourceRevision),
            inventoryGeneration: r.inventoryGeneration, expectedInventoryRevision: r.expectedInventoryRevision,
            ownerID: r.ownerID, packageID: r.packageID, draftGeneration: r.draftGeneration, assetID: r.assetID,
            assetGeneration: r.assetGeneration, referenceID: r.referenceID, leaseID: r.leaseID, sourceHoldID: r.sourceHoldID,
            ordinal: r.ordinal, byteCount: r.byteCount, sha256: r.sha256)
    }
    static func value(_ r: SharedMediaInboxHandoffRecord) -> SharedMediaInboxHandoff {
        .init(request: request(r), phase: r.phaseRaw, writerEpoch: r.writerEpoch, writerState: r.writerStateRaw,
            device: r.partialDevice, inode: r.partialInode, finalIdentity: r.finalIdentity)
    }
}
