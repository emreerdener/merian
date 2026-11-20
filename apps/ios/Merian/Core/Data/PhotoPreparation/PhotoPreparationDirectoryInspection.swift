import Darwin
import Foundation

enum PhotoPreparationInspectionStage: Sendable { case initialEmpty, inventory }

/// POSIX EOF is distinct from enumeration failure. Error injection exists only
/// in Debug and follows the same errno branch as a real filesystem failure.
struct PhotoPreparationDirectoryInspection: Sendable {
    #if DEBUG
    private var failure: PhotoPreparationInspectionStage?
    init(failing stage: PhotoPreparationInspectionStage) { failure = stage }
    #endif
    init() {}

    func next(stage: PhotoPreparationInspectionStage, read: () -> UnsafeMutablePointer<dirent>?) throws -> UnsafeMutablePointer<dirent>? {
        errno = 0
        let entry: UnsafeMutablePointer<dirent>?
        #if DEBUG
        if failure == stage { errno = EIO; entry = nil } else { entry = read() }
        #else
        entry = read()
        #endif
        guard entry != nil || errno == 0 else { throw PhotoPreparationFailure.unavailable }
        return entry
    }
}

extension PhotoPreparationDirectoryInspection {
    /// Called only while the file owner holds the namespace and exclusive root lock.
    /// Removes empty UUID descendants; the owner alone removes the namespace.
    func removeEmptyChildren(namespaceFD: Int32) throws {
        func removeChildren(_ fd: Int32, depth: Int) throws {
            let copy = dup(fd)
            guard copy >= 0 else { throw PhotoPreparationFailure.cleanupPending }
            guard let stream = fdopendir(copy) else { Darwin.close(copy); throw PhotoPreparationFailure.cleanupPending }
            defer { closedir(stream) }
            // dup shares the directory offset with the held descriptor. Each
            // traversal must restart, including purge after inventory.
            rewinddir(stream)
            var count = 0
            while let entry = try next(stage: .inventory, read: { readdir(stream) }) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                count += 1
                guard depth < 2, count <= 128, UUID(uuidString: name) != nil else { throw PhotoPreparationFailure.cleanupPending }
                let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard child >= 0 else { throw PhotoPreparationFailure.cleanupPending }
                do { try removeChildren(child, depth: depth + 1) } catch { Darwin.close(child); throw error }
                Darwin.close(child)
                guard unlinkat(fd, name, AT_REMOVEDIR) == 0 else { throw PhotoPreparationFailure.cleanupPending }
            }
            guard fsync(fd) == 0 else { throw PhotoPreparationFailure.cleanupPending }
        }
        try removeChildren(namespaceFD, depth: 0)
    }

    /// Root ownership is closed: extra entries are not adopted or collected.
    func requireNamespaceRoot(rootFD: Int32) throws {
        let fd = openat(rootFD, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw PhotoPreparationFailure.unavailable }
        guard let stream = fdopendir(fd) else { Darwin.close(fd); throw PhotoPreparationFailure.unavailable }
        defer { closedir(stream) }
        var found = false
        while let entry = try next(stage: .inventory, read: { readdir(stream) }) {
            try Task.checkCancellation()
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard name == "PhotoPreparation", !found else { throw PhotoPreparationFailure.inconsistentOwnership }
            found = true
        }
        guard found else { throw PhotoPreparationFailure.inconsistentOwnership }
    }

    /// Descriptor-only seal of a prior hash proof. Replacement or in-place edits
    /// change the full inode/size/mtime/ctime tuple; no proof is minted here.
    func requireCurrentFile(parentFD: Int32, namespaceFD: Int32, name: String,
                            proof: SharedMediaPhotoRetirementInspection, revalidate: () throws -> Void) throws {
        try Task.checkCancellation(); try revalidate()
        let fd = openat(parentFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw PhotoPreparationFailure.missingMedia }
        defer { Darwin.close(fd) }
        var held = stat(), named = stat(), parent = stat(), namespace = stat()
        func identity(_ value: stat) -> String {
            "\(value.st_dev):\(value.st_ino):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
        }
        guard fstat(fd, &held) == 0, fstatat(parentFD, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(parentFD, &parent) == 0, fstat(namespaceFD, &namespace) == 0,
              held.st_mode & S_IFMT == S_IFREG, named.st_mode & S_IFMT == S_IFREG,
              held.st_nlink == 1, named.st_nlink == 1, held.st_size == proof.file.byteCount,
              identity(held) == proof.identity.file, identity(named) == proof.identity.file,
              parent.st_mode & S_IFMT == S_IFDIR, namespace.st_mode & S_IFMT == S_IFDIR,
              "\(parent.st_dev):\(parent.st_ino)" == proof.identity.parent,
              "\(namespace.st_dev):\(namespace.st_ino)" == proof.identity.namespace else { throw PhotoPreparationFailure.inconsistentOwnership }
        try revalidate()
    }

    /// Read-only absence observation; never unlinks or issues release authority.
    /// The enclosing owner supplies held descriptors and revalidates their path.
    func requireNativeAbsence(parentFD: Int32, namespaceFD: Int32, name: String,
                              proof: SharedMediaPhotoRetirementIdentity, revalidate: () throws -> Void) throws {
        func directories() throws {
            try revalidate()
            var parent = stat(), namespace = stat()
            guard fstat(parentFD, &parent) == 0, fstat(namespaceFD, &namespace) == 0,
                  parent.st_mode & S_IFMT == S_IFDIR, namespace.st_mode & S_IFMT == S_IFDIR,
                  proof.parent == "\(parent.st_dev):\(parent.st_ino)",
                  proof.namespace == "\(namespace.st_dev):\(namespace.st_ino)" else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
        }
        func absent() throws {
            for leaf in [name, name + ".partial"] {
                var info = stat()
                guard fstatat(parentFD, leaf, &info, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                    throw PhotoPreparationFailure.inconsistentOwnership
                }
            }
        }
        try Task.checkCancellation(); try directories(); try absent()
        guard fsync(parentFD) == 0, fsync(namespaceFD) == 0 else { throw PhotoPreparationFailure.unavailable }
        try Task.checkCancellation(); try directories(); try absent()
    }

    /// Bounded directory enumeration; the file owner retains its identity fence.
    func checkInventory(namespaceFD: Int32, knownTokens: Set<String>) throws {
        var count = 0
        func walk(_ fd: Int32, prefix: String, depth: Int) throws {
            let copy = dup(fd)
            guard copy >= 0 else { throw PhotoPreparationFailure.unavailable }
            guard let stream = fdopendir(copy) else { Darwin.close(copy); throw PhotoPreparationFailure.unavailable }
            defer { closedir(stream) }
            // dup shares the directory offset with the held descriptor. Each
            // traversal must restart, including purge after inventory.
            rewinddir(stream)
            while let entry = try next(stage: .inventory, read: { readdir(stream) }) {
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
                    do { try walk(child, prefix: token + "/", depth: depth + 1) } catch { Darwin.close(child); throw error }
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

    /// Exact terminal emptiness without removing the bound namespace.
    func requireEmpty(namespaceFD: Int32) throws {
        let copy = dup(namespaceFD)
        guard copy >= 0 else { throw PhotoPreparationFailure.unavailable }
        guard let stream = fdopendir(copy) else { Darwin.close(copy); throw PhotoPreparationFailure.unavailable }
        defer { closedir(stream) }
        rewinddir(stream)
        while let entry = try next(stage: .inventory, read: { readdir(stream) }) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            guard name == "." || name == ".." else { throw PhotoPreparationFailure.cleanupPending }
        }
    }

    /// One bounded pass precedes the steady-state 256-entry inventory gate.
    /// No files, held prefixes, namespace or root can be removed by this path.
    func pruneEmptyDirectories(namespaceFD: Int32, knownTokens: Set<String>) throws -> Bool {
        var visited = 0
        func entries(_ fd: Int32, body: (String) throws -> Bool) throws -> Bool {
            let copy = dup(fd)
            guard copy >= 0 else { throw PhotoPreparationFailure.unavailable }
            guard let stream = fdopendir(copy) else { Darwin.close(copy); throw PhotoPreparationFailure.unavailable }
            defer { closedir(stream) }
            rewinddir(stream)
            while let entry = try next(stage: .inventory, read: { readdir(stream) }) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name != "." && name != "..", try !body(name) { return false }
            }
            return true
        }
        func empty(_ fd: Int32) throws -> Bool { try entries(fd) { _ in false } }
        func walk(_ fd: Int32, prefix: String, depth: Int) throws -> Bool {
            try entries(fd) { name in
                guard visited < 128 else { return false }
                visited += 1
                guard let id = UUID(uuidString: name), id.uuidString.lowercased() == name else { throw PhotoPreparationFailure.inconsistentOwnership }
                let token = prefix + name + "/"
                let held = knownTokens.contains { $0.hasPrefix(token) }
                let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard child >= 0 else { throw PhotoPreparationFailure.inconsistentOwnership }
                defer { Darwin.close(child) }
                if depth == 0 {
                    guard try walk(child, prefix: token, depth: 1) else { return false }
                } else if held { return true }
                let isEmpty = try empty(child)
                guard depth == 0 || isEmpty else { throw PhotoPreparationFailure.inconsistentOwnership }
                if isEmpty && !held {
                    var opened = stat(), named = stat()
                    guard fstat(child, &opened) == 0, fstatat(fd, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                          named.st_mode & S_IFMT == S_IFDIR, opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
                          unlinkat(fd, name, AT_REMOVEDIR) == 0, fsync(fd) == 0, fsync(namespaceFD) == 0 else {
                        throw PhotoPreparationFailure.cleanupPending
                    }
                }
                return true
            }
        }
        return try walk(namespaceFD, prefix: "", depth: 0)
    }
}

/// A momentary structural observation, not a media proof or retained capability.
struct PhotoPreparationNativeLeaf: Equatable, Sendable {
    let token: String
    let byteCount: Int64
    let descriptor: String
}

extension PhotoPreparationDirectoryInspection {
    private struct NativeAncestor {
        let fd: Int32
        let parent: Int32
        let name: String
        let identity: stat
    }

    /// Fixed-depth streaming traversal. No retained-library set or count cap.
    /// The observer receives values only, with backpressure across actor hops.
    /// Ancestor/leaf descriptors stay open across suspension and are checked on
    /// return. Cancellation cannot detach the observer or close its held files.
    /// The observer must not commit authority before the entire audit succeeds.
    func visitNative(namespaceFD: Int32, revalidate: @Sendable () throws -> Void,
                     observe: @Sendable (PhotoPreparationNativeLeaf) async throws -> Void) async throws {
        func same(_ a: stat, _ b: stat) -> Bool {
            a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode
                && a.st_nlink == b.st_nlink && a.st_size == b.st_size
                && a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec
                && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
                && a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec
                && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
        }
        func check(_ fd: Int32, initial: stat, parent: Int32, name: String) throws {
            var held = stat(), named = stat()
            guard fstat(fd, &held) == 0, fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
                  same(initial, held), same(held, named) else { throw PhotoPreparationFailure.inconsistentOwnership }
        }
        func checkAncestors(_ ancestors: [NativeAncestor]) throws {
            for entry in ancestors { try check(entry.fd, initial: entry.identity, parent: entry.parent, name: entry.name) }
        }
        func noSibling(_ parent: Int32, name: String) throws {
            let sibling = name.hasSuffix(".partial") ? String(name.dropLast(8)) : name + ".partial"
            var info = stat()
            guard fstatat(parent, sibling, &info, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
        }
        func leaf(_ parent: Int32, name: String, token: String, named: stat, ancestors: [NativeAncestor]) async throws {
            let base = name.hasSuffix(".partial") ? String(name.dropLast(8)) : name
            guard let id = UUID(uuidString: base), id.uuidString.lowercased() == base,
                  named.st_mode & S_IFMT == S_IFREG, named.st_nlink == 1,
                  named.st_size >= 0, named.st_size > 0 || name.hasSuffix(".partial"),
                  named.st_size <= PhotoPreparationPolicy.original else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
            let fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw PhotoPreparationFailure.unavailable }
            defer { Darwin.close(fd) }
            try check(fd, initial: named, parent: parent, name: name)
            try noSibling(parent, name: name)
            try Task.checkCancellation(); try revalidate(); try checkAncestors(ancestors)
            let identity = "\(named.st_dev):\(named.st_ino):\(named.st_size):\(named.st_mtimespec.tv_sec):\(named.st_mtimespec.tv_nsec):\(named.st_ctimespec.tv_sec):\(named.st_ctimespec.tv_nsec)"
            try await observe(.init(token: token, byteCount: named.st_size, descriptor: identity))
            try Task.checkCancellation(); try revalidate(); try checkAncestors(ancestors)
            try check(fd, initial: named, parent: parent, name: name)
            try noSibling(parent, name: name)
        }
        func walk(_ fd: Int32, prefix: String, depth: Int, ancestors: [NativeAncestor]) async throws {
            try Task.checkCancellation(); try revalidate()
            var before = stat()
            guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFDIR else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
            // openat gives this traversal its own offset; dup would share it.
            let enumeration = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard enumeration >= 0 else { throw PhotoPreparationFailure.unavailable }
            guard let stream = fdopendir(enumeration) else { Darwin.close(enumeration); throw PhotoPreparationFailure.unavailable }
            defer { closedir(stream) }
            try check(enumeration, initial: before, parent: fd, name: ".")
            while let entry = try next(stage: .inventory, read: { readdir(stream) }) {
                try Task.checkCancellation()
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                var named = stat()
                guard fstatat(fd, name, &named, AT_SYMLINK_NOFOLLOW) == 0 else { throw PhotoPreparationFailure.unavailable }
                let token = prefix + name
                if depth < 2 {
                    guard let id = UUID(uuidString: name), id.uuidString.lowercased() == name,
                          named.st_mode & S_IFMT == S_IFDIR else { throw PhotoPreparationFailure.inconsistentOwnership }
                    let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { throw PhotoPreparationFailure.unavailable }
                    defer { Darwin.close(child) }
                    try check(child, initial: named, parent: fd, name: name)
                    try await walk(child, prefix: token + "/", depth: depth + 1,
                        ancestors: ancestors + [.init(fd: child, parent: fd, name: name, identity: named)])
                    try check(child, initial: named, parent: fd, name: name)
                    try revalidate()
                } else { try await leaf(fd, name: name, token: token, named: named, ancestors: ancestors) }
            }
            try check(enumeration, initial: before, parent: fd, name: ".")
            try Task.checkCancellation(); try revalidate()
        }
        try await walk(namespaceFD, prefix: "", depth: 0, ancestors: [])
    }
}
