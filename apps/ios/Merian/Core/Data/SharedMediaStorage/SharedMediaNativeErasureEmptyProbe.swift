import Darwin
import Foundation
import SwiftData

/// The no-native-library route retains the same startup/store/account fence.
/// Only ENOENT beneath a held canonical support directory is absence; an open
/// error, foreign inventory or malformed existing parent is never treated as an
/// empty library. This owner creates no directory, receipt or recovery marker.
@MainActor
final class SharedMediaNativeErasureEmptyProbe {
    private let container: ModelContainer
    private let admission: NativeReleaseStartupAdmission
    private let authorization: SharedMediaNativeErasureAuthorization
    private let operation: SharedMediaNativeErasureAuthorization.Identity
    private let runtimeCheckpoint: () throws -> Void
    private let fence: SharedMediaStoreReadFence
    private let support: URL, storeURL: URL
    private let supportFD: Int32, storeFD: Int32
    private let supportIdentity: String, storeFileIdentity: String, storeIdentity: String

    static func openIfAbsent(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                             authorization: SharedMediaNativeErasureAuthorization,
                             runtimeCheckpoint: @escaping () throws -> Void) throws -> SharedMediaNativeErasureEmptyProbe? {
        guard !TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        return try .init(container: container, admission: admission, authorization: authorization,
            support: URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL,
            runtimeCheckpoint: runtimeCheckpoint)
    }

    #if DEBUG
    static func qualification(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                              authorization: SharedMediaNativeErasureAuthorization, support: URL,
                              runtimeCheckpoint: @escaping () throws -> Void) throws -> SharedMediaNativeErasureEmptyProbe? {
        guard TestExecutionCoordinator.isRunningTests,
              support != URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL else {
            throw SharedMediaStorageFailure.closed
        }
        return try .init(container: container, admission: admission, authorization: authorization,
            support: support, runtimeCheckpoint: runtimeCheckpoint)
    }
    #endif

    private init?(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                  authorization: SharedMediaNativeErasureAuthorization, support: URL,
                  runtimeCheckpoint: @escaping () throws -> Void) throws {
        let operation = try authorization.require(container: container)
        try runtimeCheckpoint()
        let fence = try admission.acquireFence(container: container)
        guard !container.mainContext.hasChanges, let configuration = container.configurations.first,
              support == support.resolvingSymlinksInPath().standardizedFileURL else { throw SharedMediaStorageFailure.conflict }
        let supportFD = try SharedMediaStorageFileOwner.openDirectory(support)
        var retained = false
        defer { if !retained { Darwin.close(supportFD) } }
        var named = stat()
        if fstatat(supportFD, SharedMediaNativeBootstrapCodec.parentName, &named, AT_SYMLINK_NOFOLLOW) == 0 { return nil }
        guard errno == ENOENT else { throw SharedMediaStorageFailure.unavailable }
        let storeFD = Darwin.open(configuration.url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard storeFD >= 0 else { throw SharedMediaStorageFailure.unavailable }
        defer { if !retained { Darwin.close(storeFD) } }
        self.container = container; self.admission = admission; self.authorization = authorization
        self.operation = operation; self.runtimeCheckpoint = runtimeCheckpoint; self.fence = fence
        self.support = support; storeURL = configuration.url; self.supportFD = supportFD; self.storeFD = storeFD
        supportIdentity = try Self.identity(supportFD, type: S_IFDIR)
        storeFileIdentity = try Self.identity(storeFD, type: S_IFREG)
        storeIdentity = try SharedMediaNativeEligibility.storeIdentity(at: configuration.url)
        // Once initialized, deinit owns both descriptors even if validation fails.
        retained = true
        try requireCurrent()
    }

    deinit { Darwin.close(storeFD); Darwin.close(supportFD) }

    func requireCurrent() throws {
        try requirePhysicalScope()
        try SharedMediaNativeErasureJournal.requireNoNativeRows(container: container, checkpoint: requirePhysicalScope)
        try requirePhysicalScope()
    }

    /// Descriptor/store/operation validation only; callers still need a fresh
    /// complete zero-row audit before accepting library cleanup.
    func requirePhysicalScope() throws {
        try runtimeCheckpoint(); try admission.require(container: container, fence: fence)
        guard try authorization.require(container: container) == operation,
              !container.mainContext.hasChanges,
              try Self.identity(supportFD, type: S_IFDIR) == supportIdentity,
              try SharedMediaStorageFileOwner.directoryIdentity(support) == supportIdentity,
              try Self.identity(storeFD, type: S_IFREG) == storeFileIdentity,
              try SharedMediaNativeEligibility.storeIdentity(at: storeURL) == storeIdentity else { throw SharedMediaStorageFailure.stale }
        var store = stat(), parent = stat()
        guard lstat(storeURL.path, &store) == 0, store.st_mode & S_IFMT == S_IFREG, store.st_nlink == 1,
              "\(store.st_dev):\(store.st_ino)" == storeFileIdentity else { throw SharedMediaStorageFailure.stale }
        guard fstatat(supportFD, SharedMediaNativeBootstrapCodec.parentName, &parent, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else { throw SharedMediaStorageFailure.conflict }
        try runtimeCheckpoint()
        guard try authorization.require(container: container) == operation else { throw SharedMediaStorageFailure.stale }
    }

    private static func identity(_ fd: Int32, type: mode_t) throws -> String {
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == type,
              type != S_IFREG || value.st_nlink == 1 else { throw SharedMediaStorageFailure.conflict }
        return "\(value.st_dev):\(value.st_ino)"
    }
}
