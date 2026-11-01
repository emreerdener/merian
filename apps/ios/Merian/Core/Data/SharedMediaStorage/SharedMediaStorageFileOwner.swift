import Darwin
import Foundation

/// Explicit private authority root, separate from every observed media root.
/// L1 owns its exclusive fixture lifetime, not the lifetime of legacy producers.
@MainActor
final class SharedMediaStorageFileOwner {
    private let admissionFence: SharedMediaStoreReadFence
    private let root: URL
    private let sources: [String: URL]
    private var descriptor: Int32
    private let storeURL: URL
    private let storeDescriptor: Int32
    private let storeIdentity: String
    private let storeDirectoryURL: URL
    private let storeDirectoryDescriptor: Int32
    private let storeDirectoryIdentity: String
    let identity: String
    private let nativeBootstrap: SharedMediaNativeBootstrapFiles?

    init(root: URL, storeURL: URL, sources: [String: URL], requireExistingFence: Bool = false, bootstrap: SharedMediaNativeBootstrapAuthority? = nil,
         discovery: SharedMediaNativeBootstrapDiscovery? = nil) throws {
        self.root = root
        self.sources = sources
        func contains(_ directory: URL, _ item: URL) -> Bool {
            let prefix = directory.standardizedFileURL.pathComponents
            return item.standardizedFileURL.pathComponents.starts(with: prefix)
        }
        guard !contains(root, storeURL), sources.values.allSatisfy({
            !contains($0, root) && !contains(root, $0) && !contains($0, storeURL)
        }) else { throw SharedMediaStorageFailure.invalid }
        let registered = Array(sources.values)
        for index in registered.indices {
            for other in registered.indices where other > index {
                guard !contains(registered[index], registered[other]),
                      !contains(registered[other], registered[index]) else { throw SharedMediaStorageFailure.invalid }
            }
        }
        self.storeURL = storeURL
        let handoff: SharedMediaNativeBootstrapHandoff?
        if let discovery {
            guard let bootstrap else { throw SharedMediaStorageFailure.invalid }
            handoff = try discovery.consume(authority: bootstrap, storeURL: storeURL)
        } else { handoff = nil }
        admissionFence = try handoff?.fence ?? SharedMediaStoreReadFence(store: storeURL, access: .sharedWriter, requireExisting: requireExistingFence)
        storeDirectoryURL = storeURL.deletingLastPathComponent()
        let parent = try Self.openDirectory(storeDirectoryURL)
        var retainedParent = false
        defer { if !retainedParent { Darwin.close(parent) } }
        // Core Data owns the SQLite file locks. Our separate directory lock
        // serializes repository lifetimes without competing with SQLite.
        guard flock(parent, LOCK_EX | LOCK_NB) == 0 else { throw SharedMediaStorageFailure.busy }
        var parentInfo = stat()
        guard fstat(parent, &parentInfo) == 0 else { throw SharedMediaStorageFailure.unavailable }
        let storeFD = openat(parent, storeURL.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard storeFD >= 0 else { throw SharedMediaStorageFailure.unavailable }
        var retained = false
        defer { if !retained { Darwin.close(storeFD) } }
        var storeInfo = stat()
        guard fstat(storeFD, &storeInfo) == 0, storeInfo.st_mode & S_IFMT == S_IFREG,
              storeInfo.st_nlink == 1 else { throw SharedMediaStorageFailure.conflict }
        if let handoff {
            guard Self.identity(storeInfo) == handoff.storeFileIdentity else { throw SharedMediaStorageFailure.conflict }
        }
        let bootstrapFiles: SharedMediaNativeBootstrapFiles?
        if let bootstrap {
            guard requireExistingFence == bootstrap.existingOnly, root == bootstrap.parent.appendingPathComponent("authority", isDirectory: true),
                  sources[SharedMediaPhotoLedger.namespace] == bootstrap.parent.appendingPathComponent("photo", isDirectory: true),
                  sources[SharedMediaInboxFiles.namespace] == bootstrap.parent.appendingPathComponent("inbox", isDirectory: true),
                  sources.count == 2, bootstrap.parent != storeDirectoryURL else { throw SharedMediaStorageFailure.invalid }
            bootstrapFiles = try SharedMediaNativeBootstrapFiles(authority: bootstrap, storeParentIdentity: Self.identity(parentInfo), handoff: handoff)
        } else { bootstrapFiles = nil }
        nativeBootstrap = bootstrapFiles
        let fd: Int32
        if let bootstrapFiles { fd = try bootstrapFiles.take("authority").consume(at: root).root }
        else { fd = try Self.openDirectory(root) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd); throw SharedMediaStorageFailure.busy
        }
        var info = stat()
        guard fstat(fd, &info) == 0 else {
            Darwin.close(fd); throw SharedMediaStorageFailure.unavailable
        }
        descriptor = fd
        identity = Self.identity(info)
        storeDescriptor = storeFD
        storeIdentity = Self.identity(storeInfo)
        storeDirectoryDescriptor = parent
        storeDirectoryIdentity = Self.identity(parentInfo)
        retainedParent = true
        retained = true
    }

    deinit {
        Darwin.close(descriptor)
        Darwin.close(storeDescriptor)
        Darwin.close(storeDirectoryDescriptor)
    }

    func check() throws {
        try nativeBootstrap?.check()
        let measurement = nativeBootstrap?.inspectionMeasurement ?? SharedMediaNativeInspectionMeasurement()
        try measurement.measure(.fileOwnerIdentity) { try checkFileIdentity() }
    }
    /// Audit database reads only; this does not authorize media or control use.
    func checkAuditReadIdentity() throws { try checkFileIdentity() }
    private func checkFileIdentity() throws {
        do { try admissionFence.check() }
        catch { throw SharedMediaStorageFailure.conflict }
        let namedParentFD = try Self.openDirectory(storeDirectoryURL)
        defer { Darwin.close(namedParentFD) }
        var heldParent = stat(), namedParent = stat()
        guard fstat(storeDirectoryDescriptor, &heldParent) == 0, fstat(namedParentFD, &namedParent) == 0,
              Self.identity(heldParent) == storeDirectoryIdentity,
              Self.identity(namedParent) == storeDirectoryIdentity else { throw SharedMediaStorageFailure.conflict }
        var heldStore = stat(), namedStore = stat()
        guard fstat(storeDescriptor, &heldStore) == 0, lstat(storeURL.path, &namedStore) == 0,
              namedStore.st_mode & S_IFMT == S_IFREG, namedStore.st_nlink == 1,
              Self.identity(heldStore) == storeIdentity, Self.identity(namedStore) == storeIdentity else {
            throw SharedMediaStorageFailure.conflict
        }
        var held = stat(), named = stat()
        guard descriptor >= 0, fstat(descriptor, &held) == 0,
              lstat(root.path, &named) == 0, named.st_mode & S_IFMT == S_IFDIR,
              Self.identity(held) == identity, held.st_dev == named.st_dev, held.st_ino == named.st_ino else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    func bootstrapProfile() throws -> SharedMediaNativeAppProfile {
        guard let value = nativeBootstrap?.profile else { throw SharedMediaStorageFailure.closed }; return value
    }
    func bootstrapRoot(_ name: String) throws -> SharedMediaNativeLockedRoot {
        guard let nativeBootstrap else { throw SharedMediaStorageFailure.closed }; return try nativeBootstrap.take(name)
    }

    func requireEmpty() throws {
        try check()
        guard try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty else {
            throw SharedMediaStorageFailure.conflict
        }
        try check()
    }

    /// Create-only authority metadata survives a lost/replaced database. Never
    /// clear this marker on errors: unresolved initialization must fail closed.
    func bindStore(_ binding: Data, initializing: Bool) throws {
        try check()
        guard binding.count <= 512 else { throw SharedMediaStorageFailure.invalid }
        let name = "com.merian.shared-media-store-v1"
        let size = fgetxattr(descriptor, name, nil, 0, 0, 0)
        if size >= 0 {
            guard !initializing, size == binding.count else { throw SharedMediaStorageFailure.conflict }
            var bytes = [UInt8](repeating: 0, count: size)
            let count = bytes.withUnsafeMutableBytes { fgetxattr(descriptor, name, $0.baseAddress, size, 0, 0) }
            guard count == size, Data(bytes) == binding else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard errno == ENOATTR, initializing else { throw SharedMediaStorageFailure.conflict }
            let result = binding.withUnsafeBytes { fsetxattr(descriptor, name, $0.baseAddress, binding.count, 0, XATTR_CREATE) }
            guard result == 0, fsync(descriptor) == 0 else { throw SharedMediaStorageFailure.unavailable }
        }
        try check()
    }

    func availableBytes() throws -> Int64 {
        try check()
        var info = statfs()
        guard fstatfs(descriptor, &info) == 0, info.f_bsize > 0 else { throw SharedMediaStorageFailure.unavailable }
        let (bytes, overflow) = UInt64(info.f_bavail).multipliedReportingOverflow(by: UInt64(info.f_bsize))
        guard !overflow, bytes <= UInt64(Int64.max) else { throw SharedMediaStorageFailure.invalid }
        return Int64(bytes)
    }

    func observe(id: UUID, namespace: String, token: String) throws -> SharedMediaStorageObservation {
        try check()
        guard let sourceRoot = sources[namespace] else { throw SharedMediaStorageFailure.invalid }
        return try Self.observe(id: id, namespace: namespace, token: token, sourceRoot: sourceRoot)
    }

    /// Stat only; no decoding, copying, hashing, adoption or removal.
    /// The caller registers a concrete source directory, never arbitrary tmp traversal.
    private static func observe(id: UUID, namespace: String, token: String, sourceRoot: URL) throws -> SharedMediaStorageObservation {
        try SharedMediaStoragePolicy.token(namespace)
        try SharedMediaStoragePolicy.token(token)
        let rootFD = try openDirectory(sourceRoot)
        defer { Darwin.close(rootFD) }
        let fd = openat(rootFD, token, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
        defer { Darwin.close(fd) }
        var before = stat(), after = stat(), named = stat(), heldRoot = stat(), namedRoot = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_nlink == 1, before.st_size >= 0,
              fstatat(rootFD, token, &named, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(fd, &after) == 0, before.st_dev == named.st_dev, before.st_ino == named.st_ino,
              before.st_size == named.st_size, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              fstat(rootFD, &heldRoot) == 0, lstat(sourceRoot.path, &namedRoot) == 0,
              namedRoot.st_mode & S_IFMT == S_IFDIR,
              heldRoot.st_dev == namedRoot.st_dev, heldRoot.st_ino == namedRoot.st_ino else {
            throw SharedMediaStorageFailure.conflict
        }
        return SharedMediaStorageObservation(id: id, namespace: namespace, token: token,
            bytes: Int64(before.st_size), physicalIdentity: "\(identity(before)):\(before.st_mtimespec.tv_sec):\(before.st_mtimespec.tv_nsec):\(before.st_ctimespec.tv_sec):\(before.st_ctimespec.tv_nsec)")
    }

    static func directoryIdentity(_ root: URL, measurement: SharedMediaNativeInspectionMeasurement? = nil) throws -> String {
        let fd = try openDirectory(root, measurement: measurement)
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw SharedMediaStorageFailure.unavailable }
        return identity(info)
    }

    private static func identity(_ value: stat) -> String { "\(value.st_dev):\(value.st_ino)" }

    static func openDirectory(_ url: URL, measurement: SharedMediaNativeInspectionMeasurement? = nil) throws -> Int32 {
        let measurement = measurement ?? SharedMediaNativeInspectionMeasurement()
        let components = try measurement.measure(.directoryLexicalValidation) {
            guard url.isFileURL, url.path.hasPrefix("/") else { throw SharedMediaStorageFailure.invalid }
            let components = url.pathComponents
            guard !components.contains("..") else { throw SharedMediaStorageFailure.invalid }
            return components
        }
        return try measurement.measure(.directoryDescriptorWalk) {
            var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
            for part in components.dropFirst() {
                let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                Darwin.close(fd)
                guard next >= 0 else { throw SharedMediaStorageFailure.unavailable }
                fd = next
            }
            return fd
        }
    }
}
