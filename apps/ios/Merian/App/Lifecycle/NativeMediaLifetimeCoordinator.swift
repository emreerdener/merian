import Foundation
import Observation
import SwiftData

/// Owns the app's native-media account lifetime, retained storage admission and
/// prepared-input drains. AppDIContainer constructs this owner; feature and Auth
/// callers enter its explicit role-specific methods directly.
@MainActor
@Observable
final class NativeMediaLifetimeCoordinator {
    private let supabaseManager: SupabaseManager
    private let offlineQueueManager: OfflineQueueManager
    private let scanRepository: ScanRepository
    private let privateScanMapStore: PrivateScanMapStore

    init(manager: SupabaseManager, queue: OfflineQueueManager, repository: ScanRepository, mapStore: PrivateScanMapStore) {
        supabaseManager = manager; offlineQueueManager = queue
        scanRepository = repository; privateScanMapStore = mapStore
    }

    @ObservationIgnored private(set) lazy var libraryCleanup = NativeLibraryCleanup(
        manager: supabaseManager, queue: offlineQueueManager, repository: scanRepository, mapStore: privateScanMapStore,
        preparedHost: { [weak self] in self?.preparedReanalysisHostOwner },
        captureRuntime: { [weak self] context, authorization in
            guard let self else { throw SharedMediaStorageFailure.closed }
            return try self.libraryCleanupRuntime(modelContext: context, authorization: authorization)
        })

    /// App lifetime retains idle fresh-media inputs as well as active presentation work.
    private(set) var preparedReanalysisHostOwner = CaptureAudioReanalysisHostOwner()
    @ObservationIgnored private var captureDraftWorkHost = CaptureInitialDraftWorkHost()
    @ObservationIgnored private var captureDraftProducerHost = CaptureInitialDraftWorkHost()

    /// Registered separately from History's prepared inputs. Shutdown waits for
    /// actual rendering/staging exit and cleanup of any undelivered result.
    func runCaptureDraftWork<Value: Sendable>(
        ownerID: UUID,
        operation: @escaping @MainActor () async throws -> Value,
        discard: @escaping @MainActor (Value) async -> Void = { _ in }
    ) async throws -> Value {
        let (host, current) = try captureDraftWorkAdmission(ownerID: ownerID)
        return try await host.run(requireCurrent: current, operation: operation, discard: discard)
    }

    /// The retained registration owns files during both preparation and idle
    /// review. UI replacement/clear must release its lease before dropping it.
    func captureDraftPresentation(session: CaptureInitialDraftSession) async throws
        -> CaptureInitialDraftWorkHost.Retained<CaptureInitialDraftPresentation> {
        let (host, current) = try captureDraftWorkAdmission(ownerID: session.identity.ownerID)
        let resources = CaptureDraftPresentationResources()
        return try await host.runRetained(requireCurrent: current,
            operation: { try await session.reviewPresentation(resources: resources) },
            cleanup: { await resources.discard() })
    }

    func captureDraftProducerResources(ownerID: UUID) async throws
        -> CaptureInitialDraftWorkHost.Retained<CaptureInitialProducerResources> {
        let (host, current) = try captureDraftWorkAdmission(ownerID: ownerID, producers: true)
        let resources = CaptureInitialProducerResources()
        return try await host.runRetained(requireCurrent: current,
            operation: { resources }, cleanup: { await resources.discard() })
    }

    private func captureDraftWorkAdmission(ownerID: UUID, producers: Bool = false) throws
        -> (CaptureInitialDraftWorkHost, @MainActor () throws -> Void) {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              let container = offlineQueueManager.modelContext?.container,
              supabaseManager.currentUser?.id == ownerID else { throw SharedMediaStorageFailure.closed }
        let manager = supabaseManager, generation = manager.authSessionGeneration
        let host = producers ? captureDraftProducerHost : captureDraftWorkHost
        let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: ownerID,
            begin: { try manager.beginUnownedAccountBoundWork(expectedUserID: ownerID) },
            isCurrent: { manager.isAccountBoundWorkLeaseCurrent($0) },
            finish: { manager.finishAccountBoundWork($0) })
        let borrow = try admitPreparedInputBorrow(container: container, account: account,
            role: producers ? .captureDraftProducers : .captureDraftWork,
            consumer: host, install: { try manager.installNativeMediaAccountTransitionDrain($0) },
            close: {
                guard await host.close() else { return false }
                return await FileIOActor.shared.retryProducerCleanup()
            })
        let fence = try borrow.fence(container: container)
        return (host, { [self] in
            guard (producers ? captureDraftProducerHost : captureDraftWorkHost) === host,
                  offlineQueueManager.modelContext?.container === container,
                  manager.currentUser?.id == ownerID, manager.authSessionGeneration == generation,
                  !manager.isAuthTransitionInProgress, !manager.libraryAccountRecoveryRequired,
                  !manager.librarySignOutRecoveryPending else { throw SharedMediaStorageFailure.closed }
            try borrow.require(container: container, fence: fence)
        })
    }
    /// Called synchronously under the explicit feature-open account lease.
    func prepareReanalysisHostLifetimeForFeature() throws {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified else { throw ObservationHistoryError.unavailable }
        try preparedReanalysisHostOwner.armAccountLifetime(manager: supabaseManager)
    }

    /// Reuse construction provenance without adopting the native-media profile.
    func reanalysisStartupForFeature(container: ModelContainer) throws -> NativeReleaseStartupAdmission {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              let startup = nativeMediaStartup, startup.container === container else { throw ObservationHistoryError.unavailable }
        return startup.admission
    }

    func reanalysisBorrowForFeature(container: ModelContainer) throws -> SharedMediaNativeOriginalDrain.LocalBorrow {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              let ownerID = supabaseManager.currentUser?.id else { throw ObservationHistoryError.unavailable }
        let manager = supabaseManager
        let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: ownerID,
            begin: { try manager.beginUnownedAccountBoundWork(expectedUserID: ownerID) },
            isCurrent: { manager.isAccountBoundWorkLeaseCurrent($0) },
            finish: { manager.finishAccountBoundWork($0) })
        let owner = preparedReanalysisHostOwner
        return try admitPreparedInputBorrow(container: container, account: account,
            consumer: owner, install: { try manager.installNativeMediaAccountTransitionDrain($0) },
            close: { await owner.drainAccountLifetimeDisposition(manager: manager).isRuntimeQuiescent })
    }

    private func retainedNativeLifetime(install: (SharedMediaNativeOriginalDrain) throws -> Void) throws -> SharedMediaNativeOriginalDrain {
        if let lifetime = nativeMediaLifetime { return lifetime }
        guard let startup = nativeMediaStartup else { throw SharedMediaStorageFailure.closed }
        let lifetime = SharedMediaNativeOriginalDrain(container: startup.container, admission: startup.admission) { [weak self] completed in
            guard let self, self.nativeMediaLifetime === completed else { return }
            self.nativeMediaOwner = nil
        }
        try install(lifetime)
        nativeMediaLifetime = lifetime
        return lifetime
    }

    private func admitPreparedInputBorrow(container: ModelContainer, account: PhotoOriginalPreparationOwner.AccountAccess,
                                          role: SharedMediaNativeOriginalDrain.LocalConsumer = .preparedInputs,
                                          consumer: AnyObject, install: (SharedMediaNativeOriginalDrain) throws -> Void,
                                          close: @escaping @MainActor () async -> Bool) throws -> SharedMediaNativeOriginalDrain.LocalBorrow {
        let lease = try account.begin()
        defer { account.finish(lease) }
        guard account.isCurrent(lease), lease.session.userID == account.ownerID,
              nativeMediaStartup?.container === container else { throw PhotoPreparationFailure.accountChanged }
        let lifetime = try retainedNativeLifetime(install: install)
        try lifetime.bindPreparedAccount(account)
        return try lifetime.borrowLocalFence(for: consumer, role: role, container: container, close: close)
    }

    /// Called by this exact manager after Auth closes admission. An unarmed lifetime is inert.
    func awaitPreparedReanalysisHostDrain(for manager: SupabaseManager,
                                          recoveryAuthority: AuthRecoveryAuthority? = nil) async -> Bool {
        guard manager === supabaseManager, recoveryAuthority?.isCurrent ?? true else { return false }
        let result = await preparedReanalysisHostOwner.drainAccountLifetimeDisposition(manager: manager)
        guard recoveryAuthority?.isCurrent ?? true else { return false }
        return result == .cleaned || (recoveryAuthority != nil && result.isRuntimeQuiescent)
    }

    private func libraryCleanupRuntime(modelContext: ModelContext,
                                       authorization: SharedMediaNativeErasureAuthorization) throws -> NativeLibraryCleanup.Runtime? {
        guard let startup = nativeMediaStartup else { return nil }
        let lifetime = nativeMediaLifetime, prepared = preparedReanalysisHostOwner
        let work = captureDraftWorkHost, producers = captureDraftProducerHost
        let check: () throws -> Void = { [self] in
            guard startup.container === modelContext.container,
                  nativeMediaStartup?.container === startup.container,
                  offlineQueueManager.modelContext?.container === startup.container,
                  nativeMediaLifetime === lifetime, nativeMediaOpening == nil, nativeMediaOwner == nil,
                  lifetime == nil || (lifetime?.isClosed == true && lifetime?.shutdownFinished == true),
                  preparedReanalysisHostOwner === prepared, captureDraftWorkHost === work, captureDraftProducerHost === producers,
                  work.isQuiescent, producers.isQuiescent else { throw SharedMediaStorageFailure.closed }
            _ = try authorization.require(container: startup.container)
        }
        return .init(container: startup.container, admission: startup.admission, check: check)
    }

    @ObservationIgnored private(set) var nativeMediaLifetime: SharedMediaNativeOriginalDrain?
    @ObservationIgnored private(set) var nativeMediaOwner: SharedMediaNativeOriginalOwner?
    @ObservationIgnored private var nativeMediaStartup: (container: ModelContainer, admission: NativeReleaseStartupAdmission)?
    @ObservationIgnored private var nativeMediaOpening: Task<SharedMediaNativeOriginalOwner, Error>?
    @ObservationIgnored private var nativeMediaAccountID: UUID?
    @ObservationIgnored private var captureExecutionDrain: SharedMediaCaptureExecutionDrain?
    @ObservationIgnored private var captureExecutionTask: Task<Void, Never>?
    @ObservationIgnored private var captureFundingDrain: SharedMediaCaptureFundingDrain?
    @ObservationIgnored private var captureHistoryDrain: CaptureCompletedHistoryDrain?
    @ObservationIgnored private var captureHistoryTask: Task<Void, Never>?
    @ObservationIgnored private var captureHistoryTaskID: UUID?
    @ObservationIgnored private var captureHistoryWakePending = false

    /// Stable Auth only. Original bootstrap provenance stays bound to its container;
    /// every retired owner remains terminal, including after a stale completion.
    func renewNativeMediaLifetime(for manager: SupabaseManager, isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        guard let startup = nativeMediaStartup else { return true }
        let lifetime = nativeMediaLifetime, prepared = preparedReanalysisHostOwner, cleanup = offlineQueueManager.reanalysisErasureOwner
        let current = { [self] in
            !Task.isCancelled && isCurrent() && manager === supabaseManager && !manager.isAuthTransitionInProgress &&
                !manager.librarySignOutRecoveryPending && !AccountDeletionLocalCleanupStore.isPending() &&
                offlineQueueManager.modelContext?.container === startup.container && nativeMediaLifetime === lifetime &&
                preparedReanalysisHostOwner === prepared && offlineQueueManager.reanalysisErasureOwner === cleanup
        }
        guard current(), nativeMediaOpening == nil else { return false }
        guard lifetime?.isClosed == true || prepared.isClosed else { return true }
        guard lifetime == nil || lifetime?.shutdownFinished == true else { return false }
        guard await prepared.retireAccountLifetime(manager: manager), current(), await cleanup.retire(), current() else { return false }
        do {
            try offlineQueueManager.renewReanalysisErasureOwner(cleanup) { successor in
                try configureInputRecovery(owner: successor, manager: manager)
                if let lifetime { try manager.retireNativeMediaAccountTransitionDrain(lifetime) }
            }
            preparedReanalysisHostOwner = CaptureAudioReanalysisHostOwner()
            captureDraftWorkHost = CaptureInitialDraftWorkHost()
            captureDraftProducerHost = CaptureInitialDraftWorkHost()
            nativeMediaLifetime = nil; nativeMediaAccountID = nil
            captureFundingDrain = nil; captureExecutionDrain = nil; captureExecutionTask = nil
            captureHistoryDrain = nil; captureHistoryTask?.cancel(); captureHistoryTask = nil; captureHistoryTaskID = nil
            captureHistoryWakePending = false
            return true
        } catch { return false }
    }

    /// Inert in ordinary builds. No account or filesystem work occurs at setup.
    func configureNativeMediaLifetime(container: ModelContainer?, admission: NativeReleaseStartupAdmission?) throws {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified else { return }
        guard nativeMediaStartup == nil, nativeMediaLifetime == nil else { throw SharedMediaStorageFailure.closed }
        guard let container, let admission else { return }
        nativeMediaStartup = (container, admission)
        try configureInputRecovery(owner: offlineQueueManager.reanalysisErasureOwner, manager: supabaseManager)
        offlineQueueManager.captureExecutionRecovery = { [weak self] in self?.requestCaptureExecution() }
        offlineQueueManager.captureFundingRecovery = { [weak self] in await self?.drainCaptureFunding() }
        offlineQueueManager.captureHistoryRecovery = { [weak self] in self?.requestCaptureHistory() }
    }

    private func requestCaptureExecution() {
        guard captureExecutionTask == nil else { return }
        captureExecutionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { captureExecutionTask = nil }
            await drainCaptureFunding()
            await drainCaptureExecution()
            await drainCaptureHistory()
        }
    }

    private func drainCaptureExecution() async {
        guard let startup = nativeMediaStartup,
              offlineQueueManager.modelContext?.container === startup.container,
              offlineQueueManager.isOnline, !offlineQueueManager.isCurrentNetworkConstrained,
              !supabaseManager.isAuthTransitionInProgress, !supabaseManager.librarySignOutRecoveryPending,
              !AccountDeletionLocalCleanupStore.isPending(), let ownerID = supabaseManager.currentUser?.id else { return }
        if let worker = captureExecutionDrain { await worker.drain(); return }
        do {
            let capture = SharedMediaCaptureAcceptance.mediaAuthority
            var query = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.mediaAuthorityRaw == capture })
            query.fetchLimit = 1
            guard try !ModelContext(startup.container).fetch(query).isEmpty else { return }
            let owner = try await admittedNativeMediaOwner()
            guard owner.isReadyForCaptureSettlement, supabaseManager.currentUser?.id == ownerID,
                  nativeMediaStartup?.container === startup.container,
                  offlineQueueManager.modelContext?.container === startup.container,
                  let lifetime = nativeMediaLifetime, !lifetime.isClosed else { return }
            if let worker = captureExecutionDrain { await worker.drain(); return }
            let manager = supabaseManager
            let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: ownerID,
                begin: { try manager.beginUnownedAccountBoundWork(expectedUserID: ownerID) },
                isCurrent: { manager.isAccountBoundWorkLeaseCurrent($0) },
                finish: { manager.finishAccountBoundWork($0) })
            let worker = SharedMediaCaptureExecutionLifetime.make(owner: owner, account: account, network: .shared,
                isCurrent: { [weak self, weak lifetime] in
                    guard let self, let lifetime else { return false }
                    return self.nativeMediaLifetime === lifetime && !lifetime.isClosed &&
                        self.nativeMediaOwner === owner && manager.currentUser?.id == ownerID &&
                        !manager.isAuthTransitionInProgress && !manager.librarySignOutRecoveryPending &&
                        !AccountDeletionLocalCleanupStore.isPending() &&
                        self.offlineQueueManager.modelContext?.container === startup.container
                }, canUseNetwork: { [weak self] in
                    self?.offlineQueueManager.isOnline == true && self?.offlineQueueManager.isCurrentNetworkConstrained == false
                }, didComplete: { [weak self] in self?.requestCaptureHistory() })
            _ = try admitPreparedInputBorrow(container: startup.container, account: account,
                role: .captureExecution, consumer: worker, install: manager.installNativeMediaAccountTransitionDrain,
                close: { await worker.close(); return !worker.isRunning })
            captureExecutionDrain = worker
            await worker.drain()
        } catch {
            // A later scheduler wake reopens only this retained root. It cannot
            // fall back to the legacy inference or media upload queue.
        }
    }

    private func drainCaptureFunding() async {
        guard let startup = nativeMediaStartup,
              offlineQueueManager.modelContext?.container === startup.container,
              !supabaseManager.isAuthTransitionInProgress, !supabaseManager.librarySignOutRecoveryPending,
              !AccountDeletionLocalCleanupStore.isPending(), let ownerID = supabaseManager.currentUser?.id else { return }
        if let worker = captureFundingDrain { await worker.drain(); return }
        do {
            // This bounded hint avoids opening an empty storage root. It grants
            // no authority; the owner performs the full audit before effects.
            let capture = SharedMediaCaptureAcceptance.mediaAuthority
            var query = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.mediaAuthorityRaw == capture })
            query.fetchLimit = 1
            guard try !ModelContext(startup.container).fetch(query).isEmpty else { return }
            let owner = try await admittedNativeMediaOwner()
            guard owner.isReadyForCaptureSettlement, supabaseManager.currentUser?.id == ownerID,
                  nativeMediaStartup?.container === startup.container,
                  offlineQueueManager.modelContext?.container === startup.container,
                  let lifetime = nativeMediaLifetime, !lifetime.isClosed else { return }
            // Another scheduler pass may have joined the same opening task.
            if let worker = captureFundingDrain { await worker.drain(); return }
            let manager = supabaseManager
            let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: ownerID,
                begin: { try manager.beginUnownedAccountBoundWork(expectedUserID: ownerID) },
                isCurrent: { manager.isAccountBoundWorkLeaseCurrent($0) },
                finish: { manager.finishAccountBoundWork($0) })
            let worker = SharedMediaCaptureFundingLifetime.make(owner: owner, account: account,
                isCurrent: { [weak self, weak lifetime] in
                    guard let self, let lifetime else { return false }
                    return self.nativeMediaLifetime === lifetime && !lifetime.isClosed &&
                        self.nativeMediaOwner === owner && manager.currentUser?.id == ownerID &&
                        !manager.isAuthTransitionInProgress && !manager.librarySignOutRecoveryPending &&
                        !AccountDeletionLocalCleanupStore.isPending() &&
                        self.offlineQueueManager.modelContext?.container === startup.container
                }, didRecover: { [weak self] in self?.requestCaptureHistory() })
            // Register and retain synchronously before the first worker task.
            _ = try admitPreparedInputBorrow(container: startup.container, account: account,
                role: .captureFunding, consumer: worker, install: manager.installNativeMediaAccountTransitionDrain,
                close: { await worker.close(); return !worker.isRunning })
            captureFundingDrain = worker
            await worker.drain()
        } catch {
            // Opening uncertainty is not repaired by a funding worker. A later
            // qualified scheduler/feature admission may retry the retained root.
        }
    }

    private func requestCaptureHistory() {
        requestCaptureHistory { [weak self] in await self?.drainCaptureHistory() }
    }

    private func requestCaptureHistory(drain: @escaping @MainActor () async -> Void) {
        captureHistoryWakePending = true
        guard captureHistoryTask == nil else { return }
        let id = UUID(); captureHistoryTaskID = id
        captureHistoryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if captureHistoryTaskID == id { captureHistoryTask = nil; captureHistoryTaskID = nil }
            }
            while captureHistoryTaskID == id, captureHistoryWakePending, !Task.isCancelled {
                captureHistoryWakePending = false
                await drain()
            }
        }
    }

    private func drainCaptureHistory() async {
        guard let startup = nativeMediaStartup,
              offlineQueueManager.modelContext?.container === startup.container,
              !supabaseManager.isAuthTransitionInProgress, !supabaseManager.libraryAccountRecoveryRequired,
              !supabaseManager.librarySignOutRecoveryPending, !AccountDeletionLocalCleanupStore.isPending(),
              supabaseManager.libraryTransferResult == .completed || supabaseManager.isGuestUser,
              let ownerID = supabaseManager.currentUser?.id else { return }
        if let worker = captureHistoryDrain { await worker.drain(); return }
        do {
            // Only a bounded hint. Completion discovery and finish independently
            // requalify the full retained submission; completed jobs need not
            // remain in the runnable OfflineQueuedScan set.
            let format = SharedMediaCaptureSubmission.Format.v1.rawValue
            var query = FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(predicate: #Predicate { $0.formatRaw == format })
            query.fetchLimit = 1
            guard try !ModelContext(startup.container).fetch(query).isEmpty else { return }
            let manager = supabaseManager, generation = manager.authSessionGeneration, queue = offlineQueueManager
            // Opening precedes registration: a failed open can join shutdown
            // without waiting on the worker that requested the same open.
            let owner = try await admittedNativeMediaOwner()
            guard let lifetime = nativeMediaLifetime, !lifetime.isClosed else { return }
            let current = { [weak self, weak lifetime] in
                guard let self, let lifetime else { return false }
                return self.nativeMediaLifetime === lifetime && !lifetime.isClosed && self.nativeMediaOwner === owner &&
                    manager.currentUser?.id == ownerID && manager.authSessionGeneration == generation &&
                    !manager.isAuthTransitionInProgress && !manager.libraryAccountRecoveryRequired &&
                    !manager.librarySignOutRecoveryPending && !AccountDeletionLocalCleanupStore.isPending() &&
                    (manager.libraryTransferResult == .completed || manager.isGuestUser) &&
                    queue.modelContext?.container === startup.container
            }
            guard current(), owner.isReadyForCaptureSettlement else { return }
            if let worker = captureHistoryDrain { await worker.drain(); return }
            let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: ownerID,
                begin: { try manager.beginUnownedAccountBoundWork(expectedUserID: ownerID) },
                isCurrent: { manager.isAccountBoundWorkLeaseCurrent($0) }, finish: { manager.finishAccountBoundWork($0) })
            let network = { queue.isOnline && !queue.isCurrentNetworkConstrained }
            let worker = CaptureCompletedHistoryDrain(dependencies: .init(begin: {
                guard current() else { throw SharedMediaStorageFailure.closed }
                let lease = try account.begin()
                let scope = InferenceCompletionAccountScope(ownerID: ownerID,
                    isCurrent: { current() && lease.session.userID == ownerID && account.isCurrent(lease) },
                    release: { account.finish(lease) })
                do { try scope.validate(); return scope } catch { scope.finish(); throw error }
            }, page: { cursor, scope in
                try scope.validate()
                if owner.requiresCaptureRecovery { try await owner.resumeAppCaptureRoot() }
                try scope.validate()
                return try await owner.captureCompletedRecoveryPage(after: cursor)
            }, finish: { candidate, scope in
                let continuation = CaptureCompletedHistoryContinuation(requireCurrent: { try scope.validate() }, inspect: {
                    try scope.validate()
                    return try await owner.inspectCompletedAppCapture($0)
                }, enroll: { observation in
                    try scope.validate()
                    guard network() else { throw SharedMediaStorageFailure.unavailable }
                    _ = try await queue.historyEnrollmentOwner.continueInitialHistory(observation: observation,
                        owner: ownerID, generation: generation, container: startup.container,
                        cloud: .live(manager: manager), isCurrent: {
                            guard current() else { return false }
                            do { try scope.validate(); return true } catch { return false }
                        })
                }, release: { candidate in
                    try scope.validate()
                    _ = try await owner.releaseAppCaptureSubmission(scanID: candidate.scanID, generation: candidate.generation)
                })
                try await continuation.finish(candidate)
            }, isCurrent: current, canUseNetwork: network))
            _ = try admitPreparedInputBorrow(container: startup.container, account: account,
                role: .captureHistory, consumer: worker, install: manager.installNativeMediaAccountTransitionDrain,
                close: { await worker.close(); return !worker.isRunning })
            captureHistoryDrain = worker
            await worker.drain()
        } catch {
            // Retained completion remains successful. A later startup/network
            // wake retries discovery; this path cannot resubmit inference.
        }
    }

    private func configureInputRecovery(owner: ObservationReanalysisErasureOwner, manager: SupabaseManager) throws {
        try configureInputRecovery(owner: owner, isCurrent: { [weak self] in
            self?.supabaseManager === manager && !manager.isAuthTransitionInProgress &&
                !manager.librarySignOutRecoveryPending && !AccountDeletionLocalCleanupStore.isPending()
        }, install: manager.installNativeMediaAccountTransitionDrain)
    }

    private func configureInputRecovery(owner: ObservationReanalysisErasureOwner,
                                        isCurrent: @escaping @MainActor () -> Bool,
                                        install: @escaping (SharedMediaNativeOriginalDrain) throws -> Void) throws {
        try owner.configureInputRecovery(admission: { [weak self, weak owner] container in
            guard let self, let owner, isCurrent(), self.nativeMediaStartup?.container === container else {
                throw SharedMediaStorageFailure.closed
            }
            let lifetime = try self.retainedNativeLifetime(install: install)
            return try lifetime.borrowLocalFence(for: owner, role: .inputRecovery, container: container,
                close: { await owner.closeInputRecovery() })
        }, isCurrent: isCurrent)
    }

    /// Explicit feature admission only. Initial Auth transitions occur before
    /// any lifetime/hook is installed; refusal here does not consume startup.
    func nativeMediaOwnerForFeature() async throws -> SharedMediaNativeOriginalOwner {
        let owner = try await admittedNativeMediaOwner()
        guard owner.isReadyForAppDispatch else { throw SharedMediaStorageFailure.closed }
        return owner
    }

    func nativeMediaOwnerForCaptureResume() async throws -> SharedMediaNativeOriginalOwner {
        let owner = try await admittedNativeMediaOwner()
        guard owner.isReadyForCaptureDispatch else { throw SharedMediaStorageFailure.closed }
        return owner
    }

    func nativeMediaOwnerForCaptureDraft() async throws -> SharedMediaNativeOriginalOwner {
        let owner = try await admittedNativeMediaOwner()
        guard owner.isReadyForCaptureDraft else { throw SharedMediaStorageFailure.closed }
        return owner
    }

    private func admittedNativeMediaOwner() async throws -> SharedMediaNativeOriginalOwner {
        guard PreparedHistoryReanalysisComposition.isAppInstallationQualified,
              let ownerID = supabaseManager.currentUser?.id else { throw SharedMediaStorageFailure.closed }
        let manager = supabaseManager
        let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: ownerID,
            begin: { try manager.beginUnownedAccountBoundWork(expectedUserID: ownerID) },
            isCurrent: { manager.isAccountBoundWorkLeaseCurrent($0) },
            finish: { manager.finishAccountBoundWork($0) })
        let task = try admitNativeMedia(account: account,
            install: { try manager.installNativeMediaAccountTransitionDrain($0) },
            discover: { try $0.discover(account: account) })
        let owner = try await task.value
        try Task.checkCancellation()
        guard owner === nativeMediaOwner else { throw SharedMediaStorageFailure.closed }
        return owner
    }

    /// Account admission, hook installation, discovery and task retention are a
    /// single MainActor turn. The preliminary lease is always finished here.
    private func admitNativeMedia(account: PhotoOriginalPreparationOwner.AccountAccess,
                                  install: (SharedMediaNativeOriginalDrain) throws -> Void,
                                  discover: (SharedMediaNativeOriginalDrain) throws -> SharedMediaNativeBootstrapDiscovery,
                                  configure: (SharedMediaNativeOriginalOwner) throws -> Void = { _ in }) throws -> Task<SharedMediaNativeOriginalOwner, Error> {
        try Task.checkCancellation()
        let lease = try account.begin()
        defer { account.finish(lease) }
        guard lease.session.userID == account.ownerID, account.isCurrent(lease) else { throw PhotoPreparationFailure.accountChanged }
        if let lifetime = nativeMediaLifetime, !lifetime.permitsNativeDiscovery {
            guard nativeMediaAccountID == account.ownerID, lifetime.recognizes(account: account) else { throw PhotoPreparationFailure.accountChanged }
            if let opening = nativeMediaOpening { return opening }
            guard let owner = nativeMediaOwner, owner.isReadyForCaptureDraft || owner.requiresCaptureRecovery else {
                throw SharedMediaStorageFailure.closed
            }
            if owner.requiresCaptureRecovery {
                let task = Task { @MainActor [self] in
                    defer { nativeMediaOpening = nil }
                    try await owner.resumeAppCaptureRoot()
                    guard nativeMediaLifetime === lifetime, nativeMediaOwner === owner else { throw SharedMediaStorageFailure.closed }
                    return owner
                }
                nativeMediaOpening = task
                return task
            }
            // Keep the installed terminal lifetime; it is never replaced.
            return Task { @MainActor in owner }
        }
        guard let startup = nativeMediaStartup else { throw SharedMediaStorageFailure.closed }
        let lifetime = try retainedNativeLifetime(install: install)
        try lifetime.requirePreparedAccount(account)
        nativeMediaAccountID = account.ownerID
        do {
            let discovery = try discover(lifetime)
            let owner = try SharedMediaNativeOriginalOwner.app(account: account, drain: lifetime, discovery: discovery)
            nativeMediaOwner = owner
            try configure(owner)
            let task = Task { @MainActor [self] in
                defer { nativeMediaOpening = nil }
                do {
                    let opened = try await owner.openApp(container: startup.container, discovery: discovery)
                    // Feature admission is explicit. Passive startup discovery
                    // never repairs the journal or publishes a pending owner.
                    if case .captureRootRecovery = opened { try await owner.resumeAppCaptureRoot() }
                    guard nativeMediaLifetime === lifetime, nativeMediaOwner === owner,
                          nativeMediaStartup?.container === startup.container,
                          owner.isReadyForCaptureDraft else {
                        throw PhotoPreparationFailure.accountChanged
                    }
                    return owner
                } catch {
                    _ = await lifetime.shutdown()
                    throw error
                }
            }
            nativeMediaOpening = task
            return task
        } catch {
            // Own cleanup even if the feature caller immediately disappears.
            let task = Task<SharedMediaNativeOriginalOwner, Error> { @MainActor [self] in
                defer { nativeMediaOpening = nil }
                _ = await lifetime.shutdown()
                throw error
            }
            nativeMediaOpening = task
            return task
        }
    }

    #if DEBUG
    func requestCaptureHistoryForTesting(drain: @escaping @MainActor () async -> Void) throws {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        requestCaptureHistory(drain: drain)
    }

    func configureNativeMediaForTesting(container: ModelContainer, admission: NativeReleaseStartupAdmission) throws {
        guard TestExecutionCoordinator.isRunningTests, nativeMediaStartup == nil, nativeMediaLifetime == nil else { throw SharedMediaStorageFailure.closed }
        nativeMediaStartup = (container, admission)
    }
    func preparedInputBorrowForTesting(container: ModelContainer, account: PhotoOriginalPreparationOwner.AccountAccess,
                                       consumer: AnyObject, install: (SharedMediaNativeOriginalDrain) throws -> Void,
                                       close: @escaping @MainActor () async -> Bool) throws -> SharedMediaNativeOriginalDrain.LocalBorrow {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        return try admitPreparedInputBorrow(container: container, account: account, consumer: consumer, install: install, close: close)
    }
    func configureInputRecoveryForTesting(owner: ObservationReanalysisErasureOwner) throws {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        try configureInputRecovery(owner: owner, manager: supabaseManager)
    }
    func configureInputRecoveryForTesting(owner: ObservationReanalysisErasureOwner,
                                          isCurrent: @escaping @MainActor () -> Bool,
                                          install: @escaping (SharedMediaNativeOriginalDrain) throws -> Void) throws {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        try configureInputRecovery(owner: owner, isCurrent: isCurrent, install: install)
    }
    func nativeMediaOwnerForTesting(account: PhotoOriginalPreparationOwner.AccountAccess, support: URL,
                                    install: (SharedMediaNativeOriginalDrain) throws -> Void,
                                    captureResume: Bool = false,
                                    configure: (SharedMediaNativeOriginalOwner) throws -> Void = { _ in }) async throws -> SharedMediaNativeOriginalOwner {
        guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
        let task = try admitNativeMedia(account: account, install: install,
            discover: { try $0.qualificationDiscover(account: account, support: support) }, configure: configure)
        let owner = try await task.value
        try Task.checkCancellation()
        guard owner === nativeMediaOwner,
              captureResume ? owner.isReadyForCaptureDispatch : owner.isReadyForAppDispatch else { throw SharedMediaStorageFailure.closed }
        return owner
    }
    #endif

}
