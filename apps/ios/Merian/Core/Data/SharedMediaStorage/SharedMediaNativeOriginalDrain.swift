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

    private let configured: Bool
    private var startup: (container: ModelContainer, admission: NativeReleaseStartupAdmission)?
    private var lifetime: (account: PhotoOriginalPreparationOwner.AccountAccess, lease: AccountBoundWorkLease)?
    private var discovery: SharedMediaNativeBootstrapDiscovery?
    private var discoveryAttempted = false
    private var registration: Registration?
    private var callback: (@MainActor () async -> Bool)?
    private var sealed = false
    private var shutdownTask: Task<Bool, Never>?

    init() { configured = false }

    init(container: ModelContainer, admission: NativeReleaseStartupAdmission) {
        configured = true
        startup = (container, admission)
    }

    func discover(account: PhotoOriginalPreparationOwner.AccountAccess) throws -> SharedMediaNativeBootstrapDiscovery {
        try discover(account: account) { container, admission in
            try SharedMediaNativeBootstrapDiscovery.startup(container: container, admission: admission, ownerID: account.ownerID)
        }
    }

    #if DEBUG
    func qualificationDiscover(account: PhotoOriginalPreparationOwner.AccountAccess, support: URL,
                               fault: ((SharedMediaNativeParentCreationBoundary) throws -> Void)? = nil) throws -> SharedMediaNativeBootstrapDiscovery {
        try discover(account: account) { container, admission in
            try .qualificationStartup(container: container, admission: admission, support: support, ownerID: account.ownerID, fault: fault)
        }
    }
    #endif

    private func discover(account: PhotoOriginalPreparationOwner.AccountAccess,
                          make: (ModelContainer, NativeReleaseStartupAdmission) throws -> SharedMediaNativeBootstrapDiscovery) throws -> SharedMediaNativeBootstrapDiscovery {
        guard !sealed, configured, !discoveryAttempted, let startup else { throw SharedMediaStorageFailure.closed }
        discoveryAttempted = true
        do {
            try Task.checkCancellation()
            let lease = try account.begin()
            lifetime = (account, lease)
            guard lease.session.userID == account.ownerID, account.isCurrent(lease) else { throw PhotoPreparationFailure.accountChanged }
            try Task.checkCancellation()
            let value = try make(startup.container, startup.admission)
            discovery = value
            try Task.checkCancellation()
            guard account.isCurrent(lease) else { throw PhotoPreparationFailure.accountChanged }
            return value
        } catch {
            sealed = true
            discovery?.invalidate(); discovery = nil
            finishLifetime()
            throw error
        }
    }

    func register(account: PhotoOriginalPreparationOwner.AccountAccess,
                  _ callback: @escaping @MainActor () async -> Bool) throws -> Registration {
        guard !sealed, registration == nil else { throw SharedMediaStorageFailure.closed }
        if configured {
            guard discovery != nil, let lifetime, account.ownerID == lifetime.account.ownerID,
                  lifetime.account.isCurrent(lifetime.lease), account.isCurrent(lifetime.lease) else { throw PhotoPreparationFailure.accountChanged }
        }
        let value = Registration()
        registration = value; self.callback = callback
        return value
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
        if let shutdownTask { return await shutdownTask.value }
        sealed = true
        discovery?.invalidate(); discovery = nil
        let task = Task { @MainActor [self] in
            let result = await callback?() ?? true
            if result {
                callback = nil; registration = nil
                finishLifetime()
            } else { shutdownTask = nil } // Explicit retry only; admission stays sealed.
            return result
        }
        shutdownTask = task
        return await task.value
    }

    private func finishLifetime() {
        let retained = lifetime
        lifetime = nil; startup = nil
        if let retained { retained.account.finish(retained.lease) }
    }
}
