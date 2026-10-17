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
