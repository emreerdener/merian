import Darwin
import Foundation

/// Legacy operations hold shared locks on every traversed directory. A source
/// owner cannot bind an ancestor while a legacy operation creates descendants.
final class SharedMediaInboxLegacyFence {
    private let descriptors: [Int32]

    init(root: URL, createIfMissing: Bool) throws {
        guard root.isFileURL, root.path.hasPrefix("/") else { throw SharedMediaStorageFailure.invalid }
        var held: [Int32] = []
        do {
            var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
            held.append(fd)
            try Self.lockUnbound(fd)
            for component in root.standardizedFileURL.pathComponents.dropFirst() {
                var next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                let openError = errno
                if next < 0, openError == ENOENT, createIfMissing {
                    // The parent is already locked and checked through its own
                    // descriptor. Never create through an unvalidated path.
                    try Self.requireUnbound(fd)
                    guard mkdirat(fd, component, 0o700) == 0 || errno == EEXIST else {
                        throw SharedMediaStorageFailure.unavailable
                    }
                    next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw SharedMediaStorageFailure.unavailable }
                held.append(next)
                try Self.lockUnbound(next)
                fd = next
            }
        } catch {
            for fd in held.reversed() { Darwin.close(fd) }
            throw error
        }
        descriptors = held
    }

    deinit { for fd in descriptors.reversed() { Darwin.close(fd) } }

    private static func lockUnbound(_ fd: Int32) throws {
        guard flock(fd, LOCK_SH | LOCK_NB) == 0 else { throw SharedMediaStorageFailure.busy }
        try requireUnbound(fd)
    }

    private static func requireUnbound(_ fd: Int32) throws {
        let size = fgetxattr(fd, SharedMediaInboxFiles.marker, nil, 0, 0, 0)
        let attributeError = errno
        guard size < 0 && attributeError == ENOATTR else { throw SharedMediaStorageFailure.conflict }
    }
}
