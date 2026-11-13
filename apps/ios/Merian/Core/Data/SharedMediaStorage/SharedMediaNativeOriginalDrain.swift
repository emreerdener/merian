import Foundation
import SwiftData

/// One account lifecycle. Configuration is inert; explicit discovery retains an
/// exact account lease before filesystem work. Auth joins shutdown before its drain.
@MainActor
final class SharedMediaNativeOriginalDrain {
    struct Registration: Equatable {
        fileprivate let id: UUID
        fileprivate init() { id = UUID() }
    }

    struct RecoveryRegistration: Equatable {
        fileprivate let id = UUID()
        fileprivate init() {}
    }

    /// Two bounded local consumers, independent of native profile/account grants.
    enum LocalConsumer: Hashable { case preparedInputs, inputRecovery }

    @MainActor final class LocalBorrow {
        fileprivate let id = UUID()
        fileprivate weak var owner: SharedMediaNativeOriginalDrain?
        fileprivate init(owner: SharedMediaNativeOriginalDrain) { self.owner = owner }

        func fence(container: ModelContainer, cleanup: Bool = false) throws -> SharedMediaStoreReadFence {
            guard let owner else { throw SharedMediaStorageFailure.closed }
            return try owner.localFence(self, container: container, cleanup: cleanup)
        }

        func require(container: ModelContainer, fence: SharedMediaStoreReadFence, cleanup: Bool = false) throws {
            guard try self.fence(container: container, cleanup: cleanup) === fence else { throw SharedMediaStorageFailure.closed }
        }
    }

    private struct LocalRegistration {
        let consumer: AnyObject
        let borrow: LocalBorrow
        let close: @MainActor () async -> Bool
    }
    private var localConsumers: [LocalConsumer: LocalRegistration] = [:]
    private var sharedFence: SharedMediaStoreReadFence?
    private var preparedAccount: (account: PhotoOriginalPreparationOwner.AccountAccess, lease: AccountBoundWorkLease)?

    private let configured: Bool
    private var startup: (container: ModelContainer, admission: NativeReleaseStartupAdmission)?
    private var lifetime: (account: PhotoOriginalPreparationOwner.AccountAccess, lease: AccountBoundWorkLease)?
    private var discovery: SharedMediaNativeBootstrapDiscovery?
    private var discoveryAttempted = false
    private var registration: Registration?
    private var callback: (@MainActor () async -> Bool)?
    private var registeredOwnerID: UUID?
    private var recoveryPresentation: (token: RecoveryRegistration, close: @MainActor () async -> Void)?
    private var sealed = false
    private(set) var shutdownFinished = false
    var isClosed: Bool { sealed }
    private var shutdownTask: Task<Bool, Never>?
    private var didShutdown: (@MainActor (SharedMediaNativeOriginalDrain) -> Void)?

    init() { configured = false }

    init(container: ModelContainer, admission: NativeReleaseStartupAdmission,
         didShutdown: (@MainActor (SharedMediaNativeOriginalDrain) -> Void)? = nil) {
        configured = true
        startup = (container, admission)
        self.didShutdown = didShutdown
    }

    func discover(account: PhotoOriginalPreparationOwner.AccountAccess) throws -> SharedMediaNativeBootstrapDiscovery {
        try discover(account: account) { container, admission, fence in
            try SharedMediaNativeBootstrapDiscovery.startup(container: container, admission: admission, ownerID: account.ownerID, borrowing: fence)
        }
    }

    #if DEBUG
    func qualificationDiscover(account: PhotoOriginalPreparationOwner.AccountAccess, support: URL,
                               fault: ((SharedMediaNativeParentCreationBoundary) throws -> Void)? = nil) throws -> SharedMediaNativeBootstrapDiscovery {
        try discover(account: account) { container, admission, fence in
            try .qualificationStartup(container: container, admission: admission, support: support, ownerID: account.ownerID, fault: fault, borrowing: fence)
        }
    }
    #endif

    private func discover(account: PhotoOriginalPreparationOwner.AccountAccess,
                          make: (ModelContainer, NativeReleaseStartupAdmission, SharedMediaStoreReadFence) throws -> SharedMediaNativeBootstrapDiscovery) throws -> SharedMediaNativeBootstrapDiscovery {
        guard !sealed, configured, !discoveryAttempted, let startup else { throw SharedMediaStorageFailure.closed }
        try requirePreparedAccount(account)
        discoveryAttempted = true
        do {
            try Task.checkCancellation()
            let lease = try account.begin()
            lifetime = (account, lease)
            guard lease.session.userID == account.ownerID, account.isCurrent(lease) else { throw PhotoPreparationFailure.accountChanged }
            try Task.checkCancellation()
            let fence = try retainFence(container: startup.container)
            let value = try make(startup.container, startup.admission, fence)
            discovery = value
            try Task.checkCancellation()
            guard account.isCurrent(lease) else { throw PhotoPreparationFailure.accountChanged }
            return value
        } catch {
            sealed = true
            discovery?.invalidate(); discovery = nil
            // Active borrowers must exit through the owned asynchronous shutdown.
            if localConsumers.isEmpty { finishLifetime() }
            throw error
        }
    }

    /// Registration retains the exact consumer until its actual-exit callback.
    /// Repeated opens reuse its slot; a different owner cannot replace it.
    func borrowLocalFence(for consumer: AnyObject, role: LocalConsumer, container: ModelContainer,
                          close: @escaping @MainActor () async -> Bool) throws -> LocalBorrow {
        guard !sealed, configured else { throw SharedMediaStorageFailure.closed }
        _ = try retainFence(container: container)
        if let existing = localConsumers[role] {
            guard existing.consumer === consumer else { throw SharedMediaStorageFailure.closed }
            return existing.borrow
        }
        let borrow = LocalBorrow(owner: self)
        localConsumers[role] = LocalRegistration(consumer: consumer, borrow: borrow, close: close)
        return borrow
    }

    func requirePreparedAccount(_ account: PhotoOriginalPreparationOwner.AccountAccess) throws {
        guard !sealed else { throw SharedMediaStorageFailure.closed }
        if let preparedAccount {
            guard preparedAccount.account.ownerID == account.ownerID,
                  preparedAccount.account.isCurrent(preparedAccount.lease), account.isCurrent(preparedAccount.lease) else {
                throw PhotoPreparationFailure.accountChanged
            }
        }
    }

    var permitsNativeDiscovery: Bool { configured && !sealed && !discoveryAttempted }

    /// Prepared input has an account lifetime; cold erasure intentionally does not.
    func bindPreparedAccount(_ account: PhotoOriginalPreparationOwner.AccountAccess) throws {
        guard !sealed else { throw SharedMediaStorageFailure.closed }
        if let preparedAccount {
            guard preparedAccount.account.ownerID == account.ownerID,
                  preparedAccount.account.isCurrent(preparedAccount.lease), account.isCurrent(preparedAccount.lease) else {
                throw PhotoPreparationFailure.accountChanged
            }
            return
        }
        if lifetime != nil, !recognizes(account: account) { throw PhotoPreparationFailure.accountChanged }
        let lease = try account.begin()
        guard lease.session.userID == account.ownerID, account.isCurrent(lease) else {
            account.finish(lease); throw PhotoPreparationFailure.accountChanged
        }
        preparedAccount = (account, lease)
    }

    private func retainFence(container: ModelContainer) throws -> SharedMediaStoreReadFence {
        guard let startup, startup.container === container else { throw SharedMediaStorageFailure.closed }
        let fence = try sharedFence ?? startup.admission.acquireFence(container: container)
        try startup.admission.require(container: container, fence: fence)
        sharedFence = fence
        return fence
    }

    private func localFence(_ borrow: LocalBorrow, container: ModelContainer, cleanup: Bool) throws -> SharedMediaStoreReadFence {
        guard !sealed || cleanup,
              localConsumers.values.contains(where: { $0.borrow === borrow }),
              let fence = sharedFence, let startup, startup.container === container else { throw SharedMediaStorageFailure.closed }
        try startup.admission.require(container: container, fence: fence)
        return fence
    }

    func register(account: PhotoOriginalPreparationOwner.AccountAccess,
                  _ callback: @escaping @MainActor () async -> Bool) throws -> Registration {
        guard !sealed, registration == nil else { throw SharedMediaStorageFailure.closed }
        if configured {
            guard discovery != nil, let lifetime, account.ownerID == lifetime.account.ownerID,
                  lifetime.account.isCurrent(lifetime.lease), account.isCurrent(lifetime.lease) else { throw PhotoPreparationFailure.accountChanged }
        }
        let value = Registration()
        registration = value; registeredOwnerID = account.ownerID; self.callback = callback
        return value
    }

    /// One presentation per retained native lifetime. A dismissed presentation
    /// retains this slot until its owned tasks and best-effort settlement end.
    func registerRecoveryPresentation(ownerID: UUID,
                                      close: @escaping @MainActor () async -> Void) throws -> RecoveryRegistration {
        guard let registration, isCurrent(registration), registeredOwnerID == ownerID,
              recoveryPresentation == nil else { throw SharedMediaStorageFailure.closed }
        let token = RecoveryRegistration()
        recoveryPresentation = (token, close)
        return token
    }

    func isCurrentRecoveryPresentation(_ token: RecoveryRegistration, ownerID: UUID) -> Bool {
        guard let registration else { return false }
        return isCurrent(registration) && registeredOwnerID == ownerID && recoveryPresentation?.token == token
    }

    func unregisterRecoveryPresentation(_ token: RecoveryRegistration) {
        if recoveryPresentation?.token == token { recoveryPresentation = nil }
    }

    func recognizes(account: PhotoOriginalPreparationOwner.AccountAccess) -> Bool {
        guard !sealed, let lifetime, account.ownerID == lifetime.account.ownerID else { return false }
        return lifetime.account.isCurrent(lifetime.lease) && account.isCurrent(lifetime.lease)
    }

    func isCurrent(_ value: Registration, container: ModelContainer? = nil, discovery: SharedMediaNativeBootstrapDiscovery? = nil) -> Bool {
        guard !sealed, registration == value else { return false }
        guard configured else { return true }
        guard let lifetime, lifetime.account.isCurrent(lifetime.lease), let startup else { return false }
        guard let container else { return true }
        return container === startup.container && discovery != nil && discovery === self.discovery
    }

    func seal(_ value: Registration) {
        if registration == value { sealed = true }
    }

    func shutdown() async -> Bool {
        if let shutdownTask {
            let result = await shutdownTask.value
            shutdownFinished = result
            return result
        }
        sealed = true
        discovery?.invalidate(); discovery = nil
        if localConsumers.isEmpty { sharedFence = nil }
        let task = Task { @MainActor [self] in
            // Sealing prevents new native work, but never prevents joining the
            // model's already-owned tasks. Denied refund is still quiescence.
            let presentation = recoveryPresentation
            await presentation?.close()
            var localResult = true
            for role in [LocalConsumer.preparedInputs, .inputRecovery] {
                guard let consumer = localConsumers[role] else { continue }
                if await consumer.close() { localConsumers.removeValue(forKey: role) } else { localResult = false }
            }
            // Always join native work, including when a local borrower is blocked.
            let nativeResult = await callback?() ?? true
            let result = localResult && nativeResult
            if result {
                callback = nil; registration = nil; registeredOwnerID = nil
                recoveryPresentation = nil
                finishLifetime()
                let completed = didShutdown; didShutdown = nil
                completed?(self)
            } else { shutdownTask = nil } // Explicit retry only; admission stays sealed.
            return result
        }
        shutdownTask = task
        let result = await task.value
        shutdownFinished = result
        return result
    }

    private func finishLifetime() {
        let retained = lifetime, prepared = preparedAccount
        preparedAccount = nil
        lifetime = nil; startup = nil; sharedFence = nil
        if let retained { retained.account.finish(retained.lease) }
        if let prepared { prepared.account.finish(prepared.lease) }
    }
}
