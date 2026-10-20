import Foundation

/// Frozen app-local facts, not save or file capabilities. A later replay may
/// tolerate unrelated inventory progress, but never changes to this local tuple.
struct SharedMediaNativeAppOriginalRequest: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case share(SharedMediaNativeShareRequest)
        case remove(SharedMediaNativeRemovalRequest)
    }
    let profile: SharedMediaNativeAppProfile
    let source: PhotoOriginalReference
    let package: SharedMediaNativeAppMetadataFacts.Package
    let member: SharedMediaNativeAppMetadataFacts.Member
    let original: SharedMediaNativeOriginalAccounting.Snapshot
    let ordinal: Int64
    let action: Action
}

extension SharedMediaNativeOriginalAccounting.Snapshot {
    /// Only global progress is disregarded. Every original-local scalar remains
    /// exact, including lease epoch and physical descriptor.
    func atInventoryRevision(_ revision: Int64, liveCount: Int64? = nil, countRevision: Int64? = nil,
                             retirement: SharedMediaNativeRetirementIdentity? = nil) throws -> Self {
        .init(inventoryID: inventoryID, inventoryGeneration: inventoryGeneration, inventoryRevision: revision,
            assetID: assetID, assetGeneration: assetGeneration, ownerID: ownerID,
            liveCount: liveCount ?? self.liveCount, countRevision: countRevision ?? self.countRevision,
            retirement: retirement ?? self.retirement, leaseID: leaseID, leaseEpoch: leaseEpoch,
            fileToken: fileToken, physicalIdentity: try retirement?.encoded() ?? physicalIdentity,
            byteCount: byteCount, sha256: sha256, contentType: contentType)
    }
    var file: PhotoPreparationFile {
        .init(assetID: assetID, generation: assetGeneration, token: fileToken,
            byteCount: byteCount, sha256: sha256, contentType: contentType)
    }
}
