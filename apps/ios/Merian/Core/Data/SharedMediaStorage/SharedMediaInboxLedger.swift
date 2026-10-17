import Foundation
import SwiftData

/// Source-owner mutations share the already fenced SQLite transaction. The
/// catalog is this bounded projection; there is no second durable manifest.
@MainActor
final class SharedMediaInboxLedger {
    private let joint: SharedMediaPhotoTransaction
    private let inventory: SharedMediaInventoryRecord
    private let binding: SharedMediaPhotoBinding
    private let rootIdentity: String
    private var context: ModelContext { joint.context }

    init(joint: SharedMediaPhotoTransaction, inventory: SharedMediaInventoryRecord,
         binding: SharedMediaPhotoBinding, rootIdentity: String) {
        self.joint = joint; self.inventory = inventory; self.binding = binding; self.rootIdentity = rootIdentity
    }

    var photos: SharedMediaPhotoLedger { .init(joint: joint, inventoryID: inventory.id, includesInbox: true) }
    var derivatives: SharedMediaDerivativeLedger { .init(joint: joint, inventory: inventory, binding: binding) }
    var handoffs: SharedMediaInboxHandoffLedger { .init(joint: joint, inventory: inventory, binding: binding) }

    func sources() throws -> [SharedMediaInboxSource] { try rows().map(value) }

    func source(_ handle: SharedMediaInboxHandle) throws -> SharedMediaInboxSource {
        try value(find(handle))
    }

    func reserve(id: UUID, generation: UUID, workID: UUID, maximumBytes: Int64) throws -> SharedMediaInboxSource {
        let current = try rows()
        guard current.count < 8, !current.contains(where: { $0.id == id || $0.workID == workID }),
              !current.contains(where: { $0.writerStateRaw == "open" || $0.phaseRaw == "retiring" }),
              try handoffs.all().allSatisfy({ $0.detached }),
              maximumBytes > 0, maximumBytes <= PhotoPreparationPolicy.original else { throw SharedMediaStorageFailure.inUse }
        let row = SharedMediaInboxSourceRecord(id: id, inventoryID: inventory.id, generation: generation,
            receivedAt: Date(), rootIdentity: rootIdentity, maximumBytes: maximumBytes, workID: workID, writerEpoch: binding.epoch)
        context.insert(row)
        context.insert(SharedMediaAllocationRecord(id: id, inventoryID: inventory.id, accountID: nil, packageID: nil,
            namespaceRaw: SharedMediaInboxFiles.namespace, fileToken: row.finalToken, poolRaw: "acquisition", stateRaw: "inboxReserved",
            materializedBytes: 0, reservedBytes: maximumBytes, physicalIdentity: nil))
        context.insert(SharedMediaLeaseRecord(id: workID, allocationID: id, processEpoch: binding.epoch,
            purposeRaw: SharedMediaInboxFiles.namespace, stateRaw: "open"))
        return value(row)
    }

    func prepare(_ source: SharedMediaInboxSource, facts: SharedMediaInboxPrepared) throws -> SharedMediaInboxSource {
        let row = try exact(source)
        guard row.phaseRaw == "reserved", row.writerStateRaw == "open", row.writerEpoch == binding.epoch,
              facts.bytes > 0, facts.bytes <= row.maximumBytes, validDigest(facts.sha256),
              !facts.contentType.isEmpty, facts.contentType.utf8.count <= 128 else { throw SharedMediaStorageFailure.conflict }
        row.byteCount = facts.bytes; row.sha256 = facts.sha256; row.contentType = facts.contentType; row.phaseRaw = "prepared"
        let allocation = try allocation(row)
        allocation.reservedBytes = facts.bytes
        return try advance(row)
    }

    func recordPartial(_ source: SharedMediaInboxSource, identity: SharedMediaInboxFileIdentity) throws -> SharedMediaInboxSource {
        let row = try exact(source)
        guard row.phaseRaw == "prepared", row.writerStateRaw == "open", row.writerEpoch == binding.epoch,
              identity.bytes == 0 else { throw SharedMediaStorageFailure.conflict }
        row.partialDevice = identity.device; row.partialInode = identity.inode; row.phaseRaw = "writing"
        return try advance(row)
    }

    func complete(_ proof: SharedMediaInboxCompletionProof) throws -> SharedMediaInboxSource {
        let row = try exact(proof.source)
        guard proof.binding == binding.bytes, proof.epoch == binding.epoch,
              ["writing", "ready"].contains(row.phaseRaw), row.retirementID == nil,
              proof.identity.bytes == row.byteCount, proof.identity.device == row.partialDevice,
              proof.identity.inode == row.partialInode else { throw SharedMediaStorageFailure.conflict }
        if row.phaseRaw == "ready" {
            guard row.finalIdentity == proof.identity.exact else { throw SharedMediaStorageFailure.conflict }; return value(row)
        }
        row.phaseRaw = "ready"; row.writerStateRaw = "closed"; row.finalIdentity = proof.identity.exact
        let allocation = try allocation(row), work = try work(row)
        allocation.stateRaw = "inboxReady"; allocation.materializedBytes = row.byteCount
        allocation.reservedBytes = 0; allocation.physicalIdentity = proof.identity.exact; work.stateRaw = "closed"
        context.insert(SharedMediaReferenceRecord(id: row.id, allocationID: row.id, accountID: nil,
            ownerID: row.id.uuidString.lowercased(), roleRaw: SharedMediaInboxFiles.namespace, stateRaw: "unassigned", revision: 0))
        return try advance(row)
    }

    /// Only the orchestrator can present actual task-drain evidence. A restart
    /// fence closes a local writer, without claiming copy or provider success.
    func closeWriter(_ proof: SharedMediaInboxWriterClosure) throws -> SharedMediaInboxSource {
        let row = try exact(proof.source)
        guard proof.epoch == binding.epoch, row.retirementID == nil else { throw SharedMediaStorageFailure.conflict }
        if row.writerStateRaw == "closed" { return value(row) }
        row.writerStateRaw = "closed"; try work(row).stateRaw = "closed"
        return try advance(row)
    }

    func retire(_ inspection: SharedMediaInboxRetirementInspection) throws -> SharedMediaInboxSource {
        try handoffs.requireNoHold(sourceID: inspection.source.handle.id)
        return try retireUnheld(inspection)
    }

    func retireHandoff(_ inspection: SharedMediaInboxRetirementInspection, request: SharedMediaInboxHandoffRequest) throws -> SharedMediaInboxSource {
        guard inspection.source.handle == request.source else { throw SharedMediaStorageFailure.stale }
        try handoffs.pinRetirement(request)
        return try retireUnheld(inspection)
    }

    private func retireUnheld(_ inspection: SharedMediaInboxRetirementInspection) throws -> SharedMediaInboxSource {
        let row = try exact(inspection.source)
        guard inspection.binding == binding.bytes, inspection.epoch == binding.epoch,
              row.writerStateRaw == "closed", row.retirementID == nil else { throw SharedMediaStorageFailure.inUse }
        row.retirementID = UUID(); row.retirementPartialIdentity = inspection.partial
        row.retirementFinalIdentity = inspection.final; row.phaseRaw = "retiring"
        try allocation(row).stateRaw = "inboxRetiring"
        if let reference = try reference(row) { reference.stateRaw = "retired"; reference.revision += 1 }
        return try advance(row)
    }

    func release(_ proof: SharedMediaInboxReleaseProof) throws {
        let intent = proof.retirement, row = try exact(intent.source)
        guard intent.binding == binding.bytes, intent.epoch == binding.epoch, row.phaseRaw == "retiring",
              row.writerStateRaw == "closed", row.retirementID != nil else { throw SharedMediaStorageFailure.conflict }
        try handoffs.releaseSource(row.id)
        context.delete(try allocation(row)); context.delete(try work(row))
        if let reference = try reference(row) { context.delete(reference) }
        context.delete(row)
    }

    func reconcileOccupancy(_ proof: SharedMediaInboxOccupancyProof) throws {
        let row = try exact(proof.source)
        guard proof.binding == binding.bytes, proof.epoch == binding.epoch,
              row.writerStateRaw == "closed", row.phaseRaw != "retiring" else { throw SharedMediaStorageFailure.conflict }
        // Completed/missing originals retain their full logical charge. Only
        // unfinished allocations divide occupied bytes from outstanding space.
        if row.finalIdentity != nil { return }
        let ceiling = row.byteCount > 0 ? row.byteCount : row.maximumBytes
        guard proof.bytes >= 0, proof.bytes <= ceiling,
              proof.bytes == 0 || row.partialInode != nil else { throw SharedMediaStorageFailure.conflict }
        let item = try allocation(row)
        item.materializedBytes = proof.bytes; item.reservedBytes = ceiling - proof.bytes
    }

    func validate() throws -> SharedMediaStoragePolicy.Totals {
        let derivativeLeases = try derivatives.validate()
        let sources = try rows()
        let handoffCharges = try handoffs.validate(excludingDerivativeLeases: derivativeLeases)
        var total: Int64 = 0, outstanding: Int64 = 0
        let allocations = try fetch(SharedMediaAllocationRecord.self, maximum: 104)
        let references = try fetch(SharedMediaReferenceRecord.self, maximum: 144)
        let leases = try fetch(SharedMediaLeaseRecord.self, maximum: 104)
        guard allocations.filter({ $0.namespaceRaw == SharedMediaInboxFiles.namespace }).count == sources.count,
              leases.filter({ $0.purposeRaw == SharedMediaInboxFiles.namespace }).count == sources.count,
              references.filter({ $0.roleRaw == SharedMediaInboxFiles.namespace }).count == sources.filter({ $0.finalIdentity != nil }).count else { throw SharedMediaStorageFailure.conflict }
        for row in sources {
            guard row.inventoryID == inventory.id, row.rootIdentity == rootIdentity, row.revision >= 0,
                  row.maximumBytes > 0, row.maximumBytes <= PhotoPreparationPolicy.original,
                  row.finalToken == row.id.uuidString.lowercased(), row.partialToken == row.finalToken + ".partial",
                  ["reserved", "prepared", "writing", "ready", "retiring"].contains(row.phaseRaw),
                  ["open", "closed"].contains(row.writerStateRaw),
                  (row.partialDevice == nil) == (row.partialInode == nil),
                  (row.retirementID != nil) == (row.phaseRaw == "retiring") else { throw SharedMediaStorageFailure.conflict }
            if row.phaseRaw != "reserved" && !(row.phaseRaw == "retiring" && row.sha256 == nil) {
                guard row.byteCount > 0, row.byteCount <= row.maximumBytes, let hash = row.sha256, validDigest(hash),
                      let type = row.contentType, !type.isEmpty, type.utf8.count <= 128 else { throw SharedMediaStorageFailure.conflict }
            } else {
                guard row.byteCount == 0, row.sha256 == nil, row.contentType == nil else { throw SharedMediaStorageFailure.conflict }
            }
            let a = try allocation(row), w = try work(row), edge = try reference(row)
            guard a.inventoryID == inventory.id, a.accountID == nil, a.packageID == nil,
                  a.namespaceRaw == SharedMediaInboxFiles.namespace, a.fileToken == row.finalToken, a.poolRaw == "acquisition",
                  w.allocationID == row.id, w.processEpoch == row.writerEpoch, w.purposeRaw == SharedMediaInboxFiles.namespace,
                  w.stateRaw == row.writerStateRaw else { throw SharedMediaStorageFailure.conflict }
            let completed = row.finalIdentity != nil
            let charge = row.byteCount > 0 ? row.byteCount : row.maximumBytes
            guard a.stateRaw == (row.phaseRaw == "retiring" ? "inboxRetiring" : (completed ? "inboxReady" : "inboxReserved")),
                  a.materializedBytes >= 0, a.materializedBytes <= charge,
                  !completed || a.materializedBytes == row.byteCount,
                  a.materializedBytes == 0 || row.partialInode != nil,
                  a.reservedBytes == (completed ? 0 : charge - a.materializedBytes),
                  a.physicalIdentity == row.finalIdentity, (edge != nil) == completed else { throw SharedMediaStorageFailure.conflict }
            if completed {
                guard row.writerStateRaw == "closed", row.partialInode != nil, ["ready", "retiring"].contains(row.phaseRaw),
                      let edge, edge.allocationID == row.id, edge.accountID == nil, edge.ownerID == row.id.uuidString.lowercased(),
                      edge.roleRaw == SharedMediaInboxFiles.namespace, edge.stateRaw == (row.phaseRaw == "retiring" ? "retired" : "unassigned"),
                      edge.revision == (row.phaseRaw == "retiring" ? 1 : 0) else { throw SharedMediaStorageFailure.conflict }
            }
            if row.phaseRaw == "retiring" {
                guard row.writerStateRaw == "closed", row.retirementPartialIdentity != nil, row.retirementFinalIdentity != nil else { throw SharedMediaStorageFailure.conflict }
            }
            total = try SharedMediaStoragePolicy.add(total, SharedMediaStoragePolicy.add(a.materializedBytes, a.reservedBytes))
            outstanding = try SharedMediaStoragePolicy.add(outstanding, a.reservedBytes)
        }
        let headroom: Int64 = sources.isEmpty ? 0 : PhotoPreparationPolicy.original
        guard handoffCharges.active <= headroom else { throw SharedMediaStorageFailure.conflict }
        var totals = try SharedMediaPhotoLedger(joint: joint, inventoryID: inventory.id, includesInbox: true).validate()
        try totals.includeInboxAcquisition(bytes: SharedMediaStoragePolicy.add(SharedMediaStoragePolicy.add(total, headroom), handoffCharges.abandoned),
            unmaterialized: SharedMediaStoragePolicy.add(outstanding, headroom - handoffCharges.active))
        return totals
    }

    private func rows() throws -> [SharedMediaInboxSourceRecord] { try fetch(SharedMediaInboxSourceRecord.self, maximum: 8) }
    private func fetch<T: PersistentModel>(_ type: T.Type, maximum: Int) throws -> [T] {
        var query = FetchDescriptor<T>(); query.fetchLimit = maximum + 1
        let rows = try context.fetch(query)
        guard rows.count <= maximum else { throw SharedMediaStorageFailure.conflict }; return rows
    }
    private func find(_ handle: SharedMediaInboxHandle) throws -> SharedMediaInboxSourceRecord {
        guard let row = try rows().first(where: { $0.id == handle.id }), row.generation == handle.generation,
              row.revision == handle.revision else { throw SharedMediaStorageFailure.stale }; return row
    }
    private func exact(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxSourceRecord {
        let row = try find(source.handle)
        guard value(row) == source else { throw SharedMediaStorageFailure.conflict }; return row
    }
    private func allocation(_ row: SharedMediaInboxSourceRecord) throws -> SharedMediaAllocationRecord {
        guard let result = try fetch(SharedMediaAllocationRecord.self, maximum: 104).first(where: { $0.id == row.id }) else { throw SharedMediaStorageFailure.conflict }; return result
    }
    private func work(_ row: SharedMediaInboxSourceRecord) throws -> SharedMediaLeaseRecord {
        guard let result = try fetch(SharedMediaLeaseRecord.self, maximum: 104).first(where: { $0.id == row.workID }) else { throw SharedMediaStorageFailure.conflict }; return result
    }
    private func reference(_ row: SharedMediaInboxSourceRecord) throws -> SharedMediaReferenceRecord? {
        try fetch(SharedMediaReferenceRecord.self, maximum: 144).first(where: { $0.id == row.id })
    }
    private func advance(_ row: SharedMediaInboxSourceRecord) throws -> SharedMediaInboxSource {
        row.revision = try SharedMediaStoragePolicy.add(row.revision, 1); return value(row)
    }
    private func validDigest(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) } }
    private func value(_ row: SharedMediaInboxSourceRecord) -> SharedMediaInboxSource {
        .init(handle: .init(id: row.id, generation: row.generation, revision: row.revision), workID: row.workID,
            writerEpoch: row.writerEpoch, writerState: row.writerStateRaw, phase: row.phaseRaw, maximumBytes: row.maximumBytes,
            expectedBytes: row.byteCount, sha256: row.sha256, contentType: row.contentType, device: row.partialDevice,
            inode: row.partialInode, finalIdentity: row.finalIdentity, rootIdentity: row.rootIdentity,
            retirementID: row.retirementID, retirementPartialIdentity: row.retirementPartialIdentity, retirementFinalIdentity: row.retirementFinalIdentity)
    }
}
