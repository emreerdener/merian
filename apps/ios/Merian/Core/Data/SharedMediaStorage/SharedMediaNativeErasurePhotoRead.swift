import Darwin
import Foundation

/// Read-only byte observations for the erasure manifest. The caller supplies
/// facts from its frozen, semantically audited graph; these values grant no
/// normal admission, write, repair or unlink capability.
enum SharedMediaNativeErasurePhotoRead {
    enum Request {
        case pending(SharedMediaAcquisitionIntent, SharedMediaNativePendingClosure?)
        /// Used only by the full erasure projection after its semantic audit.
        /// The frozen graph binds the request fingerprint; directory and leaf
        /// entries bind the observed closure. This never settles the receipt.
        case interrupted(SharedMediaAcquisitionIntent)
        case original(PhotoPreparationFile, SharedMediaPhotoRetirementIdentity, retiring: Bool)
        case derivative(PhotoPreparationFile, SharedMediaNativePairFileState.Work)

        var token: String {
            switch self {
            case .pending(let request, _), .interrupted(let request): request.finalToken
            case .original(let file, _, _), .derivative(let file, _): file.token
            }
        }
        var maximum: Int64 {
            switch self {
            case .pending(let request, _), .interrupted(let request): request.maximumBytes
            case .original(let file, _, _), .derivative(let file, _): file.byteCount
            }
        }
    }

    struct Observation: Equatable {
        let parent: String?
        let namespace: String
        let partial: String?
        let final: String?

        func entries(token: String) -> [SharedMediaNativeErasureManifest.Entry] {
            [(token, final), (token + ".partial", partial)].map { name, identity in
                .init(namespace: .photo, token: "PhotoPreparation/" + name,
                    kind: identity == nil ? .absent : .file, identity: identity)
            }
        }
    }

    /// Opens only the two canonical ancestor components beneath the already
    /// held namespace. Missing ancestors are observed, never created.
    static func inspect(_ request: Request, namespace: Int32, ownerID: UUID,
                        checkpoint: @escaping () throws -> Void) throws -> Observation {
        try checkpoint(); try Task.checkCancellation()
        let entry = SharedMediaNativeErasureManifest.Entry(namespace: .photo,
            token: "PhotoPreparation/" + request.token, kind: .absent, identity: nil)
        try entry.validate(ownerID: ownerID)
        let parts = request.token.split(separator: "/").map(String.init)
        guard parts.count == 3, request.maximum > 0, request.maximum <= PhotoPreparationPolicy.original else {
            throw SharedMediaStorageFailure.conflict
        }
        let owner = try openDirectory(namespace, parts[0])
        defer { if owner >= 0 { Darwin.close(owner) } }
        let package = try openDirectory(owner, parts[1])
        defer { if package >= 0 { Darwin.close(package) } }
        let ownerIdentity = try directoryIdentity(owner), packageIdentity = try directoryIdentity(package)
        func current() throws {
            try checkpoint(); try Task.checkCancellation()
            try requireDirectory(owner, parent: namespace, name: parts[0], expected: ownerIdentity)
            try requireDirectory(package, parent: owner, name: parts[1], expected: packageIdentity)
        }
        try current()
        let value = try SharedMediaInboxDestinationAccess.inspectErasure(parent: package, namespace: namespace,
            name: parts[2], request: request, check: current)
        try current(); return value
    }

    /// Called only inside the file owner's nonescaping descriptor scope.
    static func inspect(_ request: Request, access: SharedMediaInboxDestinationAccess) throws -> Observation {
        let before = try observation(access, maximum: request.maximum)
        switch request {
        case .interrupted(let request):
            try request.validate()
            // The complete immutable manifest is the cleanup closure. The
            // bounded, single-link, mutually exclusive slots were checked above.
            // Its owner must persist and revalidate the complete chain before
            // any unlink, and never promote these bytes to normal media.
        case .pending(let request, let closure):
            try request.validate()
            if let closure {
                try closure.validate(request: request)
                guard before.parent == closure.parent, before.namespace == closure.namespace,
                      before.partial == nil || (closure.kind == .partial && before.partial == closure.file),
                      before.final == nil || (closure.kind == .final && before.final == closure.file) else {
                    throw SharedMediaStorageFailure.conflict
                }
            } else {
                // A reservation alone has no saved descriptor. A crashed writer
                // must close through normal abandonment before its bytes can be
                // accepted as immutable erasure evidence.
                guard before.partial == nil, before.final == nil else { throw SharedMediaStorageFailure.closed }
            }
        case .original(let file, let saved, let retiring):
            guard before.partial == nil, before.namespace == saved.namespace,
                  before.parent == saved.parent,
                  before.final == saved.file || (retiring && before.final == nil) else { throw SharedMediaStorageFailure.conflict }
            if before.final != nil {
                guard try PhotoPreparationOriginalFiles(access: access).verifiedIdentity(file) == saved.file else {
                    throw SharedMediaStorageFailure.conflict
                }
            }
        case .derivative(let file, let work):
            try inspectDerivative(file, work: work, access: access, observed: before)
        }
        guard try observation(access, maximum: request.maximum) == before else { throw SharedMediaStorageFailure.stale }
        return before
    }

    private static func inspectDerivative(_ file: PhotoPreparationFile, work: SharedMediaNativePairFileState.Work,
                                          access: SharedMediaInboxDestinationAccess, observed: Observation) throws {
        let bytes = SharedMediaDestinationBytes(access: access, expected: file, device: work.device,
            inode: work.inode, finalIdentity: work.finalIdentity)
        switch work.phase {
        case "planned": _ = try bytes.inspectPlannedAbsent()
        case "reserved": _ = try bytes.inspectReservedEmpty()
        case "writing": _ = try bytes.inspectRetirement()
        case "completed": _ = try bytes.inspectCompleted()
        case "retiring":
            guard work.writerState == "closed", work.retirementID != nil, work.closure != nil,
                  let parent = work.retirementParent, let namespace = work.retirementNamespace,
                  let partial = work.retirementPartial, let final = work.retirementFinal else { throw SharedMediaStorageFailure.conflict }
            let actual = try work.device == nil ? bytes.inspectReservedEmpty() : bytes.inspectRetirement()
            guard actual.parent == parent, actual.namespace == namespace,
                  actual.partial == "absent" || actual.partial == partial,
                  actual.final == "absent" || actual.final == final else { throw SharedMediaStorageFailure.conflict }
        default: throw SharedMediaStorageFailure.conflict
        }
        // Completed work is immutable even when it is retained by a historical
        // consumer rather than the current editable package revision.
        if work.phase == "completed" {
            guard observed.final == work.finalIdentity, observed.partial == nil else { throw SharedMediaStorageFailure.conflict }
        }
    }

    private static func observation(_ access: SharedMediaInboxDestinationAccess, maximum: Int64) throws -> Observation {
        try access.perform { parent, namespace in
            let partial = try fileIdentity(parent, access.name + ".partial", maximum: maximum)
            let final = try fileIdentity(parent, access.name, maximum: maximum)
            guard partial == nil || final == nil, let namespace = try directoryIdentity(namespace) else { throw SharedMediaStorageFailure.conflict }
            return try .init(parent: directoryIdentity(parent), namespace: namespace, partial: partial, final: final)
        }
    }

    private static func fileIdentity(_ parent: Int32, _ name: String, maximum: Int64) throws -> String? {
        guard parent >= 0 else { return nil }
        var value = stat()
        if fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw SharedMediaStorageFailure.unavailable }; return nil
        }
        guard value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1,
              value.st_size >= 0, value.st_size <= maximum else { throw SharedMediaStorageFailure.conflict }
        return "\(value.st_dev):\(value.st_ino):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
    }

    private static func openDirectory(_ parent: Int32, _ name: String) throws -> Int32 {
        guard parent >= 0 else { return -1 }
        var named = stat()
        if fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw SharedMediaStorageFailure.unavailable }; return -1
        }
        guard named.st_mode & S_IFMT == S_IFDIR else { throw SharedMediaStorageFailure.conflict }
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SharedMediaStorageFailure.conflict }
        do {
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw SharedMediaStorageFailure.busy }
            try requireDirectory(fd, parent: parent, name: name, expected: "\(named.st_dev):\(named.st_ino)")
            return fd
        } catch { Darwin.close(fd); throw error }
    }

    private static func requireDirectory(_ fd: Int32, parent: Int32, name: String, expected: String?) throws {
        guard try directoryIdentity(fd) == expected else { throw SharedMediaStorageFailure.stale }
        if parent < 0 { guard expected == nil else { throw SharedMediaStorageFailure.stale }; return }
        var named = stat()
        if fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT, expected == nil else { throw SharedMediaStorageFailure.stale }; return
        }
        guard named.st_mode & S_IFMT == S_IFDIR, "\(named.st_dev):\(named.st_ino)" == expected else { throw SharedMediaStorageFailure.stale }
    }
    private static func directoryIdentity(_ fd: Int32) throws -> String? {
        guard fd >= 0 else { return nil }
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else { throw SharedMediaStorageFailure.conflict }
        return "\(value.st_dev):\(value.st_ino)"
    }
}
