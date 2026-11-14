import CryptoKit
import Foundation

/// Immutable direct-original intent. Encoding establishes identity, never
/// permission to invoke a loader, access media or reconstruct a missing graph.
struct SharedMediaAcquisitionIntent: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case originalRequest = "nativeOriginalRequestV1" }
    enum Kind: String, Codable, Sendable { case picker, camera }
    enum Role: String, Codable, Sendable { case original }
    enum PackageExpectation: Codable, Equatable, Sendable {
        case absent
        case revision(Int64)

        // Keep the persisted coding vocabulary local to its encoded value.
        // swiftlint:disable:next nesting
        private enum CodingKeys: String, CodingKey { case kind, revision }
        // Keep the persisted coding vocabulary local to its encoded value.
        // swiftlint:disable:next nesting
        private enum Kind: String, Codable { case absent, revision }

        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            switch try fields.decode(Kind.self, forKey: .kind) {
            case .absent:
                guard !fields.contains(.revision) else { throw SharedMediaStorageFailure.conflict }
                self = .absent
            case .revision: self = .revision(try fields.decode(Int64.self, forKey: .revision))
            }
        }

        func encode(to encoder: Encoder) throws {
            var fields = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .absent: try fields.encode(Kind.absent, forKey: .kind)
            case .revision(let value):
                try fields.encode(Kind.revision, forKey: .kind)
                try fields.encode(value, forKey: .revision)
            }
        }
    }

    let format: Format
    let version: Int
    let operationID: UUID
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let ownerID: UUID
    let expectedInventoryRevision: Int64
    let packageID: UUID
    let draftGeneration: UUID
    let packageExpectation: PackageExpectation
    let assetID: UUID
    let assetGeneration: UUID
    let referenceID: UUID
    let initialReferenceRevision: Int64
    let role: Role
    let ordinal: Int64
    let kind: Kind
    let writerEpoch: UUID
    let maximumBytes: Int64
    let partialToken: String
    let finalToken: String

    init(operationID: UUID, inventoryID: UUID, inventoryGeneration: UUID,
         ownerID: UUID, expectedInventoryRevision: Int64, packageID: UUID,
         draftGeneration: UUID, packageExpectation: PackageExpectation,
         assetID: UUID, assetGeneration: UUID, referenceID: UUID, ordinal: Int64,
         kind: Kind, writerEpoch: UUID, maximumBytes: Int64) {
        format = .originalRequest; version = 1
        self.operationID = operationID; self.inventoryID = inventoryID
        self.inventoryGeneration = inventoryGeneration; self.ownerID = ownerID
        self.expectedInventoryRevision = expectedInventoryRevision
        self.packageID = packageID; self.draftGeneration = draftGeneration
        self.packageExpectation = packageExpectation
        self.assetID = assetID; self.assetGeneration = assetGeneration
        self.referenceID = referenceID; initialReferenceRevision = 0
        role = .original; self.ordinal = ordinal; self.kind = kind
        self.writerEpoch = writerEpoch; self.maximumBytes = maximumBytes
        finalToken = [ownerID, packageID, assetID].map { $0.uuidString.lowercased() }.joined(separator: "/")
        partialToken = finalToken + ".partial"
    }

    func validate() throws {
        guard version == 1, expectedInventoryRevision >= 0,
              expectedInventoryRevision <= Int64.max - 2,
              initialReferenceRevision == 0, (0..<2).contains(ordinal),
              maximumBytes > 0, maximumBytes <= PhotoPreparationPolicy.original,
              Set([operationID, assetID, referenceID]).count == 3,
              finalToken == [ownerID, packageID, assetID].map({ $0.uuidString.lowercased() }).joined(separator: "/"),
              partialToken == finalToken + ".partial" else { throw SharedMediaStorageFailure.conflict }
        if case .revision(let revision) = packageExpectation {
            guard revision >= 0, revision <= Int64.max - 2 else { throw SharedMediaStorageFailure.conflict }
        }
    }

    func encoded() throws -> Data {
        try validate()
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Int(PhotoPreparationPolicy.metadata))
    }

    static func decode(_ bytes: Data) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: Int(PhotoPreparationPolicy.metadata))
        guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    func fingerprint() throws -> String { SharedMediaAcquisitionEncoding.digest(try encoded()) }
}

/// Shared canonical wire mechanics. Bounds precede decoding. UUIDs use the
/// canonical Foundation UUID encoding; filesystem components remain lowercase.
enum SharedMediaAcquisitionEncoding {
    static func encode<T: Encodable>(_ value: T, maximum: Int) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(value)
        guard !bytes.isEmpty, bytes.count <= maximum else { throw SharedMediaStorageFailure.capacity }
        return bytes
    }

    static func decode<T: Decodable>(_ bytes: Data, maximum: Int) throws -> T {
        guard !bytes.isEmpty, bytes.count <= maximum else { throw SharedMediaStorageFailure.capacity }
        return try JSONDecoder().decode(T.self, from: bytes)
    }

    static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
