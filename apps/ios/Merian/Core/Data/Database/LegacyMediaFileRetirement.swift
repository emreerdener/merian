import Darwin
import Foundation

/// A synchronous, descriptor-scoped capability for one trusted flat legacy root.
/// It cannot name descendants. Immutable descriptors may be held by an owner across suspension.
final class LegacyMediaDirectory: Sendable {
    let url: URL
    let fd: Int32

    init?(_ url: URL) {
        self.url = url
        let descriptor = Self.openDirectory(url)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_SH | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            return nil
        }
        fd = descriptor
    }

    deinit { if fd >= 0 { Darwin.close(fd) } }

    func isCurrent() -> Bool {
        let current = Self.openDirectory(url)
        guard current >= 0 else { return false }
        defer { Darwin.close(current) }
        var held = stat(), named = stat()
        return fstat(fd, &held) == 0 && fstat(current, &named) == 0
            && held.st_dev == named.st_dev && held.st_ino == named.st_ino
    }

    private static func openDirectory(_ url: URL) -> Int32 {
        var current = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard current >= 0 else { return -1 }
        for part in url.pathComponents.dropFirst() {
            let next = openat(current, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            Darwin.close(current)
            guard next >= 0 else { return -1 }
            current = next
        }
        return current
    }

    func matches(_ name: String, descriptor: Int32, snapshot: stat? = nil) -> Bool {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return false }
        let current = Self.openDirectory(url)
        guard current >= 0 else { return false }
        defer { Darwin.close(current) }
        var heldRoot = stat(), namedRoot = stat(), held = stat(), named = stat()
        let identityMatches = fstat(fd, &heldRoot) == 0 && fstat(current, &namedRoot) == 0
            && heldRoot.st_dev == namedRoot.st_dev && heldRoot.st_ino == namedRoot.st_ino
            && fstat(descriptor, &held) == 0 && fstatat(fd, name, &named, AT_SYMLINK_NOFOLLOW) == 0
            && held.st_mode & S_IFMT == S_IFREG && named.st_mode & S_IFMT == S_IFREG
            && held.st_nlink == 1 && named.st_nlink == 1
            && held.st_dev == named.st_dev && held.st_ino == named.st_ino
        guard identityMatches else { return false }
        guard let snapshot else { return true }
        return held.st_size == snapshot.st_size
            && held.st_mtimespec.tv_sec == snapshot.st_mtimespec.tv_sec
            && held.st_mtimespec.tv_nsec == snapshot.st_mtimespec.tv_nsec
            && held.st_ctimespec.tv_sec == snapshot.st_ctimespec.tv_sec
            && held.st_ctimespec.tv_nsec == snapshot.st_ctimespec.tv_nsec
    }

    func remove(_ name: String, matching descriptor: Int32, snapshot: stat? = nil,
                synchronize: (Int32) -> Int32 = { fsync($0) }) -> Bool {
        guard matches(name, descriptor: descriptor, snapshot: snapshot), unlinkat(fd, name, 0) == 0 else { return false }
        return synchronize(fd) == 0
    }
}

/// Deletion-only identity for one disposable flat file. A missing original is
/// idempotent, but a replacement file or root never inherits this permission.
struct LegacyMediaFileRetirement: Sendable {
    private let root: URL
    private let name: String
    private let rootDevice: dev_t, rootInode: ino_t
    private let file: Identity

    /// Synchronous producer handoff before any reader-drain suspension. Only a
    /// flat file in the trusted temporary root can receive this permission.
    static func temporaryFile(at url: URL) -> Self? {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        guard url.isFileURL, !url.pathComponents.contains(".."),
              parent == root.path || parent == root.path.replacingOccurrences(of: "/private/var/", with: "/var/", options: .anchored),
              let directory = LegacyMediaDirectory(root) else { return nil }
        let name = url.lastPathComponent
        let fd = openat(directory.fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1 else { return nil }
        return Self(directory: directory, name: name, descriptor: fd)
    }

    /// Bounded exact-identity read for a producer recovery handoff. The file
    /// cannot be adopted merely because another file occupies the same name.
    func read(maximumBytes: Int) -> Data? {
        guard maximumBytes > 0, file.size > 0, file.size <= maximumBytes,
              let directory = LegacyMediaDirectory(root) else { return nil }
        var parent = stat()
        guard fstat(directory.fd, &parent) == 0, parent.st_dev == rootDevice,
              parent.st_ino == rootInode, directory.isCurrent() else { return nil }
        let fd = openat(directory.fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        var before = stat(), after = stat()
        guard fstat(fd, &before) == 0, Identity(before) == file,
              before.st_mode & S_IFMT == S_IFREG, before.st_nlink == 1 else { return nil }
        var data = Data(count: Int(before.st_size)), offset = 0
        while offset < data.count {
            let count = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { return nil }
            offset += count
        }
        guard fstat(fd, &after) == 0, Identity(after) == file,
              directory.matches(name, descriptor: fd, snapshot: before) else { return nil }
        return data
    }

    /// Used by synchronous producer-lease finalization; the receipt still
    /// rechecks both root and file identity and synchronizes the unlink.
    func retire() -> Bool { remove(synchronize: { fsync($0) }) }

    init?(directory: LegacyMediaDirectory, name: String, descriptor: Int32) {
        var parent = stat(), info = stat()
        guard directory.matches(name, descriptor: descriptor),
              fstat(directory.fd, &parent) == 0, fstat(descriptor, &info) == 0 else { return nil }
        root = directory.url; self.name = name
        rootDevice = parent.st_dev; rootInode = parent.st_ino; file = Identity(info)
    }

    func remove(synchronize: (Int32) -> Int32) -> Bool {
        guard let directory = LegacyMediaDirectory(root) else { return false }
        func isAbsent() -> Bool {
            var value = stat()
            let absent = fstatat(directory.fd, name, &value, AT_SYMLINK_NOFOLLOW) != 0 && errno == ENOENT
            return absent && directory.isCurrent()
        }
        var parent = stat(), named = stat()
        guard fstat(directory.fd, &parent) == 0, parent.st_dev == rootDevice,
              parent.st_ino == rootInode, directory.isCurrent() else { return false }
        if fstatat(directory.fd, name, &named, AT_SYMLINK_NOFOLLOW) != 0 {
            // A failed directory sync after a prior unlink must be retryable.
            return errno == ENOENT && synchronize(directory.fd) == 0 && isAbsent()
        }
        guard named.st_mode & S_IFMT == S_IFREG, named.st_nlink == 1,
              Identity(named) == file else { return false }
        let descriptor = openat(directory.fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        var held = stat()
        guard fstat(descriptor, &held) == 0, Identity(held) == file else { return false }
        return directory.remove(name, matching: descriptor, snapshot: held, synchronize: synchronize)
            && isAbsent()
    }

    private struct Identity: Equatable, Sendable {
        let device: dev_t, inode: ino_t, size: off_t
        let modifiedSeconds: time_t, changedSeconds: time_t
        let modifiedNanos: Int, changedNanos: Int
        init(_ value: stat) {
            device = value.st_dev; inode = value.st_ino; size = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec; modifiedNanos = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec; changedNanos = value.st_ctimespec.tv_nsec
        }
    }
}
