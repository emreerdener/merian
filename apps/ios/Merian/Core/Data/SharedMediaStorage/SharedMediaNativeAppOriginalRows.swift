import Foundation
import SwiftData

/// Model rows confined to one private transaction. This value grants no I/O.
@MainActor
struct SharedMediaNativeAppOriginalRows {
    let inventory: SharedMediaInventoryRecord
    let package: PhotoPreparationRecord
    let member: SharedMediaPendingMembershipRecord
    let asset: PhotoPreparationAsset
    let allocation: SharedMediaAllocationRecord
    let lease: SharedMediaLeaseRecord
    let count: SharedMediaAssetReferenceCountRecord
    let receipt: SharedMediaAcquisitionReceiptRecord

    init(_ c: ModelContext, profile: SharedMediaNativeAppProfile, source: PhotoOriginalReference) throws {
        let inventoryID = profile.inventoryID, packageID = source.packageID, assetID = source.assetID
        inventory = try Self.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        package = try Self.one(c, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try Self.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        asset = try Self.one(c, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        allocation = try Self.one(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        lease = try Self.one(c, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.allocationID == assetID }))
        count = try Self.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        receipt = try Self.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
    }
    static func originalFacts(_ c: ModelContext, facts: SharedMediaNativeAppMetadataFacts) throws -> [UUID: SharedMediaNativeOriginalAccounting.Snapshot] {
        var ids = Set<UUID>(), result: [UUID: SharedMediaNativeOriginalAccounting.Snapshot] = [:]
        for member in facts.members.values {
            let membership = try SharedMediaMembership.decode(member.bytes)
            ids.formUnion(membership.ids(.asset)); ids.formUnion(membership.ids(.allocation))
        }
        for id in ids {
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: id, context: c) != nil { continue }
            if try c.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id })) == 0 { continue }
            result[id] = try SharedMediaNativeOriginalAccounting.audit(assetID: id, inventoryID: facts.profile.inventoryID, context: c)
        }
        return result
    }
    static func one<T: PersistentModel>(_ c: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(c, query)
    }
    static func reference(_ c: ModelContext, source: PhotoOriginalReference, live: Bool, ordinal: Int64? = nil) throws -> (PhotoPreparationReference, SharedMediaReferenceRecord) {
        let id = source.referenceID
        let ref = try one(c, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id }))
        let edge = try one(c, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id }))
        let revision = try SharedMediaStoragePolicy.add(source.referenceRevision, live ? 0 : 1)
        guard ref.packageID == source.packageID, ref.assetID == source.assetID, ref.ownerID == source.ownerID,
              ref.roleRaw == "original", ref.isLive == live, ref.revision == revision,
              (0..<2).contains(ref.ordinal), ordinal == nil || ref.ordinal == ordinal,
              edge.allocationID == source.assetID, edge.accountID == source.ownerID,
              edge.ownerID == id.uuidString.lowercased(), edge.roleRaw == SharedMediaPhotoLedger.namespace,
              edge.stateRaw == (live ? "live" : "retired"), edge.revision == revision else { throw SharedMediaStorageFailure.stale }
        return (ref, edge)
    }
    static func absentReference(_ c: ModelContext, _ id: UUID) throws {
        guard try c.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id })) == 0,
              try c.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id })) == 0 else { throw SharedMediaStorageFailure.stale }
    }
    static func noPair(_ c: ModelContext, source: PhotoOriginalReference) throws {
        let id = source.referenceID
        guard try c.fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.originalReferenceID == id })) == 0 else { throw SharedMediaStorageFailure.inUse }
    }
    func completed() throws -> (SharedMediaAcquisitionIntent, SharedMediaAcquisitionResult) {
        guard case .completed(let request, let result) = try SharedMediaAcquisitionReceipt.read(receipt),
              request.assetID == asset.id, request.inventoryID == inventory.id,
              request.inventoryGeneration == inventory.generation, request.ownerID == asset.ownerID,
              request.assetGeneration == asset.generation, request.finalToken == asset.fileToken,
              result.byteCount == asset.byteCount, result.sha256 == asset.sha256,
              result.contentType == asset.contentType else { throw SharedMediaStorageFailure.conflict }
        return (request, result)
    }
    func readyPackage(_ source: PhotoOriginalReference, facts: SharedMediaNativeAppMetadataFacts) throws {
        try source.validate()
        guard facts.consumers[package.id] == nil, facts.packages[package.id] == .init(package),
              facts.members[package.id] == .init(member), source.ownerID == facts.profile.ownerID,
              source.draftGeneration == package.draftGeneration, source.assetGeneration == asset.generation,
              package.phaseRaw == "draftOwned", package.accountingTierRaw == "pending", !package.retirementRequested,
              package.contractVersion == PhotoPreparationPolicy.contract else { throw SharedMediaStorageFailure.closed }
        let envelope = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        guard envelope.attempt == nil else { throw SharedMediaStorageFailure.closed }
        if case .preparation(let value) = envelope, value.frozen != nil { throw SharedMediaStorageFailure.closed }
    }
    func removalMember(_ c: ModelContext, source: PhotoOriginalReference, final: Bool) throws -> Data {
        if final { return member.membersData }
        let assetID = source.assetID, packageID = source.packageID
        let number = try c.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID && $0.packageID == packageID }))
        guard number > 0 else { throw SharedMediaStorageFailure.conflict }
        return try SharedMediaNativeLifecycleMembership.removing(member.membersData, referenceID: source.referenceID,
            assetID: assetID, leaseID: lease.id, removeAsset: number == 1)
    }
    static func shareMembership(_ destination: PhotoOriginalReference, leaseID: UUID) throws -> Data {
        try SharedMediaMembership(groups: [
            .init(kind: .asset, ids: [destination.assetID]), .init(kind: .allocation, ids: [destination.assetID]),
            .init(kind: .lease, ids: [leaseID]), .init(kind: .reference, ids: [destination.referenceID]),
            .init(kind: .edge, ids: [destination.referenceID])
        ].sorted { $0.kind.rawValue < $1.kind.rawValue }).encoded()
    }
}
