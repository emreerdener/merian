import Foundation
import SwiftData

struct SharedMediaPhotoInventory: Sendable {
    let files: [PhotoPreparationFile]
    let originals: [PhotoOriginalReference]
    let identities: [UUID: String]
    let pendingTokens: Set<String>
    var hasPending: Bool { !pendingTokens.isEmpty }
}

/// A bounded join of the two native ownership graphs. Models never leave this
/// transaction; the caller owns its single save and the exclusive store fence.
@MainActor
final class SharedMediaPhotoLedger {
    static let namespace = "p1OriginalV1"
    private let joint: SharedMediaPhotoTransaction
    private let inventoryID: UUID
    private var context: ModelContext { joint.context }

    init(joint: SharedMediaPhotoTransaction, inventoryID: UUID) {
        self.joint = joint
        self.inventoryID = inventoryID
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
            allocations: bounded(SharedMediaAllocationRecord.self, maximum: 96),
            edges: bounded(SharedMediaReferenceRecord.self, maximum: 128),
            leases: bounded(SharedMediaLeaseRecord.self, maximum: 96))
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
              r.assets.count == r.references.count, r.references.count == r.edges.count,
              r.allocations.count == r.assets.count + r.work.count else { throw SharedMediaStorageFailure.conflict }
        var totals = SharedMediaStoragePolicy.Totals()
        for p in r.packages {
            let envelope = try PhotoPreparationPolicy.decodeDraft(p.supportingContextData)
            let allocations = r.allocations.filter { $0.packageID == p.id }
            let assets = r.assets.filter { a in allocations.contains { $0.id == a.id } }
            let refs = r.references.filter { $0.packageID == p.id }
            guard !allocations.isEmpty, allocations.count <= 2,
                  p.contractVersion == PhotoPreparationPolicy.contract, p.draftID == p.id,
                  !p.retirementRequested, p.revision >= 0,
                  ["acquiring", "draftOwned", "needsAttention"].contains(p.phaseRaw),
                  envelope.contexts.isEmpty, envelope.presentation.isEmpty,
                  p.supportingContextData.count <= PhotoPreparationPolicy.metadata,
                  p.allocatedByteCount == (try PhotoPreparationPolicy.add(assets.map(\.byteCount))),
                  Set(refs.map(\.ordinal)).count == refs.count,
                  try PhotoPreparationPolicy.add(allocations.map { try SharedMediaStoragePolicy.add($0.materializedBytes, $0.reservedBytes) }) <= PhotoPreparationPolicy.originalCohort else {
                throw SharedMediaStorageFailure.conflict
            }
            try totals.includeLogical(package: p.id, pool: .durable, bytes: Int64(p.supportingContextData.count))
        }
        for a in r.allocations {
            guard a.inventoryID == inventoryID, let owner = a.accountID, let package = a.packageID,
                  let p = r.packages.first(where: { $0.id == package && $0.ownerID == owner }),
                  a.namespaceRaw == Self.namespace, a.poolRaw == "durable",
                  a.fileToken == owner.uuidString.lowercased() + "/" + package.uuidString.lowercased() + "/" + a.id.uuidString.lowercased(),
                  r.leases.filter({ $0.allocationID == a.id }).count == 1,
                  let lease = r.leases.first(where: { $0.allocationID == a.id }),
                  lease.purposeRaw == "p1AcquireV1" else { throw SharedMediaStorageFailure.conflict }
            if a.stateRaw == "p1Materialized" {
                guard a.reservedBytes == 0, a.materializedBytes > 0, a.materializedBytes <= PhotoPreparationPolicy.original,
                      let identity = a.physicalIdentity, !identity.isEmpty, identity.utf8.count <= 256,
                      lease.stateRaw == "closed", !r.work.contains(where: { $0.assetID == a.id }),
                      let asset = r.assets.first(where: { $0.id == a.id }), asset.ownerID == owner,
                      asset.fileToken == a.fileToken, asset.byteCount == a.materializedBytes, asset.cleanupStateRaw == "ready",
                      asset.sha256.count == 64, asset.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                      !asset.contentType.isEmpty, asset.contentType.utf8.count <= 128,
                      let edge = r.references.first(where: { $0.assetID == a.id }),
                      r.references.filter({ $0.assetID == a.id }).count == 1,
                      edge.ownerID == owner, edge.packageID == package, edge.roleRaw == "original", edge.isLive,
                      (0..<2).contains(edge.ordinal), edge.revision == 0,
                      let shared = r.edges.first(where: { $0.id == edge.id }),
                      shared.allocationID == a.id, shared.accountID == owner,
                      shared.ownerID == edge.id.uuidString.lowercased(), shared.roleRaw == Self.namespace,
                      shared.stateRaw == "live", shared.revision == edge.revision else { throw SharedMediaStorageFailure.conflict }
            } else {
                guard ["p1Reserved", "p1Held"].contains(a.stateRaw), a.materializedBytes == 0,
                      a.reservedBytes > 0, a.reservedBytes <= PhotoPreparationPolicy.original, a.physicalIdentity == nil,
                      !r.assets.contains(where: { $0.id == a.id }), !r.edges.contains(where: { $0.allocationID == a.id }),
                      let work = r.work.first(where: { $0.id == lease.id }),
                      work.assetID == a.id, work.packageID == package, work.ownerID == owner,
                      work.processEpoch == lease.processEpoch, work.purposeRaw == "acquire",
                      work.finalFileToken == a.fileToken, work.partialFileToken == a.fileToken + ".partial",
                      work.reservedByteCount == a.reservedBytes, work.allocatedByteCount == 0, work.sourceIdentity == nil,
                      work.terminalProof == nil,
                      lease.stateRaw == (a.stateRaw == "p1Reserved" ? "open" : "unknown"),
                      work.writerStateRaw == (a.stateRaw == "p1Reserved" ? "open" : "unknown"),
                      a.stateRaw != "p1Held" || p.phaseRaw == "needsAttention" else { throw SharedMediaStorageFailure.conflict }
                try totals.includeLogical(package: package, pool: .acquisition, bytes: a.reservedBytes)
            }
            try totals.include(.init(packageID: package, pool: .durable, materialized: a.materializedBytes, reserved: a.reservedBytes))
        }
        return totals
    }

    func inventory() throws -> SharedMediaPhotoInventory {
        _ = try validate()
        let r = try rows()
        let handles = try r.references.map { edge in
            guard let asset = r.assets.first(where: { $0.id == edge.assetID }),
                  let package = r.packages.first(where: { $0.id == edge.packageID }) else { throw SharedMediaStorageFailure.conflict }
            return PhotoOriginalReference(ownerID: edge.ownerID, packageID: edge.packageID, referenceID: edge.id,
                assetID: asset.id, assetGeneration: asset.generation, draftGeneration: package.draftGeneration,
                referenceRevision: edge.revision)
        }
        return SharedMediaPhotoInventory(files: r.assets.map(Self.file), originals: handles,
            identities: Dictionary(uniqueKeysWithValues: r.allocations.compactMap { a in a.physicalIdentity.map { (a.id, $0) } }),
            pendingTokens: Set(r.work.flatMap { [$0.partialFileToken, $0.finalFileToken] }))
    }

    func reserve(_ intent: PhotoPreparationIntent) throws {
        let r = try rows()
        guard r.work.isEmpty, intent.role == .original, intent.sourceByteLiability == 0, intent.sourceIdentity == nil,
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
              ref.packageID == handle.packageID, ref.revision == handle.referenceRevision,
              let asset = r.assets.first(where: { $0.id == handle.assetID }), asset.generation == handle.assetGeneration else {
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

    private static func file(_ asset: PhotoPreparationAsset) -> PhotoPreparationFile {
        .init(assetID: asset.id, generation: asset.generation, token: asset.fileToken,
              byteCount: asset.byteCount, sha256: asset.sha256, contentType: asset.contentType)
    }
}
