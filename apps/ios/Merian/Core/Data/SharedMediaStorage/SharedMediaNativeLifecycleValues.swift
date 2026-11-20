import CryptoKit
import Foundation

/// Frozen local intents, not mutation or file capabilities. Sharing is limited
/// to a new destination draft; an existing envelope can never be overwritten.
struct SharedMediaNativeShareRequest: Codable, Equatable, Sendable {
    let source: PhotoOriginalReference
    let inventoryID: UUID, inventoryGeneration: UUID
    let inventoryRevision: Int64, sourcePackageRevision: Int64, liveCount: Int64, countRevision: Int64
    let packageID: UUID, draftGeneration: UUID, nonce: UUID
    let envelope: Data
    func destination() throws -> PhotoOriginalReference {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = Array(SHA256.hash(data: Data("merian.native-share.v1\0".utf8) + (try encoder.encode(self))))
        let id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return .init(ownerID: source.ownerID, packageID: packageID, referenceID: id, assetID: source.assetID,
            assetGeneration: source.assetGeneration, draftGeneration: draftGeneration, referenceRevision: 0)
    }
}

struct SharedMediaNativeRemovalRequest: Equatable, Sendable {
    let source: PhotoOriginalReference
    let inventoryID: UUID, inventoryGeneration: UUID
    let inventoryRevision: Int64, packageRevision: Int64, membershipRevision: Int64
    let membershipBytes: Data, previousEnvelope: Data, envelope: Data
    let liveCount: Int64, countRevision: Int64, retirementID: UUID
}

enum SharedMediaNativeLifecycleBoundary: Equatable, Sendable {
    case beforeSave, afterSave, beforeReadback, beforeReleaseSave, afterReleaseSave
}

/// Values describing a saved final retirement, without authority to unlink it.
struct SharedMediaNativeRetirementState: Equatable, Sendable {
    let request: SharedMediaAcquisitionIntent
    let file: PhotoPreparationFile
    let identity: SharedMediaNativeRetirementIdentity
    let reference: PhotoOriginalReference
    let inventoryRevision: Int64, packageRevision: Int64, membershipRevision: Int64, countRevision: Int64
    let membershipBytes: Data, envelope: Data
}

/// Canonical successor of the saved membership tuple. No unrelated group or ID
/// may disappear merely because the resulting current graph is self-consistent.
enum SharedMediaNativeLifecycleMembership {
    static func removing(_ previous: Data, referenceID: UUID, assetID: UUID, leaseID: UUID, removeAsset: Bool) throws -> Data {
        let old = try SharedMediaMembership.decode(previous)
        let removed: [SharedMediaMembership.Kind: UUID] = removeAsset
            ? [.reference: referenceID, .edge: referenceID, .asset: assetID, .allocation: assetID, .lease: leaseID]
            : [.reference: referenceID, .edge: referenceID]
        for (kind, id) in removed { guard old.ids(kind).contains(id) else { throw SharedMediaStorageFailure.conflict } }
        let groups = old.groups.compactMap { group -> SharedMediaMembership.Group? in
            let ids = group.ids.filter { $0 != removed[group.kind] }
            return ids.isEmpty ? nil : .init(kind: group.kind, ids: ids)
        }
        return try SharedMediaMembership(groups: groups).encoded()
    }
}
