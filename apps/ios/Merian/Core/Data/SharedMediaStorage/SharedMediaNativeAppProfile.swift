import CryptoKit
import Foundation

/// Versioned identity assertion, never a grant or permission to adopt roots.
/// Existing profiles keep their original path-bound bytes; only a new journal
/// selects the physical-root format. No opener converts a saved profile.
struct SharedMediaNativeAppProfile: Codable, Equatable, Sendable {
    static let mode = "nativeAppContainerV2"
    static let phase = "readyNativeAppContainerV2"

    enum PhysicalBindingFormat: String, Sendable {
        case absolutePathsV1, physicalRootsV1

        init(journalVersion: Int) throws {
            switch journalVersion {
            case 2: self = .absolutePathsV1
            case 3: self = .physicalRootsV1
            default: throw SharedMediaStorageFailure.conflict
            }
        }

        init(bindingFields: [String]) throws {
            if bindingFields.count == 7 { self = .absolutePathsV1 }
            else if bindingFields.count == 8, bindingFields[7] == Self.physicalRootsV1.rawValue {
                self = .physicalRootsV1
            } else { throw SharedMediaStorageFailure.conflict }
        }
    }

    let ownerID: UUID, inventoryID: UUID, generation: UUID
    let storeIdentity: String, physicalBinding: String, receiptDigest: String
    let physicalBindingFormat: PhysicalBindingFormat

    init(ownerID: UUID, inventoryID: UUID, generation: UUID, storeIdentity: String,
         physicalBinding: String, receiptDigest: String,
         physicalBindingFormat: PhysicalBindingFormat = .absolutePathsV1) {
        self.ownerID = ownerID; self.inventoryID = inventoryID; self.generation = generation
        self.storeIdentity = storeIdentity; self.physicalBinding = physicalBinding; self.receiptDigest = receiptDigest
        self.physicalBindingFormat = physicalBindingFormat
    }

    /// Validate the complete saved assertion against the currently held roots.
    /// Matching values cannot mint authority or adopt a different physical root.
    @MainActor
    func requireMatch(_ expected: Self, generation: UUID, authority: String, sources: [String: URL]) throws {
        guard self == expected, self.generation == generation,
              physicalBinding == (try Self.rootBinding(format: physicalBindingFormat, authority: authority, sources: sources)) else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private enum CodingKeys: String, CodingKey {
        case ownerID, inventoryID, generation, storeIdentity, physicalBinding, receiptDigest, physicalBindingFormat
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ownerID = try values.decode(UUID.self, forKey: .ownerID)
        inventoryID = try values.decode(UUID.self, forKey: .inventoryID)
        generation = try values.decode(UUID.self, forKey: .generation)
        storeIdentity = try values.decode(String.self, forKey: .storeIdentity)
        physicalBinding = try values.decode(String.self, forKey: .physicalBinding)
        receiptDigest = try values.decode(String.self, forKey: .receiptDigest)
        if values.contains(.physicalBindingFormat) {
            // Null and explicit legacy tags are noncanonical: the historical
            // form has no discriminator, while the new form requires this tag.
            guard try values.decode(String.self, forKey: .physicalBindingFormat) == PhysicalBindingFormat.physicalRootsV1.rawValue else {
                throw SharedMediaStorageFailure.conflict
            }
            physicalBindingFormat = .physicalRootsV1
        } else { physicalBindingFormat = .absolutePathsV1 }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(ownerID, forKey: .ownerID); try values.encode(inventoryID, forKey: .inventoryID)
        try values.encode(generation, forKey: .generation); try values.encode(storeIdentity, forKey: .storeIdentity)
        try values.encode(physicalBinding, forKey: .physicalBinding); try values.encode(receiptDigest, forKey: .receiptDigest)
        if physicalBindingFormat == .physicalRootsV1 {
            try values.encode(physicalBindingFormat.rawValue, forKey: .physicalBindingFormat)
        }
    }

    var binding: Data {
        get throws {
            var fields = [Self.mode, ownerID.uuidString, inventoryID.uuidString, generation.uuidString,
                storeIdentity, physicalBinding, receiptDigest]
            if physicalBindingFormat == .physicalRootsV1 { fields.append(physicalBindingFormat.rawValue) }
            let result = try SharedMediaNativeBootstrapCodec.encode(fields)
            guard result.count <= 512 else { throw SharedMediaStorageFailure.invalid }; return result
        }
    }
    var rootIdentity: String { get throws { String(decoding: try binding, as: UTF8.self) } }

    /// Current paths locate the fixed child roots. Journal identities, markers
    /// and held/named descriptor checks remain necessary around this digest.
    @MainActor static func rootBinding(format: PhysicalBindingFormat, authority: String,
                                      sources: [String: URL]) throws -> String {
        if format == .absolutePathsV1 {
            return try SharedMediaStorageLookup.binding(authority: authority, sources: sources)
        }
        let namespaces = [SharedMediaInboxFiles.namespace, SharedMediaPhotoLedger.namespace]
        guard Set(sources.keys) == Set(namespaces), SharedMediaNativeBootstrapCodec.identity(authority) else {
            throw SharedMediaStorageFailure.invalid
        }
        var fields = ["nativeAppPhysicalRootsV1", "authority", authority], identities = [authority]
        for namespace in namespaces {
            let root = sources[namespace]!
            guard root.isFileURL, root == root.resolvingSymlinksInPath().standardizedFileURL else {
                throw SharedMediaStorageFailure.invalid
            }
            let identity = try SharedMediaStorageFileOwner.directoryIdentity(root)
            guard SharedMediaNativeBootstrapCodec.identity(identity), !identities.contains(identity) else {
                throw SharedMediaStorageFailure.conflict
            }
            identities.append(identity); fields += [namespace, identity]
        }
        return SHA256.hash(data: try SharedMediaNativeBootstrapCodec.encode(fields)).map { String(format: "%02x", $0) }.joined()
    }
}
