import Foundation

/// Persisted proof binding for the native owner, not an unlink capability.
/// Only a jointly saved retirement and separately verified writer/absence
/// conditions may authorize cleanup. Qualification V1 never reads this format.
struct SharedMediaNativeRetirementIdentity: Equatable, Sendable {
    static let allocationState = "nativeOriginalRetiringV2"
    let retirementID: UUID
    let assetID: UUID
    let assetGeneration: UUID
    let inventoryID: UUID
    let inventoryGeneration: UUID
    let ownerID: UUID
    let proof: SharedMediaPhotoRetirementIdentity

    init(retirementID: UUID, assetID: UUID, assetGeneration: UUID,
         inventoryID: UUID, inventoryGeneration: UUID, ownerID: UUID,
         proof: SharedMediaPhotoRetirementIdentity) throws {
        try Self.validate(proof)
        self.retirementID = retirementID; self.assetID = assetID
        self.assetGeneration = assetGeneration; self.inventoryID = inventoryID
        self.inventoryGeneration = inventoryGeneration; self.ownerID = ownerID
        self.proof = proof
    }

    func encoded() throws -> String {
        try Self.validate(proof)
        let wire = Wire(v: 2, r: retirementID.uuidString.lowercased(),
            a: assetID.uuidString.lowercased(), g: assetGeneration.uuidString.lowercased(),
            i: inventoryID.uuidString.lowercased(), j: inventoryGeneration.uuidString.lowercased(),
            o: ownerID.uuidString.lowercased(), f: proof.file, p: proof.parent, n: proof.namespace)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(wire)
        guard bytes.count <= 512, let text = String(data: bytes, encoding: .utf8) else {
            throw SharedMediaStorageFailure.conflict
        }
        return text
    }

    static func decode(_ text: String) throws -> Self {
        guard text.utf8.count <= 512 else { throw SharedMediaStorageFailure.conflict }
        let wire = try JSONDecoder().decode(Wire.self, from: Data(text.utf8))
        guard wire.v == 2 else { throw SharedMediaStorageFailure.conflict }
        let value = try Self(retirementID: uuid(wire.r), assetID: uuid(wire.a), assetGeneration: uuid(wire.g),
            inventoryID: uuid(wire.i), inventoryGeneration: uuid(wire.j), ownerID: uuid(wire.o),
            proof: .init(version: 1, file: wire.f, parent: wire.p, namespace: wire.n))
        // Reject extra/duplicate keys, whitespace, alternate number spellings,
        // escaping and key order, even if JSONDecoder accepts them.
        guard try value.encoded() == text else { throw SharedMediaStorageFailure.conflict }
        return value
    }

    private struct Wire: Codable {
        let v: Int
        let r: String, a: String, g: String, i: String, j: String, o: String
        let f: String, p: String, n: String
    }

    private static func uuid(_ text: String) throws -> UUID {
        guard let value = UUID(uuidString: text), value.uuidString.lowercased() == text else {
            throw SharedMediaStorageFailure.conflict
        }
        return value
    }

    private static func validate(_ proof: SharedMediaPhotoRetirementIdentity) throws {
        guard proof.version == 1, proof.file.utf8.count <= 112,
              proof.parent.utf8.count <= 41, proof.namespace.utf8.count <= 41 else {
            throw SharedMediaStorageFailure.conflict
        }
        let file = proof.file.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard file.count == 7 else { throw SharedMediaStorageFailure.conflict }
        try device(file[0]); try inode(file[1])
        try signed(file[2], minimum: 1, maximum: PhotoPreparationPolicy.original)
        try signed(file[3]); try signed(file[4], minimum: 0, maximum: 999_999_999)
        try signed(file[5]); try signed(file[6], minimum: 0, maximum: 999_999_999)
        for directory in [proof.parent, proof.namespace] {
            let parts = directory.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2 else { throw SharedMediaStorageFailure.conflict }
            try device(parts[0]); try inode(parts[1])
        }
    }

    private static func device(_ text: String) throws {
        try signed(text, minimum: Int64(Int32.min), maximum: Int64(Int32.max))
    }

    private static func inode(_ text: String) throws {
        guard let value = UInt64(text), String(value) == text else { throw SharedMediaStorageFailure.conflict }
    }

    private static func signed(_ text: String, minimum: Int64 = .min, maximum: Int64 = .max) throws {
        guard let value = Int64(text), String(value) == text, (minimum...maximum).contains(value) else {
            throw SharedMediaStorageFailure.conflict
        }
    }
}
