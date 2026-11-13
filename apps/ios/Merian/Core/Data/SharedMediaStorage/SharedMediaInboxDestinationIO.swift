import Foundation

actor SharedMediaInboxDestinationIO {
    private let files: PhotoPreparationLockedFiles
    #if DEBUG
    private var fault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?
    private var pause: (@Sendable () async -> Void)?
    func setPause(_ value: (@Sendable () async -> Void)?) { pause = value }
    func setFault(_ value: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?) { fault = value }
    #endif
    init(files: PhotoPreparationLockedFiles) { self.files = files }
    private func withFiles<T>(_ state: SharedMediaInboxHandoff, create: Bool = false,
                              _ body: (SharedMediaInboxDestinationFiles) throws -> T) throws -> T {
        try files.withInboxDestination(state, create: create) { value in
            var value = value
            #if DEBUG
            value.fault = fault
            #endif
            return try body(value)
        }
    }
    func begin(_ state: SharedMediaInboxHandoff) throws -> SharedMediaInboxDestinationPartial {
        try withFiles(state, create: true) { try $0.begin() }
    }
    func write(_ data: Data, state: SharedMediaInboxHandoff) async throws -> SharedMediaInboxDestinationCompletion {
        #if DEBUG
        await pause?()
        #endif
        return try withFiles(state) { try $0.write(data) }
    }
    func recover(_ state: SharedMediaInboxHandoff) throws -> SharedMediaInboxDestinationCompletion? {
        do { return try withFiles(state) { try $0.recover() } } catch PhotoPreparationFailure.missingMedia {
            guard state.phase == "reserved", state.inode == nil else { throw SharedMediaStorageFailure.conflict }
            return nil
        }
    }
    func prune(_ inventory: SharedMediaPhotoInventory) throws {
        try files.pruneSharedEmptyDirectories(knownTokens: Set(inventory.files.map(\.token)).union(inventory.pendingTokens))
    }
    func validate(_ inventory: SharedMediaPhotoInventory) throws {
        try files.checkInventory(knownTokens: Set(inventory.files.map(\.token)).union(inventory.pendingTokens))
    }
    func read(_ file: PhotoPreparationFile, identity: String) throws -> Data {
        guard try files.verifiedIdentity(file) == identity else { throw SharedMediaStorageFailure.conflict }
        return try files.read(file)
    }
    func inspectRetirement(_ state: SharedMediaInboxHandoff) throws -> SharedMediaInboxDestinationInspection {
        try withFiles(state) { try $0.inspectRetirement() }
    }
    func release(_ intent: SharedMediaInboxDestinationRetirement) throws -> SharedMediaInboxDestinationRelease {
        try withFiles(intent.handoff) { try $0.release(intent) }
    }
    func closure(_ state: SharedMediaInboxHandoff) throws -> SharedMediaInboxDestinationClosure { try withFiles(state) { try $0.closure() } }

    func inspectOriginal(_ file: PhotoPreparationFile) throws -> SharedMediaPhotoRetirementInspection {
        try files.inspectSharedRetirement(file)
    }
    func releaseOriginal(_ intent: SharedMediaPhotoRetirement) throws -> SharedMediaPhotoReleaseProof {
        try files.releaseSharedPhoto(intent)
    }
    #if DEBUG
    func setOriginalReleaseFault(_ value: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) {
        files.sharedReleaseFault = value
    }
    #endif

    private func withDerivative<T>(_ work: SharedMediaDerivativeWork, create: Bool = false,
                                   _ body: (SharedMediaDerivativeWorkFiles) throws -> T) throws -> T {
        try files.withDerivativeDestination(work, create: create) { value in
            var value = value
            #if DEBUG
            value.fault = fault
            #endif
            return try body(value)
        }
    }
    func prepareDerivative(_ data: Data, role: PhotoPreparationRole) throws -> SharedMediaDerivativeInput {
        try SharedMediaDerivativeWorkFiles.prepare(data, role: role)
    }
    func validateDerivative(_ data: Data, input: SharedMediaDerivativeInput) throws {
        try SharedMediaDerivativeWorkFiles.validate(data, input: input)
    }
    func begin(_ work: SharedMediaDerivativeWork) throws -> SharedMediaDerivativePartial {
        try withDerivative(work, create: true) { try $0.begin() }
    }
    func write(_ data: Data, work: SharedMediaDerivativeWork) async throws -> SharedMediaDerivativeCompletion {
        #if DEBUG
        await pause?()
        #endif
        return try withDerivative(work) { try $0.write(data) }
    }
    func recover(_ work: SharedMediaDerivativeWork) throws -> SharedMediaDerivativeCompletion? {
        try withDerivative(work) { try $0.recover() }
    }
    func closure(_ work: SharedMediaDerivativeWork) throws -> SharedMediaDerivativeClosure {
        try withDerivative(work) { try $0.closure() }
    }
    func inspectRetirement(_ work: SharedMediaDerivativeWork) throws -> SharedMediaDerivativeInspection {
        try withDerivative(work) { try $0.inspectRetirement() }
    }
    func release(_ intent: SharedMediaDerivativeRetirement) throws -> SharedMediaDerivativeRelease {
        try withDerivative(intent.work) { try $0.release(intent) }
    }
}
