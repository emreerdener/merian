import Foundation
import SwiftData

/// Registered acquisition/release settlement owner; production wiring stays disabled.
@MainActor
final class SharedMediaNativeOriginalOwner {
    private let openKind: SharedMediaNativeOriginalOpenKind
    private var scopedIdentity: SharedMediaNativeScopeIdentity?
    private var appProfile: SharedMediaNativeAppProfile?, appParent: URL?
    private let account: PhotoOriginalPreparationOwner.AccountAccess, drain: SharedMediaNativeOriginalDrain
    private var registration: SharedMediaNativeOriginalDrain.Registration?
    private var phase = SharedMediaNativeOriginalPhase.unopened
    private let writerEpoch = UUID()
    private var pendingSettlement: SharedMediaNativeOriginalPendingSettlement?
    private let releaseStageSettlement = SharedMediaNativeReleaseStageSettlement()
    #if DEBUG
    /// Read-only fault-test observation. No capability or mutation grant escapes.
    var heldOriginalAdmissionClosedForTesting: Bool { phase == .suspended }
    var observedHeldOriginalAbsenceForTesting: Bool {
        releaseStageSettlement.pendingOriginalDisposal?.permit.hasObservedAbsence ?? false
    }
    #endif
    private var writerActive = false
    private var activeDispatchID: UUID?
    #if DEBUG
    fileprivate let debug = SharedMediaNativeDebugHooks()
    #endif
    private var storage: SharedMediaNativeStorageRepository?
    private var cancelActive: (() -> Void)?, awaitActive: (() async -> Void)?

    private init(account: PhotoOriginalPreparationOwner.AccountAccess, drain: SharedMediaNativeOriginalDrain,
                 openKind: SharedMediaNativeOriginalOpenKind = .qualification) throws {
        self.account = account; self.drain = drain; self.openKind = openKind
        registration = try drain.register(account: account) { [weak self] in
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
        guard openKind == .qualification, phase == .unopened, let registration, drain.isCurrent(registration, container: container) else { throw SharedMediaStorageFailure.closed }
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
                       availableBytes: Int64? = nil, discovery: SharedMediaNativeBootstrapDiscovery? = nil) async throws -> SharedMediaStorageSnapshot {
        defer { discovery?.invalidate() }
        guard openKind == .appInitialization, phase == .unopened,
              let registration, drain.isCurrent(registration, container: container, discovery: discovery) else { throw SharedMediaStorageFailure.closed }
        phase = .opening; debug.bootstrapFault = fault; debug.bootstrapAvailableBytes = availableBytes
        do {
            return try await performOperation { [self] lease, identity in
                let grant = SharedMediaNativeAppGrant(owner: self, identity: identity, lease: lease,
                    ownerID: account.ownerID, writerEpoch: writerEpoch)
                let candidate = try SharedMediaNativeStorageRepository.initializeApp(container: container, parent: parent,
                    inventoryID: inventoryID, grant: grant, discovery: discovery)
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
    func openApp(container: ModelContainer, parent: URL, inventoryID: UUID, pause: (@Sendable () async -> Void)? = nil,
                 inspectionTrace: SharedMediaNativeDebugHooks.InspectionTrace? = nil,
                 discovery: SharedMediaNativeBootstrapDiscovery? = nil) async throws -> SharedMediaNativeScopedSnapshot {
        defer { discovery?.invalidate() }
        guard openKind == .appDispatch, phase == .unopened, let registration, drain.isCurrent(registration, container: container, discovery: discovery) else { throw SharedMediaStorageFailure.closed }
        phase = .opening; debug.scopedPagePause = pause; debug.inspectionTrace = inspectionTrace
        defer {
            inspectionTrace?.finish()
            if debug.inspectionTrace === inspectionTrace { debug.inspectionTrace = nil }
        }
        do {
            return try await performOperation { [self] lease, identity in
                inspectionTrace?.enter(.identity)
                let profile = try SharedMediaNativeAppEligibility.identity(container: container, inventoryID: inventoryID, ownerID: account.ownerID)
                appProfile = profile; appParent = parent
                let grant = SharedMediaNativeAppDispatchGrant(owner: self, identity: identity, lease: lease,
                    profile: profile, parent: parent, writerEpoch: writerEpoch)
                inspectionTrace?.enter(.repository)
                let candidate = try SharedMediaNativeStorageRepository.openApp(container: container, parent: parent,
                    inventoryID: inventoryID, grant: grant, discovery: discovery)
                storage = candidate
                inspectionTrace?.enter(.inspect)
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
              let registration, drain.isCurrent(registration, container: container) else { throw SharedMediaStorageFailure.closed }
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
        try await withAppDispatch(settled: false) { storage, grant in try await storage.inspectApp(grant: grant) }
    }
    func prepareAppMetadata(packageID: UUID, draftGeneration: UUID, contexts: [ObservationContext],
                            presentation: [PhotoPreparationImagePresentation]? = nil) async throws -> SharedMediaNativeAppMetadataRequest {
        try await appMetadata { try $0.request(packageID: packageID, draftGeneration: draftGeneration, contexts: contexts, presentation: presentation) }
    }
    func saveAppMetadata(_ request: SharedMediaNativeAppMetadataRequest) async throws -> Int64 {
        try await appMetadata { try $0.apply(request) }
    }
    private func appMetadata<T: Sendable>(_ body: @escaping @MainActor (SharedMediaNativeAppMetadataOperations) throws -> T) async throws -> T {
        try await withAppDispatch(settled: false) { storage, grant in
            let operation = try await storage.appMetadata(grant: grant)
            try grant.validate(); return try body(operation)
        }
    }
    func appPreparationWorkflow<T: Sendable>(_ body: @escaping @MainActor (SharedMediaNativeAppPreparationOperations) async throws -> T) async throws -> T {
        try await withAppDispatch { storage, grant in
            let operation = try await storage.appPreparation(grant: grant)
            try grant.validate(); return try await body(operation)
        }
    }
    func appOriginalLifecycle<T: Sendable>(_ body: @escaping @MainActor (SharedMediaNativeAppOriginalOperations) async throws -> T) async throws -> T {
        try await withAppDispatch { storage, grant in
            let operation = try await storage.appOriginal(grant: grant)
            try grant.validate(); return try await body(operation)
        }
    }
    func appPendingWorkflow<T: Sendable>(_ body: @escaping @MainActor (SharedMediaNativeAppPendingOperations) async throws -> T) async throws -> T {
        try await withAppDispatch { storage, grant in
            let operation = try await storage.appPending(grant: grant)
            try grant.validate(); return try await body(operation)
        }
    }
    func discoverAppReceivingIntent(packageID: UUID) async throws -> SharedMediaNativeReceivingIntent.Prepared? {
        try await withAppDispatch { storage, grant in
            try await storage.appReceivingIntent(grant: grant, packageID: packageID)
        }
    }
    func discoverAppReceivingSlot(packageID: UUID) async throws -> SharedMediaNativeReceivingIntentGraph.Row? {
        try await withAppDispatch { storage, grant in
            try await storage.appReceivingSlot(grant: grant, packageID: packageID)
        }
    }
    func appReceivingWorkflow<T: Sendable>(lock: SharedMediaNativeReceivingLockGrant, _ body: @escaping @MainActor (SharedMediaNativeAppReceivingOperations) async throws -> T) async throws -> T {
        try lock.validate()
        return try await withAppDispatch { storage, grant in
            try lock.validate()
            let operation = try await storage.appReceiving(grant: grant, lock: lock, releaseStage: self.releaseStageSettlement)
            try lock.validate(); try grant.validate(); return try await body(operation)
        }
    }
    /// An outer audit or lock failure must also spend an existing continuation.
    func abandonAppReleaseContinuation(_ progress: SharedMediaNativeReceivingReleaseValues.Progress) {
        releaseStageSettlement.abandonContinuation(progress)
    }
    func appReleaseStageWorkflow<T: Sendable>(lock: SharedMediaNativeReceivingLockGrant,
        _ body: @escaping @MainActor (SharedMediaNativeAppReleaseStageOperations) async throws -> T) async throws -> T {
        try lock.validate()
        guard pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await withAppDispatch(settled: false, releaseStage: true) { storage, grant in
            try await body(storage.appReleaseStage(grant: grant, lock: lock, settlement: self.releaseStageSettlement))
        }
    }
    private func withAppDispatch<T: Sendable>(settled: Bool = true, releaseStage: Bool = false,
        _ body: @escaping @MainActor (SharedMediaNativeStorageRepository, SharedMediaNativeAppDispatchGrant) async throws -> T) async throws -> T {
        guard openKind == .appDispatch, phase == .ready, !settled || pendingSettlement == nil, releaseStage || !releaseStageSettlement.hasPending else { throw SharedMediaStorageFailure.closed }
        return try await performOperation { [self] lease, identity in
            guard let storage, let appProfile, let appParent else { throw SharedMediaStorageFailure.closed }
            let grant = SharedMediaNativeAppDispatchGrant(owner: self, identity: identity, lease: lease,
                profile: appProfile, parent: appParent, writerEpoch: writerEpoch)
            return try await body(storage, grant)
        }
    }
    func prepareAppOriginal(packageID: UUID, draftGeneration: UUID, ordinal: Int64,
                            kind: SharedMediaAcquisitionIntent.Kind) async throws -> SharedMediaAcquisitionIntent {
        try await appAcquisition(request: nil) { try $0.request(packageID: packageID, draftGeneration: draftGeneration, ordinal: ordinal, kind: kind) }
    }
    func acquireAppOriginal(_ request: SharedMediaAcquisitionIntent,
                            load: @escaping @Sendable () async throws -> Data) async throws -> SharedMediaAcquisitionResult {
        try await appAcquisition(request: request) { [self] operation in
            if let saved = try operation.receipt(request) {
                if case .completed(_, let result) = saved { return result }
                throw PhotoPreparationFailure.cleanupPending
            }
            _ = try operation.settlement(request)
            var loaderStarted = false
            do {
                return try await operation.acquire(request, load: load,
                    writerState: { self.writerActive = $0 }, didStartLoader: { loaderStarted = true })
            } catch {
                pendingSettlement = .init(request: request, loaderStarted: loaderStarted, writerReturned: !writerActive, appTicket: try operation.settlement(request))
                if let result = try? await reconcileAppSettlement() { return result }
                throw error
            }
        }
    }
    private func appAcquisition<T: Sendable>(request: SharedMediaAcquisitionIntent?,
        _ body: @escaping @MainActor (SharedMediaNativeAppAcquisitionOperations) async throws -> T) async throws -> T {
        try await withAppDispatch { storage, grant in try await body(storage.appAcquisition(grant: grant, request: request)) }
    }
    private func reconcileAppSettlement() async throws -> SharedMediaAcquisitionResult? {
        guard let pending = pendingSettlement, let ticket = pending.appTicket, let storage else { return nil }
        let grant = SharedMediaNativeAppSettlementGrant(owner: self, identity: pending.id, ticket: ticket,
            loaderStarted: pending.loaderStarted, writerEpoch: writerEpoch)
        // A separate task permits bounded settlement after dispatch cancellation.
        // It stays awaited, retains all fences and can never invoke a writer.
        let result = try await Task { @MainActor in try storage.settleAppOriginal(grant) }.value
        pendingSettlement = nil; return result
    }
    fileprivate func validateAppSettlement(identity: UUID, ticket: SharedMediaNativeAppAcquisitionSettlement, loaderStarted: Bool, epoch: UUID) throws {
        guard openKind == .appDispatch, let pending = pendingSettlement, pending.id == identity,
              pending.appTicket?.request == ticket.request, pending.request == ticket.request,
              pending.loaderStarted == loaderStarted, pending.writerReturned, !writerActive,
              ticket.profile == appProfile, ticket.profile.ownerID == account.ownerID, epoch == writerEpoch,
              phase == .ready || phase == .suspended else { throw SharedMediaStorageFailure.closed }
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
    func setAcquisitionEntryPause(_ pause: (@Sendable (SharedMediaNativeOriginalIOEntry) async -> Void)?) async throws {
        guard phase == .ready, cancelActive == nil, let storage else { throw SharedMediaStorageFailure.closed }
        await storage.setAcquisitionEntryPause(pause)
    }
    var inspectionAuditCount: Int { debug.inspectionAuditCount }
    var hasInspectionTraceForTesting: Bool { debug.inspectionTrace != nil }
    func setMetadataFault(_ fault: ((SharedMediaNativeMetadataBoundary) throws -> Void)?, availableBytes: Int64? = nil) throws {
        guard phase == .ready, cancelActive == nil, storage != nil else { throw SharedMediaStorageFailure.closed }
        debug.metadataFault = fault; debug.metadataAvailableBytes = availableBytes
    }
    #endif

    func qualificationWorkflow<T: Sendable>(recovery: Bool = false,
        _ body: @escaping @MainActor (SharedMediaNativeQualificationOperations) async throws -> T) async throws -> T {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] grant in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            let snapshot = try await storage.inspectOriginals(grant: grant)
            guard recovery || !snapshot.requiresRecovery else { throw PhotoPreparationFailure.cleanupPending }
            return try await body(storage.qualificationOperations(grant: grant))
        }
    }
    #if DEBUG
    func setLifecycleFault(_ fault: ((SharedMediaNativeLifecycleBoundary) throws -> Void)?, availableBytes: Int64? = nil) throws {
        guard phase == .ready, cancelActive == nil, storage != nil else { throw SharedMediaStorageFailure.closed }; debug.lifecycleFault = fault
        debug.lifecycleAvailableBytes = availableBytes
    }

    func setPreparationFault(_ fault: ((SharedMediaNativePreparationBoundary) throws -> Void)?, availableBytes: Int64? = nil, focusFactory: ImageFocusWorkFactory = .init(), fileEpochObserved: ((UUID) -> Void)? = nil) throws {
        guard phase == .ready, cancelActive == nil, storage != nil else { throw SharedMediaStorageFailure.closed }
        debug.preparationFault = fault; debug.preparationAvailableBytes = availableBytes; debug.preparationFocusFactory = focusFactory
        debug.preparationFileEpochObserved = fileEpochObserved
    }
    #endif

    /// Exact saved acknowledgement precedes current physical availability checks.
    func freeze(_ request: SharedMediaNativeFreezeRequest) async throws -> SharedMediaNativeFreezeCommit {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] grant in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            return try await storage.qualificationOperations(grant: grant).preparationOperations().freeze(request)
        }
    }

    func prepareOriginal(packageID: UUID, draftGeneration: UUID, ordinal: Int64,
                         kind: SharedMediaAcquisitionIntent.Kind) async throws -> SharedMediaAcquisitionIntent {
        try await qualificationWorkflow { [self] operations in
            try operations.originalReadback().request(packageID: packageID, draftGeneration: draftGeneration, ordinal: ordinal, kind: kind, epoch: writerEpoch)
        }
    }

    func acquireOriginal(_ request: SharedMediaAcquisitionIntent,
                         load: @escaping @Sendable () async throws -> Data) async throws -> SharedMediaAcquisitionResult {
        guard phase == .ready, pendingSettlement == nil else { throw SharedMediaStorageFailure.closed }
        return try await perform { [self] grant in
            guard let storage else { throw SharedMediaStorageFailure.closed }
            let snapshot = try await storage.inspectOriginals(grant: grant)
            let operations = try storage.qualificationOperations(grant: grant)
            if let existing = try operations.originalReceipt(request) {
                if case .completed(_, let result) = existing { return result }
                throw PhotoPreparationFailure.cleanupPending
            }
            guard !snapshot.requiresRecovery, request.writerEpoch == writerEpoch else { throw PhotoPreparationFailure.cleanupPending }
            try grant.validate()
            var loaderStarted = false
            do {
                return try await operations.acquireOriginal(request, load: load,
                    writerState: { self.writerActive = $0 }, didStartLoader: { loaderStarted = true })
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
        phase = .suspended; releaseStageSettlement.closeAdmission()
        if let registration { drain.seal(registration) }
        cancelActive?()
        await awaitActive?()
        do {
            if pendingSettlement?.appTicket != nil { _ = try await reconcileAppSettlement() }
            else { _ = try reconcileSettlement() }
            try await releaseStageSettlement.reconcileAfterTermination()
        } catch { return false }
        guard pendingSettlement == nil, !releaseStageSettlement.hasPending else { return false }
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

/// Terminated-writer settlement only; V1 grants and app dispatch cannot mint it.
@MainActor
final class SharedMediaNativeAppSettlementGrant {
    private weak var owner: SharedMediaNativeOriginalOwner?
    private let identity: UUID
    let ticket: SharedMediaNativeAppAcquisitionSettlement
    let loaderStarted: Bool
    let writerEpoch: UUID
    fileprivate init(owner: SharedMediaNativeOriginalOwner, identity: UUID, ticket: SharedMediaNativeAppAcquisitionSettlement,
                     loaderStarted: Bool, writerEpoch: UUID) {
        self.owner = owner; self.identity = identity; self.ticket = ticket
        self.loaderStarted = loaderStarted; self.writerEpoch = writerEpoch
    }
    func validate() throws {
        guard let owner else { throw SharedMediaStorageFailure.closed }
        try owner.validateAppSettlement(identity: identity, ticket: ticket, loaderStarted: loaderStarted, epoch: writerEpoch)
    }
}
