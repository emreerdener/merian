import CryptoKit
import Darwin
import Foundation
import SwiftData

/// Physical capture owner. It consumes only a marked, already locked root.
/// Writes additionally require a fresh repository authority and saved ledger;
/// read inspection alone cannot create, adopt or unlink media.
/// Holding this owner does not waive the caller's current store/account fence.
@MainActor
final class SharedMediaCaptureArtifactFiles {
    struct Inventory: Equatable, Sendable {
        let ledger: SharedMediaCaptureArtifactStoreAudit.Snapshot
        let physicalBytes: Int64
        let ambiguousEmptyPartials: Int64
    }

    private let validateControls: () throws -> Void
    private let rootURL: URL
    private let root: Int32, child: Int32
    private let binding: SharedMediaNativeLockedRoot.CaptureBinding
    let rootBindingSHA256: String
    #if DEBUG
    var afterByteAudit: (() throws -> Void)?
    var afterWriteChunk: (@Sendable (Int) async -> Void)?
    #endif

    init(controls: SharedMediaNativeCaptureRootFiles, rootURL: URL) throws {
        try controls.check()
        let transfer = try controls.take().consumeCapture(at: rootURL)
        validateControls = { try controls.check() }; self.rootURL = rootURL
        root = transfer.root; child = transfer.child; binding = transfer.binding
        rootBindingSHA256 = SharedMediaAcquisitionEncoding.digest(binding.marker)
    }

    /// Read inspection under the whole-library owner's already held controls.
    /// The transfer cannot bootstrap or finish an interrupted registration.
    init(erasureRoot: SharedMediaNativeLockedRoot, rootURL: URL,
         checkpoint: @escaping () throws -> Void) throws {
        try checkpoint()
        let transfer = try erasureRoot.consumeCapture(at: rootURL)
        validateControls = checkpoint; self.rootURL = rootURL
        root = transfer.root; child = transfer.child; binding = transfer.binding
        rootBindingSHA256 = SharedMediaAcquisitionEncoding.digest(binding.marker)
    }

    deinit { Darwin.close(root); Darwin.close(child) }

    func check() throws {
        try Task.checkCancellation()
        try validateControls()
        try SharedMediaNativeLockedRoot.requireCapture((root, child), at: rootURL, binding: binding)
    }

    /// The empty partial's inode must be durable before bytes are copied. An
    /// unrecorded partial is never adopted, even if it has the expected name.
    func materialize(_ initial: SharedMediaCaptureArtifactLedger.Snapshot, bytes: Data,
                     container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                     boundary: SharedMediaCaptureArtifactWriter.Boundary,
                     partialSaved: (String) throws -> SharedMediaCaptureArtifactLedger.Snapshot,
                     complete: (String, String) throws -> SharedMediaCaptureArtifactLedger.Snapshot
    ) async throws -> SharedMediaCaptureArtifactLedger.Snapshot {
        let request = initial.request
        func current() throws -> SharedMediaCaptureArtifactLedger.Snapshot {
            _ = try authority.header(container); try check()
            guard authority.profile == request.profile, request.rootBindingSHA256 == rootBindingSHA256 else {
                throw SharedMediaStorageFailure.closed
            }
            let context = ModelContext(container); context.autosaveEnabled = false
            let value = try SharedMediaCaptureArtifactLedger.read(id: request.id, profile: request.profile,
                rootBindingSHA256: rootBindingSHA256, context: context)
            guard value.request == request else { throw SharedMediaStorageFailure.conflict }
            return value
        }
        guard bytes.count == request.byteCount,
              try current() == initial, initial.phase != .ready else { throw SharedMediaStorageFailure.conflict }
        var value = initial
        let observed = try inspect(value)
        guard !observed.ambiguous else { throw SharedMediaStorageFailure.closed }
        if value.phase == .reserved {
            let fd = openat(child, request.partialName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw SharedMediaStorageFailure.conflict }
            defer { Darwin.close(fd) }
            guard fsync(fd) == 0, fsync(child) == 0, let partial = try identity(request.partialName), partial.bytes == 0 else {
                throw SharedMediaStorageFailure.unavailable
            }
            try boundary(.afterPartialCreation)
            guard try current() == value else { throw SharedMediaStorageFailure.stale }
            value = try partialSaved(partial.exact)
            guard value.phase == .writing, value.stage?.partialIdentity == partial.exact,
                  try current() == value else { throw SharedMediaStorageFailure.conflict }
        }
        guard let saved = value.stage, saved.phase == .partial else { throw SharedMediaStorageFailure.conflict }
        if let final = try identity(request.finalName) {
            try requireInode(final, saved: saved.partialIdentity)
            try await verifyBytes(request.finalName, identity: final, request: request)
        } else {
            guard let partial = try identity(request.partialName) else { throw SharedMediaStorageFailure.conflict }
            try requireInode(partial, saved: saved.partialIdentity)
            let fd = openat(child, request.partialName, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
            // Transfer the descriptor once; await includes termination on
            // cancellation, so account drain cannot release the locks early.
            let writer = SharedMediaCaptureArtifactByteWriter(descriptor: fd)
            #if DEBUG
            await writer.configurePause(afterWriteChunk)
            #endif
            let header = try authority.header(container)
            try await writer.write(bytes, expected: partial, request: request)
            guard try authority.header(container) == header, try current() == value else { throw SharedMediaStorageFailure.stale }
            try boundary(.afterBytes)
            guard try current() == value, let written = try identity(request.partialName) else { throw SharedMediaStorageFailure.stale }
            try requireInode(written, saved: saved.partialIdentity)
            try await verifyBytes(request.partialName, identity: written, request: request)
            guard try current() == value, try identity(request.partialName) == written else { throw SharedMediaStorageFailure.stale }
            guard renameatx_np(child, request.partialName, child, request.finalName, UInt32(RENAME_EXCL)) == 0,
                  fsync(child) == 0 else { throw SharedMediaStorageFailure.unavailable }
            try boundary(.afterRename)
        }
        guard try current() == value, try identity(request.partialName) == nil,
              let final = try identity(request.finalName), final.bytes == request.byteCount else { throw SharedMediaStorageFailure.conflict }
        try requireInode(final, saved: saved.partialIdentity)
        let result = try complete(saved.partialIdentity, final.exact)
        guard result.phase == .ready, result.stage?.finalIdentity == final.exact, try current() == result else {
            throw SharedMediaStorageFailure.conflict
        }
        return result
    }

    /// Both forward and reverse joins are mandatory: a missing ready file and
    /// an unregistered file are equally unsafe. Enumeration is streaming and
    /// bounded by the already audited ledger count, not a pathname array.
    func verify(context: ModelContext, profile: SharedMediaNativeAppProfile,
                checkpoint: () throws -> Void = {}) async throws -> Inventory {
        try await verify(context: context, profile: profile, erasure: nil, checkpoint: checkpoint)
    }

    func verifyForErasure(context: ModelContext, erasure: SharedMediaNativeErasureAuditScope,
                          checkpoint: () throws -> Void) async throws -> Inventory {
        try await verify(context: context, profile: erasure.profile, erasure: erasure, checkpoint: checkpoint)
    }

    private func verify(context: ModelContext, profile: SharedMediaNativeAppProfile,
                        erasure: SharedMediaNativeErasureAuditScope?, checkpoint: () throws -> Void) async throws -> Inventory {
        var physical: Int64 = 0, ambiguous: Int64 = 0
        func current() throws { try checkpoint(); try check(); try erasure?.requireCurrent(context) }
        func read(_ id: UUID) throws -> SharedMediaCaptureArtifactLedger.Snapshot {
            if let erasure {
                return try SharedMediaCaptureArtifactLedger.auditErasureRead(id: id, profile: profile,
                    rootBindingSHA256: rootBindingSHA256, context: context, erasure: erasure)
            }
            return try SharedMediaCaptureArtifactLedger.auditRead(id: id, profile: profile,
                rootBindingSHA256: rootBindingSHA256, context: context)
        }
        func audit(_ inspect: (SharedMediaCaptureArtifactLedger.Snapshot) throws -> Void) throws -> SharedMediaCaptureArtifactStoreAudit.Snapshot {
            if let erasure {
                return try SharedMediaCaptureArtifactStoreAudit.verifyForErasure(context: context, erasure: erasure,
                    rootBindingSHA256: rootBindingSHA256, checkpoint: current, inspectArtifact: inspect)
            }
            return try SharedMediaCaptureArtifactStoreAudit.verify(context: context, profile: profile,
                rootBindingSHA256: rootBindingSHA256, checkpoint: current, inspectArtifact: inspect)
        }
        try current()
        let namespaceStamp = try directoryStamp()
        let ledger = try audit { value in
                let observed = try self.inspect(value)
                physical = try SharedMediaStoragePolicy.add(physical, observed.bytes)
                if observed.ambiguous { ambiguous = try SharedMediaStoragePolicy.add(ambiguous, 1) }
            }
        try await visit(maximum: ledger.artifacts) { name in
            try current()
            let token = name.hasSuffix(".partial") ? String(name.dropLast(8)) : name
            guard let id = UUID(uuidString: token), id.uuidString.lowercased() == token,
                  name == token || name == token + ".partial" else { throw SharedMediaStorageFailure.conflict }
            let value = try read(id)
            _ = try self.inspect(value)
            if !value.isRetiring, !name.hasSuffix(".partial"), let final = try self.identity(name) {
                try await self.verifyBytes(name, identity: final, request: value.request)
                try current()
                guard try read(id) == value else {
                    throw SharedMediaStorageFailure.stale
                }
            }
        }
        #if DEBUG
        try afterByteAudit?()
        #endif
        try current()
        // Re-read the bounded ledger after hashing and enumeration. Never save
        // this snapshot as a reusable authorization to bypass a later audit.
        var finalPhysical: Int64 = 0, finalAmbiguous: Int64 = 0
        let finalLedger = try audit { value in
                let observed = try self.inspect(value)
                finalPhysical = try SharedMediaStoragePolicy.add(finalPhysical, observed.bytes)
                if observed.ambiguous { finalAmbiguous = try SharedMediaStoragePolicy.add(finalAmbiguous, 1) }
            }
        guard finalLedger == ledger, finalPhysical == physical, finalAmbiguous == ambiguous,
              try directoryStamp() == namespaceStamp else {
            throw SharedMediaStorageFailure.stale
        }
        return .init(ledger: ledger, physicalBytes: physical, ambiguousEmptyPartials: ambiguous)
    }

    /// An empty partial without a saved inode stays ambiguous. Reporting it
    /// never upgrades the reservation to writing or grants cleanup authority.
    func inspect(_ value: SharedMediaCaptureArtifactLedger.Snapshot) throws -> (bytes: Int64, ambiguous: Bool) {
        try check()
        let request = value.request
        try request.validate()
        guard request.rootBindingSHA256 == rootBindingSHA256 else { throw SharedMediaStorageFailure.conflict }
        let partial = try identity(request.partialName), final = try identity(request.finalName)
        guard partial == nil || final == nil else { throw SharedMediaStorageFailure.conflict }
        if let release = value.acceptedRelease {
            guard let stage = value.stage, let remote = value.remoteStage else { throw SharedMediaStorageFailure.conflict }
            try release.validate(request: request, stage: stage, remote: remote)
            guard partial == nil,
                  release.releasedRevision == nil ? (final == nil || final?.exact == release.member.finalIdentity) : final == nil else {
                throw SharedMediaStorageFailure.conflict
            }
            try check()
            return (final?.bytes ?? 0, false)
        }
        if let retirement = value.retirement {
            try retirement.validate(request: request, stage: value.stage)
            if retirement.releasedRevision != nil {
                guard partial == nil, final == nil else { throw SharedMediaStorageFailure.conflict }
            } else {
                guard partial == nil || partial?.exact == retirement.partialIdentity,
                      final == nil || final?.exact == retirement.finalIdentity else { throw SharedMediaStorageFailure.conflict }
            }
            try check()
            return ((partial ?? final)?.bytes ?? 0, false)
        }
        switch value.phase {
        case .reserved:
            guard value.stage == nil, final == nil, partial == nil || partial?.bytes == 0 else {
                throw SharedMediaStorageFailure.conflict
            }
        case .writing:
            guard let stage = value.stage, stage.phase == .partial, let present = partial ?? final else {
                throw SharedMediaStorageFailure.conflict
            }
            try stage.validate(request)
            try requireInode(present, saved: stage.partialIdentity)
            guard present.bytes <= request.byteCount else { throw SharedMediaStorageFailure.conflict }
            if final != nil, present.bytes != request.byteCount { throw SharedMediaStorageFailure.conflict }
        case .ready:
            guard let stage = value.stage, stage.phase == .complete, partial == nil,
                  let final, stage.finalIdentity == final.exact else { throw SharedMediaStorageFailure.conflict }
            try stage.validate(request)
            guard final.bytes == request.byteCount else { throw SharedMediaStorageFailure.conflict }
        }
        try check()
        return ((partial ?? final)?.bytes ?? 0, value.phase == .reserved && partial != nil)
    }

    /// Records the exact deletion target under the held namespace. An empty
    /// unrecorded partial is cleanup-only and never becomes a saved source.
    func discardIdentities(_ value: SharedMediaCaptureArtifactLedger.Snapshot) throws -> (partial: String?, final: String?) {
        guard !value.isRetiring, value.request.format == .draftSourceV1, value.remoteStage == nil else {
            throw SharedMediaStorageFailure.closed
        }
        _ = try inspect(value)
        return (try identity(value.request.partialName)?.exact, try identity(value.request.finalName)?.exact)
    }

    /// Descriptive leaves for a separately audited, frozen erasure graph.
    /// No write or unlink authority is issued by this observation.
    func erasureEntries(_ value: SharedMediaCaptureArtifactLedger.Snapshot) throws -> [SharedMediaNativeErasureManifest.Entry] {
        _ = try inspect(value)
        return try [value.request.partialName, value.request.finalName].map { name in
            let observed = try identity(name)
            return .init(namespace: .capture, token: SharedMediaCaptureRootJournal.childName + "/" + name,
                kind: observed == nil ? .absent : .file, identity: observed?.exact)
        }
    }

    func preparedDiscardIdentities(_ value: SharedMediaCaptureArtifactLedger.Snapshot,
                                   preparationSHA256: String, context: ModelContext) throws -> (partial: String?, final: String?) {
        guard !value.isRetiring, value.remoteStage == nil else { throw SharedMediaStorageFailure.closed }
        try SharedMediaCapturePreparedAttempt.requireAbortMember(value.request, digest: preparationSHA256, context: context)
        _ = try inspect(value)
        return (try identity(value.request.partialName)?.exact, try identity(value.request.finalName)?.exact)
    }

    func unlinkDiscardedSource(_ value: SharedMediaCaptureArtifactLedger.Snapshot) throws {
        guard let retirement = value.retirement, retirement.releasedRevision == nil else { throw SharedMediaStorageFailure.closed }
        _ = try inspect(value)
        let paths = [(value.request.partialName, retirement.partialIdentity), (value.request.finalName, retirement.finalIdentity)]
        for (name, expected) in paths {
            try check()
            if let present = try identity(name) {
                guard present.exact == expected else { throw SharedMediaStorageFailure.conflict }
                guard unlinkat(child, name, 0) == 0 else { throw SharedMediaStorageFailure.unavailable }
            }
        }
        guard fsync(child) == 0 else { throw SharedMediaStorageFailure.unavailable }
        try check()
        guard try identity(value.request.partialName) == nil, try identity(value.request.finalName) == nil else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    /// Only an exact accepted-member intent can remove these files. Parent
    /// membership is revalidated by the release owner immediately before this
    /// synchronous operation, under its scan/account/root fences.
    func unlinkAcceptedArtifact(_ value: SharedMediaCaptureArtifactLedger.Snapshot) throws {
        guard let release = value.acceptedRelease, release.releasedRevision == nil,
              value.retirement == nil else { throw SharedMediaStorageFailure.closed }
        _ = try inspect(value)
        try check()
        if let present = try identity(value.request.finalName) {
            guard present.exact == release.member.finalIdentity else { throw SharedMediaStorageFailure.conflict }
            guard unlinkat(child, value.request.finalName, 0) == 0 else { throw SharedMediaStorageFailure.unavailable }
        }
        guard fsync(child) == 0 else { throw SharedMediaStorageFailure.unavailable }
        try check()
        guard try identity(value.request.partialName) == nil, try identity(value.request.finalName) == nil else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    /// A bounded upload read of a complete immutable member, under the same
    /// live operation that will send it. No URL or descriptor escapes.
    func readReady(_ artifact: SharedMediaCaptureArtifactLedger.Snapshot, container: ModelContainer,
                   authority: SharedMediaNativeAppOperationAuthority) async throws -> Data {
        let header = try authority.header(container), request = artifact.request
        guard request.profile == authority.profile, request.rootBindingSHA256 == rootBindingSHA256,
              !artifact.isRetiring, artifact.phase == .ready, let expected = try identity(request.finalName),
              expected.exact == artifact.stage?.finalIdentity else { throw SharedMediaStorageFailure.conflict }
        try check()
        let context = ModelContext(container); context.autosaveEnabled = false
        guard try SharedMediaCaptureArtifactLedger.read(id: request.id, profile: authority.profile,
            rootBindingSHA256: rootBindingSHA256, context: context) == artifact else { throw SharedMediaStorageFailure.stale }
        let fd = openat(child, request.finalName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
        let reader = SharedMediaCaptureArtifactByteReader(descriptor: fd)
        let bytes = try await reader.read(expected: expected, request: request, collect: true)
        try check()
        guard try authority.header(container) == header, try identity(request.finalName) == expected else {
            throw SharedMediaStorageFailure.stale
        }
        return bytes
    }

    private func requireInode(_ observed: SharedMediaInboxFileIdentity, saved: String) throws {
        let fields = saved.split(separator: ":")
        guard fields.count == 7, String(observed.device) == fields[0], String(observed.inode) == fields[1] else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private func verifyBytes(_ name: String, identity expected: SharedMediaInboxFileIdentity,
                             request: SharedMediaCaptureArtifactRequest) async throws {
        guard expected.bytes == request.byteCount else { throw SharedMediaStorageFailure.conflict }
        let fd = openat(child, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
        // The actor owns and closes this descriptor. Hashing stays off the main
        // actor, with no pathname reopen, detached task or retained media Data.
        let reader = SharedMediaCaptureArtifactByteReader(descriptor: fd)
        try await reader.verify(expected: expected, request: request)
        try check()
        guard try identity(name) == expected else { throw SharedMediaStorageFailure.conflict }
    }

    private func identity(_ name: String) throws -> SharedMediaInboxFileIdentity? {
        var info = stat()
        if fstatat(child, name, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw SharedMediaStorageFailure.conflict }
            return nil
        }
        return try value(info)
    }

    private func directoryStamp() throws -> String {
        var info = stat()
        guard fstat(child, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw SharedMediaStorageFailure.unavailable }
        return "\(info.st_dev):\(info.st_ino):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
    }

    private func value(_ info: stat) throws -> SharedMediaInboxFileIdentity {
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_size >= 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        return .init(device: Int64(info.st_dev), inode: Int64(info.st_ino), bytes: info.st_size,
            exact: "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)")
    }

    private func visit(maximum: Int64, _ body: (String) async throws -> Void) async throws {
        // Opening '.' relative to the held namespace gives enumeration its own
        // offset; dup would share an offset across repeated audits.
        let fd = openat(child, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.unavailable }
        guard let directory = fdopendir(fd) else { Darwin.close(fd); throw SharedMediaStorageFailure.unavailable }
        defer { closedir(directory) }
        var count: Int64 = 0
        while true {
            try check(); errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw SharedMediaStorageFailure.unavailable }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            count = try SharedMediaStoragePolicy.add(count, 1)
            guard count <= maximum else { throw SharedMediaStorageFailure.conflict }
            try await body(name)
        }
    }
}

/// The descriptor is transferred once and never escapes this I/O actor.
private actor SharedMediaCaptureArtifactByteReader {
    private let descriptor: Int32
    init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { Darwin.close(descriptor) }

    func verify(expected: SharedMediaInboxFileIdentity, request: SharedMediaCaptureArtifactRequest) throws {
        _ = try read(expected: expected, request: request, collect: false)
    }

    func read(expected: SharedMediaInboxFileIdentity, request: SharedMediaCaptureArtifactRequest, collect: Bool) throws -> Data {
        func requireIdentity() throws {
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
                  "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)" == expected.exact else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        try requireIdentity()
        var hash = SHA256(), count: Int64 = 0, buffer = [UInt8](repeating: 0, count: 65_536), bytes = Data()
        while true {
            try Task.checkCancellation()
            let amount = Darwin.read(descriptor, &buffer, buffer.count)
            if amount < 0 && errno == EINTR { continue }
            guard amount >= 0 else { throw SharedMediaStorageFailure.unavailable }
            if amount == 0 { break }
            count = try SharedMediaStoragePolicy.add(count, Int64(amount))
            guard count <= request.byteCount else { throw SharedMediaStorageFailure.conflict }
            hash.update(data: buffer.prefix(amount))
            if collect { bytes.append(contentsOf: buffer.prefix(amount)) }
        }
        try Task.checkCancellation(); try requireIdentity()
        guard count == request.byteCount, hash.finalize().map({ String(format: "%02x", $0) }).joined() == request.sha256 else {
            throw SharedMediaStorageFailure.conflict
        }
        return bytes
    }
}

/// Bounded I/O runs away from the main actor. A recorded partial may be
/// rewritten after interruption, but its descriptor must still name that inode.
private actor SharedMediaCaptureArtifactByteWriter {
    private let descriptor: Int32
    #if DEBUG
    private var pause: (@Sendable (Int) async -> Void)?
    func configurePause(_ pause: (@Sendable (Int) async -> Void)?) { self.pause = pause }
    #endif
    init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { Darwin.close(descriptor) }

    func write(_ bytes: Data, expected: SharedMediaInboxFileIdentity,
               request: SharedMediaCaptureArtifactRequest) async throws {
        try Task.checkCancellation()
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)" == expected.exact,
              bytes.count == request.byteCount, SharedMediaAcquisitionEncoding.digest(bytes) == request.sha256 else {
            throw SharedMediaStorageFailure.conflict
        }
        guard ftruncate(descriptor, 0) == 0 else { throw SharedMediaStorageFailure.unavailable }
        var offset = 0
        while offset < bytes.count {
            try Task.checkCancellation()
            let count = try bytes.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { throw SharedMediaStorageFailure.invalid }
                return Darwin.pwrite(descriptor, base.advanced(by: offset), min(65_536, buffer.count - offset), off_t(offset))
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw SharedMediaStorageFailure.unavailable }
            offset += count
            #if DEBUG
            await pause?(offset)
            #endif
        }
        guard fsync(descriptor) == 0 else { throw SharedMediaStorageFailure.unavailable }
        try Task.checkCancellation()
    }
}
