import Foundation

/// Additive registration of capture artifacts beneath the existing native
/// authority. The base profile and all existing root markers remain immutable.
/// Values describe a journal; only the fenced filesystem owner may create it.
enum SharedMediaCaptureRootJournal {
    static let namespace = "captureArtifactsV1"
    static let rootName = "capture"
    static let childName = "CaptureArtifacts"
    static let marker = "com.merian.capture-artifacts-v1"
    static let intentName = "capture-root-intent-v1.json"
    static let rootReceiptName = "capture-root-created-v1.json"
    static let childReceiptName = "capture-namespace-created-v1.json"
    static let finalName = "capture-root-final-v1.json"
    static let names: Set<String> = [rootName, intentName, rootReceiptName, childReceiptName, finalName]
    static let maximumRecordBytes = 4096

    struct Intent: Codable, Equatable, Sendable {
        let version: Int
        let operationID: UUID
        let ownerID: UUID
        let inventoryID: UUID
        let inventoryGeneration: UUID
        let profileSHA256: String
        let parentIdentity: String

        init(profile: SharedMediaNativeAppProfile, parentIdentity: String, operationID: UUID) throws {
            version = 1; self.operationID = operationID
            ownerID = profile.ownerID; inventoryID = profile.inventoryID; inventoryGeneration = profile.generation
            profileSHA256 = try SharedMediaNativeBootstrapCodec.digest(profile.binding)
            self.parentIdentity = parentIdentity
            try require(profile: profile, parentIdentity: parentIdentity)
        }

        func require(profile: SharedMediaNativeAppProfile, parentIdentity: String) throws {
            guard version == 1, ownerID == profile.ownerID, inventoryID == profile.inventoryID,
                  inventoryGeneration == profile.generation,
                  Set([operationID, ownerID, inventoryID, inventoryGeneration]).count == 4,
                  profileSHA256 == (try SharedMediaNativeBootstrapCodec.digest(profile.binding)),
                  self.parentIdentity == parentIdentity,
                  SharedMediaNativeBootstrapCodec.identity(parentIdentity) else {
                throw SharedMediaStorageFailure.conflict
            }
        }

        var digest: String { get throws { try SharedMediaNativeBootstrapCodec.digest(SharedMediaCaptureRootJournal.encode(self)) } }
    }

    enum DirectoryKind: String, Codable, Sendable { case root, namespace }

    struct Directory: Codable, Equatable, Sendable {
        let version: Int
        let intentSHA256: String
        let kind: DirectoryKind
        let parentIdentity: String
        let identity: String

        init(intent: Intent, kind: DirectoryKind, parentIdentity: String, identity: String) throws {
            version = 1; intentSHA256 = try intent.digest; self.kind = kind
            self.parentIdentity = parentIdentity; self.identity = identity
            try require(intent: intent, kind: kind, parentIdentity: parentIdentity)
        }

        func require(intent: Intent, kind: DirectoryKind, parentIdentity: String) throws {
            guard version == 1, intentSHA256 == (try intent.digest), self.kind == kind,
                  self.parentIdentity == parentIdentity, identity != parentIdentity,
                  SharedMediaNativeBootstrapCodec.identity(identity),
                  SharedMediaNativeBootstrapCodec.identity(parentIdentity),
                  kind != .root || parentIdentity == intent.parentIdentity else {
                throw SharedMediaStorageFailure.conflict
            }
        }

        var digest: String { get throws { try SharedMediaNativeBootstrapCodec.digest(SharedMediaCaptureRootJournal.encode(self)) } }
    }

    struct Final: Codable, Equatable, Sendable {
        let version: Int
        let intentSHA256: String
        let rootSHA256: String
        let namespaceSHA256: String

        init(intent: Intent, root: Directory, namespace: Directory) throws {
            version = 1; intentSHA256 = try intent.digest
            rootSHA256 = try root.digest; namespaceSHA256 = try namespace.digest
            try require(intent: intent, root: root, namespace: namespace)
        }

        func require(intent: Intent, root: Directory, namespace: Directory) throws {
            try root.require(intent: intent, kind: .root, parentIdentity: intent.parentIdentity)
            try namespace.require(intent: intent, kind: .namespace, parentIdentity: root.identity)
            guard version == 1, intentSHA256 == (try intent.digest), rootSHA256 == (try root.digest),
                  namespaceSHA256 == (try namespace.digest),
                  Set([intent.parentIdentity, root.identity, namespace.identity]).count == 3 else {
                throw SharedMediaStorageFailure.conflict
            }
        }

        /// The extension gets a separate marker. This never replaces the base
        /// profile marker or creates permission to use its photo/inbox roots.
        func binding(intent: Intent, root: Directory, namespace: Directory) throws -> Data {
            try require(intent: intent, root: root, namespace: namespace)
            let result = try SharedMediaNativeBootstrapCodec.encode([
                "nativeCaptureArtifactsV1", intent.profileSHA256, intentSHA256,
                root.identity, namespace.identity, SharedMediaNativeBootstrapCodec.digest(SharedMediaCaptureRootJournal.encode(self))
            ])
            guard result.count <= 512 else { throw SharedMediaStorageFailure.capacity }
            return result
        }
    }

    /// Completed-prefix validation does not infer ownership of a path whose
    /// creation receipt is missing. The file owner separately proves exact
    /// absence before creating each next directory, or holds ambiguous paths.
    struct Prefix: Equatable, Sendable {
        let intent: Intent
        let root: Directory?
        let namespace: Directory?
        let final: Final?

        init(profile: SharedMediaNativeAppProfile, parentIdentity: String,
             intent: Data, root: Data?, namespace: Data?, final: Data?) throws {
            self.intent = try decode(Intent.self, intent)
            try self.intent.require(profile: profile, parentIdentity: parentIdentity)
            self.root = try root.map { try decode(Directory.self, $0) }
            self.namespace = try namespace.map { try decode(Directory.self, $0) }
            self.final = try final.map { try decode(Final.self, $0) }
            try self.root?.require(intent: self.intent, kind: .root, parentIdentity: parentIdentity)
            if let child = self.namespace {
                guard let root = self.root else { throw SharedMediaStorageFailure.conflict }
                try child.require(intent: self.intent, kind: .namespace, parentIdentity: root.identity)
                guard child.identity != parentIdentity else { throw SharedMediaStorageFailure.conflict }
            }
            if let completion = self.final {
                guard let root = self.root, let namespace = self.namespace else { throw SharedMediaStorageFailure.conflict }
                try completion.require(intent: self.intent, root: root, namespace: namespace)
            }
        }
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let bytes = try SharedMediaNativeBootstrapCodec.encode(value)
        guard !bytes.isEmpty, bytes.count <= maximumRecordBytes else { throw SharedMediaStorageFailure.capacity }
        return bytes
    }

    static func decode<T: Codable>(_ type: T.Type, _ bytes: Data) throws -> T {
        guard !bytes.isEmpty, bytes.count <= maximumRecordBytes else { throw SharedMediaStorageFailure.capacity }
        let value = try JSONDecoder().decode(type, from: bytes)
        // Unknown keys, null optionals, altered UUID spelling and alternate
        // encodings cannot silently describe another persisted contract.
        guard try encode(value) == bytes else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}
