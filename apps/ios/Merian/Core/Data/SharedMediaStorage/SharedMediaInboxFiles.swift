import CryptoKit
import Darwin
import Foundation

/// The isolated inbox namespace owner. All operations are serialized by its I/O
/// actor; root/namespace descriptors and the create-only binding outlive work.
final class SharedMediaInboxFiles: @unchecked Sendable {
    static let namespace = "inboxOriginalV1"
    static let marker = "com.merian.inbox-shared-v1"
    private let root: URL
    private let binding: SharedMediaPhotoBinding
    private var rootFD: Int32 = -1
    private var namespaceFD: Int32 = -1
    private(set) var identity = ""
    #if DEBUG
    var fault: (@Sendable (SharedMediaInboxBoundary) throws -> Void)?
    #endif

    init(root: URL, binding: SharedMediaPhotoBinding) throws {
        self.root = root; self.binding = binding
        do {
            rootFD = try Self.openDirectory(root)
            guard flock(rootFD, LOCK_EX | LOCK_NB) == 0 else { throw SharedMediaStorageFailure.busy }
            if binding.initializing { try names(rootFD, maximum: 0) }
            try checkBinding(initializing: binding.initializing)
            guard mkdirat(rootFD, "InboxSources", 0o700) == 0 || errno == EEXIST else { throw SharedMediaStorageFailure.unavailable }
            namespaceFD = openat(rootFD, "InboxSources", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard namespaceFD >= 0, flock(namespaceFD, LOCK_EX | LOCK_NB) == 0,
                  fsync(namespaceFD) == 0, fsync(rootFD) == 0 else { throw SharedMediaStorageFailure.unavailable }
            var r = stat(), n = stat()
            guard fstat(rootFD, &r) == 0, fstat(namespaceFD, &n) == 0 else { throw SharedMediaStorageFailure.unavailable }
            identity = Self.directoryIdentity(r) + "/" + Self.directoryIdentity(n)
            try check()
        } catch { close(); throw error }
    }

    deinit { close() }
    private func close() {
        if namespaceFD >= 0 { Darwin.close(namespaceFD); namespaceFD = -1 }
        if rootFD >= 0 { Darwin.close(rootFD); rootFD = -1 }
    }

    func check() throws {
        try checkBinding(initializing: false)
        let named = try Self.openDirectory(root)
        defer { Darwin.close(named) }
        var r = stat(), n = stat(), rn = stat(), nn = stat()
        guard fstat(rootFD, &r) == 0, fstat(named, &rn) == 0, fstat(namespaceFD, &n) == 0,
              fstatat(rootFD, "InboxSources", &nn, AT_SYMLINK_NOFOLLOW) == 0,
              nn.st_mode & S_IFMT == S_IFDIR, Self.directoryIdentity(r) == Self.directoryIdentity(rn),
              Self.directoryIdentity(n) == Self.directoryIdentity(nn),
              identity == Self.directoryIdentity(r) + "/" + Self.directoryIdentity(n) else { throw SharedMediaStorageFailure.conflict }
        guard try names(rootFD, maximum: 1) == ["InboxSources"] else { throw SharedMediaStorageFailure.conflict }
    }

    func validateInventory(_ sources: [SharedMediaInboxSource]) throws {
        try check()
        let allowed = Set(sources.flatMap { [$0.token, $0.partialToken] })
        guard sources.count <= 8, try names(namespaceFD, maximum: 16).isSubset(of: allowed) else { throw SharedMediaStorageFailure.conflict }
        for source in sources {
            guard source.rootIdentity == identity else { throw SharedMediaStorageFailure.conflict }
            for token in [source.token, source.partialToken] { _ = try inspect(token) }
        }
    }

    /// Only a closed local writer can yield stable occupied-byte accounting.
    /// This proves occupancy, not successful image preparation or AI execution.
    func occupancy(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxOccupancyProof {
        try require(source)
        guard source.writerState == "closed", source.phase != "retiring" else { throw SharedMediaStorageFailure.inUse }
        let partial = try inspect(source.partialToken), final = try inspect(source.token)
        guard partial == nil || final == nil else { throw SharedMediaStorageFailure.conflict }
        let file = partial ?? final
        if let file {
            try matchesInode(file, source: source)
            guard source.expectedBytes > 0, file.bytes <= source.expectedBytes else { throw SharedMediaStorageFailure.conflict }
            if source.phase == "ready" {
                guard partial == nil, file.exact == source.finalIdentity else { throw SharedMediaStorageFailure.conflict }
            }
        }
        return .init(source: source, bytes: file?.bytes ?? 0, binding: binding.bytes, epoch: binding.epoch)
    }

    static func prepare(_ data: Data, maximumBytes: Int64) throws -> SharedMediaInboxPrepared {
        let type = try PhotoPreparationLockedFiles.validateImage(data, maximumBytes: maximumBytes)
        return .init(bytes: Int64(data.count), sha256: digest(data), contentType: type)
    }

    func begin(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxFileIdentity {
        try require(source)
        guard source.phase == "prepared", source.device == nil, source.inode == nil,
              try inspect(source.token) == nil, try inspect(source.partialToken) == nil else { throw SharedMediaStorageFailure.conflict }
        let fd = openat(namespaceFD, source.partialToken, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0, fsync(namespaceFD) == 0 else { throw SharedMediaStorageFailure.unavailable }
        try boundary(.afterPartialCreate)
        guard let result = try inspect(source.partialToken), result.bytes == 0 else { throw SharedMediaStorageFailure.conflict }
        return result
    }

    func write(_ data: Data, source: SharedMediaInboxSource) throws -> SharedMediaInboxCompletionProof {
        try require(source)
        guard source.phase == "writing", Int64(data.count) == source.expectedBytes,
              Self.digest(data) == source.sha256 else { throw SharedMediaStorageFailure.conflict }
        let fd = openat(namespaceFD, source.partialToken, O_WRONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
        defer { Darwin.close(fd) }
        let initial = try fileIdentity(fd)
        try matchesInode(initial, source: source)
        guard initial.bytes == 0, try inspect(source.partialToken) == initial,
              try inspect(source.token) == nil else { throw SharedMediaStorageFailure.conflict }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                try Task.checkCancellation()
                let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), min(65_536, raw.count - offset))
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw SharedMediaStorageFailure.unavailable }
                offset += count
                try boundary(.duringWrite)
            }
        }
        guard fsync(fd) == 0 else { throw SharedMediaStorageFailure.unavailable }
        return try finishPartial(source)
    }

    /// May finish the original rename, never invoke the original provider again.
    func recover(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxCompletionProof? {
        try require(source)
        guard source.retirementID == nil else { throw SharedMediaStorageFailure.inUse }
        let final = try inspect(source.token), partial = try inspect(source.partialToken)
        guard final == nil || partial == nil else { throw SharedMediaStorageFailure.conflict }
        if let final {
            try matchesInode(final, source: source)
            if source.phase == "ready", source.finalIdentity != final.exact { throw SharedMediaStorageFailure.conflict }
            _ = try verifiedData(source, token: source.token)
            try synchronize(source.token)
            guard fsync(namespaceFD) == 0, try inspect(source.token) == final else { throw SharedMediaStorageFailure.conflict }
            return .init(source: source, identity: final, binding: binding.bytes, epoch: binding.epoch)
        }
        guard let partial else { return nil }
        try matchesInode(partial, source: source)
        guard partial.bytes <= source.expectedBytes else { throw SharedMediaStorageFailure.conflict }
        if partial.bytes == source.expectedBytes && source.expectedBytes > 0 { return try finishPartial(source) }
        return nil
    }

    func read(_ source: SharedMediaInboxSource) throws -> Data {
        try require(source)
        guard source.phase == "ready", let file = try inspect(source.token), file.exact == source.finalIdentity,
              try inspect(source.partialToken) == nil else { throw SharedMediaStorageFailure.conflict }
        return try verifiedData(source, token: source.token)
    }

    func inspectRetirement(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxRetirementInspection {
        try require(source)
        let partial = try inspect(source.partialToken), final = try inspect(source.token)
        guard partial == nil || final == nil else { throw SharedMediaStorageFailure.conflict }
        for file in [partial, final].compactMap({ $0 }) { try matchesInode(file, source: source) }
        if source.phase == "ready", final != nil { _ = try read(source) }
        return .init(source: source, partial: partial?.exact ?? "absent", final: final?.exact ?? "absent", binding: binding.bytes, epoch: binding.epoch)
    }

    func release(_ intent: SharedMediaInboxRetirement) throws -> SharedMediaInboxReleaseProof {
        let source = intent.source
        try require(source)
        guard intent.binding == binding.bytes, intent.epoch == binding.epoch, source.retirementID != nil,
              let partial = source.retirementPartialIdentity, let final = source.retirementFinalIdentity else { throw SharedMediaStorageFailure.conflict }
        for (token, saved, point) in [(source.partialToken, partial, SharedMediaInboxBoundary.afterPartialUnlink), (source.token, final, .afterFinalUnlink)] {
            if let current = try inspect(token) {
                guard current.exact == saved else { throw SharedMediaStorageFailure.conflict }
                guard unlinkat(namespaceFD, token, 0) == 0 else { throw SharedMediaStorageFailure.unavailable }
                try boundary(point)
            }
        }
        guard fsync(namespaceFD) == 0, try inspect(source.partialToken) == nil, try inspect(source.token) == nil else { throw SharedMediaStorageFailure.unavailable }
        try check()
        return .init(retirement: intent)
    }

    private func finishPartial(_ source: SharedMediaInboxSource) throws -> SharedMediaInboxCompletionProof {
        _ = try verifiedData(source, token: source.partialToken)
        try synchronize(source.partialToken)
        guard renameatx_np(namespaceFD, source.partialToken, namespaceFD, source.token, UInt32(RENAME_EXCL)) == 0,
              fsync(namespaceFD) == 0 else { throw SharedMediaStorageFailure.unavailable }
        try boundary(.afterRename)
        guard let final = try inspect(source.token) else { throw SharedMediaStorageFailure.conflict }
        try matchesInode(final, source: source)
        _ = try verifiedData(source, token: source.token)
        guard try inspect(source.token) == final else { throw SharedMediaStorageFailure.conflict }
        return .init(source: source, identity: final, binding: binding.bytes, epoch: binding.epoch)
    }

    private func verifiedData(_ source: SharedMediaInboxSource, token: String) throws -> Data {
        guard source.expectedBytes > 0, source.expectedBytes <= source.maximumBytes,
              let expected = source.sha256 else { throw SharedMediaStorageFailure.conflict }
        let fd = openat(namespaceFD, token, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
        defer { Darwin.close(fd) }
        let before = try fileIdentity(fd)
        try matchesInode(before, source: source)
        guard before.bytes == source.expectedBytes else { throw SharedMediaStorageFailure.conflict }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while data.count < Int(source.expectedBytes) {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, min($0.count, Int(source.expectedBytes) - data.count)) }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw SharedMediaStorageFailure.unavailable }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard try fileIdentity(fd) == before, try inspect(token) == before, Self.digest(data) == expected else { throw SharedMediaStorageFailure.conflict }
        try check()
        return data
    }

    private func synchronize(_ token: String) throws {
        let fd = openat(namespaceFD, token, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
        defer { Darwin.close(fd) }
        _ = try fileIdentity(fd)
        guard fsync(fd) == 0 else { throw SharedMediaStorageFailure.unavailable }
    }

    private func require(_ source: SharedMediaInboxSource) throws {
        try check()
        guard source.rootIdentity == identity, source.maximumBytes > 0,
              source.maximumBytes <= PhotoPreparationPolicy.original else { throw SharedMediaStorageFailure.conflict }
    }
    private func matchesInode(_ file: SharedMediaInboxFileIdentity, source: SharedMediaInboxSource) throws {
        guard file.device == source.device, file.inode == source.inode else { throw SharedMediaStorageFailure.conflict }
    }
    private func inspect(_ token: String) throws -> SharedMediaInboxFileIdentity? {
        try SharedMediaStoragePolicy.token(token)
        let fd = openat(namespaceFD, token, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 { if errno == ENOENT { return nil }; throw SharedMediaStorageFailure.conflict }
        defer { Darwin.close(fd) }
        return try fileIdentity(fd)
    }
    private func fileIdentity(_ fd: Int32) throws -> SharedMediaInboxFileIdentity {
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_size >= 0, info.st_size <= PhotoPreparationPolicy.original,
              info.st_ino <= UInt64(Int64.max) else { throw SharedMediaStorageFailure.conflict }
        let exact = "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
        return .init(device: Int64(info.st_dev), inode: Int64(info.st_ino), bytes: info.st_size, exact: exact)
    }
    @discardableResult private func names(_ fd: Int32, maximum: Int) throws -> Set<String> {
        let copy = dup(fd)
        guard copy >= 0 else { throw SharedMediaStorageFailure.unavailable }
        guard let directory = fdopendir(copy) else { Darwin.close(copy); throw SharedMediaStorageFailure.unavailable }
        defer { closedir(directory) }
        rewinddir(directory)
        var result = Set<String>()
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw SharedMediaStorageFailure.unavailable }; break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            result.insert(name)
            guard result.count <= maximum else { throw SharedMediaStorageFailure.conflict }
        }
        return result
    }
    private func checkBinding(initializing: Bool) throws {
        let count = fgetxattr(rootFD, Self.marker, nil, 0, 0, 0)
        if count >= 0 {
            guard !initializing, count == binding.bytes.count else { throw SharedMediaStorageFailure.conflict }
            var bytes = [UInt8](repeating: 0, count: count)
            guard bytes.withUnsafeMutableBytes({ fgetxattr(rootFD, Self.marker, $0.baseAddress, count, 0, 0) }) == count,
                  Data(bytes) == binding.bytes else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard initializing, errno == ENOATTR, binding.bytes.count <= 512,
                  binding.bytes.withUnsafeBytes({ fsetxattr(rootFD, Self.marker, $0.baseAddress, binding.bytes.count, 0, XATTR_CREATE) }) == 0,
                  fsync(rootFD) == 0 else { throw SharedMediaStorageFailure.conflict }
        }
    }
    private static func openDirectory(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/") else { throw SharedMediaStorageFailure.invalid }
        var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            Darwin.close(fd)
            guard next >= 0 else { throw SharedMediaStorageFailure.unavailable }; fd = next
        }
        return fd
    }
    private static func directoryIdentity(_ value: stat) -> String { "\(value.st_dev):\(value.st_ino)" }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func boundary(_ value: SharedMediaInboxBoundary) throws {
        #if DEBUG
        try fault?(value)
        #endif
    }
}

struct SharedMediaInboxCompletionProof: Sendable {
    let source: SharedMediaInboxSource
    let identity: SharedMediaInboxFileIdentity
    let binding: Data
    let epoch: UUID
    fileprivate init(source: SharedMediaInboxSource, identity: SharedMediaInboxFileIdentity, binding: Data, epoch: UUID) {
        self.source = source; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaInboxRetirementInspection: Sendable {
    let source: SharedMediaInboxSource
    let partial: String
    let final: String
    let binding: Data
    let epoch: UUID
    fileprivate init(source: SharedMediaInboxSource, partial: String, final: String, binding: Data, epoch: UUID) {
        self.source = source; self.partial = partial; self.final = final; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaInboxReleaseProof: Sendable {
    let retirement: SharedMediaInboxRetirement
    fileprivate init(retirement: SharedMediaInboxRetirement) { self.retirement = retirement }
}

/// Namespace-minted occupancy; never confers completion or deletion authority.
struct SharedMediaInboxOccupancyProof: Sendable {
    let source: SharedMediaInboxSource
    let bytes: Int64
    let binding: Data
    let epoch: UUID
    fileprivate init(source: SharedMediaInboxSource, bytes: Int64, binding: Data, epoch: UUID) {
        self.source = source; self.bytes = bytes; self.binding = binding; self.epoch = epoch
    }
}
