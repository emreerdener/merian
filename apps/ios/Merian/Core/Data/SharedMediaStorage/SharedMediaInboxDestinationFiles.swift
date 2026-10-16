import CryptoKit
import Darwin
import Foundation

/// Exists only inside the locked namespace's non-escaping callback. Every
/// operation is bound to one immutable request and its saved execution state.
struct SharedMediaInboxDestinationFiles {
    let access: SharedMediaInboxDestinationAccess
    let handoff: SharedMediaInboxHandoff
    let binding: SharedMediaPhotoBinding
    #if DEBUG
    var fault: ((SharedMediaInboxHandoffBoundary) throws -> Void)?
    #endif

    func begin() throws -> SharedMediaInboxDestinationPartial {
        guard handoff.phase == "reserved", handoff.writerState == "open",
              handoff.writerEpoch == binding.epoch, handoff.inode == nil else { throw SharedMediaStorageFailure.conflict }
        return try access.perform { parent, _ in
            guard try inspect(parent, access.name) == nil, try inspect(parent, access.name + ".partial") == nil else { throw SharedMediaStorageFailure.conflict }
            let fd = openat(parent, access.name + ".partial", O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }; defer { Darwin.close(fd) }
            guard fsync(fd) == 0, fsync(parent) == 0 else { throw SharedMediaStorageFailure.unavailable }
            try boundary(.afterPartialCreate)
            guard let identity = try inspect(parent, access.name + ".partial"), identity.bytes == 0 else { throw SharedMediaStorageFailure.conflict }
            return .init(handoff: handoff, identity: identity, binding: binding.bytes, epoch: binding.epoch)
        }
    }

    func write(_ data: Data) throws -> SharedMediaInboxDestinationCompletion {
        guard handoff.phase == "writing", handoff.writerState == "open", handoff.writerEpoch == binding.epoch,
              data.count == handoff.request.byteCount, digest(data) == handoff.request.sha256 else { throw SharedMediaStorageFailure.conflict }
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
                    offset += count; try boundary(.duringWrite)
                }
            }
            guard fsync(fd) == 0 else { throw SharedMediaStorageFailure.unavailable }
            return try finish(parent, namespace)
        }
    }

    /// Original-account caller only. A short partial is never rewritten.
    func recover() throws -> SharedMediaInboxDestinationCompletion? {
        guard !handoff.detached, handoff.phase != "sourceRetiring" else { throw SharedMediaStorageFailure.inUse }
        return try access.perform { parent, namespace in
            let partial = try inspect(parent, access.name + ".partial"), final = try inspect(parent, access.name)
            guard partial == nil || final == nil else { throw SharedMediaStorageFailure.conflict }
            if let final {
                try matches(final)
                if handoff.completed, handoff.finalIdentity != final.exact { throw SharedMediaStorageFailure.conflict }
                let file = try verified(parent, access.name)
                guard fsync(parent) == 0, fsync(namespace) == 0 else { throw SharedMediaStorageFailure.unavailable }
                return .init(handoff: handoff, file: file, identity: final, binding: binding.bytes, epoch: binding.epoch)
            }
            guard let partial else { return nil }
            try matches(partial)
            guard partial.bytes <= handoff.request.byteCount else { throw SharedMediaStorageFailure.conflict }
            return partial.bytes == handoff.request.byteCount ? try finish(parent, namespace) : nil
        }
    }

    /// No payload read. Caller holds the exclusive lifetime and has drained its
    /// sole local task; this does not establish success or authorize deletion.
    func closure() throws -> SharedMediaInboxDestinationClosure {
        try access.perform { parent, _ in
            let partial = try inspect(parent, access.name + ".partial"), final = try inspect(parent, access.name)
            guard partial == nil || final == nil else { throw SharedMediaStorageFailure.conflict }
            if let file = partial ?? final {
                try matches(file)
                guard file.bytes <= handoff.request.byteCount else { throw SharedMediaStorageFailure.conflict }
                if handoff.completed {
                    guard partial == nil, file.exact == handoff.finalIdentity else { throw SharedMediaStorageFailure.conflict }
                }
            }
            return .init(handoff: handoff, occupied: (partial ?? final)?.bytes ?? 0, binding: binding.bytes, epoch: binding.epoch)
        }
    }

    func inspectRetirement() throws -> SharedMediaInboxDestinationInspection {
        guard handoff.phase == "detached", handoff.writerState == "closed" else { throw SharedMediaStorageFailure.inUse }
        return try access.perform { parent, namespace in
            let partial = try inspect(parent, access.name + ".partial"), final = try inspect(parent, access.name)
            guard partial == nil || final == nil else { throw SharedMediaStorageFailure.conflict }
            for item in [partial, final].compactMap({ $0 }) {
                try matches(item)
                guard item.bytes <= handoff.request.byteCount else { throw SharedMediaStorageFailure.conflict }
            }
            return try .init(handoff: handoff, identity: .init(partial: partial?.exact ?? "absent",
                final: final?.exact ?? "absent", parent: directoryIdentity(parent), namespace: directoryIdentity(namespace)),
                binding: binding.bytes, epoch: binding.epoch)
        }
    }

    func release(_ intent: SharedMediaInboxDestinationRetirement) throws -> SharedMediaInboxDestinationRelease {
        guard intent.handoff == handoff, intent.binding == binding.bytes, intent.epoch == binding.epoch,
              handoff.phase == "detachedRetiring", handoff.writerState == "closed" else { throw SharedMediaStorageFailure.conflict }
        return try access.perform { parent, namespace in
            guard try directoryIdentity(parent) == intent.identity.parent,
                  try directoryIdentity(namespace) == intent.identity.namespace else { throw SharedMediaStorageFailure.conflict }
            for (token, saved) in [(access.name + ".partial", intent.identity.partial), (access.name, intent.identity.final)] {
                if let present = try inspect(parent, token) {
                    guard present.exact == saved, unlinkat(parent, token, 0) == 0 else { throw SharedMediaStorageFailure.conflict }
                    try boundary(.afterUnlink)
                }
            }
            guard (parent < 0 || fsync(parent) == 0), fsync(namespace) == 0,
                  try inspect(parent, access.name + ".partial") == nil,
                  try inspect(parent, access.name) == nil else { throw SharedMediaStorageFailure.unavailable }
            return .init(retirement: intent)
        }
    }

    private func directoryIdentity(_ fd: Int32) throws -> String {
        if fd < 0 { return "absent" }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw SharedMediaStorageFailure.conflict }
        return "\(info.st_dev):\(info.st_ino)"
    }

    private func finish(_ parent: Int32, _ namespace: Int32) throws -> SharedMediaInboxDestinationCompletion {
        let partial = access.name + ".partial"
        _ = try verified(parent, partial)
        guard renameatx_np(parent, partial, parent, access.name, UInt32(RENAME_EXCL)) == 0,
              fsync(parent) == 0, fsync(namespace) == 0 else { throw SharedMediaStorageFailure.unavailable }
        try boundary(.afterRename)
        let file = try verified(parent, access.name)
        guard let identity = try inspect(parent, access.name) else { throw SharedMediaStorageFailure.conflict }
        try matches(identity)
        return .init(handoff: handoff, file: file, identity: identity, binding: binding.bytes, epoch: binding.epoch)
    }

    private func verified(_ parent: Int32, _ token: String) throws -> PhotoPreparationFile {
        guard let before = try inspect(parent, token) else { throw SharedMediaStorageFailure.unavailable }
        try matches(before)
        guard before.bytes == handoff.request.byteCount else { throw SharedMediaStorageFailure.conflict }
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
            guard data.count + amount <= handoff.request.byteCount else { throw SharedMediaStorageFailure.conflict }
            data.append(contentsOf: buffer.prefix(amount))
        }
        guard data.count == handoff.request.byteCount, digest(data) == handoff.request.sha256,
              try identity(fd) == before, try inspect(parent, token) == before, fsync(fd) == 0 else { throw SharedMediaStorageFailure.conflict }
        let type = try PhotoPreparationLockedFiles.validateImage(data, maximumBytes: handoff.request.byteCount)
        return .init(assetID: handoff.request.assetID, generation: handoff.request.assetGeneration,
            token: handoff.request.intent(epoch: handoff.writerEpoch).fileToken,
            byteCount: handoff.request.byteCount, sha256: handoff.request.sha256, contentType: type)
    }

    private func matches(_ identity: SharedMediaInboxFileIdentity) throws {
        guard identity.device == handoff.device, identity.inode == handoff.inode else { throw SharedMediaStorageFailure.conflict }
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
    private func boundary(_ point: SharedMediaInboxHandoffBoundary) throws {
        #if DEBUG
        try fault?(point)
        #endif
    }
}

struct SharedMediaInboxDestinationPartial: Sendable {
    let handoff: SharedMediaInboxHandoff, identity: SharedMediaInboxFileIdentity
    let binding: Data, epoch: UUID
    fileprivate init(handoff: SharedMediaInboxHandoff, identity: SharedMediaInboxFileIdentity, binding: Data, epoch: UUID) {
        self.handoff = handoff; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaInboxDestinationCompletion: Sendable {
    let handoff: SharedMediaInboxHandoff, file: PhotoPreparationFile, identity: SharedMediaInboxFileIdentity
    let binding: Data, epoch: UUID
    fileprivate init(handoff: SharedMediaInboxHandoff, file: PhotoPreparationFile, identity: SharedMediaInboxFileIdentity, binding: Data, epoch: UUID) {
        self.handoff = handoff; self.file = file; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaInboxDestinationClosure: Sendable {
    let handoff: SharedMediaInboxHandoff
    let occupied: Int64
    let binding: Data, epoch: UUID
    fileprivate init(handoff: SharedMediaInboxHandoff, occupied: Int64, binding: Data, epoch: UUID) {
        self.handoff = handoff; self.occupied = occupied; self.binding = binding; self.epoch = epoch
    }
}

struct SharedMediaInboxDestinationInspection: Sendable {
    let handoff: SharedMediaInboxHandoff
    let identity: SharedMediaInboxDestinationRetirementIdentity
    let binding: Data, epoch: UUID
    fileprivate init(handoff: SharedMediaInboxHandoff, identity: SharedMediaInboxDestinationRetirementIdentity, binding: Data, epoch: UUID) {
        self.handoff = handoff; self.identity = identity; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaInboxDestinationRelease: Sendable {
    let retirement: SharedMediaInboxDestinationRetirement
    fileprivate init(retirement: SharedMediaInboxDestinationRetirement) { self.retirement = retirement }
}
