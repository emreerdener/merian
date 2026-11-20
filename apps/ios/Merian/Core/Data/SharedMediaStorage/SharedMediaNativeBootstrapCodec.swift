import CryptoKit
import Foundation

/// Fixed-shape control metadata. These bytes are not a media-package reservation.
enum SharedMediaNativeBootstrapCodec {
    struct ParentCreation: Codable, Equatable, Sendable {
        let version: Int
        let store: String, storeParent: String, parent: String
    }
    static let parentName = "MerianNativeMedia"
    static let parentReceiptName = "parent-created-v1.json"
    static func validateParent(_ bytes: Data?, store: String, storeParent: String, parent: String) throws {
        guard let bytes else { return }
        let receipt = try decode(ParentCreation.self, bytes)
        guard receipt.version == 1, receipt.store == store, receipt.storeParent == storeParent,
              receipt.parent == parent else { throw SharedMediaStorageFailure.conflict }
    }
    static func allowedNames(parentReceipt: Data?) -> Set<String> {
        parentReceipt == nil ? controlNames : controlNames.union([parentReceiptName])
    }
    struct Intent: Codable, Equatable, Sendable {
        let version: Int
        let ownerID: UUID, inventoryID: UUID, generation: UUID, operationID: UUID, nonce: UUID
        let store: String, parent: String, storeParent: String
        let names: [String]
    }
    struct Progress: Codable, Equatable, Sendable {
        let version: Int
        let intentDigest: String, name: String, identity: String, parentIdentity: String
    }
    struct Final: Codable, Equatable, Sendable {
        let version: Int
        let intentDigest: String
        let identities: [String]
        let progressDigests: [String]
    }
    static let names = ["authority", "photo", "photo/PhotoPreparation", "inbox", "inbox/InboxSources"]
    static let intentName = "bootstrap-intent-v2.json", finalName = "bootstrap-final-v2.json"
    static let progressNames = (0..<5).map { "bootstrap-root-\($0)-v2.json" }
    static var controlNames: Set<String> { Set(["authority", "photo", "inbox", intentName, finalName] + progressNames) }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    static func decode<T: Codable>(_ type: T.Type, _ bytes: Data) throws -> T {
        guard bytes.count <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.invalid }
        let value = try JSONDecoder().decode(type, from: bytes)
        guard try encode(value) == bytes else { throw SharedMediaStorageFailure.conflict }; return value
    }
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func identity(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { part in
            guard let value = UInt64(part) else { return false }; return String(value) == part
        }
    }
    /// Maximum canonical encoding, using the widest supported descriptor fields.
    static var maximumControlBytes: Int64 {
        get throws {
            let id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
            let wide = "18446744073709551615:18446744073709551615"
            let intent = Intent(version: 2, ownerID: id, inventoryID: id, generation: id,
                operationID: id, nonce: id, store: id.uuidString, parent: wide, storeParent: wide, names: names)
            let digest = String(repeating: "f", count: 64)
            let final = Final(version: 2, intentDigest: digest, identities: Array(repeating: wide, count: 5), progressDigests: Array(repeating: digest, count: 5))
            let progress = try names.map { Int64(try encode(Progress(version: 2, intentDigest: digest, name: $0, identity: wide, parentIdentity: wide)).count) }
            let parent = ParentCreation(version: 1, store: id.uuidString, storeParent: wide, parent: wide)
            let sum = try PhotoPreparationPolicy.add([Int64(encode(intent).count), Int64(encode(final).count), Int64(encode(parent).count)] + progress)
            guard sum <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.invalid }
            // Exact record maxima, three maximum marker payloads, and encoding
            // working copies; no persistent reservation after materialization.
            return try PhotoPreparationPolicy.add([sum, sum, 3 * 512])
        }
    }
}
