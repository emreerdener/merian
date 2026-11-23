import Darwin
import Foundation

/// Read-only, fixed-depth physical inventory under the cleanup owner's locked
/// namespace. Entries are descriptive; the caller must prove their ledger joins
/// before accepting the complete manifest. Empty ancestor directories matter.
@MainActor
enum SharedMediaNativeErasurePhotoWalk {
    typealias Entry = SharedMediaNativeErasureManifest.Entry

    static func visit(namespace: Int32, ownerID: UUID, checkpoint: () throws -> Void,
                      observe: (Entry) throws -> Void) async throws {
        try Task.checkCancellation(); try checkpoint()
        let initial = try status(namespace)
        try await visitDirectory(namespace, components: ["PhotoPreparation"], ownerID: ownerID,
            checkpoint: checkpoint, observe: observe)
        guard same(initial, try status(namespace)) else { throw SharedMediaStorageFailure.stale }
        try checkpoint()
    }

    private static func visitDirectory(_ descriptor: Int32, components: [String], ownerID: UUID,
                                       checkpoint: () throws -> Void, observe: (Entry) throws -> Void) async throws {
        // A separate open description avoids sharing readdir offsets with the
        // retained owner's own checks or a repeated manifest reconstruction.
        let scan = openat(descriptor, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard scan >= 0 else { throw SharedMediaStorageFailure.unavailable }
        guard let directory = fdopendir(scan) else { Darwin.close(scan); throw SharedMediaStorageFailure.unavailable }
        defer { closedir(directory) }
        var visited = 0
        while true {
            try Task.checkCancellation(); try checkpoint()
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw SharedMediaStorageFailure.unavailable }; break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            let path = components + [name]
            var named = stat()
            guard fstatat(descriptor, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else { throw SharedMediaStorageFailure.stale }
            if components.count < 3 {
                guard named.st_mode & S_IFMT == S_IFDIR,
                      UUID(uuidString: name)?.uuidString.lowercased() == name,
                      components.count != 1 || name == ownerID.uuidString.lowercased() else { throw SharedMediaStorageFailure.conflict }
                let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard child >= 0 else { throw SharedMediaStorageFailure.conflict }
                do {
                    guard flock(child, LOCK_EX | LOCK_NB) == 0 else { throw SharedMediaStorageFailure.busy }
                    try require(child, parent: descriptor, name: name, expected: named)
                    let value = Entry(namespace: .photo, token: path.joined(separator: "/"), kind: .directory,
                        identity: "\(named.st_dev):\(named.st_ino)")
                    try value.validate(ownerID: ownerID); try observe(value)
                    try await visitDirectory(child, components: path, ownerID: ownerID, checkpoint: checkpoint, observe: observe)
                    try require(child, parent: descriptor, name: name, expected: named)
                    Darwin.close(child)
                } catch { Darwin.close(child); throw error }
            } else {
                guard components.count == 3, named.st_mode & S_IFMT == S_IFREG,
                      named.st_nlink == 1, named.st_size >= 0 else { throw SharedMediaStorageFailure.conflict }
                let value = Entry(namespace: .photo, token: path.joined(separator: "/"), kind: .file,
                    identity: "\(named.st_dev):\(named.st_ino):\(named.st_size):\(named.st_mtimespec.tv_sec):\(named.st_mtimespec.tv_nsec):\(named.st_ctimespec.tv_sec):\(named.st_ctimespec.tv_nsec)")
                try value.validate(ownerID: ownerID)
                let file = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
                guard file >= 0 else { throw SharedMediaStorageFailure.conflict }
                defer { Darwin.close(file) }
                try require(file, parent: descriptor, name: name, expected: named)
                try observe(value)
                try require(file, parent: descriptor, name: name, expected: named)
            }
            visited += 1
            if visited == SharedMediaNativeErasureManifest.pageSize {
                visited = 0; await Task.yield(); try checkpoint()
            }
        }
    }

    private static func status(_ descriptor: Int32) throws -> stat {
        var result = stat()
        guard fstat(descriptor, &result) == 0 else { throw SharedMediaStorageFailure.unavailable }
        return result
    }
    private static func require(_ descriptor: Int32, parent: Int32, name: String, expected: stat) throws {
        var named = stat()
        guard fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              same(expected, named), same(expected, try status(descriptor)) else { throw SharedMediaStorageFailure.stale }
    }
    private static func same(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode && a.st_nlink == b.st_nlink
            && a.st_size == b.st_size && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec
            && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec
            && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
}
