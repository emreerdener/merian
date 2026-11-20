import Darwin
import Foundation

extension ObservationReanalysisFileStore {
    typealias InputReceipt = ObservationReanalysisInputReceipt
    typealias InputLedger = ObservationReanalysisInputLedger
    typealias InputState = ObservationReanalysisInputPersistence.Snapshot
    typealias InputAdvance = @MainActor @Sendable (InputReceipt, InputReceipt) throws -> InputReceipt

    struct InputRequest: Equatable, Sendable {
        let ownerID: UUID
        let parentID: UUID
        let childID: UUID
        let planDigest: String
    }
    struct InputToken: Sendable {
        let id: UUID
        let receipt: InputReceipt
        let url: URL
    }
    /// Owned exclusively by the FileStore actor. Descriptors never cross the
    /// actor boundary except for the awaited bounded FileIO copy operation.
    final class InputLease {
        let tokenID = UUID()
        let root: Int32
        let namespace: Int32
        var directory: Int32 = -1
        var file: Int32 = -1
        var namespaceLocked = false
        var receipt: InputReceipt?

        init(root: Int32, namespace: Int32) { self.root = root; self.namespace = namespace }
        deinit {
            if file >= 0 { Darwin.close(file) }
            if directory >= 0 { Darwin.close(directory) }
            Darwin.close(namespace); Darwin.close(root)
        }
        func releaseAdmissionLock() {
            if namespaceLocked { flock(namespace, LOCK_UN); namespaceLocked = false }
        }
    }

    /// Reservation and stable identity commits precede every nonempty byte.
    /// On failure, the durable receipt retains quota; no best-effort deletion can
    /// turn an uncertain copy into an unaccounted temporary file.
    func createInput(_ request: InputRequest,
                     inspect: @escaping @MainActor @Sendable () throws -> InputState,
                     reserve: @escaping @MainActor @Sendable (InputReceipt) throws -> InputReceipt,
                     advance: @escaping InputAdvance,
                     validate: @escaping @MainActor @Sendable () throws -> Void,
                     copy: @escaping @Sendable (Int32) async -> Bool) async throws -> InputToken {
        let child = request.childID
        guard activeChildren.insert(child).inserted else { throw Failure.busy }
        defer { activeChildren.remove(child) }
        guard inputLeases[child] == nil else { throw Failure.busy }
        try Task.checkCancellation()
        let held = try openInputNamespace()
        guard flock(held.namespace, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        held.namespaceLocked = true
        defer { held.releaseAdmissionLock() }
        try await validate()
        let state = try await inspect()
        let ledger = state.ledger
        guard let slot = ledger.slots.first(where: { $0.state != .active }) else { throw Failure.busy }
        held.directory = try existingDirectory(String(slot.index), inside: held.namespace)
        guard flock(held.directory, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        let requested = try InputReceipt(ownerID: request.ownerID, parentID: request.parentID,
            childID: child, planDigest: request.planDigest, documents: ledger.documents, namespace: ledger.namespace,
            namespaceGeneration: ledger.namespaceGeneration, slot: slot.index, useGeneration: UUID(), directory: slot.directory)
        try checkInputParents(held, receipt: requested)
        guard try names(in: held.directory).isEmpty else { throw Failure.conflict }
        // Fresh metadata is validated again inside the atomic reservation while
        // the same stable slot lock excludes cleanup and competing creators.
        let reserved = try await reserve(requested)
        guard reserved == requested else { throw Failure.conflict }
        held.receipt = reserved
        let boundDirectory = reserved
        try Task.checkCancellation()
        try checkInputParents(held, receipt: boundDirectory)
        guard try names(in: held.directory).isEmpty else { throw Failure.conflict }
        held.file = openat(held.directory, "input.mp4", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard held.file >= 0, fsync(held.file) == 0, fsync(held.directory) == 0 else { throw Failure.unavailable }
        let boundFile = try boundDirectory.binding(file: inputIdentity(held.file))
        try checkInputFile(held, receipt: boundFile, permitsAbsence: false)
        guard try await advance(boundDirectory, boundFile) == boundFile else { throw Failure.conflict }
        held.receipt = boundFile
        try Task.checkCancellation()
        try checkInputParents(held, receipt: boundFile)
        try checkInputFile(held, receipt: boundFile, permitsAbsence: false)
        held.releaseAdmissionLock()
        guard await copy(held.file) else { throw Failure.unavailable }
        try Task.checkCancellation()
        try await validate()
        try checkInputParents(held, receipt: boundFile)
        try checkInputFile(held, receipt: boundFile, permitsAbsence: false)
        guard fsync(held.file) == 0, fsync(held.directory) == 0,
              fsync(held.namespace) == 0, fsync(held.root) == 0 else { throw Failure.unavailable }
        let copied = try boundFile.copied(snapshot: inputSnapshot(held.file))
        guard try await advance(boundFile, copied) == copied else { throw Failure.conflict }
        held.receipt = copied
        try Task.checkCancellation()
        try checkInputParents(held, receipt: copied)
        try checkInputFile(held, receipt: copied, permitsAbsence: false)
        inputLeases[child] = held
        return InputToken(id: held.tokenID, receipt: copied,
            url: documents.appendingPathComponent("ReanalysisInputs/\(copied.slot)/input.mp4"))
    }

    /// Existing-only reconciliation after a save uncertainty. Never creates a
    /// directory, copies bytes, or converts a partial input into a usable one.
    func recoverInput(_ receipt: InputReceipt,
                      read: @escaping @MainActor @Sendable () throws -> InputReceipt) async throws -> InputToken {
        guard receipt.phase == .copied, activeChildren.insert(receipt.childID).inserted else { throw Failure.busy }
        defer { activeChildren.remove(receipt.childID) }
        let held: InputLease
        if let existing = inputLeases[receipt.childID] {
            guard existing.receipt == receipt else { throw Failure.conflict }
            held = existing
        } else { held = try openInput(receipt) }
        guard try await read() == receipt else { throw Failure.conflict }
        try Task.checkCancellation()
        try checkInputParents(held, receipt: receipt)
        try checkInputFile(held, receipt: receipt, permitsAbsence: false)
        inputLeases[receipt.childID] = held
        return InputToken(id: held.tokenID, receipt: receipt,
            url: documents.appendingPathComponent("ReanalysisInputs/\(receipt.slot)/input.mp4"))
    }

    func inputIsCurrent(_ token: InputToken,
                        read: @escaping @MainActor @Sendable () throws -> InputReceipt) async throws {
        guard activeChildren.insert(token.receipt.childID).inserted else { throw Failure.busy }
        defer { activeChildren.remove(token.receipt.childID) }
        guard let held = inputLeases[token.receipt.childID], held.tokenID == token.id,
              held.receipt == token.receipt, token.receipt.phase == .copied else { throw Failure.conflict }
        guard try await read() == token.receipt else { throw Failure.conflict }
        try Task.checkCancellation()
        try checkInputParents(held, receipt: token.receipt)
        try checkInputFile(held, receipt: token.receipt, permitsAbsence: false)
    }

    /// Actual consumers must have exited before the caller relinquishes its
    /// exact lease. This only releases descriptors; durable ownership remains.
    func releaseInputLease(_ token: InputToken) -> Bool {
        let child = token.receipt.childID
        guard !activeChildren.contains(child) else { return false }
        guard let held = inputLeases[child] else { return true }
        guard held.tokenID == token.id else { return false }
        inputLeases[child] = nil
        return true
    }

    /// The live token may retire its own lease only after actual task exit.
    /// Backlog recovery has no token and must leave every live lease alone.
    func eraseInput(child: UUID, token: InputToken? = nil,
                    read: @escaping @MainActor @Sendable () throws -> InputReceipt,
                    advance: @escaping InputAdvance) async throws {
        guard activeChildren.insert(child).inserted else { throw Failure.busy }
        defer { activeChildren.remove(child) }
        try Task.checkCancellation()
        let receipt = try await read()
        guard receipt.childID == child else { throw Failure.conflict }
        // A completed child may refer to a slot now owned by a successor.
        // Metadata exact replay is terminal; never inspect that slot's contents.
        if receipt.phase == .complete {
            if let existing = inputLeases[child] {
                guard let token, token.id == existing.tokenID,
                      let retiring = existing.receipt, retiring.phase == .erasing,
                      try retiring.completed() == receipt else { throw Failure.busy }
                inputLeases[child] = nil
            }
            return
        }
        let held: InputLease
        if let existing = inputLeases[child] {
            guard let token, token.id == existing.tokenID,
                  token.receipt.hasSameReservation(as: receipt),
                  token.receipt.directory == receipt.directory, token.receipt.file == receipt.file,
                  token.receipt.snapshot == receipt.snapshot else { throw Failure.busy }
            held = existing
        } else { held = try openInputForErasure(receipt) }
        guard try await read() == receipt else { throw Failure.conflict }
        try Task.checkCancellation()
        try checkInputParents(held, receipt: receipt)
        try checkInputErasureContents(held, receipt: receipt)
        let retiring: InputReceipt
        if receipt.phase == .erasing { retiring = receipt } else {
            retiring = try receipt.retiring()
            guard try await advance(receipt, retiring) == retiring else { throw Failure.conflict }
        }
        held.receipt = retiring
        try Task.checkCancellation()
        try checkInputParents(held, receipt: retiring)
        try checkInputErasureContents(held, receipt: retiring)
        if held.directory >= 0 {
            var info = stat()
            if fstatat(held.directory, "input.mp4", &info, AT_SYMLINK_NOFOLLOW) == 0 {
                // Full held/named checks immediately precede this unlink; no
                // suspension or filename-only authority intervenes.
                try checkInputFile(held, receipt: retiring, permitsAbsence: false)
                guard unlinkat(held.directory, "input.mp4", 0) == 0 else { throw Failure.cleanupFailed }
            } else if errno != ENOENT { throw Failure.cleanupFailed }
            guard fsync(held.directory) == 0 else { throw Failure.cleanupFailed }
        }
        guard fsync(held.namespace) == 0, fsync(held.root) == 0 else { throw Failure.cleanupFailed }
        try checkInputParents(held, receipt: retiring)
        try requireInputAbsent(held, receipt: retiring)
        let completed = try retiring.completed()
        guard try await advance(retiring, completed) == completed else { throw Failure.conflict }
        // No post-commit cancellation may resurrect this input or authorize a
        // second copy. The caller may separately suppress stale presentation.
        held.receipt = completed
        inputLeases[child] = nil
    }

    private func openInputForErasure(_ receipt: InputReceipt) throws -> InputLease {
        let held = try openInputNamespace()
        try checkInputParents(held, receipt: receipt, directoryRequired: false)
        held.directory = try existingDirectory(String(receipt.slot), inside: held.namespace)
        guard flock(held.directory, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        try checkInputParents(held, receipt: receipt)
        if receipt.file != nil {
            held.file = openat(held.directory, "input.mp4", O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            if held.file < 0 {
                guard errno == ENOENT, receipt.phase == .erasing else { throw Failure.conflict }
            }
        }
        held.receipt = receipt
        return held
    }

    private func checkInputErasureContents(_ held: InputLease, receipt: InputReceipt) throws {
        if receipt.file == nil {
            guard try names(in: held.directory).isEmpty else { throw Failure.conflict }
            return
        }
        try checkInputFile(held, receipt: receipt, permitsAbsence: receipt.phase == .erasing || receipt.phase == .complete)
    }

    private func requireInputAbsent(_ held: InputLease, receipt: InputReceipt) throws {
        var info = stat()
        guard held.directory >= 0, fstatat(held.directory, "input.mp4", &info, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT, try names(in: held.directory).isEmpty else { throw Failure.conflict }
    }

    private func openInputNamespace() throws -> InputLease {
        let root = open(documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw Failure.unavailable }
        do {
            guard flock(root, LOCK_SH | LOCK_NB) == 0 else { throw Failure.busy }
            let namespace = try existingDirectory("ReanalysisInputs", inside: root)
            return InputLease(root: root, namespace: namespace)
        } catch { Darwin.close(root); throw error }
    }

    private func openInput(_ receipt: InputReceipt) throws -> InputLease {
        let held = try openInputNamespace()
        try checkInputParents(held, receipt: receipt, directoryRequired: false)
        held.directory = try existingDirectory(String(receipt.slot), inside: held.namespace)
        guard flock(held.directory, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        try checkInputParents(held, receipt: receipt)
        if receipt.file != nil {
            held.file = openat(held.directory, "input.mp4", O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
            guard held.file >= 0 else { throw Failure.incomplete }
        }
        held.receipt = receipt
        return held
    }

    func inputIdentity(_ descriptor: Int32) throws -> InputReceipt.Identity {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw Failure.unavailable }
        let identity = InputReceipt.Identity(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: UInt64(info.st_ino),
            birthSeconds: Int64(info.st_birthtimespec.tv_sec), birthNanoseconds: Int64(info.st_birthtimespec.tv_nsec))
        guard identity.isValid else { throw Failure.conflict }
        return identity
    }

    private func inputSnapshot(_ descriptor: Int32) throws -> InputReceipt.Snapshot {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw Failure.unavailable }
        let snapshot = InputReceipt.Snapshot(byteCount: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec))
        guard snapshot.isValid else { throw Failure.conflict }
        return snapshot
    }

    private func checkInputParents(_ held: InputLease, receipt: InputReceipt, directoryRequired: Bool = true) throws {
        let namedRoot = open(documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard namedRoot >= 0 else { throw Failure.conflict }
        defer { Darwin.close(namedRoot) }
        guard try inputIdentity(namedRoot) == receipt.documents,
              try inputIdentity(held.root) == receipt.documents,
              try inputIdentity(held.namespace) == receipt.namespace,
              sameDirectory(held.namespace, named: "ReanalysisInputs", inside: held.root) else { throw Failure.conflict }
        if directoryRequired {
            let directory = receipt.directory
            guard held.directory >= 0, try inputIdentity(held.directory) == directory,
                  sameDirectory(held.directory, named: String(receipt.slot), inside: held.namespace) else { throw Failure.conflict }
        }
    }

    private func checkInputFile(_ held: InputLease, receipt: InputReceipt, permitsAbsence: Bool) throws {
        guard held.directory >= 0 else { throw Failure.incomplete }
        var named = stat()
        if fstatat(held.directory, "input.mp4", &named, AT_SYMLINK_NOFOLLOW) != 0 {
            guard permitsAbsence, errno == ENOENT, try names(in: held.directory).isEmpty else { throw Failure.conflict }
            return
        }
        guard let identity = receipt.file, held.file >= 0,
              named.st_mode & S_IFMT == S_IFREG, named.st_nlink == 1,
              try inputIdentity(held.file) == identity,
              named.st_dev == dev_t(bitPattern: UInt32(truncatingIfNeeded: identity.device)), named.st_ino == identity.inode,
              try names(in: held.directory) == ["input.mp4"] else { throw Failure.conflict }
        var actual = stat()
        guard fstat(held.file, &actual) == 0, actual.st_mode & S_IFMT == S_IFREG, actual.st_nlink == 1,
              actual.st_size >= 0, actual.st_size <= off_t(ScanMediaPayloadPolicy.maxSavedVideoBytes) else { throw Failure.conflict }
        if let snapshot = receipt.snapshot {
            guard try inputSnapshot(held.file) == snapshot else { throw Failure.conflict }
        }
    }
}
