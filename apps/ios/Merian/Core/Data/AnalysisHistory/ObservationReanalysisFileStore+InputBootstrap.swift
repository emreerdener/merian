import Darwin
import Foundation

extension ObservationReanalysisFileStore {
    /// Read-only outgoing-library presence, never deletion or bootstrap authority.
    /// Any entry counts, including symlinks or a crash-created namespace without
    /// metadata. Failure to inspect the exact Documents root is not absence.
    nonisolated static func inputNamespaceIsPresent(documents: URL) throws -> Bool {
        let root = open(documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw Failure.unavailable }
        defer { Darwin.close(root) }
        var held = stat(), namedRoot = stat(), entry = stat()
        guard fstat(root, &held) == 0 else { throw Failure.unavailable }
        let present: Bool
        if fstatat(root, "ReanalysisInputs", &entry, AT_SYMLINK_NOFOLLOW) == 0 { present = true } else {
            guard errno == ENOENT else { throw Failure.unavailable }
            present = false
        }
        guard lstat(documents.path, &namedRoot) == 0,
              namedRoot.st_mode & S_IFMT == S_IFDIR,
              held.st_dev == namedRoot.st_dev, held.st_ino == namedRoot.st_ino,
              held.st_birthtimespec.tv_sec == namedRoot.st_birthtimespec.tv_sec,
              held.st_birthtimespec.tv_nsec == namedRoot.st_birthtimespec.tv_nsec else { throw Failure.conflict }
        return present
    }

    /// Explicit fresh preparation only. The MainActor caller retains the exact
    /// startup/store fence and source/account lease across this whole operation.
    /// readState returns nil only after a fresh check of all input ownership.
    func initializeInputs(
        readState: @escaping @MainActor @Sendable () throws -> InputState?,
        commit: @escaping @MainActor @Sendable (InputLedger) throws -> Void,
        validate: @escaping @MainActor @Sendable () throws -> Void
    ) async throws {
        try Task.checkCancellation()
        let root = open(documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw Failure.unavailable }
        defer { Darwin.close(root) }
        guard flock(root, LOCK_SH | LOCK_NB) == 0 else { throw Failure.busy }
        let rootIdentity = try inputIdentity(root)
        try await validate()
        try checkInputRoot(root, identity: rootIdentity)
        var info = stat()
        if fstatat(root, "ReanalysisInputs", &info, AT_SYMLINK_NOFOLLOW) == 0 {
            let namespace = try existingDirectory("ReanalysisInputs", inside: root)
            defer { Darwin.close(namespace) }
            guard flock(namespace, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
            guard let state = try await readState() else { throw Failure.incomplete }
            try await validate()
            try checkInputRoot(root, identity: rootIdentity)
            try checkInputBootstrap(root: root, namespace: namespace, ledger: state.ledger)
            return
        }
        guard errno == ENOENT else { throw Failure.unavailable }
        // Conversion may lose the shared lock briefly. Recheck every physical
        // and metadata premise after acquiring exclusive Documents ownership.
        guard flock(root, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        try await validate()
        try checkInputRoot(root, identity: rootIdentity)
        guard fstatat(root, "ReanalysisInputs", &info, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT, try await readState() == nil else { throw Failure.conflict }
        try await validate()
        try checkInputRoot(root, identity: rootIdentity)
        guard mkdirat(root, "ReanalysisInputs", 0o700) == 0 else { throw Failure.conflict }
        let namespace = try existingDirectory("ReanalysisInputs", inside: root)
        defer { Darwin.close(namespace) }
        guard flock(namespace, LOCK_EX | LOCK_NB) == 0 else { throw Failure.busy }
        var directories: [InputReceipt.Identity] = []
        for index in 0..<InputReceipt.maximumReservations {
            let name = String(index)
            guard mkdirat(namespace, name, 0o700) == 0 else { throw Failure.conflict }
            let slot = try existingDirectory(name, inside: namespace)
            defer { Darwin.close(slot) }
            guard fsync(slot) == 0 else { throw Failure.unavailable }
            directories.append(try inputIdentity(slot))
        }
        guard fsync(namespace) == 0, fsync(root) == 0 else { throw Failure.unavailable }
        let ledger = try InputLedger(namespaceGeneration: UUID(), documents: rootIdentity,
            namespace: inputIdentity(namespace), directories: directories)
        try checkInputBootstrap(root: root, namespace: namespace, ledger: ledger)
        try await validate()
        try await commit(ledger)
        // Save uncertainty never removes the newly created physical namespace.
        // A later explicit preparation requires its complete exact baseline.
        try await validate()
        try checkInputRoot(root, identity: rootIdentity)
        try checkInputBootstrap(root: root, namespace: namespace, ledger: ledger)
    }

    private func checkInputRoot(_ descriptor: Int32, identity: InputReceipt.Identity) throws {
        let named = open(documents.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard named >= 0 else { throw Failure.conflict }
        defer { Darwin.close(named) }
        guard try inputIdentity(descriptor) == identity,
              try inputIdentity(named) == identity else { throw Failure.conflict }
    }

    private func checkInputBootstrap(root: Int32, namespace: Int32, ledger: InputLedger) throws {
        try ledger.validate()
        try checkInputRoot(root, identity: ledger.documents)
        guard try inputIdentity(namespace) == ledger.namespace,
              sameDirectory(namespace, named: "ReanalysisInputs", inside: root),
              Set(try names(in: namespace)) == Set((0..<InputReceipt.maximumReservations).map(String.init)) else {
            throw Failure.conflict
        }
        for slot in ledger.slots {
            let name = String(slot.index), descriptor = try existingDirectory(String(slot.index), inside: namespace)
            defer { Darwin.close(descriptor) }
            guard try inputIdentity(descriptor) == slot.directory,
                  sameDirectory(descriptor, named: name, inside: namespace) else { throw Failure.conflict }
        }
    }
}
