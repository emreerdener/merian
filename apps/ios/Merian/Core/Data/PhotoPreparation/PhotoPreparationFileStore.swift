import CryptoKit
import Darwin
import Foundation
import ImageIO

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
    private var rootFD: Int32 = -1
    private var namespaceFD: Int32 = -1

    init(root: URL) throws {
        rootURL = root
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
            guard flock(rootFD, LOCK_SH | LOCK_NB) == 0 else { throw PhotoPreparationFailure.busy }
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

    func close() {
        if namespaceFD >= 0 { Darwin.close(namespaceFD); namespaceFD = -1 }
        if rootFD >= 0 { Darwin.close(rootFD); rootFD = -1 }
    }

    func checkIdentity() throws {
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

    static func validateImage(_ data: Data, maximumBytes: Int64) throws -> String {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source) as String?,
              (CGImageSourceCopyTypeIdentifiers() as? [String] ?? []).contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.int64Value > 0, height.int64Value > 0 else { throw PhotoPreparationFailure.invalidMedia }
        let (pixels, overflow) = width.int64Value.multipliedReportingOverflow(by: height.int64Value)
        guard !overflow, pixels <= PhotoPreparationPolicy.maximumPixels else { throw PhotoPreparationFailure.sizeLimit }
        return type
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

    func verify(_ file: PhotoPreparationFile) throws {
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
              named.st_ino == after.st_ino, named.st_dev == after.st_dev,
              total == file.byteCount,
              hash.finalize().map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        try checkDirectoryIdentity(directoryFD, token: file.token)
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
            while let entry = readdir(stream) {
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
            while let entry = readdir(stream) {
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
