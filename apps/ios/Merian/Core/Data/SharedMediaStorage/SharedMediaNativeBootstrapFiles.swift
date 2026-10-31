import CryptoKit
import Darwin
import Foundation
import SwiftData

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

enum SharedMediaNativeParentCreationBoundary: CaseIterable { case afterDirectory, afterBackupExclusion, afterReceipt, beforeHandoff }

fileprivate struct SharedMediaNativeParentCreationHooks {
    #if DEBUG
    var fault: ((SharedMediaNativeParentCreationBoundary) throws -> Void)?
    #endif
    func reach(_ boundary: SharedMediaNativeParentCreationBoundary) throws {
        #if DEBUG
        try fault?(boundary)
        #endif
    }
}

fileprivate final class SharedMediaNativeBootstrapDescriptor {
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
    private let expectedParentReceipt: Data?
    private var expectedNames: Set<String> { SharedMediaNativeBootstrapCodec.allowedNames(parentReceipt: expectedParentReceipt) }
    private var expectedIdentities: [String] = []
    private var expectedProgress: [Data] = []
    private(set) var profile: SharedMediaNativeAppProfile?

    init(authority: SharedMediaNativeBootstrapAuthority, storeParentIdentity: String,
         handoff: SharedMediaNativeBootstrapHandoff? = nil) throws {
        self.authority = authority; parent = authority.parent
        try handoff?.requireStore(identity: authority.storeIdentity)
        try authority.validate()
        let handle = try handoff?.parent ?? Self.lockParent(parent)
        let fd = handle.fd
        parentHandle = handle; parentIdentity = try Self.identity(fd)
        try authority.validateDatabase()
        expectedParentReceipt = try Self.read(fd, SharedMediaNativeBootstrapCodec.parentReceiptName)
        try SharedMediaNativeBootstrapCodec.validateParent(expectedParentReceipt, store: authority.storeIdentity,
            storeParent: storeParentIdentity, parent: parentIdentity)
        guard try Self.names(fd).isSubset(of: expectedNames) else { throw SharedMediaStorageFailure.conflict }
        let savedIntent = try Self.read(fd, SharedMediaNativeBootstrapCodec.intentName)
        let savedFinal = try Self.read(fd, SharedMediaNativeBootstrapCodec.finalName)
        let savedProgress = try SharedMediaNativeBootstrapCodec.progressNames.map { try Self.read(fd, $0) }
        if authority.existingOnly { guard savedIntent != nil, savedFinal != nil else { throw SharedMediaStorageFailure.conflict } }
        guard savedIntent != nil || savedFinal == nil else { throw SharedMediaStorageFailure.conflict }
        if savedIntent == nil {
            guard try Self.names(fd) == (expectedParentReceipt == nil ? [] : [SharedMediaNativeBootstrapCodec.parentReceiptName]) else { throw SharedMediaStorageFailure.conflict }
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
            try requireSpace(materializedBytes: PhotoPreparationPolicy.add([Int64(savedIntent?.count ?? 0), Int64(expectedParentReceipt?.count ?? 0)] + savedProgress.map { Int64($0?.count ?? 0) }))
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
        guard try Self.names(fd) == expectedNames else {
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
        let measurement = SharedMediaNativeInspectionMeasurement(authority: authority)
        func readControl(_ name: String) throws -> Data? {
            try measurement.measure(.controlReadAndSync) { try Self.read(parentFD, name, synchronizeParent: false, measurement: measurement) }
        }
        guard try Self.names(parentFD) == expectedNames,
              try readControl(SharedMediaNativeBootstrapCodec.parentReceiptName) == expectedParentReceipt,
              try SharedMediaStorageFileOwner.directoryIdentity(parent) == parentIdentity,
              try readControl(SharedMediaNativeBootstrapCodec.intentName) == expectedIntent,
              try readControl(SharedMediaNativeBootstrapCodec.finalName) == expectedFinal else { throw SharedMediaStorageFailure.conflict }
        for (name, bytes) in zip(SharedMediaNativeBootstrapCodec.progressNames, expectedProgress) {
            guard try readControl(name) == bytes else { throw SharedMediaStorageFailure.conflict }
        }
        for (name, expected) in zip(SharedMediaNativeBootstrapCodec.names, expectedIdentities) {
            let url = parent.appendingPathComponent(name)
            guard try SharedMediaStorageFileOwner.directoryIdentity(url) == expected else { throw SharedMediaStorageFailure.conflict }
            let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            guard values.isExcludedFromBackup == true else { throw SharedMediaStorageFailure.conflict }
        }
        // All accepted control bytes have been read and their files flushed.
        // One directory flush commits their entries before this check returns.
        try measurement.measure(.controlParentSync) {
            guard fsync(parentFD) == 0 else { throw SharedMediaStorageFailure.unavailable }
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
    fileprivate static func lockParent(_ parent: URL) throws -> SharedMediaNativeBootstrapDescriptor {
        let support = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard parent.isFileURL, parent == parent.resolvingSymlinksInPath().standardizedFileURL,
              parent.pathComponents.count > support.pathComponents.count,
              parent.pathComponents.starts(with: support.pathComponents) else { throw SharedMediaStorageFailure.invalid }
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isExcludedFromBackupKey])
        guard values.isDirectory == true, values.isExcludedFromBackup == true else { throw SharedMediaStorageFailure.conflict }
        let fd = try SharedMediaStorageFileOwner.openDirectory(parent)
        let handle = SharedMediaNativeBootstrapDescriptor(fd)
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw SharedMediaStorageFailure.busy }
        return handle
    }
    fileprivate static func identity(_ fd: Int32) throws -> String {
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
    fileprivate static func names(_ fd: Int32) throws -> Set<String> {
        let copy = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copy >= 0 else { throw SharedMediaStorageFailure.unavailable }
        guard let directory = fdopendir(copy) else { Darwin.close(copy); throw SharedMediaStorageFailure.unavailable }
        defer { closedir(directory) }
        var result = Set<String>()
        while true {
            errno = 0; guard let entry = readdir(directory) else { guard errno == 0 else { throw SharedMediaStorageFailure.unavailable }; break }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) } }
            if name != "." && name != ".." { result.insert(name); guard result.count <= SharedMediaNativeBootstrapCodec.controlNames.count + 1 else { throw SharedMediaStorageFailure.conflict } }
        }
        return result
    }
    fileprivate static func read(_ parent: Int32, _ name: String, synchronizeParent: Bool = true,
                                 measurement: SharedMediaNativeInspectionMeasurement? = nil) throws -> Data? {
        let measurement = measurement ?? SharedMediaNativeInspectionMeasurement()
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
        try measurement.measure(.controlFileSync) {
            guard fsync(fd) == 0 else { throw SharedMediaStorageFailure.unavailable }
        }
        if synchronizeParent { guard fsync(parent) == 0 else { throw SharedMediaStorageFailure.unavailable } }
        return Data(bytes)
    }
    fileprivate static func write(_ parent: Int32, _ name: String, _ bytes: Data) throws {
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

/// Provisional identity discovery only. The repository still validates every
/// journal/root/marker and database fact before it can expose an operation.
/// This value holds the exact startup fence and control-parent lock until its
/// one-shot transfer; retaining a consumed value retains neither lock.
@MainActor
final class SharedMediaNativeBootstrapDiscovery {
    let parent: URL, inventoryID: UUID
    let existingProfile: SharedMediaNativeAppProfile?
    private let ownerID: UUID, container: ModelContainer, startup: NativeReleaseStartupAdmission
    private let storeURL: URL, parentIdentity: String, storeIdentity: String
    private let controls: [Data?]
    private var held: SharedMediaNativeBootstrapHandoff?
    #if DEBUG
    private var beforeTransfer: (() throws -> Void)?
    #endif

    /// Source integration only: no App/Auth/Capture caller is installed.
    /// The namespace is fixed, app/store scoped, and never selected by Capture.
    static func startup(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                        ownerID: UUID) throws -> SharedMediaNativeBootstrapDiscovery {
        guard !TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        let support = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
        return try .init(container: container, startup: admission,
            parent: support.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName), ownerID: ownerID, creationAnchor: support)
    }

    #if DEBUG
    static func qualificationStartup(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                                     support: URL, ownerID: UUID,
                                     fault: ((SharedMediaNativeParentCreationBoundary) throws -> Void)? = nil) throws -> SharedMediaNativeBootstrapDiscovery {
        let live = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard TestExecutionCoordinator.isRunningTests, support != live,
              support.pathComponents.starts(with: live.pathComponents) else { throw SharedMediaStorageFailure.invalid }
        return try .init(container: container, startup: admission,
            parent: support.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName), ownerID: ownerID, creationAnchor: support, parentHooks: .init(fault: fault))
    }
    /// Inactive integration qualification. App must supply its trusted parent;
    /// no directory is created, adopted, or selected by Capture here.
    static func qualification(container: ModelContainer, startup: NativeReleaseStartupAdmission, parent: URL, ownerID: UUID,
                              beforeTransfer: (() throws -> Void)? = nil) throws -> SharedMediaNativeBootstrapDiscovery {
        let value = try SharedMediaNativeBootstrapDiscovery(container: container, startup: startup, parent: parent, ownerID: ownerID)
        value.beforeTransfer = beforeTransfer; return value
    }
    #endif

    private init(container: ModelContainer, startup: NativeReleaseStartupAdmission, parent: URL, ownerID: UUID, creationAnchor: URL? = nil,
                 parentHooks: SharedMediaNativeParentCreationHooks = .init()) throws {
        let fence = try startup.acquireFence(container: container)
        guard !container.mainContext.hasChanges, let configuration = container.configurations.first,
              parent != configuration.url.deletingLastPathComponent() else { throw SharedMediaStorageFailure.conflict }
        let storeFD = open(configuration.url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard storeFD >= 0 else { throw SharedMediaStorageFailure.unavailable }
        let store = SharedMediaNativeBootstrapDescriptor(storeFD)
        let storeFileIdentity = try SharedMediaNativeBootstrapFiles.identity(storeFD)
        try Self.requireStore(store, at: configuration.url, identity: storeFileIdentity)
        let storeIdentity = try SharedMediaNativeEligibility.storeIdentity(at: configuration.url)
        let handle: SharedMediaNativeBootstrapDescriptor
        if let creationAnchor {
            handle = try Self.controlParent(parent, anchor: creationAnchor, storeIdentity: storeIdentity,
                storeParent: fence.binding().parent, hooks: parentHooks) {
                    try Task.checkCancellation()
                    try startup.require(container: container, fence: fence)
                    try Self.requireStore(store, at: configuration.url, identity: storeFileIdentity)
                    guard try SharedMediaNativeEligibility.storeIdentity(at: configuration.url) == storeIdentity else { throw SharedMediaStorageFailure.conflict }
                    try SharedMediaNativeBootstrapDatabase.requireUnassociated(container)
                }
        } else { handle = try SharedMediaNativeBootstrapFiles.lockParent(parent) }
        let identity = try SharedMediaNativeBootstrapFiles.identity(handle.fd)
        let names = try SharedMediaNativeBootstrapFiles.names(handle.fd)
        let parentReceipt = try SharedMediaNativeBootstrapFiles.read(handle.fd, SharedMediaNativeBootstrapCodec.parentReceiptName)
        guard creationAnchor == nil || parentReceipt != nil else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaNativeBootstrapCodec.validateParent(parentReceipt, store: storeIdentity,
            storeParent: fence.binding().parent, parent: identity)
        guard names.isSubset(of: SharedMediaNativeBootstrapCodec.allowedNames(parentReceipt: parentReceipt)) else { throw SharedMediaStorageFailure.conflict }
        let records = try Self.readControls(handle.fd)
        let inventoryID: UUID
        if let raw = records[0] {
            let intent = try SharedMediaNativeBootstrapCodec.decode(SharedMediaNativeBootstrapCodec.Intent.self, raw)
            _ = try SharedMediaNativeAppProfile.PhysicalBindingFormat(journalVersion: intent.version)
            guard intent.ownerID == ownerID, intent.store == storeIdentity,
                  intent.parent == identity, intent.storeParent == (try fence.binding().parent),
                  intent.names == SharedMediaNativeBootstrapCodec.names else { throw SharedMediaStorageFailure.conflict }
            inventoryID = intent.inventoryID
            // Canonical control decoding is not root validation. The existing
            // bootstrap constructor performs all continuation/final checks.
            if let final = records[1] { _ = try SharedMediaNativeBootstrapCodec.decode(SharedMediaNativeBootstrapCodec.Final.self, final) }
            for raw in records.dropFirst(2).dropLast().compactMap({ $0 }) {
                _ = try SharedMediaNativeBootstrapCodec.decode(SharedMediaNativeBootstrapCodec.Progress.self, raw)
            }
        } else {
            guard names == (parentReceipt == nil ? [] : [SharedMediaNativeBootstrapCodec.parentReceiptName]), records.dropLast().allSatisfy({ $0 == nil }) else { throw SharedMediaStorageFailure.conflict }
            try SharedMediaNativeBootstrapDatabase.requireUnassociated(container)
            inventoryID = UUID()
        }
        let profile = try SharedMediaNativeBootstrapDatabase.discoveryProfile(container,
            inventoryID: inventoryID, ownerID: ownerID, storeIdentity: storeIdentity)
        guard profile == nil || records[1] != nil else { throw SharedMediaStorageFailure.conflict }
        try startup.require(container: container, fence: fence)
        self.parent = parent; self.inventoryID = inventoryID; self.ownerID = ownerID
        self.container = container; self.startup = startup; storeURL = configuration.url
        parentIdentity = identity; controls = records; existingProfile = profile
        self.storeIdentity = storeIdentity
        try Self.requireStore(store, at: configuration.url, identity: storeFileIdentity)
        held = .init(fence: fence, parent: handle, store: store, storeURL: configuration.url, storeFileIdentity: storeFileIdentity)
    }

    func invalidate() { held = nil }

    func consume(authority: SharedMediaNativeBootstrapAuthority, storeURL: URL) throws -> SharedMediaNativeBootstrapHandoff {
        guard let result = held else { throw SharedMediaStorageFailure.closed }
        held = nil // Every transfer attempt consumes the discovery, including refusal.
        #if DEBUG
        try beforeTransfer?(); beforeTransfer = nil
        #endif
        try authority.validate()
        guard authority.containerIdentity == ObjectIdentifier(container), authority.ownerID == ownerID,
              authority.inventoryID == inventoryID, authority.parent == parent, storeURL == self.storeURL,
              authority.storeIdentity == storeIdentity, authority.existingOnly == (existingProfile != nil) else { throw SharedMediaStorageFailure.conflict }
        try startup.require(container: container, fence: result.fence)
        try Self.requireStore(result.store, at: storeURL, identity: result.storeFileIdentity)
        guard try SharedMediaStorageFileOwner.directoryIdentity(parent) == parentIdentity,
              try SharedMediaNativeBootstrapFiles.identity(result.parent.fd) == parentIdentity,
              try Self.readControls(result.parent.fd) == controls else { throw SharedMediaStorageFailure.conflict }
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isExcludedFromBackupKey])
        guard values.isDirectory == true, values.isExcludedFromBackup == true else { throw SharedMediaStorageFailure.conflict }
        let profile = try SharedMediaNativeBootstrapDatabase.discoveryProfile(container,
            inventoryID: inventoryID, ownerID: ownerID, storeIdentity: authority.storeIdentity)
        guard profile == existingProfile else { throw SharedMediaStorageFailure.conflict }
        try result.requireStore(identity: storeIdentity)
        return result
    }
    private static func controlParent(_ parent: URL, anchor: URL, storeIdentity: String, storeParent: String,
                                      hooks: SharedMediaNativeParentCreationHooks,
                                      beforeCreate: () throws -> Void) throws -> SharedMediaNativeBootstrapDescriptor {
        guard anchor == anchor.resolvingSymlinksInPath().standardizedFileURL,
              parent == anchor.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName) else { throw SharedMediaStorageFailure.invalid }
        let base = try SharedMediaStorageFileOwner.openDirectory(anchor)
        defer { Darwin.close(base) }
        let baseIdentity = try SharedMediaNativeBootstrapFiles.identity(base)
        let name = SharedMediaNativeBootstrapCodec.parentName
        var fd = openat(base, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        var created = false
        if fd < 0, errno == ENOENT {
            try beforeCreate()
            guard try SharedMediaStorageFileOwner.directoryIdentity(anchor) == baseIdentity else { throw SharedMediaStorageFailure.conflict }
            var space = statfs()
            guard fstatfs(base, &space) == 0, space.f_bsize > 0 else { throw SharedMediaStorageFailure.unavailable }
            let (free, overflow) = UInt64(space.f_bavail).multipliedReportingOverflow(by: UInt64(space.f_bsize))
            guard !overflow, free <= Int64.max,
                  Int64(free) >= (try PhotoPreparationPolicy.add([PhotoPreparationPolicy.minimumFree,
                    SharedMediaNativeBootstrapCodec.maximumControlBytes])) else { throw PhotoPreparationFailure.storageLimit }
            guard mkdirat(base, name, 0o700) == 0 else { throw SharedMediaStorageFailure.conflict }
            created = true
            try hooks.reach(.afterDirectory)
            fd = openat(base, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else { throw SharedMediaStorageFailure.conflict }
        let handle = SharedMediaNativeBootstrapDescriptor(fd)
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw SharedMediaStorageFailure.busy }
        let identity = try SharedMediaNativeBootstrapFiles.identity(fd)
        func checkNamed() throws {
            guard try SharedMediaStorageFileOwner.directoryIdentity(anchor) == baseIdentity,
                  try SharedMediaStorageFileOwner.directoryIdentity(parent) == identity else { throw SharedMediaStorageFailure.conflict }
        }
        try checkNamed()
        if created {
            try beforeCreate()
            guard try SharedMediaNativeBootstrapFiles.names(fd).isEmpty else { throw SharedMediaStorageFailure.conflict }
            var url = parent, values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            try checkNamed()
            try hooks.reach(.afterBackupExclusion)
            // Establish directory durability before publishing its creation proof.
            guard fsync(fd) == 0, fsync(base) == 0 else { throw SharedMediaStorageFailure.unavailable }
            let receipt = SharedMediaNativeBootstrapCodec.ParentCreation(version: 1, store: storeIdentity,
                storeParent: storeParent, parent: identity)
            try SharedMediaNativeBootstrapFiles.write(fd, SharedMediaNativeBootstrapCodec.parentReceiptName,
                SharedMediaNativeBootstrapCodec.encode(receipt))
            try hooks.reach(.afterReceipt)
        }
        let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isExcludedFromBackupKey])
        guard values.isDirectory == true, values.isExcludedFromBackup == true,
              let receipt = try SharedMediaNativeBootstrapFiles.read(fd, SharedMediaNativeBootstrapCodec.parentReceiptName) else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaNativeBootstrapCodec.validateParent(receipt, store: storeIdentity, storeParent: storeParent, parent: identity)
        guard fsync(fd) == 0, fsync(base) == 0 else { throw SharedMediaStorageFailure.unavailable }
        try hooks.reach(.beforeHandoff)
        try checkNamed()
        return handle
    }
    fileprivate static func requireStore(_ store: SharedMediaNativeBootstrapDescriptor, at url: URL, identity: String) throws {
        var held = stat(), named = stat()
        guard fstat(store.fd, &held) == 0, lstat(url.path, &named) == 0,
              held.st_mode & S_IFMT == S_IFREG, named.st_mode & S_IFMT == S_IFREG,
              held.st_nlink == 1, named.st_nlink == 1, held.st_dev == named.st_dev, held.st_ino == named.st_ino,
              try SharedMediaNativeBootstrapFiles.identity(store.fd) == identity else { throw SharedMediaStorageFailure.conflict }
    }
    private static func readControls(_ fd: Int32) throws -> [Data?] {
        try ([SharedMediaNativeBootstrapCodec.intentName, SharedMediaNativeBootstrapCodec.finalName]
            + SharedMediaNativeBootstrapCodec.progressNames + [SharedMediaNativeBootstrapCodec.parentReceiptName]).map { try SharedMediaNativeBootstrapFiles.read(fd, $0) }
    }
}

@MainActor
struct SharedMediaNativeBootstrapHandoff {
    let fence: SharedMediaStoreReadFence
    let storeFileIdentity: String
    fileprivate let parent: SharedMediaNativeBootstrapDescriptor, store: SharedMediaNativeBootstrapDescriptor
    private let storeURL: URL
    func requireStore(identity: String) throws {
        try SharedMediaNativeBootstrapDiscovery.requireStore(store, at: storeURL, identity: storeFileIdentity)
        let current = try SharedMediaNativeEligibility.storeIdentity(at: storeURL)
        try SharedMediaNativeBootstrapDiscovery.requireStore(store, at: storeURL, identity: storeFileIdentity)
        guard current == identity else { throw SharedMediaStorageFailure.conflict }
    }
    fileprivate init(fence: SharedMediaStoreReadFence, parent: SharedMediaNativeBootstrapDescriptor,
                     store: SharedMediaNativeBootstrapDescriptor, storeURL: URL, storeFileIdentity: String) {
        self.fence = fence; self.parent = parent; self.store = store; self.storeFileIdentity = storeFileIdentity
        self.storeURL = storeURL
    }
}
