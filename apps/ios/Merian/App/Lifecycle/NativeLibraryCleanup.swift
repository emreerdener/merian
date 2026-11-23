import Foundation
import SwiftData

/// App-owned accepted account cleanup. The lifetime coordinator supplies a
/// captured runtime check; this owner holds native completion across generic
/// History cleanup and never mints storage or account authority.
@MainActor
final class NativeLibraryCleanup {
    struct Runtime {
        let container: ModelContainer
        let admission: NativeReleaseStartupAdmission
        let check: () throws -> Void
    }
    private let supabaseManager: SupabaseManager
    private let offlineQueueManager: OfflineQueueManager
    private let scanRepository: ScanRepository
    private let privateScanMapStore: PrivateScanMapStore
    private let preparedHost: () -> CaptureAudioReanalysisHostOwner?
    private let captureRuntime: (ModelContext, SharedMediaNativeErasureAuthorization) throws -> Runtime?

    init(manager: SupabaseManager, queue: OfflineQueueManager, repository: ScanRepository,
         mapStore: PrivateScanMapStore, preparedHost: @escaping () -> CaptureAudioReanalysisHostOwner?,
         captureRuntime: @escaping (ModelContext, SharedMediaNativeErasureAuthorization) throws -> Runtime?) {
        supabaseManager = manager; offlineQueueManager = queue; scanRepository = repository
        privateScanMapStore = mapStore; self.preparedHost = preparedHost; self.captureRuntime = captureRuntime
    }

    func accountDeletionLibraryContext(for manager: SupabaseManager) -> @MainActor (AnyObject?) -> Bool {
        guard manager === supabaseManager, let container = offlineQueueManager.modelContext?.container else { return { _ in false } }
        return { [weak self, weak manager] supplied in
            guard let self, let manager, manager === self.supabaseManager,
                  self.offlineQueueManager.modelContext?.container === container,
                  self.preparedHost()?.recognizesLibraryContainer(container) == true else { return false }
            return supplied == nil || supplied === container
        }
    }

    func acknowledgeDeletionPurge(for manager: SupabaseManager, scope: AccountDeletionLocalCleanupStore.RecoveryScope) -> Bool {
        guard manager === supabaseManager, let container = offlineQueueManager.modelContext?.container,
              scope.permitsLibraryPurge(in: container) else { return false }
        return preparedHost()?.acknowledgeLibraryPurge(container: container, manager: manager) == true
    }

    func librarySignOutScope(manager: SupabaseManager, transition: AuthTransitionToken,
                             journal: LibrarySignOutJournal) -> LibrarySignOutJournalStore.RecoveryScope? {
        guard manager === supabaseManager, let container = offlineQueueManager.modelContext?.container else { return nil }
        return LibrarySignOutJournalStore.live.recoveryScope(expected: journal) { [weak self, weak manager] in
            guard let self, let manager, self.supabaseManager === manager, manager.ownsAuthTransition(transition),
                  transition.kind == .recovery, self.offlineQueueManager.modelContext?.container === container,
                  self.preparedHost()?.recognizesLibraryContainer(container) == true,
                  manager.activeAuthTransition?.sourceSession.map({ $0.userID == journal.sourceUserID }) != false,
                  manager.activeAuthTransition?.expectedSession.map({ $0.userID == journal.sourceUserID }) != false,
                  manager.currentUser.map({ $0.id == journal.sourceUserID }) != false else { return false }
            let sdkOwner = manager.client.auth.currentSession?.user.id
            return journal.phase == .sourceCleared ? sdkOwner == nil : (sdkOwner == nil || sdkOwner == journal.sourceUserID)
        }
    }

    func purgeLibraryForSignOut(manager: SupabaseManager, transition: AuthTransitionToken,
                                journal: LibrarySignOutJournal,
                                drain: (LibrarySignOutJournalStore.RecoveryScope) async -> Bool) async -> Bool {
        guard let scope = librarySignOutScope(manager: manager, transition: transition, journal: journal),
              scope.allowsLibraryPurge, let context = offlineQueueManager.modelContext,
              await drain(scope), scope.allowsLibraryPurge else { return false }
        guard await purgeAcceptedLibrary(modelContext: context, authorization: .signOut(scope),
            resetDerivedState: privateScanMapStore.resetSensitiveState,
            validateAuthorization: { scope.allowsLibraryPurge }), scope.allowsLibraryPurge else { return false }
        guard preparedHost()?.acknowledgeLibraryPurge(container: context.container, manager: manager) == true else { return false }
        do { try LibraryAccountOwnerStore.clear(); return true } catch { return false }
    }

    /// Accepted account deletion survives verified local sign-out. The captured
    /// cleanup scope, not a current Auth user or library preference, binds it.
    func purgeLibraryForAccountDeletion(
        modelContext: ModelContext,
        scope: AccountDeletionLocalCleanupStore.RecoveryScope,
        resetDerivedState: @MainActor () -> Void
    ) async -> Bool {
        await purgeAcceptedLibrary(modelContext: modelContext, authorization: .accountDeletion(scope),
            resetDerivedState: resetDerivedState,
            validateAuthorization: { scope.permitsLibraryPurge(in: modelContext.container) })
    }

    private func purgeAcceptedLibrary(modelContext: ModelContext, authorization: SharedMediaNativeErasureAuthorization,
                                      resetDerivedState: @MainActor () -> Void,
                                      validateAuthorization: @MainActor @escaping () -> Bool) async -> Bool {
        guard validateAuthorization(), offlineQueueManager.modelContext?.container === modelContext.container else { return false }
        // Shipping legacy composition has no native startup admission. Its
        // existing purge still refuses every native liability before mutation.
        let admitted: Runtime?
        do { admitted = try captureRuntime(modelContext, authorization) } catch { return false }
        guard let startup = admitted else {
            return await purgeGenericLibrary(modelContext: modelContext, resetDerivedState: resetDerivedState,
                validateAuthorization: validateAuthorization)
        }
        do {
            try startup.check()
            guard let prepared = preparedHost(),
                  await prepared.drainAccountLifetimeDisposition(manager: supabaseManager).isRuntimeQuiescent else { return false }
            try startup.check()
            let completion = try await eraseNativeLibrary(container: startup.container,
                admission: startup.admission, authorization: authorization, runtimeCheckpoint: startup.check)
            try completion.validate(in: startup.container)
            // The existing purge checks this before/after its awaited cleanup
            // work and before preferences. Keep the native receipt/fence alive
            // until its final readback, before acknowledging the outer journal.
            let valid: @MainActor () -> Bool = {
                guard validateAuthorization() else { return false }
                do { try startup.check(); try completion.validate(in: startup.container); return true } catch { return false }
            }
            guard valid(), await purgeGenericLibrary(modelContext: modelContext,
                resetDerivedState: resetDerivedState, validateAuthorization: valid), valid() else { return false }
            return true
        } catch { return false }
    }

    private func eraseNativeLibrary(container: ModelContainer, admission: NativeReleaseStartupAdmission,
                                    authorization: SharedMediaNativeErasureAuthorization,
                                    runtimeCheckpoint: @escaping () throws -> Void) async throws -> SharedMediaNativeLibraryErasure.Completion {
        #if DEBUG
        if let qualification = erasureQualification {
            return try await SharedMediaNativeLibraryErasure.qualification(container: container, admission: admission,
                authorization: authorization, support: qualification.support, runtimeCheckpoint: runtimeCheckpoint)
        }
        #endif
        return try await SharedMediaNativeLibraryErasure.erase(container: container, admission: admission,
            authorization: authorization, runtimeCheckpoint: runtimeCheckpoint)
    }

    private func purgeGenericLibrary(modelContext: ModelContext, resetDerivedState: @MainActor () -> Void,
                                     validateAuthorization: @MainActor () -> Bool) async -> Bool {
        #if DEBUG
        if let qualification = erasureQualification {
            return await scanRepository.purgeAllData(modelContext: modelContext, userDefaults: qualification.defaults,
                resetDerivedState: resetDerivedState, resetRuntimeState: qualification.resetRuntime,
                validateAuthorization: validateAuthorization, eraseReanalysis: {
                    try await qualification.beforeHistoryErasure()
                    try await ObservationReanalysisFileStore(documents: qualification.documents).purgeNamespace()
                })
        }
        #endif
        return await scanRepository.purgeAllData(modelContext: modelContext, resetDerivedState: resetDerivedState,
            validateAuthorization: validateAuthorization)
    }

    #if DEBUG
    private struct ErasureQualification {
        let support: URL, documents: URL
        let defaults: UserDefaults
        let beforeHistoryErasure: @MainActor () async throws -> Void
        let resetRuntime: @MainActor () -> Void
    }
    private var erasureQualification: ErasureQualification?

    func configureErasureForTesting(support: URL, documents: URL, defaults: UserDefaults,
                                    beforeHistoryErasure: @escaping @MainActor () async throws -> Void = {},
                                    resetRuntime: @escaping @MainActor () -> Void) throws {
        guard TestExecutionCoordinator.isRunningTests, erasureQualification == nil,
              support == support.resolvingSymlinksInPath().standardizedFileURL,
              support != URL.applicationSupportDirectory.resolvingSymlinksInPath().standardizedFileURL,
              documents == documents.resolvingSymlinksInPath().standardizedFileURL,
              documents != URL.documentsDirectory.resolvingSymlinksInPath().standardizedFileURL,
              defaults !== UserDefaults.standard else { throw SharedMediaStorageFailure.closed }
        erasureQualification = .init(support: support, documents: documents, defaults: defaults,
            beforeHistoryErasure: beforeHistoryErasure, resetRuntime: resetRuntime)
    }

    #endif
}
