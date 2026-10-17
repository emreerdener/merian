import CryptoKit
import Foundation

/// An exact frozen assertion. Only the fenced coordinator may validate its joins
/// and issue a read capability; decoding this value grants no file or AI access.
struct SharedMediaConsumerCohort: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let role: String
        let ordinal: Int64
        let referenceID: UUID
        let referenceRevision: Int64
        let assetID: UUID
        let assetGeneration: UUID
        let pairID: UUID
        let workID: UUID?
        let byteCount: Int64
        let sha256: String
        let contentType: String
        let physicalIdentity: String
    }
    let version: Int
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let ownerID: UUID
    let packageID: UUID
    let draftGeneration: UUID
    let packageRevision: Int64
    let contextSHA256: String
    let entries: [Entry]

    func validate() throws {
        guard version == 1, packageRevision > 0, Self.hash(contextSHA256),
              entries.count == 3 || entries.count == 6 else { throw SharedMediaStorageFailure.conflict }
        let count = entries.count / 3
        guard Set(entries.map(\.referenceID)).count == entries.count,
              Set(entries.map(\.assetID)).count == entries.count else { throw SharedMediaStorageFailure.conflict }
        for (roleIndex, role) in ["original", "aiInput", "display"].enumerated() {
            for ordinal in 0..<count {
                let entry = entries[roleIndex * count + ordinal]
                let maximum = role == "original" ? PhotoPreparationPolicy.original :
                    (role == "aiInput" ? PhotoPreparationPolicy.aiCohort : PhotoPreparationPolicy.display)
                guard entry.role == role, entry.ordinal == Int64(ordinal), entry.referenceRevision >= 0,
                      entry.byteCount > 0, entry.byteCount <= maximum, Self.hash(entry.sha256),
                      !entry.contentType.isEmpty, entry.contentType.utf8.count <= 128,
                      !entry.physicalIdentity.isEmpty, entry.physicalIdentity.utf8.count <= 512,
                      (entry.workID == nil) == (role == "original"),
                      entry.pairID == entries[ordinal].pairID else { throw SharedMediaStorageFailure.conflict }
            }
        }
        for (role, limit) in [("original", PhotoPreparationPolicy.originalCohort),
                              ("aiInput", PhotoPreparationPolicy.aiCohort), ("display", PhotoPreparationPolicy.displayCohort)] {
            guard try PhotoPreparationPolicy.add(entries.filter { $0.role == role }.map(\.byteCount)) <= limit else {
                throw SharedMediaStorageFailure.capacity
            }
        }
        guard Set(entries.prefix(count).map(\.pairID)).count == count,
              Set(entries.compactMap(\.workID)).count == count * 2 else { throw SharedMediaStorageFailure.conflict }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        return data
    }

    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.capacity }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard try value.encoded() == data else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    func digest(context: Data) throws -> String {
        try validate()
        guard context.count <= PhotoPreparationPolicy.metadata,
              SHA256.hash(data: context).map({ String(format: "%02x", $0) }).joined() == contextSHA256 else {
            throw SharedMediaStorageFailure.conflict
        }
        var hasher = SHA256()
        func field(_ bytes: Data) {
            var size = UInt64(bytes.count).bigEndian
            withUnsafeBytes(of: &size) { hasher.update(data: Data($0)) }
            hasher.update(data: bytes)
        }
        func text(_ value: String) { field(Data(value.utf8)) }
        func integer(_ value: Int64) {
            var fixed = value.bigEndian
            withUnsafeBytes(of: &fixed) { field(Data($0)) }
        }
        text("merian.shared-photo.consumer.v1")
        for id in [inventoryID, inventoryGeneration, ownerID, packageID, draftGeneration] {
            text(id.uuidString.lowercased())
        }
        integer(packageRevision); text(PhotoPreparationPolicy.contract); field(context)
        integer(Int64(entries.count))
        for item in entries {
            text(item.role); integer(item.ordinal)
            text(item.referenceID.uuidString.lowercased()); integer(item.referenceRevision)
            text(item.assetID.uuidString.lowercased()); text(item.assetGeneration.uuidString.lowercased())
            integer(item.byteCount); text(item.contentType); text(item.sha256); text(item.physicalIdentity)
            text(item.pairID.uuidString.lowercased()); text(item.workID?.uuidString.lowercased() ?? "")
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
