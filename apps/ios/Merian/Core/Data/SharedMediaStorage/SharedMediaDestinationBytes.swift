import CryptoKit
import Darwin
import Foundation

/// Byte mechanics inside a non-escaping namespace capability. This type mints
/// no ownership or retirement authority; the typed adapters enforce lifecycle.
struct SharedMediaDestinationBytes {
    let access: SharedMediaInboxDestinationAccess
    let expected: PhotoPreparationFile
    let device: Int64?
    let inode: Int64?
    let finalIdentity: String?
    var fault: ((SharedMediaInboxHandoffBoundary) throws -> Void)?

    func begin() throws -> SharedMediaInboxFileIdentity {
        try access.perform { parent, _ in
            guard try inspect(parent, access.name) == nil, try inspect(parent, access.name + ".partial") == nil else { throw SharedMediaStorageFailure.conflict }
            let fd = openat(parent, access.name + ".partial", O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }; defer { Darwin.close(fd) }
            guard fsync(fd) == 0, fsync(parent) == 0 else { throw SharedMediaStorageFailure.unavailable }
            try fault?(.afterPartialCreate)
            guard let identity = try inspect(parent, access.name + ".partial"), identity.bytes == 0 else { throw SharedMediaStorageFailure.conflict }
            return identity
        }
    }

    func write(_ data: Data) throws -> (PhotoPreparationFile, SharedMediaInboxFileIdentity) {
        guard data.count == expected.byteCount, digest(data) == expected.sha256 else { throw SharedMediaStorageFailure.conflict }
        return try access.perform { parent, namespace in
            let token = access.name + ".partial"
            guard let initial = try inspect(parent, token), initial.bytes == 0,
                  try inspect(parent, access.name) == nil else { throw SharedMediaStorageFailure.conflict }
            try matches(initial)
            let fd = openat(parent, token, O_WRONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }; defer { Darwin.close(fd) }
            guard try identity(fd) == initial else { throw SharedMediaStorageFailure.conflict }
            try data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    try Task.checkCancellation()
                    let count = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), min(65_536, raw.count - offset))
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw SharedMediaStorageFailure.unavailable }
                    offset += count; try fault?(.duringWrite)
                }
            }
            guard fsync(fd) == 0 else { throw SharedMediaStorageFailure.unavailable }
            return try finish(parent, namespace)
        }
    }

    func recover() throws -> (PhotoPreparationFile, SharedMediaInboxFileIdentity)? {
        try access.perform { parent, namespace in
            let partial = try inspect(parent, access.name + ".partial"), final = try inspect(parent, access.name)
            guard partial == nil || final == nil else { throw SharedMediaStorageFailure.conflict }
            if let final {
                try matches(final)
                if let finalIdentity, finalIdentity != final.exact { throw SharedMediaStorageFailure.conflict }
                let file = try verified(parent, access.name)
                guard fsync(parent) == 0, fsync(namespace) == 0 else { throw SharedMediaStorageFailure.unavailable }
                return (file, final)
            }
            guard let partial else { return nil }
            try matches(partial)
            guard finalIdentity == nil, partial.bytes <= expected.byteCount else { throw SharedMediaStorageFailure.conflict }
            return partial.bytes == expected.byteCount ? try finish(parent, namespace) : nil
        }
    }

    func verifyFinal() throws {
        try access.perform { parent, _ in
            guard try inspect(parent, access.name + ".partial") == nil,
                  let final = try inspect(parent, access.name), final.exact == finalIdentity else { throw SharedMediaStorageFailure.conflict }
            _ = try verified(parent, access.name)
        }
    }

    func occupancy() throws -> Int64 {
        try access.perform { parent, _ in
            let partial = try inspect(parent, access.name + ".partial"), final = try inspect(parent, access.name)
            guard partial == nil || final == nil else { throw SharedMediaStorageFailure.conflict }
            if let file = partial ?? final {
                try matches(file)
                guard file.bytes <= expected.byteCount else { throw SharedMediaStorageFailure.conflict }
                if let finalIdentity {
                    guard partial == nil, file.exact == finalIdentity else { throw SharedMediaStorageFailure.conflict }
                }
            }
            return (partial ?? final)?.bytes ?? 0
        }
    }

    func inspectRetirement() throws -> SharedMediaInboxDestinationRetirementIdentity {
        try access.perform { parent, namespace in
            let partial = try inspect(parent, access.name + ".partial"), final = try inspect(parent, access.name)
            guard partial == nil || final == nil else { throw SharedMediaStorageFailure.conflict }
            for item in [partial, final].compactMap({ $0 }) {
                try matches(item)
                guard item.bytes <= expected.byteCount else { throw SharedMediaStorageFailure.conflict }
            }
            if let finalIdentity, let present = partial ?? final {
                guard partial == nil, present.exact == finalIdentity else { throw SharedMediaStorageFailure.conflict }
            }
            return try .init(partial: partial?.exact ?? "absent", final: final?.exact ?? "absent",
                             parent: directoryIdentity(parent), namespace: directoryIdentity(namespace))
        }
    }

    /// Read-only capture for a crash before the empty partial descriptor was
    /// saved. It cannot adopt nonempty bytes or a final file as owned work.
    func inspectReservedEmpty() throws -> SharedMediaInboxDestinationRetirementIdentity {
        guard device == nil, inode == nil, finalIdentity == nil else { throw SharedMediaStorageFailure.conflict }
        return try access.perform { parent, namespace in
            let partial = try inspect(parent, access.name + ".partial")
            guard try inspect(parent, access.name) == nil, partial == nil || partial?.bytes == 0 else {
                throw SharedMediaStorageFailure.conflict
            }
            return try .init(partial: partial?.exact ?? "absent", final: "absent",
                parent: directoryIdentity(parent), namespace: directoryIdentity(namespace))
        }
    }

    func release(_ saved: SharedMediaInboxDestinationRetirementIdentity) throws {
        try access.perform { parent, namespace in
            guard try directoryIdentity(parent) == saved.parent,
                  try directoryIdentity(namespace) == saved.namespace else { throw SharedMediaStorageFailure.conflict }
            for (token, identity) in [(access.name + ".partial", saved.partial), (access.name, saved.final)] {
                if let present = try inspect(parent, token) {
                    guard present.exact == identity, unlinkat(parent, token, 0) == 0 else { throw SharedMediaStorageFailure.conflict }
                    try fault?(.afterUnlink)
                }
            }
            guard (parent < 0 || fsync(parent) == 0), fsync(namespace) == 0,
                  try inspect(parent, access.name + ".partial") == nil,
                  try inspect(parent, access.name) == nil else { throw SharedMediaStorageFailure.unavailable }
        }
    }

    private func directoryIdentity(_ fd: Int32) throws -> String {
        if fd < 0 { return "absent" }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw SharedMediaStorageFailure.conflict }
        return "\(info.st_dev):\(info.st_ino)"
    }

    private func finish(_ parent: Int32, _ namespace: Int32) throws -> (PhotoPreparationFile, SharedMediaInboxFileIdentity) {
        let partial = access.name + ".partial"
        _ = try verified(parent, partial)
        guard renameatx_np(parent, partial, parent, access.name, UInt32(RENAME_EXCL)) == 0,
              fsync(parent) == 0, fsync(namespace) == 0 else { throw SharedMediaStorageFailure.unavailable }
        try fault?(.afterRename)
        let file = try verified(parent, access.name)
        guard let identity = try inspect(parent, access.name) else { throw SharedMediaStorageFailure.conflict }
        try matches(identity)
        return (file, identity)
    }

    private func verified(_ parent: Int32, _ token: String) throws -> PhotoPreparationFile {
        guard let before = try inspect(parent, token) else { throw SharedMediaStorageFailure.unavailable }
        try matches(before)
        guard before.bytes == expected.byteCount else { throw SharedMediaStorageFailure.conflict }
        let fd = openat(parent, token, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }; defer { Darwin.close(fd) }
        guard try identity(fd) == before else { throw SharedMediaStorageFailure.conflict }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            try Task.checkCancellation()
            let amount = Darwin.read(fd, &buffer, buffer.count)
            if amount < 0 && errno == EINTR { continue }
            guard amount >= 0 else { throw SharedMediaStorageFailure.unavailable }
            if amount == 0 { break }
            guard data.count + amount <= expected.byteCount else { throw SharedMediaStorageFailure.conflict }
            data.append(contentsOf: buffer.prefix(amount))
        }
        guard data.count == expected.byteCount, digest(data) == expected.sha256,
              try identity(fd) == before, try inspect(parent, token) == before, fsync(fd) == 0 else { throw SharedMediaStorageFailure.conflict }
        let type = try PhotoPreparationLockedFiles.validateImage(data, maximumBytes: expected.byteCount)
        guard expected.contentType.isEmpty || type == expected.contentType else { throw SharedMediaStorageFailure.conflict }
        return .init(assetID: expected.assetID, generation: expected.generation, token: expected.token,
                     byteCount: expected.byteCount, sha256: expected.sha256, contentType: type)
    }

    private func matches(_ identity: SharedMediaInboxFileIdentity) throws {
        guard identity.device == device, identity.inode == inode else { throw SharedMediaStorageFailure.conflict }
    }
    private func inspect(_ parent: Int32, _ token: String) throws -> SharedMediaInboxFileIdentity? {
        if parent < 0 { return nil }
        var info = stat()
        if fstatat(parent, token, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw SharedMediaStorageFailure.conflict }; return nil
        }
        return try value(info)
    }
    private func identity(_ fd: Int32) throws -> SharedMediaInboxFileIdentity {
        var info = stat(); guard fstat(fd, &info) == 0 else { throw SharedMediaStorageFailure.unavailable }
        return try value(info)
    }
    private func value(_ s: stat) throws -> SharedMediaInboxFileIdentity {
        guard s.st_mode & S_IFMT == S_IFREG, s.st_nlink == 1, s.st_size >= 0 else { throw SharedMediaStorageFailure.conflict }
        return .init(device: Int64(s.st_dev), inode: Int64(s.st_ino), bytes: s.st_size,
            exact: "\(s.st_dev):\(s.st_ino):\(s.st_size):\(s.st_mtimespec.tv_sec):\(s.st_mtimespec.tv_nsec):\(s.st_ctimespec.tv_sec):\(s.st_ctimespec.tv_nsec)")
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
