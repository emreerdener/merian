import CryptoKit
import Darwin
import Foundation

/// One-shot transfer of already locked descriptors to the existing file owners.
/// The mutex protects consumption; descriptors remain locked until their sole
/// receiving owner closes them. There is no reopen or lock-release interval.
final class SharedMediaNativeLockedRoot: @unchecked Sendable {
    private let mutex = NSLock()
    private var descriptors: (Int32, Int32)?
    private let url: URL
    fileprivate init(url: URL, root: Int32, child: Int32 = -1) {
        self.url = url; descriptors = (root, child)
    }
    deinit { if let (root, child) = descriptors { Darwin.close(root); if child >= 0 { Darwin.close(child) } } }
    func consume(at url: URL) throws -> (root: Int32, child: Int32) {
        mutex.lock(); defer { mutex.unlock() }
        guard url == self.url, let result = descriptors else { throw SharedMediaStorageFailure.closed }
        descriptors = nil; return result
    }
}

enum SharedMediaNativeBootstrapBoundary: String, CaseIterable, Sendable {
    case afterIntent, afterAuthorityRoot, afterPhotoRoot, afterPhotoNamespace
    case afterInboxRoot, afterInboxNamespace, afterFinal, afterAuthorityMarker
    case afterPhotoMarker, afterInboxMarker, beforeSave, afterSave
}

/// Fixed-shape control metadata. These bytes are not a media-package reservation.
enum SharedMediaNativeBootstrapCodec {
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
            let sum = try PhotoPreparationPolicy.add([Int64(encode(intent).count), Int64(encode(final).count)] + progress)
            guard sum <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.invalid }
            // Exact record maxima, three maximum marker payloads, and encoding
            // working copies; no persistent reservation after materialization.
            return try PhotoPreparationPolicy.add([sum, sum, 3 * 512])
        }
    }
}

private final class SharedMediaNativeBootstrapDescriptor {
    let fd: Int32
    init(_ fd: Int32) { self.fd = fd }
    deinit { Darwin.close(fd) }
}

/// Private V2 control journal. Only a repository-minted bootstrap authority can
/// enter it, after the existing file owner holds the store fence and parent lock.
@MainActor
final class SharedMediaNativeBootstrapFiles {
    private let authority: SharedMediaNativeBootstrapAuthority
    private let parent: URL
    private let parentHandle: SharedMediaNativeBootstrapDescriptor
    private var parentFD: Int32 { parentHandle.fd }
    private let parentIdentity: String
    private var roots: [String: SharedMediaNativeLockedRoot] = [:]
    private var expectedIntent = Data(), expectedFinal = Data()
    private var expectedIdentities: [String] = []
    private var expectedProgress: [Data] = []
    private(set) var profile: SharedMediaNativeAppProfile?

    init(authority: SharedMediaNativeBootstrapAuthority, storeParentIdentity: String) throws {
        self.authority = authority; parent = authority.parent
        try authority.validate()
        let support = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard parent.isFileURL, parent == parent.resolvingSymlinksInPath().standardizedFileURL,
              parent.pathComponents.count > support.pathComponents.count,
              parent.pathComponents.starts(with: support.pathComponents) else { throw SharedMediaStorageFailure.invalid }
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isExcludedFromBackupKey])
        guard values.isDirectory == true, values.isExcludedFromBackup == true else { throw SharedMediaStorageFailure.conflict }
        let fd = try SharedMediaStorageFileOwner.openDirectory(parent)
        let handle = SharedMediaNativeBootstrapDescriptor(fd)
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw SharedMediaStorageFailure.busy }
        parentHandle = handle; parentIdentity = try Self.identity(fd)
        try authority.validateDatabase()
        guard try Self.names(fd).isSubset(of: SharedMediaNativeBootstrapCodec.controlNames) else { throw SharedMediaStorageFailure.conflict }
        let savedIntent = try Self.read(fd, SharedMediaNativeBootstrapCodec.intentName)
        let savedFinal = try Self.read(fd, SharedMediaNativeBootstrapCodec.finalName)
        let savedProgress = try SharedMediaNativeBootstrapCodec.progressNames.map { try Self.read(fd, $0) }
        if authority.existingOnly { guard savedIntent != nil, savedFinal != nil else { throw SharedMediaStorageFailure.conflict } }
        guard savedIntent != nil || savedFinal == nil else { throw SharedMediaStorageFailure.conflict }
        if savedIntent == nil {
            guard try Self.names(fd).isEmpty else { throw SharedMediaStorageFailure.conflict }
        }
        let intent: SharedMediaNativeBootstrapCodec.Intent
        if let savedIntent {
            intent = try SharedMediaNativeBootstrapCodec.decode(SharedMediaNativeBootstrapCodec.Intent.self, savedIntent)
        } else {
            intent = .init(version: 3, ownerID: authority.ownerID, inventoryID: authority.inventoryID,
                generation: UUID(), operationID: UUID(), nonce: UUID(), store: authority.storeIdentity,
                parent: parentIdentity, storeParent: storeParentIdentity, names: SharedMediaNativeBootstrapCodec.names)
        }
        let bindingFormat = try SharedMediaNativeAppProfile.PhysicalBindingFormat(journalVersion: intent.version)
        guard intent.ownerID == authority.ownerID, intent.inventoryID == authority.inventoryID,
              intent.store == authority.storeIdentity, intent.parent == parentIdentity, intent.storeParent == storeParentIdentity,
              intent.names == SharedMediaNativeBootstrapCodec.names,
              SharedMediaNativeBootstrapCodec.identity(intent.parent), SharedMediaNativeBootstrapCodec.identity(intent.storeParent) else {
            throw SharedMediaStorageFailure.conflict
        }
        expectedIntent = try SharedMediaNativeBootstrapCodec.encode(intent)
        let intentDigest = SharedMediaNativeBootstrapCodec.digest(expectedIntent)
        let progress = try savedProgress.map { try $0.map { try SharedMediaNativeBootstrapCodec.decode(SharedMediaNativeBootstrapCodec.Progress.self, $0) } }
        var missingProgress = false
        for (index, record) in progress.enumerated() {
            guard let record else { missingProgress = true; continue }
            let parentIndex = index == 2 ? 1 : index == 4 ? 3 : nil
            let expectedParent = parentIndex.flatMap { progress[$0]?.identity } ?? parentIdentity
            guard !missingProgress, record.version == intent.version, record.intentDigest == intentDigest,
                  record.name == SharedMediaNativeBootstrapCodec.names[index], record.parentIdentity == expectedParent,
                  SharedMediaNativeBootstrapCodec.identity(record.identity), SharedMediaNativeBootstrapCodec.identity(record.parentIdentity) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        if savedFinal == nil {
            try authority.requireUnassociatedDatabase()
            try requireSpace(materializedBytes: PhotoPreparationPolicy.add([Int64(savedIntent?.count ?? 0)] + savedProgress.map { Int64($0?.count ?? 0) }))
            if savedIntent == nil { try Self.write(fd, SharedMediaNativeBootstrapCodec.intentName, expectedIntent) }
            try authority.boundary(.afterIntent)
        }
        let final: SharedMediaNativeBootstrapCodec.Final?
        if let savedFinal {
            final = try SharedMediaNativeBootstrapCodec.decode(SharedMediaNativeBootstrapCodec.Final.self, savedFinal)
            guard final?.version == intent.version, final?.intentDigest == SharedMediaNativeBootstrapCodec.digest(expectedIntent),
                  final?.identities.count == 5, final?.identities.allSatisfy(SharedMediaNativeBootstrapCodec.identity) == true,
                  !missingProgress, final?.progressDigests == savedProgress.compactMap({ $0.map(SharedMediaNativeBootstrapCodec.digest) }) else {
                throw SharedMediaStorageFailure.conflict
            }
        } else { final = nil }
        var descriptors: [String: Int32] = [:]
        defer { for value in descriptors.values { Darwin.close(value) } }
        for (index, name) in SharedMediaNativeBootstrapCodec.names.enumerated() {
            try authority.validate()
            let components = name.split(separator: "/").map(String.init)
            let base = components.count == 1 ? fd : descriptors[components[0]]!
            let leaf = components.last!
            let root = try Self.directory(base, leaf, create: progress[index] == nil)
            descriptors[name] = root
            let identity = try Self.identity(root), parentID = try Self.identity(base)
            if let record = progress[index] {
                guard record.identity == identity, record.parentIdentity == parentID else { throw SharedMediaStorageFailure.conflict }
            }
            if let final { guard final.identities[index] == identity else { throw SharedMediaStorageFailure.conflict } }
            let allowed: Set<String> = name == "photo" ? ["PhotoPreparation"] : name == "inbox" ? ["InboxSources"] : []
            if !authority.existingOnly || components.count == 1 {
                let existingNames = try Self.names(root)
                guard final == nil ? existingNames.isSubset(of: allowed) : existingNames == allowed else { throw SharedMediaStorageFailure.conflict }
            }
            if final == nil {
                let marker = Self.marker(name)
                if let marker { guard fgetxattr(root, marker, nil, 0, 0, 0) < 0, errno == ENOATTR else { throw SharedMediaStorageFailure.conflict } }
                if progress[index] == nil {
                    var url = parent.appendingPathComponent(name), attributes = URLResourceValues()
                    attributes.isExcludedFromBackup = true; try url.setResourceValues(attributes)
                    guard fsync(root) == 0, fsync(base) == 0 else { throw SharedMediaStorageFailure.unavailable }
                    let record = SharedMediaNativeBootstrapCodec.Progress(version: intent.version, intentDigest: intentDigest,
                        name: name, identity: identity, parentIdentity: parentID)
                    try Self.write(fd, SharedMediaNativeBootstrapCodec.progressNames[index], SharedMediaNativeBootstrapCodec.encode(record))
                }
                try authority.boundary([.afterAuthorityRoot, .afterPhotoRoot, .afterPhotoNamespace, .afterInboxRoot, .afterInboxNamespace][index])
            }
            let record = try SharedMediaNativeBootstrapCodec.encode(SharedMediaNativeBootstrapCodec.Progress(version: intent.version,
                intentDigest: intentDigest, name: name, identity: identity, parentIdentity: parentID))
            guard try Self.read(fd, SharedMediaNativeBootstrapCodec.progressNames[index]) == record else { throw SharedMediaStorageFailure.conflict }
            expectedProgress.append(record)
            expectedIdentities.append(identity)
        }
        let result = final ?? .init(version: intent.version, intentDigest: intentDigest, identities: expectedIdentities, progressDigests: expectedProgress.map(SharedMediaNativeBootstrapCodec.digest))
        expectedFinal = try SharedMediaNativeBootstrapCodec.encode(result)
        if final == nil { try Self.write(fd, SharedMediaNativeBootstrapCodec.finalName, expectedFinal); try authority.boundary(.afterFinal) }
        let physical = try SharedMediaNativeAppProfile.rootBinding(format: bindingFormat, authority: expectedIdentities[0], sources: [
            SharedMediaPhotoLedger.namespace: parent.appendingPathComponent("photo", isDirectory: true),
            SharedMediaInboxFiles.namespace: parent.appendingPathComponent("inbox", isDirectory: true)])
        let profile = SharedMediaNativeAppProfile(ownerID: intent.ownerID, inventoryID: intent.inventoryID,
            generation: intent.generation, storeIdentity: intent.store, physicalBinding: physical,
            receiptDigest: SharedMediaNativeBootstrapCodec.digest(expectedFinal), physicalBindingFormat: bindingFormat)
        self.profile = profile
        let binding = try profile.binding
        try authority.validateDatabase(profile: profile)
        let committed = try authority.isCommitted()
        try check()
        for name in ["authority", "photo", "inbox"] {
            try Self.checkMarker(descriptors[name]!, marker: Self.marker(name)!, bytes: binding, allowMissing: !committed)
        }
        for (index, name) in ["authority", "photo", "inbox"].enumerated() {
            try authority.validate()
            try Self.bind(descriptors[name]!, marker: Self.marker(name)!, bytes: binding, allowCreate: !committed)
            try authority.boundary([.afterAuthorityMarker, .afterPhotoMarker, .afterInboxMarker][index])
        }
        guard try Self.names(fd) == SharedMediaNativeBootstrapCodec.controlNames else {
            throw SharedMediaStorageFailure.conflict
        }
        for (name, child) in [("authority", ""), ("photo", "photo/PhotoPreparation"), ("inbox", "inbox/InboxSources")] {
            roots[name] = SharedMediaNativeLockedRoot(url: parent.appendingPathComponent(name, isDirectory: true),
                root: descriptors.removeValue(forKey: name)!, child: child.isEmpty ? -1 : descriptors.removeValue(forKey: child)!)
        }
        try check()
    }
    func take(_ name: String) throws -> SharedMediaNativeLockedRoot {
        guard let result = roots.removeValue(forKey: name) else { throw SharedMediaStorageFailure.closed }; return result
    }
    func check() throws {
        guard try Self.names(parentFD) == SharedMediaNativeBootstrapCodec.controlNames,
              try SharedMediaStorageFileOwner.directoryIdentity(parent) == parentIdentity,
              try Self.read(parentFD, SharedMediaNativeBootstrapCodec.intentName) == expectedIntent,
              try Self.read(parentFD, SharedMediaNativeBootstrapCodec.finalName) == expectedFinal else { throw SharedMediaStorageFailure.conflict }
        for (name, bytes) in zip(SharedMediaNativeBootstrapCodec.progressNames, expectedProgress) {
            guard try Self.read(parentFD, name) == bytes else { throw SharedMediaStorageFailure.conflict }
        }
        for (name, expected) in zip(SharedMediaNativeBootstrapCodec.names, expectedIdentities) {
            let url = parent.appendingPathComponent(name)
            guard try SharedMediaStorageFileOwner.directoryIdentity(url) == expected else { throw SharedMediaStorageFailure.conflict }
            let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            guard values.isExcludedFromBackup == true else { throw SharedMediaStorageFailure.conflict }
        }
    }
    private func requireSpace(materializedBytes: Int64) throws {
        var value = statfs(); guard fstatfs(parentFD, &value) == 0, value.f_bsize > 0 else { throw SharedMediaStorageFailure.unavailable }
        let (bytes, overflow) = UInt64(value.f_bavail).multipliedReportingOverflow(by: UInt64(value.f_bsize))
        guard !overflow, bytes <= Int64.max else { throw SharedMediaStorageFailure.invalid }
        let available = authority.availableBytes ?? Int64(bytes)
        let remaining = try SharedMediaNativeBootstrapCodec.maximumControlBytes - materializedBytes
        guard remaining >= 0, available >= (try PhotoPreparationPolicy.add([PhotoPreparationPolicy.minimumFree, remaining])) else {
            throw PhotoPreparationFailure.storageLimit
        }
    }
    private static func identity(_ fd: Int32) throws -> String {
        var value = stat(); guard fstat(fd, &value) == 0 else { throw SharedMediaStorageFailure.unavailable }
        return "\(value.st_dev):\(value.st_ino)"
    }
    private static func marker(_ name: String) -> String? {
        switch name { case "authority": "com.merian.shared-media-store-v1"
        case "photo": "com.merian.p1-shared-v1"; case "inbox": SharedMediaInboxFiles.marker; default: nil }
    }
    private static func directory(_ parent: Int32, _ name: String, create: Bool) throws -> Int32 {
        // No receipt means no authority to adopt an existing path, even empty.
        // A crash between mkdir and its durable receipt remains held.
        if create, mkdirat(parent, name, 0o700) != 0 { throw SharedMediaStorageFailure.conflict }
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.conflict }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(fd); throw SharedMediaStorageFailure.busy }
        return fd
    }
    private static func names(_ fd: Int32) throws -> Set<String> {
        let copy = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copy >= 0 else { throw SharedMediaStorageFailure.unavailable }
        guard let directory = fdopendir(copy) else { Darwin.close(copy); throw SharedMediaStorageFailure.unavailable }
        defer { closedir(directory) }
        var result = Set<String>()
        while true {
            errno = 0; guard let entry = readdir(directory) else { guard errno == 0 else { throw SharedMediaStorageFailure.unavailable }; break }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) } }
            if name != "." && name != ".." { result.insert(name); guard result.count <= SharedMediaNativeBootstrapCodec.controlNames.count else { throw SharedMediaStorageFailure.conflict } }
        }
        return result
    }
    private static func read(_ parent: Int32, _ name: String) throws -> Data? {
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 { guard errno == ENOENT else { throw SharedMediaStorageFailure.conflict }; return nil }
        defer { Darwin.close(fd) }
        var before = stat(), after = stat(), named = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1,
              before.st_size > 0, before.st_size <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.conflict }
        var bytes = [UInt8](repeating: 0, count: Int(before.st_size)); var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if count < 0 && errno == EINTR { continue }; guard count > 0 else { throw SharedMediaStorageFailure.unavailable }; offset += count
        }
        guard fstat(fd, &after) == 0, fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & S_IFMT == S_IFREG, named.st_nlink == 1,
              before.st_dev == named.st_dev, before.st_ino == named.st_ino,
              before.st_size == after.st_size, before.st_size == named.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw SharedMediaStorageFailure.conflict }
        guard fsync(fd) == 0, fsync(parent) == 0 else { throw SharedMediaStorageFailure.unavailable }
        return Data(bytes)
    }
    private static func write(_ parent: Int32, _ name: String, _ bytes: Data) throws {
        guard bytes.count <= PhotoPreparationPolicy.metadata else { throw SharedMediaStorageFailure.invalid }
        let fd = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SharedMediaStorageFailure.conflict }; defer { Darwin.close(fd) }
        var offset = 0
        while offset < bytes.count {
            let count = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if count < 0 && errno == EINTR { continue }; guard count > 0 else { throw SharedMediaStorageFailure.unavailable }; offset += count
        }
        guard fsync(fd) == 0, fsync(parent) == 0 else { throw SharedMediaStorageFailure.unavailable }
    }
    private static func checkMarker(_ fd: Int32, marker: String, bytes: Data, allowMissing: Bool) throws {
        let size = fgetxattr(fd, marker, nil, 0, 0, 0)
        if size < 0 { guard allowMissing, errno == ENOATTR else { throw SharedMediaStorageFailure.conflict }; return }
        guard size == bytes.count else { throw SharedMediaStorageFailure.conflict }
        var saved = [UInt8](repeating: 0, count: size)
        guard saved.withUnsafeMutableBytes({ fgetxattr(fd, marker, $0.baseAddress, size, 0, 0) }) == size,
              Data(saved) == bytes else { throw SharedMediaStorageFailure.conflict }
    }
    private static func bind(_ fd: Int32, marker: String, bytes: Data, allowCreate: Bool) throws {
        let size = fgetxattr(fd, marker, nil, 0, 0, 0)
        if size >= 0 {
            guard size == bytes.count else { throw SharedMediaStorageFailure.conflict }
            var saved = [UInt8](repeating: 0, count: size)
            guard saved.withUnsafeMutableBytes({ fgetxattr(fd, marker, $0.baseAddress, size, 0, 0) }) == size,
                  Data(saved) == bytes else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard allowCreate, errno == ENOATTR, bytes.withUnsafeBytes({ fsetxattr(fd, marker, $0.baseAddress, bytes.count, 0, XATTR_CREATE) }) == 0 else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        guard fsync(fd) == 0 else { throw SharedMediaStorageFailure.unavailable }
    }
}
