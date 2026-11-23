import Darwin
import Foundation
import SwiftData

/// Descriptor-only replay of a complete immutable erasure manifest. The outer
/// owner retains the accepted account operation and exclusive store fence.
/// This owner cannot discover targets, mint a manifest, or reopen admission.
@MainActor
final class SharedMediaNativeErasureTree {
    typealias Manifest = SharedMediaNativeErasureManifest
    typealias Header = SharedMediaNativeErasureHeader
    typealias Pages = (_ removing: Bool, _ body: (Data) throws -> Void) throws -> Void
    enum Boundary { case beforeUnlink, afterUnlink, afterParentSync }
    enum TerminalBoundary { case beforeWrite, afterWrite, afterSync, beforeReadback }

    private let parent: URL
    private let descriptor: Int32
    private let profile: SharedMediaNativeAppProfile
    private let header: Header
    private let checkpoint: () throws -> Void
    private let pages: Pages

    init(parent: URL, held: SharedMediaNativeLockedRoot, profile: SharedMediaNativeAppProfile,
         header: Header, checkpoint: @escaping () throws -> Void, pages: @escaping Pages) throws {
        _ = try header.encoded(profile: profile)
        let transfer = try held.consume(at: parent)
        guard transfer.child < 0 else {
            Darwin.close(transfer.root); Darwin.close(transfer.child)
            throw SharedMediaStorageFailure.conflict
        }
        self.parent = parent; descriptor = transfer.root; self.profile = profile
        self.header = header; self.checkpoint = checkpoint; self.pages = pages
        try check()
    }

    deinit { Darwin.close(descriptor) }

    /// Before the first unlink, every present manifest target must match and
    /// the entire physical tree must contain exactly those entries. Unique
    /// canonical paths plus equal cardinality prove there are no extra leaves.
    func verify() throws {
        try check()
        var expected: Int64 = 0
        try visit { entry in
            if try inspect(entry, remove: false, boundary: { _ in }) {
                expected = try SharedMediaStoragePolicy.add(expected, 1)
            }
        }
        guard try countTree() == expected else { throw SharedMediaStorageFailure.conflict }
        try check()
    }

    /// Only the saved manifest supplies targets. Each pass is bounded by one
    /// page and a directory stack of at most four components. Missing targets
    /// are replayable; replacements and unlisted entries always stop recovery.
    func retire(boundary: (Boundary) throws -> Void = { _ in }) throws -> SharedMediaNativeErasureAbsence {
        try verify()
        try visit(removing: true) { entry in
            if entry.kind == .file && entry.namespace != .control {
                _ = try inspect(entry, remove: true, boundary: boundary)
            }
        }
        // Files first, deepest directories next, fixed control records last.
        for depth in stride(from: 4, through: 1, by: -1) {
            try visit(removing: true) { entry in
                if entry.kind == .directory && components(entry).count == depth {
                    _ = try inspect(entry, remove: true, boundary: boundary)
                }
            }
        }
        try visit(removing: true) { entry in
            if entry.kind == .file && entry.namespace == .control {
                _ = try inspect(entry, remove: true, boundary: boundary)
            }
        }
        return try absence()
    }

    func absence() throws -> SharedMediaNativeErasureAbsence {
        try requireAbsent()
        return SharedMediaNativeErasureAbsence(header: header, profile: profile) { [self] in try requireAbsent() }
    }

    /// The receipt outlives the same-store journal. It is written only after
    /// source deletion commits, while the exact parent and outer fences remain
    /// held. It never authorizes bootstrap, media access or a different purge.
    func persistTerminal(container: ModelContainer,
                         boundary: (TerminalBoundary) throws -> Void = { _ in }) throws -> SharedMediaNativeErasureTerminal {
        func requireCleared() throws {
            let saved = try SharedMediaNativeErasureJournal.read(container: container, profile: profile,
                operationID: header.operationID, checkpoint: checkpoint)
            guard saved.header == header, saved.state.stage == .cleared, saved.hasCompleteManifest else {
                throw SharedMediaStorageFailure.conflict
            }
            try requireAbsent()
        }
        try requireCleared()
        let receipt = SharedMediaNativeErasureTerminalReceipt(version: 1, profile: profile, header: header)
        let bytes = try receipt.encoded(), old = try readTerminal()
        if let old, old != bytes {
            let previous = try SharedMediaNativeErasureTerminalReceipt.decode(old)
            guard previous.header.operationID != header.operationID,
                  previous.profile.storeIdentity == profile.storeIdentity,
                  previous.header.storeFileIdentity == header.storeFileIdentity,
                  previous.header.storeParentIdentity == header.storeParentIdentity,
                  previous.header.controlParentIdentity == header.controlParentIdentity,
                  previous.header.parentReceiptSHA256 == header.parentReceiptSHA256 else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        if old != bytes {
            try boundary(.beforeWrite); try requireCleared()
            guard try readTerminal() == old else { throw SharedMediaStorageFailure.stale }
            let options = old == nil ? XATTR_CREATE : XATTR_REPLACE
            guard bytes.withUnsafeBytes({ fsetxattr(descriptor, SharedMediaNativeErasureTerminalReceipt.marker,
                $0.baseAddress, $0.count, 0, options) }) == 0 else { throw SharedMediaStorageFailure.unavailable }
            try boundary(.afterWrite)
        }
        guard fsync(descriptor) == 0 else { throw SharedMediaStorageFailure.unavailable }
        try boundary(.afterSync); try boundary(.beforeReadback)
        try requireTerminal(bytes); try requireCleared()
        return SharedMediaNativeErasureTerminal(header: header, profile: profile) { [self] in
            try requireTerminal(bytes)
        }
    }

    /// Component recovery after the carrier transaction. The outer cleanup
    /// owner must supply the receipt expected by its accepted operation and
    /// independently validate the store in checkpoint. No journal is rebuilt.
    static func recoverTerminal(container: ModelContainer, parent: URL, held: SharedMediaNativeLockedRoot,
                                expected: SharedMediaNativeErasureTerminalReceipt,
                                checkpoint: @escaping () throws -> Void) throws -> SharedMediaNativeErasureTerminal {
        let bytes = try expected.encoded()
        let tree = try Self(parent: parent, held: held, profile: expected.profile, header: expected.header,
            checkpoint: checkpoint, pages: { _, _ in throw SharedMediaStorageFailure.closed })
        try SharedMediaNativeErasureJournal.requireNoNativeRows(container: container, checkpoint: checkpoint)
        try tree.requireTerminal(bytes)
        try SharedMediaNativeErasureJournal.requireNoNativeRows(container: container, checkpoint: checkpoint)
        return SharedMediaNativeErasureTerminal(header: expected.header, profile: expected.profile) {
            try tree.requireTerminal(bytes)
        }
    }

    private func readTerminal() throws -> Data? {
        let marker = SharedMediaNativeErasureTerminalReceipt.marker
        let count = fgetxattr(descriptor, marker, nil, 0, 0, 0)
        if count < 0 { guard errno == ENOATTR else { throw SharedMediaStorageFailure.conflict }; return nil }
        guard count > 0, count <= SharedMediaNativeErasureTerminalReceipt.maximumBytes else { throw SharedMediaStorageFailure.conflict }
        var bytes = [UInt8](repeating: 0, count: count)
        guard bytes.withUnsafeMutableBytes({ fgetxattr(descriptor, marker, $0.baseAddress, $0.count, 0, 0) }) == count else {
            throw SharedMediaStorageFailure.stale
        }
        let result = Data(bytes)
        _ = try SharedMediaNativeErasureTerminalReceipt.decode(result)
        return result
    }

    private func requireTerminal(_ bytes: Data) throws {
        try check()
        guard try readTerminal() == bytes, try countTree() == 0, fsync(descriptor) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        try check()
    }

    private func requireAbsent() throws {
        try check()
        try visit { entry in
            guard try !inspect(entry, remove: false, boundary: { _ in }) else { throw SharedMediaStorageFailure.conflict }
        }
        // Also rejects a late unlisted writer, even after every listed target
        // disappeared. The preserved parent receipt is outside this universe.
        guard try countTree() == 0, fsync(descriptor) == 0 else { throw SharedMediaStorageFailure.conflict }
        try check()
    }

    private func visit(removing: Bool = false, _ body: (Manifest.Entry) throws -> Void) throws {
        var chain = Manifest.Chain(operationID: header.operationID, profile: profile)
        try pages(removing) { bytes in
            try check()
            for entry in try chain.consume(bytes) { try check(); try body(entry) }
        }
        try chain.requireComplete(pages: header.pageCount, entries: header.entryCount, lastSHA256: header.lastPageSHA256)
        try check()
    }

    private func check() throws {
        try Task.checkCancellation(); try checkpoint()
        var held = stat(), named = stat()
        guard fstat(descriptor, &held) == 0, lstat(parent.path, &named) == 0,
              held.st_mode & S_IFMT == S_IFDIR, named.st_mode & S_IFMT == S_IFDIR,
              identity(held) == header.controlParentIdentity, identity(named) == header.controlParentIdentity else {
            throw SharedMediaStorageFailure.stale
        }
        let name = SharedMediaNativeBootstrapCodec.parentReceiptName
        if let expected = header.parentReceiptSHA256 {
            guard let bytes = try readControl(name), SharedMediaAcquisitionEncoding.digest(bytes) == expected else {
                throw SharedMediaStorageFailure.conflict
            }
        } else {
            guard try info(descriptor, name) == nil else { throw SharedMediaStorageFailure.conflict }
        }
    }

    private func components(_ entry: Manifest.Entry) -> [String] {
        if entry.namespace == .control { return [entry.token] }
        let root = entry.namespace == .capture ? SharedMediaCaptureRootJournal.rootName : entry.namespace.rawValue
        return [root] + (entry.token == "." ? [] : entry.token.split(separator: "/").map(String.init))
    }

    /// Returns whether the exact target was present at inspection. Ancestors
    /// are opened without following links and remain locked through the unlink.
    private func inspect(_ entry: Manifest.Entry, remove: Bool, boundary: (Boundary) throws -> Void) throws -> Bool {
        try entry.validate(ownerID: profile.ownerID)
        let path = components(entry)
        var opened: [Int32] = [], current = descriptor
        defer { for fd in opened.reversed() { Darwin.close(fd) } }
        for component in path.dropLast() {
            guard let value = try info(current, component) else { return false }
            let fd = try openDirectory(current, component, expected: value)
            opened.append(fd); current = fd
        }
        let name = path.last!
        guard let value = try info(current, name) else { return false }
        guard entry.kind != .absent else { throw SharedMediaStorageFailure.conflict }
        let directory = entry.kind == .directory
        guard directory ? value.st_mode & S_IFMT == S_IFDIR : value.st_mode & S_IFMT == S_IFREG && value.st_nlink == 1,
              entry.identity == (directory ? identity(value) : fileIdentity(value)) else { throw SharedMediaStorageFailure.conflict }
        guard remove else { return true }
        let fd = directory ? try openDirectory(current, name, expected: value)
            : openat(current, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.conflict }
        defer { Darwin.close(fd) }
        var held = stat()
        guard fstat(fd, &held) == 0, fileIdentity(held) == fileIdentity(value) else { throw SharedMediaStorageFailure.stale }
        try check(); try boundary(.beforeUnlink)
        guard let named = try info(current, name), fileIdentity(named) == fileIdentity(value) else { throw SharedMediaStorageFailure.stale }
        guard unlinkat(current, name, directory ? AT_REMOVEDIR : 0) == 0 else { throw SharedMediaStorageFailure.unavailable }
        try boundary(.afterUnlink)
        guard fsync(current) == 0, try info(current, name) == nil else { throw SharedMediaStorageFailure.unavailable }
        try boundary(.afterParentSync); try check()
        return true
    }

    private func countTree() throws -> Int64 {
        let controls = Set([SharedMediaNativeBootstrapCodec.intentName, SharedMediaNativeBootstrapCodec.finalName]
            + SharedMediaNativeBootstrapCodec.progressNames).union(SharedMediaCaptureRootJournal.names)
        let allowed = controls.union(["authority", "photo", "inbox"])
        var count: Int64 = 0
        func walk(_ fd: Int32, depth: Int) throws {
            guard depth <= 4 else { throw SharedMediaStorageFailure.conflict }
            try names(fd) { name in
                try check()
                if depth == 0 && name == SharedMediaNativeBootstrapCodec.parentReceiptName { return }
                guard depth != 0 || allowed.contains(name), let value = try info(fd, name) else { throw SharedMediaStorageFailure.conflict }
                count = try SharedMediaStoragePolicy.add(count, 1)
                guard count <= header.entryCount else { throw SharedMediaStorageFailure.conflict }
                if value.st_mode & S_IFMT == S_IFDIR {
                    let child = try openDirectory(fd, name, expected: value)
                    defer { Darwin.close(child) }
                    try walk(child, depth: depth + 1)
                } else {
                    guard value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1 else { throw SharedMediaStorageFailure.conflict }
                }
            }
        }
        try walk(descriptor, depth: 0)
        return count
    }

    private func info(_ parent: Int32, _ name: String) throws -> stat? {
        var value = stat()
        if fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW) == 0 { return value }
        guard errno == ENOENT else { throw SharedMediaStorageFailure.unavailable }
        return nil
    }

    private func openDirectory(_ parent: Int32, _ name: String, expected: stat) throws -> Int32 {
        guard expected.st_mode & S_IFMT == S_IFDIR else { throw SharedMediaStorageFailure.conflict }
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.conflict }
        var held = stat()
        guard fstat(fd, &held) == 0, identity(held) == identity(expected), flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd); throw SharedMediaStorageFailure.conflict
        }
        return fd
    }

    private func names(_ fd: Int32, body: (String) throws -> Void) throws {
        let copy = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard copy >= 0 else { throw SharedMediaStorageFailure.unavailable }
        guard let directory = fdopendir(copy) else { Darwin.close(copy); throw SharedMediaStorageFailure.unavailable }
        defer { closedir(directory) }
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw SharedMediaStorageFailure.unavailable }; return
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." { try body(name) }
        }
    }

    private func readControl(_ name: String) throws -> Data? {
        guard let value = try info(descriptor, name) else { return nil }
        guard value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1,
              value.st_size > 0, value.st_size <= 4096 else { throw SharedMediaStorageFailure.conflict }
        let fd = openat(descriptor, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.conflict }
        defer { Darwin.close(fd) }
        var bytes = Data(count: Int(value.st_size)), offset = 0, held = stat()
        guard fstat(fd, &held) == 0, fileIdentity(held) == fileIdentity(value) else { throw SharedMediaStorageFailure.stale }
        while offset < bytes.count {
            let n = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw SharedMediaStorageFailure.unavailable }; offset += n
        }
        guard fstat(fd, &held) == 0, fileIdentity(held) == fileIdentity(value),
              try info(descriptor, name).map(fileIdentity) == fileIdentity(value) else { throw SharedMediaStorageFailure.stale }
        return bytes
    }

    private func identity(_ value: stat) -> String { "\(value.st_dev):\(value.st_ino)" }
    private func fileIdentity(_ value: stat) -> String {
        "\(identity(value)):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
    }
}

/// Only the held physical-tree verifier can mint this. Every use rechecks the
/// same complete absence and parent identity; it is not a saved Boolean.
@MainActor
struct SharedMediaNativeErasureAbsence {
    private let header: SharedMediaNativeErasureHeader
    private let profile: SharedMediaNativeAppProfile
    private let verify: () throws -> Void
    fileprivate init(header: SharedMediaNativeErasureHeader, profile: SharedMediaNativeAppProfile,
                     verify: @escaping () throws -> Void) {
        self.header = header; self.profile = profile; self.verify = verify
    }
    func require(_ expected: SharedMediaNativeErasureHeader, profile: SharedMediaNativeAppProfile) throws {
        guard expected == header, profile == self.profile else { throw SharedMediaStorageFailure.conflict }
        try verify()
    }
}

/// Durable descriptive evidence only. The accepted outer operation and current
/// store/parent descriptors must independently match before cold recovery.
struct SharedMediaNativeErasureTerminalReceipt: Codable, Equatable {
    static let marker = "com.merian.native-erasure-terminal-v1"
    static let maximumBytes = SharedMediaNativeErasureHeader.maximumBytes + 4096
    let version: Int
    let profile: SharedMediaNativeAppProfile
    let header: SharedMediaNativeErasureHeader

    @MainActor func encoded() throws -> Data {
        guard version == 1 else { throw SharedMediaStorageFailure.invalid }
        _ = try header.encoded(profile: profile)
        return try SharedMediaAcquisitionEncoding.encode(self, maximum: Self.maximumBytes)
    }

    @MainActor static func decode(_ bytes: Data) throws -> Self {
        let value: Self = try SharedMediaAcquisitionEncoding.decode(bytes, maximum: maximumBytes)
        guard try value.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }
        return value
    }
}

/// Minted only after cleared-journal and descriptor-backed receipt readback.
/// Unlike absence(), its recheck survives removal of the database carrier.
@MainActor
struct SharedMediaNativeErasureTerminal {
    private let header: SharedMediaNativeErasureHeader
    private let profile: SharedMediaNativeAppProfile
    private let verify: () throws -> Void
    fileprivate init(header: SharedMediaNativeErasureHeader, profile: SharedMediaNativeAppProfile,
                     verify: @escaping () throws -> Void) {
        self.header = header; self.profile = profile; self.verify = verify
    }
    func require(_ expected: SharedMediaNativeErasureHeader, profile: SharedMediaNativeAppProfile) throws {
        guard expected == header, profile == self.profile else { throw SharedMediaStorageFailure.conflict }
        try verify()
    }

    func requireCurrent() throws { try verify() }
}
