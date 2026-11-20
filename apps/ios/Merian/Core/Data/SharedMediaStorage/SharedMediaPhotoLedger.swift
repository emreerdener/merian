import Foundation
import SwiftData

struct SharedMediaPhotoInventory: Sendable {
    let files: [PhotoPreparationFile]
    let originals: [PhotoOriginalReference]
    let identities: [UUID: String]
    let pendingTokens: Set<String>
    let retiringIDs: Set<UUID>
    var hasPending: Bool { !pendingTokens.isEmpty }
}

/// A bounded join of the two native ownership graphs. Models never leave this
/// transaction; the caller owns its single save and the exclusive store fence.
@MainActor
final class SharedMediaPhotoLedger {
    static let namespace = "p1OriginalV1"
    private let joint: SharedMediaPhotoTransaction
    private let inventoryID: UUID
    private let includesInbox: Bool
    private let inventoryRow: SharedMediaInventoryRecord?
    private var purging: Bool { inventoryRow?.phaseRaw == "purgingP1" }
    private var context: ModelContext { joint.context }

    init(joint: SharedMediaPhotoTransaction, inventoryID: UUID, includesInbox: Bool = false, inventory: SharedMediaInventoryRecord? = nil) {
        self.inventoryRow = inventory
        self.joint = joint
        self.inventoryID = inventoryID
        self.includesInbox = includesInbox
    }

    private struct Rows {
        let packages: [PhotoPreparationRecord]
        let assets: [PhotoPreparationAsset]
        let references: [PhotoPreparationReference]
        let work: [PhotoPreparationLease]
        let allocations: [SharedMediaAllocationRecord]
        let edges: [SharedMediaReferenceRecord]
        let leases: [SharedMediaLeaseRecord]
    }

    private func rows() throws -> Rows {
        func bounded<T: PersistentModel>(_ type: T.Type, maximum: Int) throws -> [T] {
            var query = FetchDescriptor<T>()
            query.fetchLimit = maximum + 1
            let result = try context.fetch(query)
            guard result.count <= maximum else { throw SharedMediaStorageFailure.conflict }
            return result
        }
        return try Rows(packages: bounded(PhotoPreparationRecord.self, maximum: 4),
            assets: bounded(PhotoPreparationAsset.self, maximum: 96),
            references: bounded(PhotoPreparationReference.self, maximum: 128),
            work: bounded(PhotoPreparationLease.self, maximum: 96),
            allocations: bounded(SharedMediaAllocationRecord.self, maximum: includesInbox ? 104 : 96).filter { !includesInbox || $0.namespaceRaw != SharedMediaInboxFiles.namespace },
            edges: bounded(SharedMediaReferenceRecord.self, maximum: includesInbox ? 144 : 128).filter { !includesInbox || ![SharedMediaInboxFiles.namespace, SharedMediaInboxHandoffLedger.holdRole].contains($0.roleRaw) },
            leases: bounded(SharedMediaLeaseRecord.self, maximum: includesInbox ? 104 : 96).filter { !includesInbox || $0.purposeRaw != SharedMediaInboxFiles.namespace })
    }

    func validate() throws -> SharedMediaStoragePolicy.Totals {
        let r = try rows()
        guard Set(r.packages.map(\.id)).count == r.packages.count,
              Set(r.assets.map(\.id)).count == r.assets.count,
              Set(r.references.map(\.id)).count == r.references.count,
              Set(r.work.map(\.id)).count == r.work.count,
              Set(r.allocations.map(\.id)).count == r.allocations.count,
              Set(r.edges.map(\.id)).count == r.edges.count,
              Set(r.leases.map(\.id)).count == r.leases.count,
              Set(r.allocations.map(\.fileToken)).count == r.allocations.count,
              r.allocations.count == r.leases.count,
              r.references.count == r.edges.count,
              r.allocations.count == r.assets.count + r.work.filter({ !["closedSourceRetained", "closedPairWaiting"].contains($0.writerStateRaw) }).count else { throw SharedMediaStorageFailure.conflict }
        var totals = SharedMediaStoragePolicy.Totals()
        for p in r.packages {
            let envelope = try PhotoPreparationPolicy.decodeDraft(p.supportingContextData)
            let refs = r.references.filter { $0.packageID == p.id }
            let work = r.work.filter { $0.packageID == p.id }
            let ids = Set(refs.map(\.assetID))
            let bytes = try PhotoPreparationPolicy.add(r.assets.filter { ids.contains($0.id) }.map(\.byteCount))
            let reserved = try PhotoPreparationPolicy.add(work.map(\.reservedByteCount))
            let retiring = !refs.isEmpty && refs.allSatisfy { !$0.isLive }
            guard !refs.isEmpty || !work.isEmpty, work.filter({ $0.purposeRaw == "acquire" && $0.writerStateRaw != "closedSourceRetained" }).count + refs.filter({ $0.roleRaw == "original" }).count <= 2,
                  p.contractVersion == PhotoPreparationPolicy.contract, p.draftID == p.id, p.accountingTierRaw == "pending",
                  p.retirementRequested == retiring, p.revision >= 0,
                  retiring ? p.phaseRaw == "retiring" : (includesInbox ? (["acquiring", "draftOwned", "needsAttention", "preparedHeld"] + (purging ? ["purging"] : [])) : ["acquiring", "draftOwned", "needsAttention"]).contains(p.phaseRaw),
                  includesInbox || (envelope.contexts.isEmpty && envelope.presentation.isEmpty),
                  purging || envelope.presentation.allSatisfy({ photo in refs.contains { $0.id == photo.referenceID && $0.isLive && $0.roleRaw == "original" } }),
                  p.supportingContextData.count <= PhotoPreparationPolicy.metadata,
                  p.allocatedByteCount == bytes,
                  Set(refs.filter(\.isLive).map { $0.roleRaw + ":" + String($0.ordinal) }).count == refs.filter(\.isLive).count else {
                throw SharedMediaStorageFailure.conflict
            }
            if p.phaseRaw == "preparedHeld" {
                let originals = refs.filter { $0.isLive && $0.roleRaw == "original" }.map(\.ordinal).sorted()
                var handoffQuery = FetchDescriptor<SharedMediaInboxHandoffRecord>(); handoffQuery.fetchLimit = 9
                var pairQuery = FetchDescriptor<SharedMediaDerivativePairRecord>(); pairQuery.fetchLimit = 10
                let handoffs = try context.fetch(handoffQuery), pairs = try context.fetch(pairQuery)
                guard !originals.isEmpty, work.isEmpty, refs.allSatisfy(\.isLive), handoffs.count <= 8, pairs.count <= 9,
                      handoffs.allSatisfy({ $0.packageID != p.id }),
                      pairs.filter({ $0.packageID == p.id }).count == originals.count,
                      pairs.filter({ $0.packageID == p.id }).allSatisfy({ $0.phaseRaw == "ready" }),
                      ["aiInput", "display"].allSatisfy({ role in refs.filter { $0.roleRaw == role }.map(\.ordinal).sorted() == originals }) else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
            let originalIDs = Set(refs.filter { $0.roleRaw == "original" }.map(\.assetID))
            let originalBytes = try PhotoPreparationPolicy.add(r.assets.filter { originalIDs.contains($0.id) }.map(\.byteCount)
                + work.filter { $0.purposeRaw == "acquire" }.map(\.reservedByteCount))
            guard originalBytes <= PhotoPreparationPolicy.originalCohort else { throw SharedMediaStorageFailure.capacity }
            try totals.includePhotoPackage(id: p.id, bytes: PhotoPreparationPolicy.add([bytes, reserved, Int64(p.supportingContextData.count)]))
            try totals.includePhotoPhysical(materialized: Int64(p.supportingContextData.count), reserved: 0)
        }
        for a in r.allocations {
            guard a.inventoryID == inventoryID, let owner = a.accountID, let origin = a.packageID,
                  a.namespaceRaw == Self.namespace, a.poolRaw == "durable",
                  a.fileToken == owner.uuidString.lowercased() + "/" + origin.uuidString.lowercased() + "/" + a.id.uuidString.lowercased(),
                  r.leases.filter({ $0.allocationID == a.id }).count == 1,
                  let lease = r.leases.first(where: { $0.allocationID == a.id }),
                  lease.purposeRaw == "p1AcquireV1" || (includesInbox && lease.purposeRaw == "p1DerivativeV1") else { throw SharedMediaStorageFailure.conflict }
            if includesInbox && a.stateRaw.hasPrefix("p1Derivative") {
                // The derivative ledger proves every role/pair/file/lease join.
                guard lease.purposeRaw == "p1DerivativeV1", a.materializedBytes >= 0, a.reservedBytes >= 0 else { throw SharedMediaStorageFailure.conflict }
                if r.work.contains(where: { $0.assetID == a.id && $0.writerStateRaw != "closedPairWaiting" }) {
                    try totals.includePhotoPreparation(package: origin, bytes: SharedMediaStoragePolicy.add(a.materializedBytes, a.reservedBytes))
                }
            } else if ["p1Materialized", "p1Retiring"].contains(a.stateRaw) {
                let retiring = a.stateRaw == "p1Retiring"
                let refs = r.references.filter { $0.assetID == a.id }
                guard a.reservedBytes == 0, a.materializedBytes > 0, a.materializedBytes <= PhotoPreparationPolicy.original,
                      let identity = a.physicalIdentity, !identity.isEmpty, identity.utf8.count <= 512,
                      lease.stateRaw == "closed",
                      r.work.filter({ $0.assetID == a.id }).allSatisfy({ includesInbox && $0.writerStateRaw == "closedSourceRetained" }),
                      let asset = r.assets.first(where: { $0.id == a.id }), asset.ownerID == owner,
                      asset.fileToken == a.fileToken, asset.byteCount == a.materializedBytes,
                      asset.cleanupStateRaw == (retiring ? "retiring" : "ready"),
                      asset.sha256.count == 64, asset.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                      !asset.contentType.isEmpty, asset.contentType.utf8.count <= 128,
                      !refs.isEmpty, refs.allSatisfy({ $0.isLive != retiring }),
                      !retiring || refs.count == 1 else { throw SharedMediaStorageFailure.conflict }
                if retiring { _ = try SharedMediaPhotoRetirementIdentity.decode(identity) }
            } else if includesInbox && a.stateRaw.hasPrefix("p1Inbox") {
                // The paired handoff validator owns the exact request/source
                // joins. B is already inside H; detached A is added there once.
                guard a.materializedBytes >= 0, a.reservedBytes >= 0,
                      try SharedMediaStoragePolicy.add(a.materializedBytes, a.reservedBytes) <= PhotoPreparationPolicy.original,
                      !r.assets.contains(where: { $0.id == a.id }),
                      !r.references.contains(where: { $0.assetID == a.id }),
                      !r.edges.contains(where: { $0.allocationID == a.id }) else { throw SharedMediaStorageFailure.conflict }
            } else {
                guard ["p1Reserved", "p1Held"].contains(a.stateRaw), a.materializedBytes == 0,
                      a.reservedBytes > 0, a.reservedBytes <= PhotoPreparationPolicy.original, a.physicalIdentity == nil,
                      !r.assets.contains(where: { $0.id == a.id }), !r.references.contains(where: { $0.assetID == a.id }),
                      !r.edges.contains(where: { $0.allocationID == a.id }),
                      let work = r.work.first(where: { $0.id == lease.id }),
                      let p = r.packages.first(where: { $0.id == origin && $0.ownerID == owner }),
                      work.assetID == a.id, work.packageID == origin, work.ownerID == owner,
                      work.processEpoch == lease.processEpoch, work.purposeRaw == "acquire",
                      work.finalFileToken == a.fileToken, work.partialFileToken == a.fileToken + ".partial",
                      work.reservedByteCount == a.reservedBytes, work.allocatedByteCount == 0, work.sourceIdentity == nil,
                      work.terminalProof == nil,
                      lease.stateRaw == (a.stateRaw == "p1Reserved" ? "open" : "unknown"),
                      work.writerStateRaw == (a.stateRaw == "p1Reserved" ? "open" : "unknown"),
                      a.stateRaw != "p1Held" || p.phaseRaw == "needsAttention" else { throw SharedMediaStorageFailure.conflict }
                try totals.includeLogical(package: origin, pool: .acquisition, bytes: a.reservedBytes)
            }
            try totals.includePhotoPhysical(materialized: a.materializedBytes, reserved: a.reservedBytes)
        }
        for edge in r.references {
            guard let asset = r.assets.first(where: { $0.id == edge.assetID }), asset.ownerID == edge.ownerID,
                  r.packages.contains(where: { $0.id == edge.packageID && $0.ownerID == edge.ownerID }),
                  edge.roleRaw == "original" || (includesInbox && ["aiInput", "display"].contains(edge.roleRaw)), (0..<2).contains(edge.ordinal), edge.revision == (edge.isLive ? 0 : 1),
                  let shared = r.edges.first(where: { $0.id == edge.id }),
                  shared.allocationID == edge.assetID, shared.accountID == edge.ownerID,
                  shared.ownerID == edge.id.uuidString.lowercased(), shared.roleRaw == Self.namespace,
                  shared.stateRaw == (edge.isLive ? "live" : "retired"), shared.revision == edge.revision else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        return totals
    }

    func inventory() throws -> SharedMediaPhotoInventory {
        _ = try validate()
        let r = try rows()
        let handles = try r.references.filter { $0.isLive && $0.roleRaw == "original" }.map { edge in
            guard let asset = r.assets.first(where: { $0.id == edge.assetID }),
                  let package = r.packages.first(where: { $0.id == edge.packageID }) else { throw SharedMediaStorageFailure.conflict }
            return PhotoOriginalReference(ownerID: edge.ownerID, packageID: edge.packageID, referenceID: edge.id,
                assetID: asset.id, assetGeneration: asset.generation, draftGeneration: package.draftGeneration,
                referenceRevision: edge.revision)
        }
        return SharedMediaPhotoInventory(files: r.assets.map(Self.file), originals: handles,
            identities: Dictionary(uniqueKeysWithValues: r.allocations.compactMap { a in a.physicalIdentity.map { (a.id, $0) } }),
            pendingTokens: Set(r.work.flatMap { [$0.partialFileToken, $0.finalFileToken] }).union(try derivativeTokens()),
            retiringIDs: Set(r.allocations.filter { ["p1Retiring", "p1DerivativeRetiring"].contains($0.stateRaw) }.map(\.id)))
    }

    func reserve(_ intent: PhotoPreparationIntent) throws {
        let r = try rows()
        guard r.work.isEmpty, !r.assets.contains(where: { $0.cleanupStateRaw == "retiring" }), intent.role == .original, intent.sourceByteLiability == 0, intent.sourceIdentity == nil,
              !r.allocations.contains(where: { $0.id == intent.assetID }), !r.leases.contains(where: { $0.id == intent.leaseID }),
              !r.edges.contains(where: { $0.id == intent.referenceID }) else { throw SharedMediaStorageFailure.conflict }
        try PhotoPreparationRepository.reserve(intent, joint: joint)
        context.insert(SharedMediaAllocationRecord(id: intent.assetID, inventoryID: inventoryID,
            accountID: intent.ownerID, packageID: intent.packageID, namespaceRaw: Self.namespace,
            fileToken: intent.fileToken, poolRaw: "durable", stateRaw: "p1Reserved",
            materializedBytes: 0, reservedBytes: intent.maximumBytes, physicalIdentity: nil))
        context.insert(SharedMediaLeaseRecord(id: intent.leaseID, allocationID: intent.assetID,
            processEpoch: intent.processEpoch, purposeRaw: "p1AcquireV1", stateRaw: "open"))
    }

    func requireReservation(_ intent: PhotoPreparationIntent) throws {
        _ = try validate()
        let r = try rows()
        guard let a = r.allocations.first(where: { $0.id == intent.assetID }), a.stateRaw == "p1Reserved",
              a.accountID == intent.ownerID, a.packageID == intent.packageID,
              a.fileToken == intent.fileToken, a.reservedBytes == intent.maximumBytes,
              let w = r.work.first(where: { $0.id == intent.leaseID }), w.assetID == intent.assetID,
              w.processEpoch == intent.processEpoch,
              let p = r.packages.first(where: { $0.id == intent.packageID }), p.draftGeneration == intent.draftGeneration else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    func commit(_ intent: PhotoPreparationIntent, file: PhotoPreparationFile, identity: String) throws -> PhotoOriginalReference {
        try requireReservation(intent)
        let r = try rows()
        guard let a = r.allocations.first(where: { $0.id == intent.assetID }),
              let lease = r.leases.first(where: { $0.id == intent.leaseID }) else { throw SharedMediaStorageFailure.conflict }
        let handle = try PhotoPreparationRepository.commit(intent, file: file, joint: joint)
        a.stateRaw = "p1Materialized"
        a.materializedBytes = file.byteCount
        a.reservedBytes = 0
        a.physicalIdentity = identity
        lease.stateRaw = "closed"
        context.insert(SharedMediaReferenceRecord(id: intent.referenceID, allocationID: intent.assetID,
            accountID: intent.ownerID, ownerID: intent.referenceID.uuidString.lowercased(),
            roleRaw: Self.namespace, stateRaw: "live", revision: 0))
        return handle
    }

    func completed(_ intent: PhotoPreparationIntent, file: PhotoPreparationFile) throws -> PhotoOriginalReference {
        let handle = PhotoOriginalReference(ownerID: intent.ownerID, packageID: intent.packageID,
            referenceID: intent.referenceID, assetID: intent.assetID, assetGeneration: intent.assetGeneration,
            draftGeneration: intent.draftGeneration, referenceRevision: 0)
        guard try resolve(handle) == file else { throw SharedMediaStorageFailure.conflict }
        let r = try rows()
        guard let lease = r.leases.first(where: { $0.id == intent.leaseID }),
              lease.allocationID == intent.assetID, lease.processEpoch == intent.processEpoch,
              r.references.first(where: { $0.id == intent.referenceID })?.ordinal == intent.ordinal else {
            throw SharedMediaStorageFailure.conflict
        }
        return handle
    }

    func resolve(_ handle: PhotoOriginalReference) throws -> PhotoPreparationFile {
        try handle.validate()
        _ = try validate()
        let r = try rows()
        guard let p = r.packages.first(where: { $0.id == handle.packageID }), p.ownerID == handle.ownerID,
              p.draftGeneration == handle.draftGeneration,
              let ref = r.references.first(where: { $0.id == handle.referenceID }), ref.assetID == handle.assetID,
              ref.packageID == handle.packageID, ref.ownerID == handle.ownerID, ref.roleRaw == "original", ref.isLive, ref.revision == handle.referenceRevision,
              let asset = r.assets.first(where: { $0.id == handle.assetID }), asset.generation == handle.assetGeneration, asset.cleanupStateRaw == "ready" else {
            throw PhotoPreparationFailure.staleGeneration
        }
        return Self.file(asset)
    }

    func hold(_ intent: PhotoPreparationIntent) throws {
        let r = try rows()
        guard let a = r.allocations.first(where: { $0.id == intent.assetID }) else { return }
        if a.stateRaw != "p1Reserved" { return }
        try requireReservation(intent)
        guard let lease = r.leases.first(where: { $0.id == intent.leaseID }),
              let work = r.work.first(where: { $0.id == intent.leaseID }),
              let package = r.packages.first(where: { $0.id == intent.packageID }) else { throw SharedMediaStorageFailure.conflict }
        a.stateRaw = "p1Held"
        lease.stateRaw = "unknown"
        work.writerStateRaw = "unknown"
        package.phaseRaw = "needsAttention"
        package.revision = try SharedMediaStoragePolicy.add(package.revision, 1)
    }

    func share(_ request: SharedMediaPhotoShareRequest) throws {
        let r = try rows(), destination = try request.destination()
        guard r.work.isEmpty, !r.assets.contains(where: { $0.cleanupStateRaw == "retiring" }) else { throw SharedMediaStorageFailure.inUse }
        guard r.packages.first(where: { $0.id == request.source.packageID })?.phaseRaw != "preparedHeld" else { throw PhotoPreparationFailure.immutablePackage }
        let file = try resolve(request.source)
        guard r.packages.count < 4, !r.packages.contains(where: { $0.id == destination.packageID }),
              !r.references.contains(where: { $0.id == destination.referenceID }) else { throw SharedMediaStorageFailure.conflict }
        context.insert(PhotoPreparationRecord(id: destination.packageID, ownerID: destination.ownerID,
            contractVersion: PhotoPreparationPolicy.contract, draftID: destination.packageID,
            draftGeneration: destination.draftGeneration, revision: 0, phaseRaw: "draftOwned",
            supportingContextData: try PhotoPreparationPolicy.encodeDraft(contexts: []), allocatedByteCount: file.byteCount, retirementRequested: false))
        context.insert(PhotoPreparationReference(id: destination.referenceID, packageID: destination.packageID,
            assetID: destination.assetID, ownerID: destination.ownerID, roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
        context.insert(SharedMediaReferenceRecord(id: destination.referenceID, allocationID: destination.assetID,
            accountID: destination.ownerID, ownerID: destination.referenceID.uuidString.lowercased(), roleRaw: Self.namespace, stateRaw: "live", revision: 0))
    }

    // The optional result returns the file, binding and ownership flag from one ledger read.
    /// Missing IDs convey no file authority and never recreate a row.
    func reference(_ handle: PhotoOriginalReference) throws -> (PhotoPreparationFile, String, Bool)? { // swiftlint:disable:this large_tuple
        try handle.validate()
        _ = try validate()
        let r = try rows()
        guard let edge = r.references.first(where: { $0.id == handle.referenceID }) else {
            if let asset = r.assets.first(where: { $0.id == handle.assetID }) {
                guard asset.ownerID == handle.ownerID, asset.generation == handle.assetGeneration else { throw SharedMediaStorageFailure.conflict }
            }
            return nil
        }
        guard let package = r.packages.first(where: { $0.id == edge.packageID }),
              let asset = r.assets.first(where: { $0.id == edge.assetID }),
              let allocation = r.allocations.first(where: { $0.id == asset.id }),
              edge.ownerID == handle.ownerID, edge.packageID == handle.packageID, edge.assetID == handle.assetID, edge.roleRaw == "original",
              package.draftGeneration == handle.draftGeneration, asset.generation == handle.assetGeneration,
              edge.revision == (try SharedMediaStoragePolicy.add(handle.referenceRevision, edge.isLive ? 0 : 1)),
              let identity = allocation.physicalIdentity else { throw SharedMediaStorageFailure.stale }
        return (Self.file(asset), identity, !edge.isLive)
    }

    func purgeHandles() throws -> [PhotoOriginalReference] {
        guard purging else { throw SharedMediaStorageFailure.closed }
        _ = try validate()
        let r = try rows()
        guard r.work.isEmpty else { throw SharedMediaStorageFailure.inUse }
        return try r.references.filter { $0.roleRaw == "original" }.map { edge in
            guard let asset = r.assets.first(where: { $0.id == edge.assetID }),
                  let package = r.packages.first(where: { $0.id == edge.packageID }) else { throw SharedMediaStorageFailure.conflict }
            return .init(ownerID: edge.ownerID, packageID: package.id, referenceID: edge.id,
                assetID: asset.id, assetGeneration: asset.generation, draftGeneration: package.draftGeneration,
                referenceRevision: edge.isLive ? edge.revision : edge.revision - 1)
        }.sorted { $0.referenceID.uuidString < $1.referenceID.uuidString }
    }

    func retirementHandles(ownerID: UUID) throws -> [PhotoOriginalReference] {
        _ = try validate()
        let r = try rows()
        guard r.work.isEmpty else { throw SharedMediaStorageFailure.inUse }
        return try r.references.filter { !$0.isLive && $0.ownerID == ownerID }.map { edge in
            guard let asset = r.assets.first(where: { $0.id == edge.assetID }),
                  let package = r.packages.first(where: { $0.id == edge.packageID }), edge.revision > 0 else { throw SharedMediaStorageFailure.conflict }
            return PhotoOriginalReference(ownerID: ownerID, packageID: package.id, referenceID: edge.id,
                assetID: asset.id, assetGeneration: asset.generation, draftGeneration: package.draftGeneration, referenceRevision: edge.revision - 1)
        }
    }

    func retire(_ handle: PhotoOriginalReference, inspection: SharedMediaPhotoRetirementInspection) throws {
        if includesInbox {
            var query = FetchDescriptor<SharedMediaDerivativePairRecord>(); query.fetchLimit = 10
            let pairs = try context.fetch(query)
            guard pairs.count <= 9, pairs.allSatisfy({ $0.originalReferenceID != handle.referenceID }) else { throw SharedMediaStorageFailure.inUse }
        }
        let r = try rows()
        guard r.work.isEmpty else { throw SharedMediaStorageFailure.inUse }
        guard purging || r.packages.first(where: { $0.id == handle.packageID })?.phaseRaw != "preparedHeld" else { throw PhotoPreparationFailure.immutablePackage }
        guard let (file, identity, retiring) = try reference(handle), !retiring,
              file == inspection.file, identity == inspection.identity.file,
              let edge = r.references.first(where: { $0.id == handle.referenceID }),
              let shared = r.edges.first(where: { $0.id == edge.id }),
              let allocation = r.allocations.first(where: { $0.id == edge.assetID }),
              let asset = r.assets.first(where: { $0.id == edge.assetID }) else { throw SharedMediaStorageFailure.stale }
        if r.references.contains(where: { $0.assetID == asset.id && $0.id != edge.id && $0.isLive }) {
            context.delete(edge); context.delete(shared)
            try refreshPackages(r, excluding: [edge.id])
        } else {
            edge.isLive = false; edge.revision = try SharedMediaStoragePolicy.add(edge.revision, 1)
            shared.stateRaw = "retired"; shared.revision = edge.revision
            allocation.stateRaw = "p1Retiring"; allocation.physicalIdentity = try inspection.identity.encoded()
            asset.cleanupStateRaw = "retiring"
            try refreshPackages(r, excluding: [])
        }
    }

    func release(_ retirement: SharedMediaPhotoRetirement) throws {
        let r = try rows()
        guard r.work.isEmpty, let (file, identity, retiring) = try reference(retirement.handle), retiring,
              file == retirement.file, try SharedMediaPhotoRetirementIdentity.decode(identity) == retirement.identity,
              let asset = r.assets.first(where: { $0.id == file.assetID }),
              let allocation = r.allocations.first(where: { $0.id == file.assetID }),
              let lease = r.leases.first(where: { $0.allocationID == file.assetID }), lease.stateRaw == "closed" else {
            throw SharedMediaStorageFailure.stale
        }
        let refs = r.references.filter { $0.assetID == file.assetID }
        guard refs.count == 1, refs.allSatisfy({ !$0.isLive }) else { throw SharedMediaStorageFailure.inUse }
        let ids = Set(refs.map(\.id))
        for edge in refs { context.delete(edge) }
        for edge in r.edges where ids.contains(edge.id) { context.delete(edge) }
        context.delete(asset); context.delete(allocation); context.delete(lease)
        try refreshPackages(r, excluding: ids)
    }

    private func refreshPackages(_ r: Rows, excluding ids: Set<UUID>) throws {
        for package in r.packages {
            let refs = r.references.filter { $0.packageID == package.id && !ids.contains($0.id) }
            let work = r.work.filter { $0.packageID == package.id }
            if refs.isEmpty && work.isEmpty { context.delete(package); continue }
            let assetIDs = Set(refs.map(\.assetID))
            package.allocatedByteCount = try PhotoPreparationPolicy.add(r.assets.filter { assetIDs.contains($0.id) }.map(\.byteCount))
            package.retirementRequested = !refs.isEmpty && refs.allSatisfy { !$0.isLive }
            if package.retirementRequested { package.phaseRaw = "retiring" } else if purging { package.phaseRaw = "purging" }
            package.revision = try SharedMediaStoragePolicy.add(package.revision, 1)
        }
    }

    private func derivativeTokens() throws -> Set<String> {
        guard includesInbox else { return [] }
        var query = FetchDescriptor<SharedMediaDerivativePairRecord>(); query.fetchLimit = 10
        let pairs = try context.fetch(query)
        var workQuery = FetchDescriptor<SharedMediaDerivativeWorkRecord>(); workQuery.fetchLimit = 19
        let work = try context.fetch(workQuery)
        guard pairs.count <= 9, work.count <= 18 else { throw SharedMediaStorageFailure.conflict }
        return Set(try work.flatMap { item -> [String] in
            guard let pair = pairs.first(where: { $0.id == item.pairID }) else { throw SharedMediaStorageFailure.conflict }
            let token = pair.ownerID.uuidString.lowercased() + "/" + pair.packageID.uuidString.lowercased() + "/" + item.assetID.uuidString.lowercased()
            return [token, token + ".partial"]
        })
    }

    private static func file(_ asset: PhotoPreparationAsset) -> PhotoPreparationFile {
        .init(assetID: asset.id, generation: asset.generation, token: asset.fileToken,
              byteCount: asset.byteCount, sha256: asset.sha256, contentType: asset.contentType)
    }
}
