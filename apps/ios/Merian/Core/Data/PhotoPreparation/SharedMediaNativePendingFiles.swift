import Darwin
import Foundation

/// Descriptor-relative pending-file inspection and disposal. Only a durable
/// abandonment capability authorizes unlink; inspection alone grants nothing.
struct SharedMediaNativePendingFiles {
    let access: SharedMediaInboxDestinationAccess
    let request: SharedMediaAcquisitionIntent
    var fault: ((SharedMediaPhotoReleaseBoundary) throws -> Void)?

    func inspect(binding: SharedMediaNativeBinding) throws -> SharedMediaNativePendingInspection {
        try Task.checkCancellation()
        let closure = try access.perform { try capture(parent: $0, namespace: $1) }
        return .init(closure: closure, binding: binding.bytes, epoch: binding.epoch)
    }
    func verify(_ saved: SharedMediaNativePendingClosure) throws {
        try Task.checkCancellation()
        try access.perform { parent, namespace in try require(saved, parent: parent, namespace: namespace) }
    }
    func release(_ disposal: SharedMediaNativePendingDisposal) throws -> SharedMediaNativePendingAbsence {
        guard disposal.state.request == request, let saved = disposal.state.closure else { throw SharedMediaStorageFailure.conflict }
        try Task.checkCancellation()
        try access.perform { parent, namespace in
            try require(saved, parent: parent, namespace: namespace)
            if parent >= 0, let name = try presentName(parent: parent) {
                try fault?(.beforeUnlink)
                try require(saved, parent: parent, namespace: namespace)
                try Task.checkCancellation()
                guard unlinkat(parent, name, 0) == 0 else { throw PhotoPreparationFailure.cleanupPending }
                try fault?(.afterUnlink)
            }
            try fault?(.beforeSync)
            guard (parent < 0 || fsync(parent) == 0), fsync(namespace) == 0 else { throw PhotoPreparationFailure.cleanupPending }
            try fault?(.afterSync)
            try require(saved, parent: parent, namespace: namespace)
            guard try parent < 0 || presentName(parent: parent) == nil else { throw PhotoPreparationFailure.cleanupPending }
        }
        return .init(disposal: disposal)
    }
    private func require(_ saved: SharedMediaNativePendingClosure, parent: Int32, namespace: Int32) throws {
        try saved.validate(request: request)
        let actual = try capture(parent: parent, namespace: namespace)
        guard actual.parent == saved.parent, actual.namespace == saved.namespace,
              actual.kind == .absent || (actual.kind == saved.kind && actual.file == saved.file) else {
            throw PhotoPreparationFailure.inconsistentOwnership
        }
        // An absent saved slot never authorizes a new file at that name.
        if saved.kind == .absent { guard actual.kind == .absent else { throw PhotoPreparationFailure.inconsistentOwnership } }
    }
    private func capture(parent: Int32, namespace: Int32) throws -> SharedMediaNativePendingClosure {
        let parentIdentity = parent < 0 ? nil : try directory(parent)
        let namespaceIdentity = try directory(namespace)
        let final = parent < 0 ? nil : try descriptor(parent: parent, name: access.name)
        let partial = parent < 0 ? nil : try descriptor(parent: parent, name: access.name + ".partial")
        guard final == nil || partial == nil else { throw PhotoPreparationFailure.inconsistentOwnership }
        let result = SharedMediaNativePendingClosure(version: 1, fingerprint: try request.fingerprint(),
            parent: parentIdentity, namespace: namespaceIdentity, kind: final != nil ? .final : (partial != nil ? .partial : .absent), file: final ?? partial)
        _ = try result.encoded(request: request)
        return result
    }
    private func presentName(parent: Int32) throws -> String? {
        let final = try descriptor(parent: parent, name: access.name)
        let partial = try descriptor(parent: parent, name: access.name + ".partial")
        guard final == nil || partial == nil else { throw PhotoPreparationFailure.inconsistentOwnership }
        return final != nil ? access.name : (partial != nil ? access.name + ".partial" : nil)
    }
    private func directory(_ fd: Int32) throws -> String {
        var value = stat()
        guard fd >= 0, fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else { throw PhotoPreparationFailure.inconsistentOwnership }
        return "\(value.st_dev):\(value.st_ino)"
    }
    private func descriptor(parent: Int32, name: String) throws -> String? {
        var value = stat()
        if fstatat(parent, name, &value, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw PhotoPreparationFailure.unavailable }; return nil
        }
        guard value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1,
              value.st_size >= 0, value.st_size <= request.maximumBytes else { throw PhotoPreparationFailure.inconsistentOwnership }
        return "\(value.st_dev):\(value.st_ino):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
    }
}

struct SharedMediaNativePendingInspection: Sendable {
    let closure: SharedMediaNativePendingClosure
    let binding: Data, epoch: UUID
    fileprivate init(closure: SharedMediaNativePendingClosure, binding: Data, epoch: UUID) {
        self.closure = closure; self.binding = binding; self.epoch = epoch
    }
}
struct SharedMediaNativePendingAbsence: Sendable {
    let disposal: SharedMediaNativePendingDisposal
    fileprivate init(disposal: SharedMediaNativePendingDisposal) { self.disposal = disposal }
}
