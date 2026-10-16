import CryptoKit
import Darwin
import Foundation

/// Qualification roots must already exist. A lock is held across the entire
/// reservation, provider callback, file commit and fresh-context ledger save.
actor PhotoPreparationFileStore {
    let root: URL
    init(root: URL) { self.root = root }

    func locked<T: Sendable>(
        _ body: @Sendable (PhotoPreparationLockedFiles) async throws -> T
    ) async throws -> T {
        let files = try PhotoPreparationLockedFiles(root: root)
        defer { files.close() }
        return try await body(files)
    }
}

/// Descriptor-relative operations only; tokens are generated UUID pairs.
/// Instances are usable only for the dynamic lifetime of `locked`.
final class PhotoPreparationLockedFiles: @unchecked Sendable {
    private let rootURL: URL
    private let sharedBinding: SharedMediaPhotoBinding?
    private let inspection: PhotoPreparationDirectoryInspection
    private var rootFD: Int32 = -1
    private var namespaceFD: Int32 = -1
    #if DEBUG
    var sharedWriteFault: (@Sendable (Int) throws -> Void)?
    var sharedReleaseFault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?
    #endif

    init(root: URL, sharedBinding: SharedMediaPhotoBinding? = nil,
         inspection: PhotoPreparationDirectoryInspection = .init()) throws {
        rootURL = root
        self.sharedBinding = sharedBinding
        self.inspection = inspection
        guard root.isFileURL, root.path.hasPrefix("/") else { throw PhotoPreparationFailure.unavailable }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw PhotoPreparationFailure.unavailable }
        do {
            for component in root.standardizedFileURL.pathComponents.dropFirst() {
                let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else { throw PhotoPreparationFailure.unavailable }
                Darwin.close(fd)
                fd = next
            }
            rootFD = fd
            guard flock(rootFD, (sharedBinding == nil ? LOCK_SH : LOCK_EX) | LOCK_NB) == 0 else { throw PhotoPreparationFailure.busy }
            if sharedBinding?.initializing == true {
                let existing = openat(rootFD, "PhotoPreparation", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                if existing >= 0 {
                    defer { Darwin.close(existing) }
                    try requireEmpty(existing)
                } else if errno != ENOENT { throw PhotoPreparationFailure.inconsistentOwnership }
            }
            try checkSharedBinding(initializing: sharedBinding?.initializing == true)
            if mkdirat(rootFD, "PhotoPreparation", 0o700) != 0 && errno != EEXIST {
                throw PhotoPreparationFailure.unavailable
            }
            namespaceFD = openat(rootFD, "PhotoPreparation", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard namespaceFD >= 0, flock(namespaceFD, LOCK_EX | LOCK_NB) == 0 else {
                throw PhotoPreparationFailure.busy
            }
            try checkIdentity()
            guard fsync(rootFD) == 0 else { throw PhotoPreparationFailure.unavailable }
        } catch {
            if rootFD < 0 { Darwin.close(fd) }
            close()
            throw error
        }
    }

    deinit { close() }

    func close() {
        if namespaceFD >= 0 { Darwin.close(namespaceFD); namespaceFD = -1 }
        if rootFD >= 0 { Darwin.close(rootFD); rootFD = -1 }
    }

    func checkIdentity() throws {
        try checkSharedBinding(initializing: false)
        var heldRoot = stat(), namedRoot = stat()
        guard fstat(rootFD, &heldRoot) == 0, lstat(rootURL.path, &namedRoot) == 0,
              namedRoot.st_mode & S_IFMT == S_IFDIR,
              heldRoot.st_dev == namedRoot.st_dev, heldRoot.st_ino == namedRoot.st_ino else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        var held = stat(), named = stat()
        guard namespaceFD >= 0, rootFD >= 0,
              fstat(namespaceFD, &held) == 0,
              fstatat(rootFD, "PhotoPreparation", &named, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_dev == named.st_dev, held.st_ino == named.st_ino,
              named.st_mode & S_IFMT == S_IFDIR else { throw PhotoPreparationFailure.inconsistentOwnership }
    }

    /// Marker is checked from the locked descriptor before namespace creation.
    private func checkSharedBinding(initializing: Bool) throws {
        let name = "com.merian.p1-shared-v1"
        let size = fgetxattr(rootFD, name, nil, 0, 0, 0)
        guard let binding = sharedBinding else {
            guard size < 0, errno == ENOATTR else { throw PhotoPreparationFailure.unsupportedComposition }
            return
        }
        if size >= 0 {
            guard !initializing, size == binding.bytes.count, size <= 512 else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
            var bytes = [UInt8](repeating: 0, count: size)
            let read = bytes.withUnsafeMutableBytes { fgetxattr(rootFD, name, $0.baseAddress, size, 0, 0) }
            guard read == size, Data(bytes) == binding.bytes else { throw PhotoPreparationFailure.inconsistentOwnership }
        } else {
            guard initializing, errno == ENOATTR, binding.bytes.count <= 512 else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
            let written = binding.bytes.withUnsafeBytes { fsetxattr(rootFD, name, $0.baseAddress, binding.bytes.count, 0, XATTR_CREATE) }
            guard written == 0, fsync(rootFD) == 0 else { throw PhotoPreparationFailure.unavailable }
        }
    }

    private func requireEmpty(_ fd: Int32) throws {
        let copy = dup(fd)
        guard copy >= 0 else { throw PhotoPreparationFailure.unavailable }
        guard let directory = fdopendir(copy) else { Darwin.close(copy); throw PhotoPreparationFailure.unavailable }
        defer { closedir(directory) }
        while let entry = try inspection.next(stage: .initialEmpty, read: { readdir(directory) }) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            guard name == "." || name == ".." else { throw PhotoPreparationFailure.inconsistentOwnership }
        }
    }

    func checkFreeSpace() throws {
        try checkIdentity()
        var info = statfs()
        guard fstatfs(namespaceFD, &info) == 0, info.f_bsize > 0 else { throw PhotoPreparationFailure.storageLimit }
        let (available, overflow) = UInt64(info.f_bavail).multipliedReportingOverflow(by: UInt64(info.f_bsize))
        guard !overflow, available >= UInt64(PhotoPreparationPolicy.minimumFree) else {
            throw PhotoPreparationFailure.storageLimit
        }
    }

    private func directory(_ token: String, create: Bool) throws -> (Int32, String) {
        try checkIdentity()
        let components = token.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 3 else { throw PhotoPreparationFailure.inconsistentOwnership }
        for part in components.prefix(2) {
            guard let id = UUID(uuidString: part), id.uuidString.lowercased() == part else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
        }
        let name = components[2]
        let identity = name.hasSuffix(".partial") ? String(name.dropLast(8)) : name
        guard let asset = UUID(uuidString: identity), asset.uuidString.lowercased() == identity else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        var fd = dup(namespaceFD)
        guard fd >= 0 else { throw PhotoPreparationFailure.unavailable }
        do {
            for component in components.prefix(2) {
                if create && mkdirat(fd, component, 0o700) != 0 && errno != EEXIST {
                    throw PhotoPreparationFailure.unavailable
                }
                let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else {
                    if errno == ENOENT { throw PhotoPreparationFailure.missingMedia }
                    throw PhotoPreparationFailure.inconsistentOwnership
                }
                if create && fsync(fd) != 0 { Darwin.close(next); throw PhotoPreparationFailure.unavailable }
                Darwin.close(fd)
                fd = next
            }
        } catch { Darwin.close(fd); throw error }
        return (fd, name)
    }

    private func checkDirectoryIdentity(_ fd: Int32, token: String) throws {
        let (namedFD, _) = try directory(token, create: false)
        defer { Darwin.close(namedFD) }
        var held = stat(), named = stat()
        guard fstat(fd, &held) == 0, fstat(namedFD, &named) == 0,
              held.st_dev == named.st_dev, held.st_ino == named.st_ino else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
    }

    func write(_ data: Data, intent: PhotoPreparationIntent) throws -> PhotoPreparationFile {
        guard !data.isEmpty, data.count <= intent.maximumBytes else { throw PhotoPreparationFailure.sizeLimit }
        let contentType = try Self.validateImage(data, maximumBytes: intent.maximumBytes)
        let (directoryFD, name) = try directory(intent.fileToken, create: true)
        defer { Darwin.close(directoryFD) }
        try checkDirectoryIdentity(directoryFD, token: intent.fileToken)
        let partial = name + ".partial"
        let fd = openat(directoryFD, partial, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw PhotoPreparationFailure.cleanupPending }
        defer { Darwin.close(fd) }
        // The file is private and is never registered with the legacy FileIO owner.
        var hash = SHA256()
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let length = min(64 * 1024, bytes.count - offset)
                guard let address = bytes.baseAddress?.advanced(by: offset) else { throw PhotoPreparationFailure.invalidMedia }
                var written = 0
                while written < length {
                    let amount = Darwin.write(fd, address.advanced(by: written), length - written)
                    if amount < 0 && errno == EINTR { continue }
                    guard amount > 0 else { throw PhotoPreparationFailure.storageLimit }
                    written += amount
                }
                hash.update(bufferPointer: UnsafeRawBufferPointer(start: address, count: length))
                offset += length
                #if DEBUG
                try sharedWriteFault?(offset)
                #endif
            }
        }
        guard fsync(fd) == 0 else { throw PhotoPreparationFailure.storageLimit }
        // Exclusive rename cannot replace an existing committed file.
        guard renameatx_np(directoryFD, partial, directoryFD, name, UInt32(RENAME_EXCL)) == 0,
              fsync(directoryFD) == 0, fsync(namespaceFD) == 0 else { throw PhotoPreparationFailure.cleanupPending }
        try checkDirectoryIdentity(directoryFD, token: intent.fileToken)
        return PhotoPreparationFile(assetID: intent.assetID, generation: intent.assetGeneration,
            token: intent.fileToken, byteCount: Int64(data.count),
            sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), contentType: contentType)
    }

    func verify(_ file: PhotoPreparationFile) throws { _ = try verifiedIdentity(file) }

    func verifiedIdentity(_ file: PhotoPreparationFile) throws -> String {
        let (directoryFD, name) = try directory(file.token, create: false)
        defer { Darwin.close(directoryFD) }
        let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw PhotoPreparationFailure.missingMedia }
        defer { Darwin.close(fd) }
        var before = stat(), after = stat(), named = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_nlink == 1, before.st_size == file.byteCount else { throw PhotoPreparationFailure.inconsistentOwnership }
        var hash = SHA256(), total: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw PhotoPreparationFailure.unavailable }
            if count == 0 { break }
            total = try PhotoPreparationPolicy.add([total, Int64(count)])
            guard total <= file.byteCount else { throw PhotoPreparationFailure.inconsistentOwnership }
            buffer.withUnsafeBytes { hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[..<count])) }
        }
        guard fstat(fd, &after) == 0,
              fstatat(directoryFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              before.st_dev == after.st_dev, before.st_ino == after.st_ino,
              before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              after.st_nlink == 1,
              named.st_ino == after.st_ino, named.st_dev == after.st_dev,
              total == file.byteCount,
              hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        try checkDirectoryIdentity(directoryFD, token: file.token)
        return "\(after.st_dev):\(after.st_ino):\(after.st_size):\(after.st_mtimespec.tv_sec):\(after.st_mtimespec.tv_nsec):\(after.st_ctimespec.tv_sec):\(after.st_ctimespec.tv_nsec)"
    }

    func sharedProof(_ file: PhotoPreparationFile) throws -> SharedMediaPhotoFileProof {
        guard let sharedBinding else { throw PhotoPreparationFailure.unsupportedComposition }
        return try SharedMediaPhotoFileProof(file: file, identity: verifiedIdentity(file), binding: sharedBinding.bytes)
    }

    /// The callback cannot escape. Its descriptors name only this retained
    /// destination under this already locked namespace; no second lock owner.
    func withInboxDestination<T>(_ handoff: SharedMediaInboxHandoff, create: Bool,
                                _ body: (SharedMediaInboxDestinationFiles) throws -> T) throws -> T {
        guard let sharedBinding else { throw PhotoPreparationFailure.unsupportedComposition }
        try handoff.request.validate()
        let token = handoff.request.intent(epoch: handoff.writerEpoch).fileToken
        let fd: Int32, name: String
        do { (fd, name) = try directory(token, create: create) }
        catch PhotoPreparationFailure.missingMedia {
            guard !create else { throw SharedMediaStorageFailure.conflict }
            fd = -1; name = handoff.request.assetID.uuidString.lowercased()
        }
        defer { if fd >= 0 { Darwin.close(fd) } }
        let access = SharedMediaInboxDestinationAccess(parent: fd, namespace: namespaceFD, name: name, check: {
            if fd >= 0 { try self.checkDirectoryIdentity(fd, token: token) }
            else {
                try self.checkIdentity()
                do { let (found, _) = try self.directory(token, create: false); Darwin.close(found) }
                catch PhotoPreparationFailure.missingMedia { return }
                throw SharedMediaStorageFailure.conflict
            }
        })
        defer { access.close() }
        return try body(SharedMediaInboxDestinationFiles(access: access, handoff: handoff, binding: sharedBinding))
    }

    private func directoryIdentity(_ fd: Int32) throws -> String {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw PhotoPreparationFailure.inconsistentOwnership }
        return "\(info.st_dev):\(info.st_ino)"
    }

    func inspectSharedRetirement(_ file: PhotoPreparationFile) throws -> SharedMediaPhotoRetirementInspection {
        guard let sharedBinding else { throw PhotoPreparationFailure.unsupportedComposition }
        let identity = try verifiedIdentity(file)
        let (fd, _) = try directory(file.token, create: false)
        defer { Darwin.close(fd) }
        try checkDirectoryIdentity(fd, token: file.token)
        return try .init(file: file, identity: .init(version: 1, file: identity,
            parent: directoryIdentity(fd), namespace: directoryIdentity(namespaceFD)),
            binding: sharedBinding.bytes, epoch: sharedBinding.epoch)
    }

    /// A saved exact retirement capability is mandatory even when the fixed
    /// object is already absent. This is not the legacy token-only unlink API.
    func releaseSharedPhoto(_ retirement: SharedMediaPhotoRetirement) throws -> SharedMediaPhotoReleaseProof {
        guard let sharedBinding, retirement.binding == sharedBinding.bytes,
              retirement.epoch == sharedBinding.epoch else { throw PhotoPreparationFailure.unsupportedComposition }
        try Task.checkCancellation()
        let file = retirement.file
        let (fd, name) = try directory(file.token, create: false)
        defer { Darwin.close(fd) }
        func checkDirectories() throws {
            try checkDirectoryIdentity(fd, token: file.token)
            guard try directoryIdentity(fd) == retirement.identity.parent,
                  try directoryIdentity(namespaceFD) == retirement.identity.namespace else { throw PhotoPreparationFailure.inconsistentOwnership }
        }
        try checkDirectories()
        var info = stat()
        let absent: Bool
        if fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw PhotoPreparationFailure.unavailable }
            absent = true
        } else {
            absent = false
            guard try verifiedIdentity(file) == retirement.identity.file else { throw PhotoPreparationFailure.inconsistentOwnership }
            try checkDirectories()
            try releaseBoundary(.beforeUnlink)
            guard try verifiedIdentity(file) == retirement.identity.file else { throw PhotoPreparationFailure.inconsistentOwnership }
            try checkDirectories()
            try Task.checkCancellation()
            guard unlinkat(fd, name, 0) == 0 else { throw PhotoPreparationFailure.cleanupPending }
            try releaseBoundary(.afterUnlink)
        }
        try releaseBoundary(.beforeSync)
        guard fsync(fd) == 0, fsync(namespaceFD) == 0 else { throw PhotoPreparationFailure.cleanupPending }
        try releaseBoundary(.afterSync)
        guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else { throw PhotoPreparationFailure.cleanupPending }
        try checkDirectories()
        if absent { return .reconciledAbsence(.init(retirement: retirement)) }
        return .unlinked(.init(retirement: retirement))
    }

    private func releaseBoundary(_ boundary: SharedMediaPhotoReleaseBoundary) throws {
        #if DEBUG
        try sharedReleaseFault?(boundary)
        #endif
    }

    /// Borrowed only while this lock is held. Verify again after decoding before
    /// accepting any output. No URL is stored in a handle or legacy file owner.
    func preparationURL(_ file: PhotoPreparationFile) throws -> URL {
        try verify(file)
        return rootURL.appendingPathComponent("PhotoPreparation", isDirectory: true).appendingPathComponent(file.token)
    }

    func read(_ file: PhotoPreparationFile) throws -> Data {
        try verify(file)
        let (directoryFD, name) = try directory(file.token, create: false)
        defer { Darwin.close(directoryFD) }
        let fd = openat(directoryFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw PhotoPreparationFailure.missingMedia }
        defer { Darwin.close(fd) }
        let data = try Self.boundedRead(fd: fd, maximumBytes: file.byteCount)
        guard data.count == file.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        try checkDirectoryIdentity(directoryFD, token: file.token)
        return data
    }

    static func boundedRead(fd: Int32, maximumBytes: Int64) throws -> Data {
        var info = stat()
        guard maximumBytes > 0, maximumBytes <= PhotoPreparationPolicy.original,
              fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size > 0, info.st_size <= maximumBytes else { throw PhotoPreparationFailure.sizeLimit }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            try Task.checkCancellation()
            let remaining = Int(maximumBytes) - data.count
            let count = Darwin.read(fd, &buffer, min(buffer.count, remaining + 1))
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw PhotoPreparationFailure.unavailable }
            if count == 0 { break }
            guard count <= remaining else { throw PhotoPreparationFailure.sizeLimit }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count == info.st_size else { throw PhotoPreparationFailure.inconsistentOwnership }
        return data
    }

    /// Empty directory remnants carry no media authority. Preserve every
    /// prefix still named by the ledger, including absent/pending originals.
    func pruneSharedEmptyDirectories(knownTokens: Set<String>) throws {
        guard sharedBinding != nil else { throw PhotoPreparationFailure.unsupportedComposition }
        try checkIdentity()
        for _ in 0..<4 {
            let complete = try inspection.pruneEmptyDirectories(namespaceFD: namespaceFD, knownTokens: knownTokens)
            try checkIdentity()
            if complete { return }
        }
        throw PhotoPreparationFailure.cleanupPending // Bounded progress; explicitly retry.
    }

    /// Inventory is bounded before trusting ledger counts. Unknown/symlinked
    /// entries block allocation and remain quarantined rather than being erased.
    func checkInventory(knownTokens: Set<String>) throws {
        try checkIdentity()
        var count = 0
        func walk(_ fd: Int32, prefix: String, depth: Int) throws {
            let copy = dup(fd)
            guard copy >= 0 else { throw PhotoPreparationFailure.unavailable }
            guard let stream = fdopendir(copy) else { Darwin.close(copy); throw PhotoPreparationFailure.unavailable }
            defer { closedir(stream) }
            // dup shares the directory offset with the held descriptor. Each
            // traversal must restart, including purge after inventory.
            rewinddir(stream)
            while let entry = try inspection.next(stage: .inventory, read: { readdir(stream) }) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                count += 1
                guard count <= 256 else { throw PhotoPreparationFailure.inconsistentOwnership }
                var info = stat()
                guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw PhotoPreparationFailure.unavailable }
                let token = prefix + name
                if depth < 2 {
                    guard let id = UUID(uuidString: name), id.uuidString.lowercased() == name,
                          info.st_mode & S_IFMT == S_IFDIR else { throw PhotoPreparationFailure.inconsistentOwnership }
                    let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                    guard child >= 0 else { throw PhotoPreparationFailure.inconsistentOwnership }
                    do { try walk(child, prefix: token + "/", depth: depth + 1) }
                    catch { Darwin.close(child); throw error }
                    Darwin.close(child)
                } else {
                    guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
                          knownTokens.contains(token), info.st_size >= 0,
                          info.st_size <= PhotoPreparationPolicy.original else { throw PhotoPreparationFailure.inconsistentOwnership }
                }
            }
        }
        try walk(namespaceFD, prefix: "", depth: 0)
    }

    func removeEmptyNamespace() throws {
        try checkIdentity()
        // Upgrade root protection before removing the lock namespace itself.
        guard flock(rootFD, LOCK_EX | LOCK_NB) == 0 else { throw PhotoPreparationFailure.busy }
        func removeChildren(_ fd: Int32, depth: Int) throws {
            let copy = dup(fd)
            guard copy >= 0 else { throw PhotoPreparationFailure.cleanupPending }
            guard let stream = fdopendir(copy) else { Darwin.close(copy); throw PhotoPreparationFailure.cleanupPending }
            defer { closedir(stream) }
            // dup shares the directory offset with the held descriptor. Each
            // traversal must restart, including purge after inventory.
            rewinddir(stream)
            var count = 0
            while let entry = try inspection.next(stage: .inventory, read: { readdir(stream) }) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                count += 1
                guard depth < 2, count <= 128, UUID(uuidString: name) != nil else { throw PhotoPreparationFailure.cleanupPending }
                let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard child >= 0 else { throw PhotoPreparationFailure.cleanupPending }
                do { try removeChildren(child, depth: depth + 1) }
                catch { Darwin.close(child); throw error }
                Darwin.close(child)
                guard unlinkat(fd, name, AT_REMOVEDIR) == 0 else { throw PhotoPreparationFailure.cleanupPending }
            }
            guard fsync(fd) == 0 else { throw PhotoPreparationFailure.cleanupPending }
        }
        try removeChildren(namespaceFD, depth: 0)
        guard unlinkat(rootFD, "PhotoPreparation", AT_REMOVEDIR) == 0, fsync(rootFD) == 0 else {
            throw PhotoPreparationFailure.cleanupPending
        }
    }

    /// Used only after a durable retirement decision under this same lock.
    func unlink(_ token: String) throws {
        let pair: (Int32, String)
        do { pair = try directory(token, create: false) }
        catch PhotoPreparationFailure.missingMedia { return }
        let (fd, name) = pair
        defer { Darwin.close(fd) }
        try checkDirectoryIdentity(fd, token: token)
        var info = stat()
        if fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw PhotoPreparationFailure.cleanupPending }
        } else {
            guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
                  unlinkat(fd, name, 0) == 0 else { throw PhotoPreparationFailure.cleanupPending }
        }
        guard fsync(fd) == 0 else { throw PhotoPreparationFailure.cleanupPending }
        if fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT {
            throw PhotoPreparationFailure.cleanupPending
        }
        try checkDirectoryIdentity(fd, token: token)
    }
}

/// Only the locked P1 namespace can construct this dynamic-scope capability.
struct SharedMediaInboxDestinationAccess {
    private let parent: Int32, namespace: Int32
    let name: String
    private let check: () throws -> Void
    private let lifetime = SharedMediaInboxDestinationScope()
    fileprivate init(parent: Int32, namespace: Int32, name: String, check: @escaping () throws -> Void) {
        self.parent = parent; self.namespace = namespace; self.name = name; self.check = check
    }
    func perform<T>(_ body: (Int32, Int32) throws -> T) throws -> T {
        guard lifetime.open else { throw SharedMediaStorageFailure.closed }
        try check(); let result = try body(parent, namespace); try check(); return result
    }
    fileprivate func close() { lifetime.open = false }
}

private final class SharedMediaInboxDestinationScope { var open = true }

struct SharedMediaPhotoFileProof: Sendable {
    let file: PhotoPreparationFile
    let identity: String
    let binding: Data
    fileprivate init(file: PhotoPreparationFile, identity: String, binding: Data) {
        self.file = file
        self.identity = identity
        self.binding = binding
    }
}

struct SharedMediaPhotoRetirementInspection: Sendable {
    let file: PhotoPreparationFile
    let identity: SharedMediaPhotoRetirementIdentity
    let binding: Data
    let epoch: UUID
    fileprivate init(file: PhotoPreparationFile, identity: SharedMediaPhotoRetirementIdentity, binding: Data, epoch: UUID) {
        self.file = file; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}

struct SharedMediaPhotoUnlinkProof: Sendable {
    let retirement: SharedMediaPhotoRetirement
    fileprivate init(retirement: SharedMediaPhotoRetirement) { self.retirement = retirement }
}

/// Proves current synchronized absence, not who performed the prior unlink.
struct SharedMediaPhotoAbsenceReconciliation: Sendable {
    let retirement: SharedMediaPhotoRetirement
    fileprivate init(retirement: SharedMediaPhotoRetirement) { self.retirement = retirement }
}

enum SharedMediaPhotoReleaseProof: Sendable {
    case unlinked(SharedMediaPhotoUnlinkProof)
    case reconciledAbsence(SharedMediaPhotoAbsenceReconciliation)
    var retirement: SharedMediaPhotoRetirement {
        switch self {
        case .unlinked(let proof): proof.retirement
        case .reconciledAbsence(let proof): proof.retirement
        }
    }
}

enum SharedMediaPhotoReleaseBoundary: Sendable { case beforeUnlink, afterUnlink, beforeSync, afterSync }
