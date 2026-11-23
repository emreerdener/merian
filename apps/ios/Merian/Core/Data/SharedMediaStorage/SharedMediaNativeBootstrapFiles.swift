import CryptoKit
import Darwin
import Foundation
import SwiftData

/// One-shot transfer of already locked descriptors to the existing file owners.
/// The mutex protects consumption; descriptors remain locked until their sole
/// receiving owner closes them. There is no reopen or lock-release interval.
final class SharedMediaNativeLockedRoot: @unchecked Sendable {
    struct CaptureBinding: Sendable {
        let rootIdentity: String, childIdentity: String
        let marker: Data
    }
    struct CaptureTransfer: Sendable {
        let root: Int32, child: Int32
        let binding: CaptureBinding
    }
    private let mutex = NSLock()
    private var descriptors: (Int32, Int32)?
    private let url: URL
    private let captureBinding: CaptureBinding?
    fileprivate init(url: URL, root: Int32, child: Int32 = -1, captureBinding: CaptureBinding? = nil) {
        self.url = url; descriptors = (root, child); self.captureBinding = captureBinding
    }
    deinit { if let (root, child) = descriptors { Darwin.close(root); if child >= 0 { Darwin.close(child) } } }
    func consume(at url: URL) throws -> (root: Int32, child: Int32) {
        mutex.lock(); defer { mutex.unlock() }
        guard url == self.url, let result = descriptors else { throw SharedMediaStorageFailure.closed }
        if let captureBinding {
            do { try Self.requireCapture(result, at: url, binding: captureBinding) } catch {
                descriptors = nil; Darwin.close(result.0); if result.1 >= 0 { Darwin.close(result.1) }
                throw error
            }
        }
        descriptors = nil; return result
    }
    /// Capture consumers must not accept the unmarked photo/inbox capability.
    func consumeCapture(at url: URL) throws -> CaptureTransfer {
        mutex.lock(); defer { mutex.unlock() }
        guard url == self.url, let result = descriptors else { throw SharedMediaStorageFailure.closed }
        do {
            guard let captureBinding else { throw SharedMediaStorageFailure.conflict }
            try Self.requireCapture(result, at: url, binding: captureBinding)
            descriptors = nil
            return .init(root: result.0, child: result.1, binding: captureBinding)
        } catch {
            descriptors = nil; Darwin.close(result.0); if result.1 >= 0 { Darwin.close(result.1) }
            throw error
        }
    }
    static func requireCapture(_ descriptors: (Int32, Int32), at url: URL, binding: CaptureBinding) throws {
        var root = stat(), namedRoot = stat(), child = stat(), namedChild = stat()
        guard fstat(descriptors.0, &root) == 0, lstat(url.path, &namedRoot) == 0,
              fstat(descriptors.1, &child) == 0,
              fstatat(descriptors.0, SharedMediaCaptureRootJournal.childName, &namedChild, AT_SYMLINK_NOFOLLOW) == 0,
              root.st_mode & S_IFMT == S_IFDIR, namedRoot.st_mode & S_IFMT == S_IFDIR,
              child.st_mode & S_IFMT == S_IFDIR, namedChild.st_mode & S_IFMT == S_IFDIR,
              "\(root.st_dev):\(root.st_ino)" == binding.rootIdentity,
              "\(namedRoot.st_dev):\(namedRoot.st_ino)" == binding.rootIdentity,
              "\(child.st_dev):\(child.st_ino)" == binding.childIdentity,
              "\(namedChild.st_dev):\(namedChild.st_ino)" == binding.childIdentity,
              !binding.marker.isEmpty, binding.marker.count <= 512 else { throw SharedMediaStorageFailure.conflict }
        let marker = SharedMediaCaptureRootJournal.marker
        guard fgetxattr(descriptors.0, marker, nil, 0, 0, 0) == binding.marker.count else { throw SharedMediaStorageFailure.conflict }
        var bytes = [UInt8](repeating: 0, count: binding.marker.count)
        guard bytes.withUnsafeMutableBytes({ fgetxattr(descriptors.0, marker, $0.baseAddress, $0.count, 0, 0) }) == bytes.count,
              Data(bytes) == binding.marker else { throw SharedMediaStorageFailure.conflict }
    }

    #if DEBUG
    @MainActor
    static func qualificationErasureParent(_ parent: URL) throws -> SharedMediaNativeLockedRoot {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        let handle = try SharedMediaNativeBootstrapFiles.lockParent(parent)
        let copy = fcntl(handle.fd, F_DUPFD_CLOEXEC, 0)
        guard copy >= 0 else { throw SharedMediaStorageFailure.unavailable }
        return SharedMediaNativeLockedRoot(url: parent, root: copy)
    }
    #endif
}

enum SharedMediaNativeBootstrapBoundary: String, CaseIterable, Sendable {
    case afterIntent, afterAuthorityRoot, afterPhotoRoot, afterPhotoNamespace
    case afterInboxRoot, afterInboxNamespace, afterFinal, afterAuthorityMarker
    case afterPhotoMarker, afterInboxMarker, beforeSave, afterSave
}

enum SharedMediaNativeParentCreationBoundary: CaseIterable { case afterDirectory, afterBackupExclusion, afterReceipt, beforeHandoff }

private struct SharedMediaNativeParentCreationHooks {
    #if DEBUG
    var fault: ((SharedMediaNativeParentCreationBoundary) throws -> Void)?
    #endif
    func reach(_ boundary: SharedMediaNativeParentCreationBoundary) throws {
        #if DEBUG
        try fault?(boundary)
        #endif
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
    private let expectedParentReceipt: Data?
    private var baseNames: Set<String> { SharedMediaNativeBootstrapCodec.allowedNames(parentReceipt: expectedParentReceipt) }
    private var captureSnapshot: SharedMediaCaptureControlSnapshot?
    private var captureSnapshotValid = true, captureQualified = false
    var captureRootNeedsRecovery: Bool { captureSnapshot != nil && !captureQualified }
    private var expectedNames: Set<String> { baseNames.union(captureSnapshot?.names ?? []) }
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
        let initialNames = try Self.names(fd, maximum: baseNames.count + SharedMediaCaptureRootJournal.names.count)
        let allowed = authority.existingOnly ? baseNames.union(SharedMediaCaptureRootJournal.names) : baseNames
        guard initialNames.isSubset(of: allowed) else { throw SharedMediaStorageFailure.conflict }
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
        captureSnapshot = try SharedMediaCaptureControlSnapshot.read(parentFD: fd, parentIdentity: parentIdentity,
            baseNames: baseNames, profile: profile)
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
        guard try Self.names(fd, maximum: expectedNames.count) == expectedNames else {
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
    var inspectionMeasurement: SharedMediaNativeInspectionMeasurement { .init(authority: authority) }
    func check() throws {
        guard captureSnapshotValid else { throw SharedMediaStorageFailure.conflict }
        if let profile {
            guard try SharedMediaCaptureControlSnapshot.read(parentFD: parentFD, parentIdentity: parentIdentity,
                baseNames: baseNames, profile: profile) == captureSnapshot else { throw SharedMediaStorageFailure.conflict }
            if captureQualified { try qualifyEmptyCaptureRoot(profile: profile) }
        }
        let measurement = inspectionMeasurement
        func readControl(_ name: String) throws -> Data? {
            try measurement.measure(.controlReadAndSync) { try Self.read(parentFD, name, synchronizeParent: false, measurement: measurement) }
        }
        guard try measurement.measure(.bootstrapEnumeration, { try Self.names(parentFD, maximum: expectedNames.count) }) == expectedNames,
              try readControl(SharedMediaNativeBootstrapCodec.parentReceiptName) == expectedParentReceipt,
              try measurement.measure(.bootstrapDirectoryIdentity, { try SharedMediaStorageFileOwner.directoryIdentity(parent, measurement: measurement) }) == parentIdentity,
              try readControl(SharedMediaNativeBootstrapCodec.intentName) == expectedIntent,
              try readControl(SharedMediaNativeBootstrapCodec.finalName) == expectedFinal else { throw SharedMediaStorageFailure.conflict }
        for (name, bytes) in zip(SharedMediaNativeBootstrapCodec.progressNames, expectedProgress) {
            guard try readControl(name) == bytes else { throw SharedMediaStorageFailure.conflict }
        }
        for (name, expected) in zip(SharedMediaNativeBootstrapCodec.names, expectedIdentities) {
            let url = parent.appendingPathComponent(name)
            guard try measurement.measure(.bootstrapDirectoryIdentity, { try SharedMediaStorageFileOwner.directoryIdentity(url, measurement: measurement) }) == expected else { throw SharedMediaStorageFailure.conflict }
            let values = try measurement.measure(.bootstrapBackupExclusion) { try url.resourceValues(forKeys: [.isExcludedFromBackupKey]) }
            guard values.isExcludedFromBackup == true else { throw SharedMediaStorageFailure.conflict }
        }
        // All accepted control bytes have been read and their files flushed.
        // One directory flush commits their entries before this check returns.
        try measurement.measure(.controlParentSync) {
            guard fsync(parentFD) == 0 else { throw SharedMediaStorageFailure.unavailable }
        }
    }
    /// Explicit operation only. The caller supplies a fresh dispatch authority;
    /// the bootstrap's opening grant must never be reused after opening returns.
    func recoverCaptureRoot(authority: SharedMediaNativeBootstrapAuthority) throws {
        try authority.validate()
        guard let profile, authority.parent == parent else { throw SharedMediaStorageFailure.closed }
        try authority.validateDatabase(profile: profile)
        try check()
        captureQualified = false
        captureSnapshotValid = false
        do {
            try recoverCaptureFiles(authority: authority, profile: profile)
            captureSnapshot = try SharedMediaCaptureControlSnapshot.read(parentFD: parentFD, parentIdentity: parentIdentity,
                baseNames: baseNames, profile: profile)
            captureSnapshotValid = true
            try qualifyEmptyCaptureRoot(profile: profile)
            try authority.validateDatabase(profile: profile)
            captureQualified = true
            try check()
        } catch {
            // Retain only freshly read evidence, never infer the missing suffix.
            // Even a complete record stays recovery-only until qualification.
            captureQualified = false
            do {
                captureSnapshot = try SharedMediaCaptureControlSnapshot.read(parentFD: parentFD, parentIdentity: parentIdentity,
                    baseNames: baseNames, profile: profile)
                captureSnapshotValid = true
            } catch { captureSnapshotValid = false }
            throw error
        }
    }
    /// The fresh dispatch grant and both directory locks live only for this
    /// operation. A successful read never qualifies generic app mutations.
    func withCaptureArtifactFiles<T>(authority: SharedMediaNativeBootstrapAuthority,
                                     body: (SharedMediaCaptureArtifactFiles) async throws -> T) async throws -> T {
        try authority.validate()
        guard let profile, authority.parent == parent else { throw SharedMediaStorageFailure.closed }
        try authority.validateDatabase(profile: profile)
        // Do not recursively acquire the empty-root locks while the explicit
        // artifact owner holds them. Ordinary dispatch remains recovery-only.
        captureQualified = false
        try check()
        captureSnapshotValid = false
        do {
            let controls = try SharedMediaNativeCaptureRootFiles(authority: authority, parentDescriptor: parentFD,
                profile: profile, createOrResume: true)
            captureSnapshot = try SharedMediaCaptureControlSnapshot.read(parentFD: parentFD, parentIdentity: parentIdentity,
                baseNames: baseNames, profile: profile)
            captureSnapshotValid = true
            let files = try SharedMediaCaptureArtifactFiles(controls: controls,
                rootURL: parent.appendingPathComponent(SharedMediaCaptureRootJournal.rootName, isDirectory: true))
            try check()
            let result = try await body(files)
            try files.check()
            try authority.validateDatabase(profile: profile)
            try check()
            return result
        } catch {
            do {
                captureSnapshot = try SharedMediaCaptureControlSnapshot.read(parentFD: parentFD, parentIdentity: parentIdentity,
                    baseNames: baseNames, profile: profile)
                captureSnapshotValid = true
            } catch { captureSnapshotValid = false }
            throw error
        }
    }

    private func recoverCaptureFiles(authority: SharedMediaNativeBootstrapAuthority, profile: SharedMediaNativeAppProfile) throws {
        let root = try SharedMediaNativeCaptureRootFiles(authority: authority, parentDescriptor: parentFD,
            profile: profile, createOrResume: true)
        try root.check()
    }
    private func qualifyEmptyCaptureRoot(profile: SharedMediaNativeAppProfile) throws {
        // Until the artifact inventory owner is installed, no unaccounted file
        // may become invisible to ordinary inspection or cleanup.
        let root = try SharedMediaNativeCaptureRootFiles(parent: parent, parentDescriptor: parentFD,
            profile: profile, baseNames: baseNames, createOrResume: false, validate: {
                guard try Self.identity(self.parentFD) == self.parentIdentity,
                      try SharedMediaStorageFileOwner.directoryIdentity(self.parent) == self.parentIdentity else {
                    throw SharedMediaStorageFailure.conflict
                }
            }, fault: nil)
        let descriptors = try root.take().consume(at: parent.appendingPathComponent(SharedMediaCaptureRootJournal.rootName, isDirectory: true))
        defer { Darwin.close(descriptors.root); Darwin.close(descriptors.child) }
        guard try Self.names(descriptors.child).isEmpty else { throw SharedMediaStorageFailure.conflict }
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
    fileprivate static func marker(_ name: String) -> String? {
        switch name {
        case "authority": "com.merian.shared-media-store-v1"
        case "photo": "com.merian.p1-shared-v1"
        case "inbox": SharedMediaInboxFiles.marker
        default: nil
        }
    }
    fileprivate static func directory(_ parent: Int32, _ name: String, create: Bool) throws -> Int32 {
        // No receipt means no authority to adopt an existing path, even empty.
        // A crash between mkdir and its durable receipt remains held.
        if create, mkdirat(parent, name, 0o700) != 0 { throw SharedMediaStorageFailure.conflict }
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.conflict }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(fd); throw SharedMediaStorageFailure.busy }
        return fd
    }
    fileprivate static func names(_ fd: Int32, maximum: Int = SharedMediaNativeBootstrapCodec.controlNames.count + 1) throws -> Set<String> {
        let copy = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copy >= 0 else { throw SharedMediaStorageFailure.unavailable }
        guard let directory = fdopendir(copy) else { Darwin.close(copy); throw SharedMediaStorageFailure.unavailable }
        defer { closedir(directory) }
        var result = Set<String>()
        while true {
            errno = 0; guard let entry = readdir(directory) else { guard errno == 0 else { throw SharedMediaStorageFailure.unavailable }; break }
            let name = withUnsafePointer(to: &entry.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) } }
            if name != "." && name != ".." { result.insert(name); guard result.count <= maximum else { throw SharedMediaStorageFailure.conflict } }
        }
        return result
    }
    fileprivate static func read(_ parent: Int32, _ name: String, synchronizeParent: Bool = true,
                                 maximumBytes: Int64 = PhotoPreparationPolicy.metadata,
                                 measurement: SharedMediaNativeInspectionMeasurement? = nil) throws -> Data? {
        let measurement = measurement ?? SharedMediaNativeInspectionMeasurement()
        let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 { guard errno == ENOENT else { throw SharedMediaStorageFailure.conflict }; return nil }
        defer { Darwin.close(fd) }
        var before = stat(), after = stat(), named = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1,
              maximumBytes > 0, maximumBytes <= PhotoPreparationPolicy.metadata,
              before.st_size > 0, before.st_size <= maximumBytes else { throw SharedMediaStorageFailure.conflict }
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
    fileprivate static func checkMarker(_ fd: Int32, marker: String, bytes: Data, allowMissing: Bool) throws {
        let size = fgetxattr(fd, marker, nil, 0, 0, 0)
        if size < 0 { guard allowMissing, errno == ENOATTR else { throw SharedMediaStorageFailure.conflict }; return }
        guard size == bytes.count else { throw SharedMediaStorageFailure.conflict }
        var saved = [UInt8](repeating: 0, count: size)
        guard saved.withUnsafeMutableBytes({ fgetxattr(fd, marker, $0.baseAddress, size, 0, 0) }) == size,
              Data(saved) == bytes else { throw SharedMediaStorageFailure.conflict }
    }
    fileprivate static func bind(_ fd: Int32, marker: String, bytes: Data, allowCreate: Bool) throws {
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
    /// Provisional control evidence only. Neither a final record nor discovery
    /// grants capture access: physical qualification and explicit recovery are
    /// separate. Default repository opening still holds any extension.
    let captureRootPrefix: SharedMediaCaptureRootJournal.Prefix?
    private let ownerID: UUID, container: ModelContainer, startup: NativeReleaseStartupAdmission
    private let storeURL: URL, parentIdentity: String, storeIdentity: String
    private let controls: [Data?]
    private let captureControls: [Data?], parentNames: Set<String>
    private var held: SharedMediaNativeBootstrapHandoff?
    #if DEBUG
    private var beforeTransfer: (() throws -> Void)?
    #endif

    /// Source integration only: no App/Auth/Capture caller is installed.
    /// The namespace is fixed, app/store scoped, and never selected by Capture.
    static func startup(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                        ownerID: UUID, borrowing: SharedMediaStoreReadFence? = nil) throws -> SharedMediaNativeBootstrapDiscovery {
        guard !TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        let support = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
        return try .init(container: container, startup: admission,
            parent: support.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName), ownerID: ownerID, creationAnchor: support, borrowing: borrowing)
    }

    #if DEBUG
    static func qualificationStartup(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                                     support: URL, ownerID: UUID,
                                     fault: ((SharedMediaNativeParentCreationBoundary) throws -> Void)? = nil,
                                     borrowing: SharedMediaStoreReadFence? = nil) throws -> SharedMediaNativeBootstrapDiscovery {
        let live = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard TestExecutionCoordinator.isRunningTests, support != live,
              support.pathComponents.starts(with: live.pathComponents) else { throw SharedMediaStorageFailure.invalid }
        return try .init(container: container, startup: admission,
            parent: support.appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName), ownerID: ownerID, creationAnchor: support, parentHooks: .init(fault: fault), borrowing: borrowing)
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
                 parentHooks: SharedMediaNativeParentCreationHooks = .init(), borrowing: SharedMediaStoreReadFence? = nil) throws {
        let fence = try borrowing ?? startup.acquireFence(container: container)
        try startup.require(container: container, fence: fence)
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
        let names = try SharedMediaNativeBootstrapFiles.names(handle.fd,
            maximum: SharedMediaNativeBootstrapCodec.controlNames.count + 1 + SharedMediaCaptureRootJournal.names.count)
        let parentReceipt = try SharedMediaNativeBootstrapFiles.read(handle.fd, SharedMediaNativeBootstrapCodec.parentReceiptName)
        guard creationAnchor == nil || parentReceipt != nil else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaNativeBootstrapCodec.validateParent(parentReceipt, store: storeIdentity,
            storeParent: fence.binding().parent, parent: identity)
        guard names.isSubset(of: SharedMediaNativeBootstrapCodec.allowedNames(parentReceipt: parentReceipt)
            .union(SharedMediaCaptureRootJournal.names)) else { throw SharedMediaStorageFailure.conflict }
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
        let captureRecords = try Self.readCaptureControls(handle.fd)
        if !names.isDisjoint(with: SharedMediaCaptureRootJournal.names) {
            guard let profile, let intent = captureRecords[0] else { throw SharedMediaStorageFailure.conflict }
            captureRootPrefix = try .init(profile: profile, parentIdentity: identity, intent: intent,
                root: captureRecords[1], namespace: captureRecords[2], final: captureRecords[3])
        } else {
            guard captureRecords.allSatisfy({ $0 == nil }) else { throw SharedMediaStorageFailure.conflict }
            captureRootPrefix = nil
        }
        try startup.require(container: container, fence: fence)
        self.parent = parent; self.inventoryID = inventoryID; self.ownerID = ownerID
        self.container = container; self.startup = startup; storeURL = configuration.url
        parentIdentity = identity; controls = records; existingProfile = profile
        captureControls = captureRecords; parentNames = names
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
              try Self.readControls(result.parent.fd) == controls,
              try Self.readCaptureControls(result.parent.fd) == captureControls,
              try SharedMediaNativeBootstrapFiles.names(result.parent.fd,
                maximum: SharedMediaNativeBootstrapCodec.controlNames.count + 1 + SharedMediaCaptureRootJournal.names.count) == parentNames else {
            throw SharedMediaStorageFailure.conflict
        }
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
    private static func readCaptureControls(_ fd: Int32) throws -> [Data?] {
        let names = [SharedMediaCaptureRootJournal.intentName, SharedMediaCaptureRootJournal.rootReceiptName,
            SharedMediaCaptureRootJournal.childReceiptName, SharedMediaCaptureRootJournal.finalName]
        return try names.map {
            try SharedMediaNativeBootstrapFiles.read(fd, $0, maximumBytes: Int64(SharedMediaCaptureRootJournal.maximumRecordBytes))
        }
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

/// Cleanup-only lease over an existing control parent and exact constructed
/// store. It never creates roots, acquires normal dispatch or mints bootstrap
/// authority. Kept here so descriptor transfers and control reads stay private.
@MainActor
final class SharedMediaNativeErasureParent {
    private typealias Files = SharedMediaNativeBootstrapFiles
    let parent: URL
    let storeIdentity: String
    let storeFileIdentity: String
    let storeParentIdentity: String
    let controlParentIdentity: String
    let parentReceiptSHA256: String
    private let container: ModelContainer
    private let admission: NativeReleaseStartupAdmission
    private let authorization: SharedMediaNativeErasureAuthorization
    private let operation: SharedMediaNativeErasureAuthorization.Identity
    private let runtimeCheckpoint: () throws -> Void
    private let fence: SharedMediaStoreReadFence
    private let storeURL: URL
    private let store: SharedMediaNativeBootstrapDescriptor
    private let handle: SharedMediaNativeBootstrapDescriptor
    private let parentReceipt: Data

    static func open(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                     authorization: SharedMediaNativeErasureAuthorization,
                     runtimeCheckpoint: @escaping () throws -> Void) throws -> SharedMediaNativeErasureParent {
        guard !TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        return try .init(container: container, admission: admission, authorization: authorization,
            parent: URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
                .appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName), runtimeCheckpoint: runtimeCheckpoint)
    }

    #if DEBUG
    static func qualification(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                              authorization: SharedMediaNativeErasureAuthorization, parent: URL,
                              runtimeCheckpoint: @escaping () throws -> Void) throws -> SharedMediaNativeErasureParent {
        let live = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
            .appendingPathComponent(SharedMediaNativeBootstrapCodec.parentName)
        guard TestExecutionCoordinator.isRunningTests, parent != live else { throw SharedMediaStorageFailure.closed }
        return try .init(container: container, admission: admission, authorization: authorization,
            parent: parent, runtimeCheckpoint: runtimeCheckpoint)
    }
    #endif

    private init(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                 authorization: SharedMediaNativeErasureAuthorization, parent: URL,
                 runtimeCheckpoint: @escaping () throws -> Void) throws {
        let operation = try authorization.require(container: container)
        try runtimeCheckpoint()
        let fence = try admission.acquireFence(container: container)
        try admission.require(container: container, fence: fence)
        guard !container.mainContext.hasChanges, let configuration = container.configurations.first,
              parent != configuration.url.deletingLastPathComponent() else { throw SharedMediaStorageFailure.conflict }
        let opened = Darwin.open(configuration.url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard opened >= 0 else { throw SharedMediaStorageFailure.unavailable }
        let store = SharedMediaNativeBootstrapDescriptor(opened)
        let fileIdentity = try Files.identity(opened)
        try SharedMediaNativeBootstrapDiscovery.requireStore(store, at: configuration.url, identity: fileIdentity)
        let storeIdentity = try SharedMediaNativeEligibility.storeIdentity(at: configuration.url)
        let storeParent = try fence.binding().parent
        let handle = try Files.lockParent(parent), controlParent = try Files.identity(handle.fd)
        // Live cleanup never adopts an unreceipted control parent, even empty.
        guard let receipt = try Files.read(handle.fd, SharedMediaNativeBootstrapCodec.parentReceiptName) else {
            throw SharedMediaStorageFailure.conflict
        }
        try SharedMediaNativeBootstrapCodec.validateParent(receipt, store: storeIdentity,
            storeParent: storeParent, parent: controlParent)
        self.container = container; self.admission = admission; self.authorization = authorization
        self.operation = operation; self.runtimeCheckpoint = runtimeCheckpoint; self.fence = fence
        self.parent = parent; storeURL = configuration.url; self.store = store; self.handle = handle
        self.storeIdentity = storeIdentity; storeFileIdentity = fileIdentity; storeParentIdentity = storeParent
        controlParentIdentity = controlParent; parentReceipt = receipt
        parentReceiptSHA256 = SharedMediaAcquisitionEncoding.digest(receipt)
        try check()
    }

    func check() throws {
        guard try authorization.require(container: container) == operation,
              !container.mainContext.hasChanges else { throw SharedMediaStorageFailure.stale }
        try runtimeCheckpoint(); try admission.require(container: container, fence: fence)
        try SharedMediaNativeBootstrapDiscovery.requireStore(store, at: storeURL, identity: storeFileIdentity)
        guard try SharedMediaNativeEligibility.storeIdentity(at: storeURL) == storeIdentity,
              try fence.binding().parent == storeParentIdentity,
              try Files.identity(handle.fd) == controlParentIdentity,
              try SharedMediaStorageFileOwner.directoryIdentity(parent) == controlParentIdentity,
              try Files.read(handle.fd, SharedMediaNativeBootstrapCodec.parentReceiptName) == parentReceipt else {
            throw SharedMediaStorageFailure.stale
        }
        let allowed = SharedMediaNativeBootstrapCodec.allowedNames(parentReceipt: parentReceipt)
            .union(SharedMediaCaptureRootJournal.names)
        let attributes = try parent.resourceValues(forKeys: [.isDirectoryKey, .isExcludedFromBackupKey])
        guard attributes.isDirectory == true, attributes.isExcludedFromBackup == true else { throw SharedMediaStorageFailure.conflict }
        guard try Files.names(handle.fd, maximum: allowed.count).isSubset(of: allowed) else {
            throw SharedMediaStorageFailure.conflict
        }
        try SharedMediaNativeBootstrapDiscovery.requireStore(store, at: storeURL, identity: storeFileIdentity)
        try runtimeCheckpoint()
        guard try authorization.require(container: container) == operation else { throw SharedMediaStorageFailure.stale }
    }

    func require(header: SharedMediaNativeErasureHeader, profile: SharedMediaNativeAppProfile) throws {
        try check(); try authorization.require(header: header, profile: profile, container: container)
        guard profile.storeIdentity == storeIdentity, header.storeFileIdentity == storeFileIdentity,
              header.storeParentIdentity == storeParentIdentity, header.controlParentIdentity == controlParentIdentity,
              header.parentReceiptSHA256 == parentReceiptSHA256 else { throw SharedMediaStorageFailure.conflict }
    }

    func makeHeader(profile: SharedMediaNativeAppProfile, controlSHA256: String, sourceRevision: Int64,
                    sourceTables: [SharedMediaNativeErasureGraph.Table],
                    chain: SharedMediaNativeErasureManifest.Chain) throws -> SharedMediaNativeErasureHeader {
        try check()
        guard chain.operationID == operation.operationID, chain.profile == profile, let digest = chain.digest else {
            throw SharedMediaStorageFailure.conflict
        }
        let header = SharedMediaNativeErasureHeader(version: 1, operation: operation.operation,
            operationID: operation.operationID, profileSHA256: try SharedMediaAcquisitionEncoding.digest(profile.binding),
            storeFileIdentity: storeFileIdentity, storeParentIdentity: storeParentIdentity,
            controlParentIdentity: controlParentIdentity, parentReceiptSHA256: parentReceiptSHA256,
            controlSHA256: controlSHA256, sourceRevision: sourceRevision, sourceTables: sourceTables,
            pageCount: chain.pageCount, entryCount: chain.entryCount, lastPageSHA256: digest)
        try require(header: header, profile: profile)
        return header
    }

    func requireOperation(_ id: UUID) throws {
        try check()
        guard operation.operationID == id else { throw SharedMediaStorageFailure.stale }
    }

    /// Independently empty native namespace for a new accepted operation.
    /// An older terminal receipt is checked only as existing metadata; it never
    /// supplies authority for this operation or substitutes for the zero-row
    /// and descriptor-held physical absence checks.
    func emptyLibraryIdentity() throws -> String? {
        try check()
        try SharedMediaNativeErasureJournal.requireNoNativeRows(container: container, checkpoint: { try self.check() })
        return try emptyPhysicalIdentity()
    }

    /// Physical proof only. This is not zero-row evidence or purge authority.
    func emptyPhysicalIdentity() throws -> String? {
        try check()
        guard try Files.names(handle.fd, maximum: 1) == [SharedMediaNativeBootstrapCodec.parentReceiptName] else {
            throw SharedMediaStorageFailure.conflict
        }
        let marker = SharedMediaNativeErasureTerminalReceipt.marker
        let count = fgetxattr(handle.fd, marker, nil, 0, 0, 0)
        if count < 0 {
            guard errno == ENOATTR else { throw SharedMediaStorageFailure.unavailable }
            try check(); return nil
        }
        guard count > 0, count <= SharedMediaNativeErasureTerminalReceipt.maximumBytes else { throw SharedMediaStorageFailure.conflict }
        var bytes = [UInt8](repeating: 0, count: count)
        guard bytes.withUnsafeMutableBytes({ fgetxattr(handle.fd, marker, $0.baseAddress, $0.count, 0, 0) }) == count else {
            throw SharedMediaStorageFailure.stale
        }
        let data = Data(bytes), receipt = try SharedMediaNativeErasureTerminalReceipt.decode(data)
        guard receipt.profile.storeIdentity == storeIdentity, receipt.header.storeFileIdentity == storeFileIdentity,
              receipt.header.storeParentIdentity == storeParentIdentity, receipt.header.controlParentIdentity == controlParentIdentity,
              receipt.header.parentReceiptSHA256 == parentReceiptSHA256 else { throw SharedMediaStorageFailure.conflict }
        try check(); return SharedMediaAcquisitionEncoding.digest(data)
    }

    /// Existing roots only. The returned owner can inspect sources but cannot
    /// bootstrap, finish a creation prefix, or obtain normal media admission.
    func openSources() throws -> SharedMediaNativeErasureSources {
        try check()
        return try SharedMediaNativeErasureSources(parent: self, descriptor: handle.fd) { [self] profile in
            try check()
            guard profile.storeIdentity == storeIdentity,
                  operation.signOutOwnerID.map({ $0 == profile.ownerID }) ?? true else {
                throw SharedMediaStorageFailure.conflict
            }
        }
    }

    func makeTree(profile: SharedMediaNativeAppProfile, header: SharedMediaNativeErasureHeader,
                  pages: @escaping SharedMediaNativeErasureTree.Pages) throws -> SharedMediaNativeErasureTree {
        try require(header: header, profile: profile)
        return try .init(parent: parent, held: transfer(), profile: profile, header: header,
            checkpoint: { [self] in try require(header: header, profile: profile) }, pages: pages)
    }

    /// Decode a candidate only after independently binding the accepted outer
    /// operation and held store/parent. The receipt is not an Auth grant.
    func recoverTerminal() throws -> SharedMediaNativeErasureTerminal {
        try check()
        let marker = SharedMediaNativeErasureTerminalReceipt.marker
        let count = fgetxattr(handle.fd, marker, nil, 0, 0, 0)
        guard count > 0, count <= SharedMediaNativeErasureTerminalReceipt.maximumBytes else {
            throw SharedMediaStorageFailure.conflict
        }
        var bytes = [UInt8](repeating: 0, count: count)
        guard bytes.withUnsafeMutableBytes({ fgetxattr(handle.fd, marker, $0.baseAddress, $0.count, 0, 0) }) == count else {
            throw SharedMediaStorageFailure.stale
        }
        let receipt = try SharedMediaNativeErasureTerminalReceipt.decode(Data(bytes))
        try require(header: receipt.header, profile: receipt.profile)
        return try SharedMediaNativeErasureTree.recoverTerminal(container: container, parent: parent,
            held: transfer(), expected: receipt, checkpoint: { [self] in
                try require(header: receipt.header, profile: receipt.profile)
            })
    }

    private func transfer() throws -> SharedMediaNativeLockedRoot {
        try check()
        let copy = fcntl(handle.fd, F_DUPFD_CLOEXEC, 0)
        guard copy >= 0 else { throw SharedMediaStorageFailure.unavailable }
        return SharedMediaNativeLockedRoot(url: parent, root: copy)
    }
}

/// Read-only fixed-root inspection under an accepted cleanup operation. The
/// physical source audit must still join every media leaf to its durable row.
/// Directory existence alone never supplies artifact ownership.
@MainActor
final class SharedMediaNativeErasureSources {
    private typealias Files = SharedMediaNativeBootstrapFiles
    private typealias Codec = SharedMediaNativeBootstrapCodec
    private typealias Capture = SharedMediaCaptureRootJournal
    typealias Entry = SharedMediaNativeErasureManifest.Entry
    let profile: SharedMediaNativeAppProfile
    let controlSHA256: String
    let hasCompleteCapture: Bool
    private let parent: SharedMediaNativeErasureParent
    private let descriptor: Int32
    private let validate: (SharedMediaNativeAppProfile) throws -> Void
    private let records: [String: Data]
    private let entries: [Entry]
    private let roots: [String: SharedMediaNativeBootstrapDescriptor]
    private let captureBinding: Data?
    private let expectedNames: Set<String>

    fileprivate init(parent: SharedMediaNativeErasureParent, descriptor: Int32,
                     validate: @escaping (SharedMediaNativeAppProfile) throws -> Void) throws {
        try parent.check()
        self.parent = parent; self.descriptor = descriptor; self.validate = validate
        var records: [String: Data] = [:], roots: [String: SharedMediaNativeBootstrapDescriptor] = [:]
        var entries: [Entry] = []
        func record(_ name: String) throws -> Data {
            guard let bytes = try Files.read(descriptor, name) else { throw SharedMediaStorageFailure.conflict }
            records[name] = bytes
            entries.append(.init(namespace: .control, token: name, kind: .file,
                identity: try Self.fileIdentity(descriptor, name)))
            return bytes
        }
        let intentBytes = try record(Codec.intentName)
        let intent = try Codec.decode(Codec.Intent.self, intentBytes)
        let format = try SharedMediaNativeAppProfile.PhysicalBindingFormat(journalVersion: intent.version)
        guard intent.store == parent.storeIdentity, intent.parent == parent.controlParentIdentity,
              intent.storeParent == parent.storeParentIdentity, intent.names == Codec.names else {
            throw SharedMediaStorageFailure.conflict
        }
        let progressBytes = try Codec.progressNames.map(record)
        let progress = try progressBytes.map { try Codec.decode(Codec.Progress.self, $0) }
        let finalBytes = try record(Codec.finalName), final = try Codec.decode(Codec.Final.self, finalBytes)
        guard final.version == intent.version, final.intentDigest == Codec.digest(intentBytes),
              final.identities.count == 5, final.progressDigests == progressBytes.map(Codec.digest),
              Set(final.identities + [parent.controlParentIdentity]).count == 6 else {
            throw SharedMediaStorageFailure.conflict
        }
        for (index, name) in Codec.names.enumerated() {
            let parts = name.split(separator: "/").map(String.init)
            let base = parts.count == 1 ? descriptor : roots[parts[0]]!.fd
            let item = progress[index], identity = final.identities[index]
            guard item.version == intent.version, item.intentDigest == final.intentDigest,
                  item.name == name, item.identity == identity,
                  item.parentIdentity == (try Files.identity(base)) else { throw SharedMediaStorageFailure.conflict }
            roots[name] = try Self.open(base, parts.last!, url: parent.parent.appendingPathComponent(name), identity: identity)
            let namespace = try Self.namespace(parts[0])
            entries.append(.init(namespace: namespace, token: parts.count == 1 ? "." : parts[1], kind: .directory, identity: identity))
        }
        let profile = try SharedMediaNativeAppProfile(ownerID: intent.ownerID, inventoryID: intent.inventoryID,
            generation: intent.generation, storeIdentity: intent.store,
            physicalBinding: SharedMediaNativeAppProfile.rootBinding(format: format, authority: final.identities[0], sources: [
                SharedMediaPhotoLedger.namespace: parent.parent.appendingPathComponent("photo"),
                SharedMediaInboxFiles.namespace: parent.parent.appendingPathComponent("inbox")]),
            receiptDigest: Codec.digest(finalBytes), physicalBindingFormat: format)
        try validate(profile)
        self.profile = profile
        let baseNames = Codec.controlNames.union([Codec.parentReceiptName])
        let capture = try SharedMediaCaptureControlSnapshot.read(parentFD: descriptor,
            parentIdentity: parent.controlParentIdentity, baseNames: baseNames, profile: profile)
        var captureBinding: Data?
        if let capture {
            let names = [Capture.intentName, Capture.rootReceiptName, Capture.childReceiptName, Capture.finalName]
            for (name, bytes) in zip(names, capture.records) {
                if let bytes {
                    guard try record(name) == bytes else { throw SharedMediaStorageFailure.stale }
                } else { entries.append(.init(namespace: .control, token: name, kind: .absent, identity: nil)) }
            }
            let prefix = capture.prefix
            if let root = prefix.root {
                roots[Capture.rootName] = try Self.open(descriptor, Capture.rootName,
                    url: parent.parent.appendingPathComponent(Capture.rootName), identity: root.identity)
                entries.append(.init(namespace: .capture, token: ".", kind: .directory, identity: root.identity))
                if let child = prefix.namespace {
                    let key = Capture.rootName + "/" + Capture.childName
                    roots[key] = try Self.open(roots[Capture.rootName]!.fd, Capture.childName,
                        url: parent.parent.appendingPathComponent(key), identity: child.identity)
                    entries.append(.init(namespace: .capture, token: Capture.childName, kind: .directory, identity: child.identity))
                    if let final = prefix.final {
                        let binding = try final.binding(intent: prefix.intent, root: root, namespace: child)
                        let fd = roots[Capture.rootName]!.fd
                        if fgetxattr(fd, Capture.marker, nil, 0, 0, 0) >= 0 {
                            try Files.checkMarker(fd, marker: Capture.marker, bytes: binding, allowMissing: false)
                            captureBinding = binding
                        } else { guard errno == ENOATTR else { throw SharedMediaStorageFailure.conflict } }
                    }
                } else { entries.append(.init(namespace: .capture, token: Capture.childName, kind: .absent, identity: nil)) }
            } else {
                entries.append(.init(namespace: .capture, token: ".", kind: .absent, identity: nil))
                entries.append(.init(namespace: .capture, token: Capture.childName, kind: .absent, identity: nil))
            }
        } else {
            for name in [Capture.intentName, Capture.rootReceiptName, Capture.childReceiptName, Capture.finalName] {
                entries.append(.init(namespace: .control, token: name, kind: .absent, identity: nil))
            }
            entries.append(.init(namespace: .capture, token: ".", kind: .absent, identity: nil))
            entries.append(.init(namespace: .capture, token: Capture.childName, kind: .absent, identity: nil))
        }
        self.records = records; self.roots = roots; self.entries = entries
        self.captureBinding = captureBinding; hasCompleteCapture = captureBinding != nil
        expectedNames = baseNames.union(capture?.names ?? [])
        // Include absent controls in the fixed encoding, so a newly added
        // prefix changes the initial/rebuilt manifest header.
        let controls = entries.filter { $0.namespace == .control }.sorted { $0.key < $1.key }.map { [$0.token, records[$0.token]?.base64EncodedString() ?? ""] }
        controlSHA256 = try Codec.digest(Codec.encode(controls))
        try check()
    }

    func check() throws {
        try validate(profile)
        guard try Files.names(descriptor, maximum: expectedNames.count) == expectedNames else { throw SharedMediaStorageFailure.conflict }
        for entry in entries {
            if entry.namespace == .control {
                guard try Files.read(descriptor, entry.token) == records[entry.token],
                      try Self.fileIdentity(descriptor, entry.token) == entry.identity else { throw SharedMediaStorageFailure.stale }
            } else {
                let key = entry.namespace.rawValue + (entry.token == "." ? "" : "/" + entry.token)
                if let root = roots[key], let identity = entry.identity {
                    guard try Files.identity(root.fd) == identity,
                          try SharedMediaStorageFileOwner.directoryIdentity(parent.parent.appendingPathComponent(key)) == identity,
                          try parent.parent.appendingPathComponent(key).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
                        throw SharedMediaStorageFailure.stale
                    }
                } else if entry.token == "." {
                    guard try !Files.names(descriptor, maximum: expectedNames.count).contains(entry.namespace.rawValue) else {
                        throw SharedMediaStorageFailure.conflict
                    }
                }
            }
        }
        for (root, children) in [("authority", Set<String>()), ("photo", ["PhotoPreparation"]), ("inbox", ["InboxSources"])] {
            guard try Files.names(roots[root]!.fd) == children else { throw SharedMediaStorageFailure.conflict }
            try Files.checkMarker(roots[root]!.fd, marker: Files.marker(root)!, bytes: profile.binding, allowMissing: false)
        }
        if let root = roots[Capture.rootName] {
            let child = roots[Capture.rootName + "/" + Capture.childName]
            guard try Files.names(root.fd) == (child == nil ? [] : [Capture.childName]) else { throw SharedMediaStorageFailure.conflict }
            if let captureBinding { try Files.checkMarker(root.fd, marker: Capture.marker, bytes: captureBinding, allowMissing: false) } else {
                guard fgetxattr(root.fd, Capture.marker, nil, 0, 0, 0) < 0, errno == ENOATTR else { throw SharedMediaStorageFailure.conflict }
                if let child { guard try Files.names(child.fd).isEmpty else { throw SharedMediaStorageFailure.conflict } }
            }
        }
        try validate(profile)
    }

    /// Bind the independently opened controls to the exact operation header.
    /// A syntactically valid digest from a caller is never sufficient evidence.
    func require(header: SharedMediaNativeErasureHeader) throws {
        try check()
        try parent.require(header: header, profile: profile)
        guard header.profileSHA256 == (try SharedMediaAcquisitionEncoding.digest(profile.binding)),
              header.controlSHA256 == controlSHA256 else { throw SharedMediaStorageFailure.conflict }
        try check()
    }

    func appendFixedEntries(to spool: SharedMediaNativeErasureManifestSpool) throws {
        try check()
        for entry in entries { try spool.append(entry) }
        try check()
    }

    func visitPhotoEntries(_ observe: (Entry) throws -> Void) async throws {
        try check()
        guard let namespace = roots["photo/PhotoPreparation"] else { throw SharedMediaStorageFailure.closed }
        try await SharedMediaNativeErasurePhotoWalk.visit(namespace: namespace.fd, ownerID: profile.ownerID,
            checkpoint: { try self.check() }, observe: observe)
        try check()
    }

    func inspectPhoto(_ request: SharedMediaNativeErasurePhotoRead.Request) throws -> SharedMediaNativeErasurePhotoRead.Observation {
        try check()
        guard let namespace = roots["photo/PhotoPreparation"] else { throw SharedMediaStorageFailure.closed }
        return try SharedMediaNativeErasurePhotoRead.inspect(request, namespace: namespace.fd, ownerID: profile.ownerID,
            checkpoint: { try self.check() })
    }

    func requireEmptyInbox() throws {
        try check()
        guard let namespace = roots["inbox/InboxSources"], try Files.names(namespace.fd, maximum: 0).isEmpty else {
            throw SharedMediaStorageFailure.conflict
        }
        try check()
    }

    func captureFiles() throws -> SharedMediaCaptureArtifactFiles? {
        try check()
        guard hasCompleteCapture else { return nil }
        guard let root = roots[Capture.rootName], let child = roots[Capture.rootName + "/" + Capture.childName],
              let captureBinding else { throw SharedMediaStorageFailure.conflict }
        let binding = try SharedMediaNativeLockedRoot.CaptureBinding(rootIdentity: Files.identity(root.fd),
            childIdentity: Files.identity(child.fd), marker: captureBinding)
        let rootCopy = fcntl(root.fd, F_DUPFD_CLOEXEC, 0)
        guard rootCopy >= 0 else { throw SharedMediaStorageFailure.unavailable }
        let childCopy = fcntl(child.fd, F_DUPFD_CLOEXEC, 0)
        guard childCopy >= 0 else { Darwin.close(rootCopy); throw SharedMediaStorageFailure.unavailable }
        let url = parent.parent.appendingPathComponent(Capture.rootName, isDirectory: true)
        let transfer = SharedMediaNativeLockedRoot(url: url, root: rootCopy, child: childCopy, captureBinding: binding)
        return try SharedMediaCaptureArtifactFiles(erasureRoot: transfer, rootURL: url, checkpoint: { [self] in try check() })
    }

    private static func namespace(_ name: String) throws -> SharedMediaNativeErasureManifest.Namespace {
        guard let value = SharedMediaNativeErasureManifest.Namespace(rawValue: name) else { throw SharedMediaStorageFailure.invalid }
        return value
    }
    private static func open(_ parent: Int32, _ name: String, url: URL, identity: String) throws -> SharedMediaNativeBootstrapDescriptor {
        let value = try SharedMediaNativeBootstrapDescriptor(Files.directory(parent, name, create: false))
        guard try Files.identity(value.fd) == identity,
              try SharedMediaStorageFileOwner.directoryIdentity(url) == identity,
              try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
            throw SharedMediaStorageFailure.conflict
        }
        return value
    }
    private static func fileIdentity(_ parent: Int32, _ name: String) throws -> String? {
        var value = stat()
        guard fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW) == 0 else {
            guard errno == ENOENT else { throw SharedMediaStorageFailure.conflict }; return nil
        }
        guard value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1 else { throw SharedMediaStorageFailure.conflict }
        return "\(value.st_dev):\(value.st_ino):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
    }
}

// The additive root shares file-private I/O with the base bootstrap. Keeping
// both here prevents arbitrary control-file writes from becoming a module API.
enum SharedMediaCaptureRootBoundary: CaseIterable {
    case afterIntent, afterRootDirectory, afterRootReceipt
    case afterNamespaceDirectory, afterNamespaceReceipt, afterFinal, afterMarker
}

private final class SharedMediaCaptureRootDescriptor {
    let fd: Int32
    init(_ fd: Int32) { self.fd = fd }
    deinit { Darwin.close(fd) }
}

/// Additive directory registration under the existing store and control-parent
/// fence. This does not authorize an artifact write, queue admission or release.
/// The native repository must first validate the immutable base bootstrap.
@MainActor
final class SharedMediaNativeCaptureRootFiles {
    private typealias Journal = SharedMediaCaptureRootJournal
    private typealias Files = SharedMediaNativeBootstrapFiles
    private let parent: URL, parentIdentity: String
    private let parentHandle: SharedMediaCaptureRootDescriptor
    private let validate: () throws -> Void
    private let baseNames: Set<String>
    private let records: [String: Data]
    private let rootIdentity: String, namespaceIdentity: String, binding: Data
    private var transfer: SharedMediaNativeLockedRoot?

    convenience init(authority: SharedMediaNativeBootstrapAuthority, parentDescriptor: Int32,
                     profile: SharedMediaNativeAppProfile, createOrResume: Bool) throws {
        try authority.validateDatabase(profile: profile)
        guard try authority.isCommitted() else { throw SharedMediaStorageFailure.closed }
        let receipt = try Files.read(parentDescriptor, SharedMediaNativeBootstrapCodec.parentReceiptName)
        try self.init(parent: authority.parent, parentDescriptor: parentDescriptor, profile: profile,
            baseNames: SharedMediaNativeBootstrapCodec.allowedNames(parentReceipt: receipt),
            createOrResume: createOrResume, validate: { try authority.validateDatabase(profile: profile) },
            fault: { try authority.captureBoundary($0) })
    }

    fileprivate init(parent: URL, parentDescriptor: Int32, profile: SharedMediaNativeAppProfile,
                     baseNames: Set<String>, createOrResume: Bool, validate: @escaping () throws -> Void,
                     fault: ((SharedMediaCaptureRootBoundary) throws -> Void)?) throws {
        try validate()
        let duplicate = fcntl(parentDescriptor, F_DUPFD_CLOEXEC, 0)
        guard duplicate >= 0 else { throw SharedMediaStorageFailure.unavailable }
        let parentHandle = SharedMediaCaptureRootDescriptor(duplicate)
        let parentID = try Files.identity(duplicate)
        self.parent = parent; self.parentHandle = parentHandle; self.parentIdentity = parentID
        self.validate = validate; self.baseNames = baseNames
        func requireParent() throws {
            try validate()
            guard try SharedMediaStorageFileOwner.directoryIdentity(parent) == parentID,
                  try Files.identity(duplicate) == parentID else { throw SharedMediaStorageFailure.conflict }
            let names = try Files.names(duplicate, maximum: baseNames.count + Journal.names.count)
            guard baseNames.isSubset(of: names), names.isSubset(of: baseNames.union(Journal.names)) else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        func boundary(_ value: SharedMediaCaptureRootBoundary) throws {
            try requireParent()
            #if DEBUG
            try fault?(value)
            #endif
        }
        try requireParent()
        let savedIntent = try Files.read(duplicate, Journal.intentName, maximumBytes: Int64(Journal.maximumRecordBytes))
        let savedRoot = try Files.read(duplicate, Journal.rootReceiptName, maximumBytes: Int64(Journal.maximumRecordBytes))
        let savedChild = try Files.read(duplicate, Journal.childReceiptName, maximumBytes: Int64(Journal.maximumRecordBytes))
        let savedFinal = try Files.read(duplicate, Journal.finalName, maximumBytes: Int64(Journal.maximumRecordBytes))
        guard createOrResume || savedFinal != nil else { throw SharedMediaStorageFailure.closed }
        let intent: Journal.Intent
        if let savedIntent {
            let prefix = try Journal.Prefix(profile: profile, parentIdentity: parentID,
                intent: savedIntent, root: savedRoot, namespace: savedChild, final: savedFinal)
            intent = prefix.intent
        } else {
            guard createOrResume, savedRoot == nil, savedChild == nil, savedFinal == nil,
                  try Files.names(duplicate, maximum: baseNames.count + Journal.names.count) == baseNames else {
                throw SharedMediaStorageFailure.conflict
            }
            intent = try .init(profile: profile, parentIdentity: parentID, operationID: UUID())
        }
        if savedFinal == nil {
            var space = statfs()
            guard fstatfs(duplicate, &space) == 0, space.f_bsize > 0 else { throw SharedMediaStorageFailure.unavailable }
            let (available, overflow) = UInt64(space.f_bavail).multipliedReportingOverflow(by: UInt64(space.f_bsize))
            guard !overflow, available <= Int64.max,
                  Int64(available) >= PhotoPreparationPolicy.minimumFree + Int64(4 * Journal.maximumRecordBytes + 512) else {
                throw PhotoPreparationFailure.storageLimit
            }
        }
        if savedIntent == nil { try Files.write(duplicate, Journal.intentName, Journal.encode(intent)) }
        try boundary(.afterIntent)
        func openDirectory(base: Int32, name: String, url: URL, receipt: Data?, kind: Journal.DirectoryKind,
                           receiptName: String, directoryBoundary: SharedMediaCaptureRootBoundary,
                           receiptBoundary: SharedMediaCaptureRootBoundary) throws -> (SharedMediaCaptureRootDescriptor, Journal.Directory) {
            try requireParent()
            guard receipt != nil || createOrResume else { throw SharedMediaStorageFailure.closed }
            let handle = try SharedMediaCaptureRootDescriptor(Files.directory(base, name, create: receipt == nil))
            let identity = try Files.identity(handle.fd), parentIdentity = try Files.identity(base)
            let record: Journal.Directory
            if let receipt {
                record = try Journal.decode(Journal.Directory.self, receipt)
                try record.require(intent: intent, kind: kind, parentIdentity: parentIdentity)
                guard record.identity == identity else { throw SharedMediaStorageFailure.conflict }
            } else {
                // A crash before the creation receipt leaves an ambiguous path.
                // A later attempt uses mkdir(O_EXCL semantics), never adoption.
                try boundary(directoryBoundary)
                guard try Files.names(handle.fd).isEmpty else { throw SharedMediaStorageFailure.conflict }
                var url = url, attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
                try url.setResourceValues(attributes)
                guard fsync(handle.fd) == 0, fsync(base) == 0 else { throw SharedMediaStorageFailure.unavailable }
                record = try .init(intent: intent, kind: kind, parentIdentity: parentIdentity, identity: identity)
                try requireParent()
                try Files.write(duplicate, receiptName, Journal.encode(record))
            }
            try boundary(receiptBoundary)
            let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            guard values.isExcludedFromBackup == true,
                  try SharedMediaStorageFileOwner.directoryIdentity(url) == identity else { throw SharedMediaStorageFailure.conflict }
            return (handle, record)
        }
        let rootURL = parent.appendingPathComponent(Journal.rootName, isDirectory: true)
        let (root, rootRecord) = try openDirectory(base: duplicate, name: Journal.rootName, url: rootURL,
            receipt: savedRoot, kind: .root, receiptName: Journal.rootReceiptName,
            directoryBoundary: .afterRootDirectory, receiptBoundary: .afterRootReceipt)
        guard try Files.names(root.fd).isSubset(of: [Journal.childName]) else { throw SharedMediaStorageFailure.conflict }
        let (child, childRecord) = try openDirectory(base: root.fd, name: Journal.childName,
            url: rootURL.appendingPathComponent(Journal.childName, isDirectory: true), receipt: savedChild,
            kind: .namespace, receiptName: Journal.childReceiptName,
            directoryBoundary: .afterNamespaceDirectory, receiptBoundary: .afterNamespaceReceipt)
        guard childRecord.identity != parentID else { throw SharedMediaStorageFailure.conflict }
        let final = try Journal.Final(intent: intent, root: rootRecord, namespace: childRecord)
        let finalBytes = try Journal.encode(final)
        if let savedFinal {
            guard savedFinal == finalBytes else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard try Files.names(child.fd).isEmpty else { throw SharedMediaStorageFailure.conflict }
            try Files.write(duplicate, Journal.finalName, finalBytes)
        }
        try boundary(.afterFinal)
        let markerBytes = try final.binding(intent: intent, root: rootRecord, namespace: childRecord)
        try Files.checkMarker(root.fd, marker: Journal.marker, bytes: markerBytes, allowMissing: createOrResume)
        if createOrResume { try Files.bind(root.fd, marker: Journal.marker, bytes: markerBytes, allowCreate: true) }
        try boundary(.afterMarker)
        records = try [Journal.intentName: Journal.encode(intent), Journal.rootReceiptName: Journal.encode(rootRecord),
            Journal.childReceiptName: Journal.encode(childRecord), Journal.finalName: finalBytes]
        binding = markerBytes; rootIdentity = rootRecord.identity; namespaceIdentity = childRecord.identity
        // Duplicate the locked descriptions; neither directory is reopened or
        // unlocked during the one-shot handoff to its artifact owner.
        let rootCopy = fcntl(root.fd, F_DUPFD_CLOEXEC, 0)
        guard rootCopy >= 0 else { throw SharedMediaStorageFailure.unavailable }
        let childCopy = fcntl(child.fd, F_DUPFD_CLOEXEC, 0)
        guard childCopy >= 0 else { Darwin.close(rootCopy); throw SharedMediaStorageFailure.unavailable }
        transfer = SharedMediaNativeLockedRoot(url: rootURL, root: rootCopy, child: childCopy,
            captureBinding: .init(rootIdentity: rootIdentity, childIdentity: namespaceIdentity, marker: binding))
        try check()
    }

    func check() throws {
        try validate()
        guard try Files.identity(parentHandle.fd) == parentIdentity,
              try SharedMediaStorageFileOwner.directoryIdentity(parent) == parentIdentity,
              try Files.names(parentHandle.fd, maximum: baseNames.count + Journal.names.count) == baseNames.union(Journal.names) else {
            throw SharedMediaStorageFailure.conflict
        }
        for (name, bytes) in records {
            guard try Files.read(parentHandle.fd, name, maximumBytes: Int64(Journal.maximumRecordBytes)) == bytes else { throw SharedMediaStorageFailure.conflict }
        }
        let rootURL = parent.appendingPathComponent(Journal.rootName, isDirectory: true)
        let fd = openat(parentHandle.fd, Journal.rootName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.conflict }; defer { Darwin.close(fd) }
        guard try Files.identity(fd) == rootIdentity, try Files.names(fd) == [Journal.childName],
              try SharedMediaStorageFileOwner.directoryIdentity(rootURL.appendingPathComponent(Journal.childName)) == namespaceIdentity else {
            throw SharedMediaStorageFailure.conflict
        }
        for url in [rootURL, rootURL.appendingPathComponent(Journal.childName)] {
            guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        try Files.checkMarker(fd, marker: Journal.marker, bytes: binding, allowMissing: false)
        try validate()
    }

    func take() throws -> SharedMediaNativeLockedRoot {
        try check()
        guard let result = transfer else { throw SharedMediaStorageFailure.closed }
        transfer = nil
        return result
    }

    #if DEBUG
    static func qualification(parent: URL, profile: SharedMediaNativeAppProfile, createOrResume: Bool,
                              fault: ((SharedMediaCaptureRootBoundary) throws -> Void)? = nil,
                              validate: @escaping () throws -> Void = {}) throws -> SharedMediaNativeCaptureRootFiles {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        let support = URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard parent == parent.resolvingSymlinksInPath().standardizedFileURL, parent != support,
              parent.pathComponents.starts(with: support.pathComponents) else { throw SharedMediaStorageFailure.invalid }
        let fd = try SharedMediaStorageFileOwner.openDirectory(parent); defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw SharedMediaStorageFailure.busy }
        return try .init(parent: parent, parentDescriptor: fd, profile: profile, baseNames: [],
            createOrResume: createOrResume, validate: validate, fault: fault)
    }
    #endif
}

/// Passive bounded snapshot. It conveys no directory or artifact authority.
@MainActor
private struct SharedMediaCaptureControlSnapshot: Equatable {
    let names: Set<String>
    let records: [Data?]
    let prefix: SharedMediaCaptureRootJournal.Prefix

    static func read(parentFD: Int32, parentIdentity: String, baseNames: Set<String>,
                     profile: SharedMediaNativeAppProfile) throws -> Self? {
        typealias Journal = SharedMediaCaptureRootJournal
        typealias Files = SharedMediaNativeBootstrapFiles
        let names = try Files.names(parentFD, maximum: baseNames.count + Journal.names.count)
        guard names.isSubset(of: baseNames.union(Journal.names)) else { throw SharedMediaStorageFailure.conflict }
        let extensionNames = names.intersection(Journal.names)
        guard !extensionNames.isEmpty else { return nil }
        let records = try [Journal.intentName, Journal.rootReceiptName, Journal.childReceiptName, Journal.finalName]
            .map { try Files.read(parentFD, $0, maximumBytes: Int64(Journal.maximumRecordBytes)) }
        guard let intent = records[0] else { throw SharedMediaStorageFailure.conflict }
        let prefix = try Journal.Prefix(profile: profile, parentIdentity: parentIdentity,
            intent: intent, root: records[1], namespace: records[2], final: records[3])
        return .init(names: extensionNames, records: records, prefix: prefix)
    }
}
