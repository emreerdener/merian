import Foundation
import SwiftData

/// Registered before admission, so Auth can reach an in-flight open. This
/// qualification composition owns acquisition and settlement; live wiring stays disabled.
@MainActor
final class SharedMediaNativeOriginalOwner {
    private enum OpenKind { case qualification, scopedInspection, appInitialization, appDispatch }
    private let openKind: OpenKind
    private var scopedIdentity: SharedMediaNativeScopeIdentity?
    private var appProfile: SharedMediaNativeAppProfile?
    private var appParent: URL?
    private enum Phase { case unopened, opening, ready, failed, suspended }
    private let account: PhotoOriginalPreparationOwner.AccountAccess
    private let drain: SharedMediaNativeOriginalDrain
    private var registration: SharedMediaNativeOriginalDrain.Registration?
    private var phase = Phase.unopened
    private let writerEpoch = UUID()
    private struct PendingSettlement {
        let id = UUID()
        let request: SharedMediaAcquisitionIntent
        let loaderStarted: Bool
        let writerReturned: Bool
    }
    private var pendingSettlement: PendingSettlement?
    private var writerActive = false
    private var activeDispatchID: UUID?
    #if DEBUG
    fileprivate let debug = SharedMediaNativeDebugHooks()
    #endif
    private var storage: SharedMediaNativeStorageRepository?
    private var cancelActive: (() -> Void)?
    private var awaitActive: (() async -> Void)?

    private init(account: PhotoOriginalPreparationOwner.AccountAccess, drain: SharedMediaNativeOriginalDrain,
                 openKind: OpenKind = .qualification) throws {
        self.account = account; self.drain = drain; self.openKind = openKind
        registration = try drain.register { [weak self] in
            guard let self else { return true }; return await self.invalidateAndAwaitForAccountTransition()
        }
    }

    #if DEBUG
    static func qualification(account: PhotoOriginalPreparationOwner.AccountAccess,
                              drain: SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeOriginalOwner {
        try .init(account: account, drain: drain)
    }

    func open(container: ModelContainer, authorityRoot: URL, photoRoot: URL, inboxRoot: URL,
              inventoryID: UUID, pause: (@Sendable () async -> Void)? = nil) async throws -> SharedMediaNativeOriginalSnapshot {
        guard openKind == .qualification, phase == .unopened, let registration, drain.isCurrent(registration) else { throw SharedMediaStorageFailure.closed }
        phase = .opening
        do {
            return try await perform { [self] grant in
                let candidate = try SharedMediaNativeStorageRepository.originalAdmission(container: container,
                    authorityRoot: authorityRoot, photoRoot: photoRoot, inboxRoot: inboxRoot, inventoryID: inventoryID, grant: grant, pause: pause)
                storage = candidate
                let result = try await candidate.inspectOriginals(grant: grant)
                try grant.validate()
                phase = .ready
                return result
            }
        } catch {
            if phase != .suspended { phase = .failed }
            storage = nil
            throw error
        }
    }

    /// Inactive native initialization qualification. No installer or dispatch is
    /// exposed; this uses the same registered owner and retained repository.
    static func appInitialization(account: PhotoOriginalPreparationOwner.AccountAccess,
                                  drain: SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeOriginalOwner {
        try .init(account: account, drain: drain, openKind: .appInitialization)
    }
    func initializeApp(container: ModelContainer, parent: URL, inventoryID: UUID,
                       fault: ((SharedMediaNativeBootstrapBoundary) throws -> Void)? = nil,
                       availableBytes: Int64? = nil) async throws -> SharedMediaStorageSnapshot {
        guard openKind == .appInitialization, phase == .unopened,
              let registration, drain.isCurrent(registration) else { throw SharedMediaStorageFailure.closed }
        phase = .opening; debug.bootstrapFault = fault; debug.bootstrapAvailableBytes = availableBytes
        do {
            return try await performOperation { [self] lease, identity in
                let grant = SharedMediaNativeAppGrant(owner: self, identity: identity, lease: lease,
                    ownerID: account.ownerID, writerEpoch: writerEpoch)
                let candidate = try SharedMediaNativeStorageRepository.initializeApp(container: container, parent: parent,
                    inventoryID: inventoryID, grant: grant)
                storage = candidate
                let result = try candidate.appInitializationSnapshot(grant: grant)
                try grant.validate(); phase = .ready; return result
            }
        } catch {
            if phase != .suspended { phase = .failed }; storage = nil; throw error
        }
    }

    /// Inactive existing-profile entry. It cannot initialize or repair storage.
    static func appDispatch(account: PhotoOriginalPreparationOwner.AccountAccess,
                            drain: SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeOriginalOwner {
        try .init(account: account, drain: drain, openKind: .appDispatch)
    }
    func openApp(container: ModelContainer, parent: URL, inventoryID: UUID, pause: (@Sendable () async -> Void)? = nil) async throws -> SharedMediaNativeScopedSnapshot {
        guard openKind == .appDispatch, phase == .unopened, let registration, drain.isCurrent(registration) else { throw SharedMediaStorageFailure.closed }
        phase = .opening; debug.scopedPagePause = pause
        do {
            return try await performOperation { [self] lease, identity in
                let profile = try SharedMediaNativeAppEligibility.identity(container: container, inventoryID: inventoryID, ownerID: account.ownerID)
                appProfile = profile; appParent = parent
                let grant = SharedMediaNativeAppDispatchGrant(owner: self, identity: identity, lease: lease,
                    profile: profile, parent: parent, writerEpoch: writerEpoch)
                let candidate = try SharedMediaNativeStorageRepository.openApp(container: container, parent: parent,
                    inventoryID: inventoryID, grant: grant)
                storage = candidate
                let result = try await candidate.inspectApp(grant: grant)
                try grant.validate(); phase = .ready; return result
            }
        } catch { if phase != .suspended { phase = .failed }; storage = nil; appProfile = nil; appParent = nil; throw error }
    }

    /// Inactive qualification seam for the existing app-container profile. This
    /// does not bootstrap a profile or install an owner in the running app.
    static func scopedInspection(account: PhotoOriginalPreparationOwner.AccountAccess,
                                 drain: SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeOriginalOwner {
        try .init(account: account, drain: drain, openKind: .scopedInspection)
    }

    func openScoped(container: ModelContainer, authorityRoot: URL, photoRoot: URL, inboxRoot: URL,
                    inventoryID: UUID, pagePause: (@Sendable () async -> Void)? = nil) async throws -> SharedMediaNativeScopedSnapshot {
        guard openKind == .scopedInspection, phase == .unopened,
              let registration, drain.isCurrent(registration) else { throw SharedMediaStorageFailure.closed }
        phase = .opening; debug.scopedPagePause = pagePause
        do {
            return try await performOperation { [self] lease, identity in
                let scope = try SharedMediaNativeScopedEligibility.identity(container: container, inventoryID: inventoryID,
                    ownerID: account.ownerID, authority: authorityRoot, photo: photoRoot, inbox: inboxRoot)
                scopedIdentity = scope
                let grant = SharedMediaNativeScopedReadGrant(owner: self, identity: identity, lease: lease,
                    scope: scope, writerEpoch: writerEpoch)
                let candidate = try SharedMediaNativeStorageRepository.scopedInspection(container: container,
                    authorityRoot: authorityRoot, photoRoot: photoRoot, inboxRoot: inboxRoot, grant: grant)
                storage = candidate
                let result = try await candidate.inspectScoped(grant: grant)
                try grant.validate(); phase = .ready
                return result
            }
        } catch {
            if phase != .suspended { phase = .failed }
            storage = nil; scopedIdentity = nil
            throw error
        }
    }
    #endif

    func inspectScoped() async throws -> SharedMediaNativeScopedSnapshot {
        guard openKind == .scopedInspection, phase == .ready, let scope = scopedIdentity else { throw SharedMediaStorageFailure.closed }
        return try await performOperation { [self] lease, identity in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            let grant = SharedMediaNativeScopedReadGrant(owner: self, identity: identity, lease: lease,
                scope: scope, writerEpoch: writerEpoch)
            return try await storage.inspectScoped(grant: grant)
        }
    }

    func inspectApp() async throws -> SharedMediaNativeScopedSnapshot {
        guard openKind == .appDispatch, phase == .ready else { throw SharedMediaStorageFailure.closed }
        return try await performOperation { [self] lease, identity in
            guard let storage, let appProfile, let appParent else { throw SharedMediaStorageFailure.closed }
            return try await storage.inspectApp(grant: .init(owner: self, identity: identity, lease: lease,
                profile: appProfile, parent: appParent, writerEpoch: writerEpoch))
        }
    }

    func prepareAppMetadata(packageID: UUID, draftGeneration: UUID, contexts: [ObservationContext],
                            presentation: [PhotoPreparationImagePresentation]? = nil) async throws -> SharedMediaNativeAppMetadataRequest {
        try await appMetadata { try $0.request(packageID: packageID, draftGeneration: draftGeneration, contexts: contexts, presentation: presentation) }
    }
    func saveAppMetadata(_ request: SharedMediaNativeAppMetadataRequest) async throws -> Int64 {
        try await appMetadata { try $0.apply(request) }
    }
    private func appMetadata<T: Sendable>(_ body: @escaping @MainActor (SharedMediaNativeAppMetadataOperations) throws -> T) async throws -> T {
        guard openKind == .appDispatch, phase == .ready else { throw SharedMediaStorageFailure.closed }
        return try await performOperation { [self] lease, identity in
            guard let storage, let appProfile, let appParent else { throw SharedMediaStorageFailure.closed }
            let grant = SharedMediaNativeAppDispatchGrant(owner: self, identity: identity, lease: lease,
                profile: appProfile, parent: appParent, writerEpoch: writerEpoch)
            let operation = try await storage.appMetadata(grant: grant)
            try grant.validate(); return try body(operation)
        }
    }

    func appInitializationSnapshot() async throws -> SharedMediaStorageSnapshot {
        guard openKind == .appInitialization, phase == .ready else { throw SharedMediaStorageFailure.closed }
        return try await performOperation { [self] lease, identity in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            return try storage.appInitializationSnapshot(grant: .init(owner: self, identity: identity, lease: lease,
                ownerID: account.ownerID, writerEpoch: writerEpoch))
        }
    }

    func snapshot() async throws -> SharedMediaNativeOriginalSnapshot {
        guard phase == .ready else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] grant in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            return try await storage.inspectOriginals(grant: grant)
        }
    }

    #if DEBUG
    func setAcquisitionFault(_ fault: ((SharedMediaNativeAcquisitionBoundary) throws -> Void)?) throws {
        guard (phase == .ready || phase == .suspended), cancelActive == nil, storage != nil else { throw SharedMediaStorageFailure.closed }
        debug.acquisitionFault = fault
    }
    var inspectionAuditCount: Int { debug.inspectionAuditCount }
    func setMetadataFault(_ fault: ((SharedMediaNativeMetadataBoundary) throws -> Void)?, availableBytes: Int64? = nil) throws {
        guard phase == .ready, cancelActive == nil, storage != nil else { throw SharedMediaStorageFailure.closed }
        debug.metadataFault = fault; debug.metadataAvailableBytes = availableBytes
    }
    #endif

    func prepareShare(_ source: PhotoOriginalReference, packageID: UUID, draftGeneration: UUID) async throws -> SharedMediaNativeShareRequest {
        try await lifecycle { storage, grant in try storage.lifecycleOperations(grant).prepareShare(source, packageID: packageID, draftGeneration: draftGeneration) }
    }
    func share(_ request: SharedMediaNativeShareRequest) async throws -> PhotoOriginalReference {
        try await lifecycle { storage, grant in try storage.lifecycleOperations(grant).share(request) }
    }
    func prepareRemoval(_ source: PhotoOriginalReference) async throws -> SharedMediaNativeRemovalRequest {
        try await lifecycle { storage, grant in try storage.lifecycleOperations(grant).prepareRemoval(source) }
    }
    func remove(_ request: SharedMediaNativeRemovalRequest) async throws {
        try await lifecycle { storage, grant in try await storage.lifecycleOperations(grant).remove(request) }
        try await recoverRetirements()
    }
    func recoverRetirements() async throws {
        try await lifecycle(recovery: true) { storage, grant in try await storage.lifecycleOperations(grant).recoverRetirements() }
    }
    func abandonPendingAcquisition(_ request: SharedMediaAcquisitionIntent) async throws {
        try await lifecycle(recovery: true) { storage, grant in try await storage.lifecycleOperations(grant).abandon(request) }
        try await recoverPendingAbandonments()
    }
    func recoverPendingAbandonments() async throws {
        try await lifecycle(recovery: true) { storage, grant in try await storage.lifecycleOperations(grant).recoverPendingAbandonments() }
    }
    private func lifecycle<T: Sendable>(recovery: Bool = false,
        _ body: @escaping @MainActor (SharedMediaNativeStorageRepository, SharedMediaNativeDispatchGrant) async throws -> T) async throws -> T {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] grant in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            let snapshot = try await storage.inspectOriginals(grant: grant)
            guard recovery || !snapshot.requiresRecovery else { throw PhotoPreparationFailure.cleanupPending }
            return try await body(storage, grant)
        }
    }
    #if DEBUG
    func setLifecycleFault(_ fault: ((SharedMediaNativeLifecycleBoundary) throws -> Void)?) throws {
        guard phase == .ready, cancelActive == nil, storage != nil else { throw SharedMediaStorageFailure.closed }; debug.lifecycleFault = fault
    }
    func setReleaseFault(_ fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)?) async throws {
        try await lifecycle(recovery: true) { storage, grant in try await storage.lifecycleOperations(grant).setReleaseFault(fault) }
    }
    #endif

    /// Reserves an explicit native attempt without dispatching a processor.
    /// Callers receive assertions, never a source URL or write access.
    func reservePreparation(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePreparationAttempt {
        try await lifecycle { storage, grant in
            try storage.preparationOperations(grant).reserve(original: original, recipe: recipe)
        }
    }
    func activePreparation(packageID: UUID) async throws -> SharedMediaNativePreparationAttempt? {
        try await lifecycle(recovery: true) { storage, grant in try storage.preparationOperations(grant).active(packageID: packageID) }
    }
    func abandonPreparation(_ attempt: SharedMediaNativePreparationAttempt) async throws {
        try await lifecycle(recovery: true) { storage, grant in try storage.preparationOperations(grant).abandon(attempt) }
    }
    #if DEBUG
    func setPreparationFault(_ fault: ((SharedMediaNativePreparationBoundary) throws -> Void)?, availableBytes: Int64? = nil, focusFactory: ImageFocusWorkFactory = .init()) throws {
        guard phase == .ready, cancelActive == nil, storage != nil else { throw SharedMediaStorageFailure.closed }
        debug.preparationFault = fault; debug.preparationAvailableBytes = availableBytes; debug.preparationFocusFactory = focusFactory
    }
    #endif

    func prepareFreeze(packageID: UUID, pairIDs: [UUID], operationID: UUID) async throws -> SharedMediaNativeFreezeRequest {
        try await lifecycle { storage, grant in
            try await storage.preparationOperations(grant).prepareFreeze(packageID: packageID, pairIDs: pairIDs, operationID: operationID)
        }
    }
    /// Exact saved acknowledgement precedes current physical availability checks.
    func freeze(_ request: SharedMediaNativeFreezeRequest) async throws -> SharedMediaNativeFreezeCommit {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] grant in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            return try await storage.preparationOperations(grant).freeze(request)
        }
    }

    func preparedFileState(packageID: UUID, pairID: UUID? = nil) async throws -> SharedMediaNativePairFileState {
        try await lifecycle(recovery: true) { storage, grant in try storage.preparationOperations(grant).fileState(packageID: packageID, pairID: pairID) }
    }
    func recoverPreparedFiles(packageID: UUID, pairID: UUID? = nil) async throws -> SharedMediaNativePairFileState {
        try await lifecycle(recovery: true) { storage, grant in try await storage.preparationOperations(grant).recoverFiles(packageID: packageID, pairID: pairID) }
    }
    func retirePreparedFiles(_ state: SharedMediaNativePairFileState) async throws {
        try await lifecycle(recovery: true) { storage, grant in try await storage.preparationOperations(grant).retireFiles(state) }
    }
    #if DEBUG
    func qualifyPreparedFiles(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe) async throws -> SharedMediaNativePairFileState {
        try await lifecycle { storage, grant in try await storage.preparationOperations(grant).prepareFiles(original: original, recipe: recipe) }
    }
    func setPairFileFault(_ fault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)?) async throws {
        try await lifecycle(recovery: true) { storage, grant in try await storage.preparationOperations(grant).setPairFileFault(fault) }
    }
    #endif

    func plannedPreparation(packageID: UUID, pairID: UUID? = nil) async throws -> SharedMediaNativePairPlan? {
        try await lifecycle(recovery: true) { storage, grant in try storage.preparationOperations(grant).plan(packageID: packageID, pairID: pairID) }
    }
    func abandonPlannedPreparation(_ plan: SharedMediaNativePairPlan) async throws {
        try await lifecycle(recovery: true) { storage, grant in try storage.preparationOperations(grant).abandonPlan(plan) }
    }
    func prepareMetadata(packageID: UUID, draftGeneration: UUID, contexts: [ObservationContext],
                         presentation: [PhotoPreparationImagePresentation]? = nil) async throws -> SharedMediaNativeMetadataRequest {
        try await lifecycle { storage, grant in
            try storage.metadata(packageID: packageID, grant: grant)
                .request(draftGeneration: draftGeneration, contexts: contexts, presentation: presentation)
        }
    }
    func saveMetadata(_ request: SharedMediaNativeMetadataRequest) async throws -> Int64 {
        try await lifecycle { storage, grant in try storage.saveMetadata(request, grant: grant) }
    }
    #if DEBUG
    /// Qualification only until the native pair owner consumes outputs in the
    /// same retained operation. Never used by live Capture or queue composition.
    func qualifyPhotoPreparation(original: PhotoOriginalReference, recipe: SharedMediaNativePreparationRecipe, savePlan: Bool = false) async throws -> SharedMediaNativePreparedOutputs {
        try await lifecycle { storage, grant in
            try await storage.preparationOperations(grant).prepare(original: original, recipe: recipe, savePlan: savePlan)
        }
    }
    #endif

    func prepareOriginal(packageID: UUID, draftGeneration: UUID, ordinal: Int64,
                         kind: SharedMediaAcquisitionIntent.Kind) async throws -> SharedMediaAcquisitionIntent {
        try await lifecycle { [self] storage, grant in
            try storage.originalReadback(grant: grant).request(packageID: packageID, draftGeneration: draftGeneration, ordinal: ordinal, kind: kind, epoch: writerEpoch)
        }
    }

    func acquireOriginal(_ request: SharedMediaAcquisitionIntent,
                         load: @escaping @Sendable () async throws -> Data) async throws -> SharedMediaAcquisitionResult {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] grant in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            let snapshot = try await storage.inspectOriginals(grant: grant)
            if let existing = try storage.originalReceipt(request, grant: grant) {
                if case .completed(_, let result) = existing { return result }
                throw PhotoPreparationFailure.cleanupPending
            }
            guard !snapshot.requiresRecovery, request.writerEpoch == writerEpoch else { throw PhotoPreparationFailure.cleanupPending }
            try grant.validate()
            var loaderStarted = false
            do {
                do { try storage.reserveOriginal(request, grant: grant) } catch { /* Exact saved-state recovery below. */ }
                guard case .reserved = try storage.originalReceipt(request, grant: grant) else { throw SharedMediaStorageFailure.conflict }
                let reserved = try storage.reservedState(request, grant: grant)
                try grant.validate()
                // This is the sole loader invocation. Cold reservations never reach it.
                loaderStarted = true
                let data: Data
                do {
                    writerActive = true; defer { writerActive = false }
                    data = try await storage.loadOriginal(load, grant: grant)
                }
                try grant.validate()
                guard try storage.reservedState(request, grant: grant) == reserved else { throw SharedMediaStorageFailure.stale }
                let proof: SharedMediaPhotoRetirementInspection
                do {
                    writerActive = true; defer { writerActive = false }
                    proof = try await storage.writeOriginal(data, request: request, grant: grant)
                }
                try grant.validate()
                guard try storage.reservedState(request, grant: grant) == reserved else { throw SharedMediaStorageFailure.stale }
                do { try storage.completeOriginal(request, proof: proof, grant: grant) } catch { /* Exact saved-state recovery below. */ }
                guard case .completed(_, let result) = try storage.originalReceipt(request, grant: grant) else { throw SharedMediaStorageFailure.conflict }
                return result
            } catch {
                pendingSettlement = .init(request: request, loaderStarted: loaderStarted, writerReturned: !writerActive)
                if let result = try? reconcileSettlement() { return result }
                throw error
            }
        }
    }

    /// Called only after the actual loader/file operation has returned. This
    /// settlement path deliberately does not reuse a cancelled dispatch check.
    private func reconcileSettlement() throws -> SharedMediaAcquisitionResult? {
        guard let pending = pendingSettlement, let storage else { return nil }
        let grant = SharedMediaNativeSettlementGrant(owner: self, identity: pending.id,
            request: pending.request, loaderStarted: pending.loaderStarted, ownerID: account.ownerID, writerEpoch: writerEpoch)
        let result = try storage.settleOriginal(grant)
        pendingSettlement = nil
        return result
    }

    fileprivate func validateDispatch(identity: UUID, lease: AccountBoundWorkLease) throws {
        guard openKind == .qualification, pendingSettlement == nil, activeDispatchID == identity else { throw SharedMediaStorageFailure.closed }
        try check(lease)
    }
    fileprivate func validateScoped(identity: UUID, lease: AccountBoundWorkLease,
                                    scope: SharedMediaNativeScopeIdentity, epoch: UUID) throws {
        guard openKind == .scopedInspection, activeDispatchID == identity, pendingSettlement == nil,
              scopedIdentity == scope, scope.ownerID == account.ownerID, writerEpoch == epoch else { throw SharedMediaStorageFailure.closed }
        try check(lease)
    }
    fileprivate func validateApp(identity: UUID, lease: AccountBoundWorkLease, epoch: UUID) throws {
        guard openKind == .appInitialization, activeDispatchID == identity, writerEpoch == epoch,
              pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }; try check(lease)
    }
    fileprivate func validateAppDispatch(identity: UUID, lease: AccountBoundWorkLease, profile: SharedMediaNativeAppProfile, parent: URL, epoch: UUID) throws {
        guard openKind == .appDispatch, activeDispatchID == identity, writerEpoch == epoch,
              appProfile == profile, appParent == parent, profile.ownerID == account.ownerID,
              pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }; try check(lease)
    }
    fileprivate func validateSettlement(identity: UUID, request: SharedMediaAcquisitionIntent, loaderStarted: Bool) throws {
        guard openKind == .qualification, let pending = pendingSettlement, pending.id == identity, pending.request == request,
              pending.loaderStarted == loaderStarted, pending.writerReturned, !writerActive,
              phase == .ready || phase == .suspended else { throw SharedMediaStorageFailure.closed }
    }

    private func check(_ lease: AccountBoundWorkLease) throws {
        guard phase == .opening || phase == .ready, let registration, drain.isCurrent(registration),
              lease.session.userID == account.ownerID, account.isCurrent(lease) else { throw PhotoPreparationFailure.accountChanged }
        try Task.checkCancellation()
    }

    private func perform<T: Sendable>(_ body: @escaping @MainActor (SharedMediaNativeDispatchGrant) async throws -> T) async throws -> T {
        guard openKind == .qualification else { throw SharedMediaStorageFailure.closed }
        return try await performOperation { [self] lease, identity in
            let grant = SharedMediaNativeDispatchGrant(owner: self, identity: identity, lease: lease, ownerID: account.ownerID, writerEpoch: writerEpoch)
            return try await body(grant)
        }
    }

    private func performOperation<T: Sendable>(_ body: @escaping @MainActor (AccountBoundWorkLease, UUID) async throws -> T) async throws -> T {
        guard cancelActive == nil, let registration, drain.isCurrent(registration) else { throw PhotoPreparationFailure.busy }
        let lease = try account.begin()
        do { try check(lease) } catch { account.finish(lease); throw error }
        let identity = UUID()
        activeDispatchID = identity
        let task = Task { @MainActor in
            defer { activeDispatchID = nil; account.finish(lease); cancelActive = nil; awaitActive = nil }
            let result = try await body(lease, identity)
            try check(lease)
            return result
        }
        cancelActive = { task.cancel() }
        awaitActive = { _ = await task.result }
        let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard phase == .ready, drain.isCurrent(registration) else { throw PhotoPreparationFailure.accountChanged }
        try Task.checkCancellation()
        return result
    }

    func invalidateAndAwaitForAccountTransition() async -> Bool {
        phase = .suspended
        if let registration { drain.seal(registration) }
        cancelActive?()
        await awaitActive?()
        // Durable held settlement retains liability but permits process-fence
        // release after actual termination. Unknown settlement remains closed.
        do { _ = try reconcileSettlement() } catch { return false }
        guard pendingSettlement == nil else { return false }
        storage = nil; scopedIdentity = nil; appProfile = nil; appParent = nil
        return true
    }
}

/// Read-only identity capability, minted only by this same registered owner.
@MainActor
final class SharedMediaNativeScopedReadGrant {
    private weak var owner: SharedMediaNativeOriginalOwner?
    private let identity: UUID
    private let lease: AccountBoundWorkLease
    let scope: SharedMediaNativeScopeIdentity
    let writerEpoch: UUID
    #if DEBUG
    let debug: SharedMediaNativeDebugHooks
    #endif
    fileprivate init(owner: SharedMediaNativeOriginalOwner, identity: UUID, lease: AccountBoundWorkLease,
                     scope: SharedMediaNativeScopeIdentity, writerEpoch: UUID) {
        self.owner = owner; self.identity = identity; self.lease = lease; self.scope = scope; self.writerEpoch = writerEpoch
        #if DEBUG
        debug = owner.debug
        #endif
    }
    func validate() throws {
        guard let owner else { throw SharedMediaStorageFailure.closed }
        try owner.validateScoped(identity: identity, lease: lease, scope: scope, epoch: writerEpoch)
    }
}

/// Separate initialization-only capability; it cannot enter existing dispatch,
/// scoped-read or settlement APIs.
@MainActor
final class SharedMediaNativeAppGrant {
    private weak var owner: SharedMediaNativeOriginalOwner?
    private let identity: UUID, lease: AccountBoundWorkLease
    let ownerID: UUID, writerEpoch: UUID
    #if DEBUG
    let debug: SharedMediaNativeDebugHooks
    #endif
    fileprivate init(owner: SharedMediaNativeOriginalOwner, identity: UUID, lease: AccountBoundWorkLease,
                     ownerID: UUID, writerEpoch: UUID) {
        self.owner = owner; self.identity = identity; self.lease = lease; self.ownerID = ownerID; self.writerEpoch = writerEpoch
        #if DEBUG
        debug = owner.debug
        #endif
    }
    func validate() throws {
        guard let owner else { throw SharedMediaStorageFailure.closed }
        try owner.validateApp(identity: identity, lease: lease, epoch: writerEpoch)
    }
}

/// Existing V2 authority is separate from both initialization and V1 dispatch.
@MainActor
final class SharedMediaNativeAppDispatchGrant {
    private weak var owner: SharedMediaNativeOriginalOwner?
    private let identity: UUID, lease: AccountBoundWorkLease
    let profile: SharedMediaNativeAppProfile
    let parent: URL
    let writerEpoch: UUID
    #if DEBUG
    let debug: SharedMediaNativeDebugHooks
    #endif
    var ownerID: UUID { profile.ownerID }
    fileprivate init(owner: SharedMediaNativeOriginalOwner, identity: UUID, lease: AccountBoundWorkLease,
                     profile: SharedMediaNativeAppProfile, parent: URL, writerEpoch: UUID) {
        self.owner = owner; self.identity = identity; self.lease = lease
        self.profile = profile; self.parent = parent; self.writerEpoch = writerEpoch
        #if DEBUG
        debug = owner.debug
        #endif
    }
    func validate() throws {
        guard let owner else { throw SharedMediaStorageFailure.closed }
        try owner.validateAppDispatch(identity: identity, lease: lease, profile: profile, parent: parent, epoch: writerEpoch)
    }
}

/// These capabilities can only be minted by this file's registered owner.
/// They are separate types so settlement cannot be supplied to a dispatch API.
@MainActor
final class SharedMediaNativeDispatchGrant {
    private weak var owner: SharedMediaNativeOriginalOwner?
    private let identity: UUID
    private let lease: AccountBoundWorkLease
    let ownerID: UUID
    let writerEpoch: UUID
    let profile = "nativeQualificationV1"
    #if DEBUG
    let debug: SharedMediaNativeDebugHooks
    #endif
    fileprivate init(owner: SharedMediaNativeOriginalOwner, identity: UUID, lease: AccountBoundWorkLease, ownerID: UUID, writerEpoch: UUID) {
        self.owner = owner; self.identity = identity; self.lease = lease; self.ownerID = ownerID; self.writerEpoch = writerEpoch
        #if DEBUG
        debug = owner.debug
        #endif
    }
    func validate() throws {
        guard let owner else { throw SharedMediaStorageFailure.closed }
        try owner.validateDispatch(identity: identity, lease: lease)
    }
}

@MainActor
final class SharedMediaNativeSettlementGrant {
    private weak var owner: SharedMediaNativeOriginalOwner?
    private let identity: UUID
    let request: SharedMediaAcquisitionIntent
    let loaderStarted: Bool
    let ownerID: UUID
    let writerEpoch: UUID
    let profile = "nativeQualificationV1"
    fileprivate init(owner: SharedMediaNativeOriginalOwner, identity: UUID, request: SharedMediaAcquisitionIntent,
                     loaderStarted: Bool, ownerID: UUID, writerEpoch: UUID) {
        self.owner = owner; self.identity = identity; self.request = request; self.loaderStarted = loaderStarted
        self.ownerID = ownerID; self.writerEpoch = writerEpoch
    }
    func validate() throws {
        guard let owner else { throw SharedMediaStorageFailure.closed }
        try owner.validateSettlement(identity: identity, request: request, loaderStarted: loaderStarted)
    }
}
