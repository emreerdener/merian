import Darwin
import Foundation

/// Stable, zero-byte control file shared by all participating store owners.
/// It is never unlinked, upgraded or used for media-capacity accounting.
@MainActor
final class SharedMediaStoreReadFence {
    enum Access { case standalone, sharedWriter }
    static let name = ".merian-media-fence"
    private let parent: URL
    private let parentDescriptor: Int32
    private let descriptor: Int32
    private let parentIdentity: String
    private let identity: String
    private var invalidated = false

    init(store: URL, access: Access = .standalone, requireExisting: Bool = false,
         creationAnchor: URL? = nil,
         synchronization: SharedMediaFenceSynchronization = .init()) throws {
        parent = store.deletingLastPathComponent()
        let directory = try Self.openParent(parent, creationAnchor: creationAnchor, synchronization: synchronization)
        var retained = false
        defer { if !retained { Darwin.close(directory) } }
        var parentInfo = stat()
        guard fstat(directory, &parentInfo) == 0 else { throw PhotoPreparationFailure.unavailable }
        var fd = requireExisting
            ? openat(directory, Self.name, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
            : openat(directory, Self.name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        if fd < 0 && !requireExisting {
            guard errno == EEXIST else { throw PhotoPreparationFailure.unavailable }
            fd = openat(directory, Self.name, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else { throw PhotoPreparationFailure.inconsistentOwnership }
        defer { if !retained { Darwin.close(fd) } }
        let fileIdentity = try Self.validate(fd: fd, parent: directory)
        guard flock(fd, (access == .standalone ? LOCK_SH : LOCK_EX) | LOCK_NB) == 0 else {
            switch access {
            case .standalone: throw PhotoPreparationFailure.busy
            case .sharedWriter: throw SharedMediaStorageFailure.busy
            }
        }
        guard try Self.validate(fd: fd, parent: directory) == fileIdentity else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        // EEXIST can race a creator before its fsync, or follow failed setup.
        // Every opener establishes durability before any work can be admitted.
        try synchronization.synchronize(file: fd, parent: directory)
        let namedParent = try SharedMediaStorageFileOwner.openDirectory(parent)
        defer { Darwin.close(namedParent) }
        var namedParentInfo = stat()
        guard fstat(namedParent, &namedParentInfo) == 0,
              Self.identity(namedParentInfo) == Self.identity(parentInfo),
              try Self.validate(fd: fd, parent: directory) == fileIdentity else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        parentDescriptor = directory
        parentIdentity = Self.identity(parentInfo)
        descriptor = fd
        identity = fileIdentity
        retained = true
    }

    deinit { Darwin.close(descriptor); Darwin.close(parentDescriptor) }

    struct Binding: Equatable {
        let parent: String
        let control: String
    }

    func binding() throws -> Binding {
        try check()
        return Binding(parent: parentIdentity, control: identity)
    }

    /// Bootstrap alone supplies a trusted, already-existing container anchor.
    /// Other owners never create a missing store parent.
    private static func openParent(_ parent: URL, creationAnchor: URL?,
                                   synchronization: SharedMediaFenceSynchronization) throws -> Int32 {
        guard let anchor = creationAnchor else {
            return try SharedMediaStorageFileOwner.openDirectory(parent)
        }
        guard anchor.isFileURL, parent.isFileURL,
              !parent.pathComponents.contains(".."), !anchor.pathComponents.contains("..") else {
            throw SharedMediaStorageFailure.invalid
        }
        let rootParts = anchor.standardizedFileURL.pathComponents
        let parentParts = parent.standardizedFileURL.pathComponents
        guard parentParts.starts(with: rootParts) else { throw SharedMediaStorageFailure.invalid }
        var fd = try SharedMediaStorageFileOwner.openDirectory(anchor)
        do {
            for component in parentParts.dropFirst(rootParts.count) {
                var next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if next < 0 && errno == ENOENT {
                    guard mkdirat(fd, component, 0o700) == 0 || errno == EEXIST else {
                        throw SharedMediaStorageFailure.unavailable
                    }
                    next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                }
                guard next >= 0 else { throw SharedMediaStorageFailure.unavailable }
                // An existing child may survive an earlier interrupted setup.
                // Re-establish each parent entry's durability before admission.
                do { try synchronization.synchronizeParent(fd) } catch { Darwin.close(next); throw error }
                Darwin.close(fd)
                fd = next
            }
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    private static func identity(_ info: stat) -> String { "\(info.st_dev):\(info.st_ino)" }

    private static func validate(fd: Int32, parent: Int32) throws -> String {
        var held = stat(), named = stat()
        guard fstat(fd, &held) == 0, fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              held.st_mode & S_IFMT == S_IFREG, named.st_mode & S_IFMT == S_IFREG,
              held.st_nlink == 1, named.st_nlink == 1, held.st_size == 0, named.st_size == 0,
              identity(held) == identity(named) else { throw PhotoPreparationFailure.inconsistentOwnership }
        return identity(held)
    }

    func check() throws {
        guard !invalidated else { throw PhotoPreparationFailure.inconsistentOwnership }
        do {
            let namedFD = try SharedMediaStorageFileOwner.openDirectory(parent)
            defer { Darwin.close(namedFD) }
            var held = stat(), named = stat()
            guard fstat(parentDescriptor, &held) == 0, fstat(namedFD, &named) == 0,
                  Self.identity(held) == parentIdentity, Self.identity(named) == parentIdentity,
                  try Self.validate(fd: descriptor, parent: parentDescriptor) == identity else {
                throw PhotoPreparationFailure.inconsistentOwnership
            }
        } catch {
            // Never repair, switch or reacquire a replaced fence in this owner.
            invalidated = true
            throw error
        }
    }
}

enum SharedMediaFenceSyncStage: Sendable { case file, parent }

struct SharedMediaFenceSynchronization: Sendable {
    #if DEBUG
    private let failing: SharedMediaFenceSyncStage?
    init(failing: SharedMediaFenceSyncStage? = nil) { self.failing = failing }
    #else
    init() {}
    #endif

    func synchronizeParent(_ descriptor: Int32) throws {
        #if DEBUG
        if failing == .parent { throw PhotoPreparationFailure.unavailable }
        #endif
        guard fsync(descriptor) == 0 else { throw PhotoPreparationFailure.unavailable }
    }

    func synchronize(file: Int32, parent: Int32) throws {
        for (stage, fd) in [(SharedMediaFenceSyncStage.file, file), (.parent, parent)] {
            #if DEBUG
            if stage == failing { throw PhotoPreparationFailure.unavailable }
            #endif
            guard fsync(fd) == 0 else { throw PhotoPreparationFailure.unavailable }
        }
    }
}
