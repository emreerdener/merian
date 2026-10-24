import Darwin
import Foundation

/// Borrowed descriptors exist only within the locked namespace's dynamic scope.
/// Saved retirement authority is required even for an already absent object.
struct SharedMediaNativeRetirementFiles {
    let access: SharedMediaInboxDestinationAccess
    let retirement: SharedMediaNativeRetirement
    var fault: ((SharedMediaPhotoReleaseBoundary) throws -> Void)?

    func release(requireAbsent: Bool = false, observedAbsence: () -> Void = {}) throws -> SharedMediaNativeReleaseProof {
        try Task.checkCancellation()
        try access.perform { parent, namespace in
            let proof = retirement.state.identity.proof
            func directories() throws {
                guard try directory(parent) == proof.parent, try directory(namespace) == proof.namespace else { throw PhotoPreparationFailure.inconsistentOwnership }
            }
            func absent(_ name: String) throws -> Bool {
                var info = stat()
                if fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 { return false }
                guard errno == ENOENT else { throw PhotoPreparationFailure.unavailable }; return true
            }
            func validateFile() throws {
                var value = stat()
                guard fstatat(parent, access.name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                      value.st_mode & S_IFMT == S_IFREG, value.st_nlink == 1,
                      "\(value.st_dev):\(value.st_ino):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)" == proof.file else {
                    throw PhotoPreparationFailure.inconsistentOwnership
                }
            }
            try directories()
            guard try absent(access.name + ".partial") else { throw PhotoPreparationFailure.cleanupPending }
            if try !absent(access.name) {
                guard !requireAbsent else { throw PhotoPreparationFailure.inconsistentOwnership }
                try validateFile(); try fault?(.beforeUnlink)
                try directories(); try validateFile()
                guard try absent(access.name + ".partial") else { throw PhotoPreparationFailure.cleanupPending }
                try Task.checkCancellation()
                guard unlinkat(parent, access.name, 0) == 0 else { throw PhotoPreparationFailure.cleanupPending }
                observedAbsence()
                try fault?(.afterUnlink)
            } else { observedAbsence() }
            try fault?(.beforeSync)
            guard fsync(parent) == 0, fsync(namespace) == 0 else { throw PhotoPreparationFailure.cleanupPending }
            try fault?(.afterSync)
            try directories()
            guard try absent(access.name), try absent(access.name + ".partial") else { throw PhotoPreparationFailure.cleanupPending }
        }
        return .init(retirement: retirement)
    }
    private func directory(_ fd: Int32) throws -> String {
        var value = stat()
        guard fd >= 0, fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFDIR else { throw PhotoPreparationFailure.inconsistentOwnership }
        return "\(value.st_dev):\(value.st_ino)"
    }
}

struct SharedMediaNativeReleaseProof: Sendable {
    let retirement: SharedMediaNativeRetirement
    fileprivate init(retirement: SharedMediaNativeRetirement) { self.retirement = retirement }
}
