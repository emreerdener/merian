import CryptoKit
import Foundation

enum SharedMediaStorageFailure: Error, Equatable {
    case unavailable, busy, invalid, conflict, stale, closed, capacity, inUse
}

enum SharedMediaStorageMode: String, Sendable { case observation, qualification, p1Qualification, p1InboxQualification
    var includesPhotoStorage: Bool { self == .p1Qualification || self == .p1InboxQualification }
}
enum SharedMediaStoragePool: String, Sendable {
    case observed, durable, acquisition, preparation, transfer
}

struct SharedMediaStorageReservation: Equatable, Sendable {
    let id: UUID
    let packageID: UUID
    let accountID: UUID
    let pool: SharedMediaStoragePool
    let bytes: Int64
}

struct SharedMediaStorageCharge: Sendable {
    let packageID: UUID?
    let pool: SharedMediaStoragePool
    let materialized: Int64
    let reserved: Int64
}

struct SharedMediaStorageObservation: Sendable {
    static func id(namespace: String, token: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data((namespace + "\0" + token).utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }

    let id: UUID
    let namespace: String
    let token: String
    let bytes: Int64
    let physicalIdentity: String
}

struct SharedMediaStorageSnapshot: Codable, Equatable, Sendable {
    let generation: UUID
    let revision: Int64
    let phase: String
    let cursor: String
}

/// Retain this exact value across uncertain saves; never rebase it during recovery.
struct SharedMediaPhotoShareRequest: Codable, Sendable {
    let source: PhotoOriginalReference
    let packageID: UUID
    let draftGeneration: UUID
    let inventoryGeneration: UUID
    let expectedRevision: Int64
    let nonce: UUID

    init(source: PhotoOriginalReference, packageID: UUID, draftGeneration: UUID,
                     snapshot: SharedMediaStorageSnapshot) {
        self.source = source; self.packageID = packageID; self.draftGeneration = draftGeneration
        inventoryGeneration = snapshot.generation; expectedRevision = snapshot.revision; nonce = UUID()
    }

    func destination() throws -> PhotoOriginalReference {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = Array(SHA256.hash(data: Data("merian.photo-share.v1\0".utf8) + (try encoder.encode(self))))
        let id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return PhotoOriginalReference(ownerID: source.ownerID, packageID: packageID, referenceID: id,
            assetID: source.assetID, assetGeneration: source.assetGeneration,
            draftGeneration: draftGeneration, referenceRevision: 0)
    }
}

struct SharedMediaPhotoRetirementIdentity: Codable, Equatable, Sendable {
    let version: Int
    let file: String
    let parent: String
    let namespace: String
    func encoded() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= 512, let text = String(data: bytes, encoding: .utf8) else { throw SharedMediaStorageFailure.conflict }
        return text
    }
    static func decode(_ value: String) throws -> Self {
        guard value.utf8.count <= 512 else { throw SharedMediaStorageFailure.conflict }
        let result = try JSONDecoder().decode(Self.self, from: Data(value.utf8))
        guard result.version == 1, !result.file.isEmpty, !result.parent.isEmpty, !result.namespace.isEmpty else {
            throw SharedMediaStorageFailure.conflict
        }
        return result
    }
}


enum SharedMediaPhotoReferenceState: Sendable {
    case absent, live(PhotoPreparationFile), retiring(SharedMediaPhotoRetirement)
}

enum SharedMediaPhotoRetirementResult: Sendable, Equatable {
    case referenceAbsent, referenceRetired, physicalReleaseConfirmed
}

enum SharedMediaPhotoBoundary: Sendable, Equatable { case beforeReservationSave, afterReservationSave, beforeCompletionSave, afterCompletionSave, beforeReadback
    case beforeShareSave, afterShareSave, beforeRetirementSave, afterRetirementSave, beforeReleaseSave, afterReleaseSave, beforeLifecycleReadback
}
