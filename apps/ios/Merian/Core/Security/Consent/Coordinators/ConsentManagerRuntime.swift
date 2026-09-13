import Foundation

@MainActor
final class ConsentManagerRuntime {
    struct CancelledWork {
        let synchronization: ConsentSynchronizationCoordinator.CancelledWork
        let restoration: RequiredConsentRestorationCoordinator.CancelledWork

        func wait() async {
            await synchronization.wait()
            await restoration.wait()
        }
    }

    let ledgerRepository: ConsentLedgerRepository
    let synchronizationCoordinator: ConsentSynchronizationCoordinator
    let restorationCoordinator: RequiredConsentRestorationCoordinator
    let realtimeCoordinator: ConsentRealtimeCoordinator
    let cloudSessionCoordinator: ConsentCloudSessionCoordinator
    let mutationService: ConsentMutationService
    let currentSDKUserIdProvider: @MainActor () -> UUID?
    let analyticsPermissionApplier: @MainActor (Bool, String?) -> Void

    private let restorationFailureReporter: @MainActor (Error) -> Void

    init(
        ledgerStore: ConsentLedgerStoring,
        remoteService: ConsentRemoteService,
        currentSDKUserIdProvider: @escaping @MainActor () -> UUID?,
        analyticsPermissionApplier: @escaping @MainActor (
            Bool,
            String?
        ) -> Void,
        synchronizationOperation: (
            @MainActor (UUID, UInt) async throws -> Void
        )?,
        realtimeCoordinator: ConsentRealtimeCoordinator,
        cloudSessionDependencies:
            ConsentCloudSessionCoordinator.Dependencies,
        shouldScheduleAutomaticRetry: @escaping () -> Bool,
        sleep: @escaping (Double) async throws -> Void,
        restorationFailureReporter: @escaping (Error) -> Void
    ) {
        let ledgerRepository = ConsentLedgerRepository(store: ledgerStore)
        self.ledgerRepository = ledgerRepository
        synchronizationCoordinator = ConsentSynchronizationCoordinator(
            ledgerRepository: ledgerRepository,
            remoteService: remoteService,
            customSynchronizationOperation: synchronizationOperation
        )
        restorationCoordinator = RequiredConsentRestorationCoordinator(
            dependencies: .init(
                shouldScheduleAutomaticRetry: shouldScheduleAutomaticRetry,
                sleep: sleep
            )
        )
        self.realtimeCoordinator = realtimeCoordinator
        cloudSessionCoordinator = ConsentCloudSessionCoordinator(
            ledgerRepository: ledgerRepository,
            synchronizationCoordinator: synchronizationCoordinator,
            dependencies: cloudSessionDependencies
        )
        mutationService = ConsentMutationService(
            ledgerRepository: ledgerRepository
        )
        self.currentSDKUserIdProvider = currentSDKUserIdProvider
        self.analyticsPermissionApplier = analyticsPermissionApplier
        self.restorationFailureReporter = restorationFailureReporter
    }

    func connect(to manager: ConsentManager) {
        ledgerRepository.setStateChangeHandler { [weak manager] in
            manager?.handleConsentLedgerStateChange()
        }
        restorationCoordinator.setHandlers(
            contextProvider: { [weak manager, weak self] in
                guard let manager, let self else { return nil }
                return manager.requiredConsentRestorationContext(
                    synchronizationGeneration:
                        self.synchronizationCoordinator.generation,
                    sdkUserId: self.currentSDKUserIdProvider()
                )
            },
            stateChangeHandler: { [weak manager] state in
                manager?.publishRequiredConsentRestorationState(state)
            },
            synchronizationHandler: { [weak manager] in
                guard let manager else { throw CancellationError() }
                try await manager.synchronizeWithCurrentSession()
            },
            failureReporter: restorationFailureReporter
        )
        synchronizationCoordinator.setHandlers(
            observedUserIdProvider: { [weak manager] in
                manager?.currentSessionUserId
            },
            sdkUserIdProvider: { [weak self] in
                self?.currentSDKUserIdProvider()
            },
            didBindUnownedRecords: { [weak manager] in
                manager?.applyAnalyticsPermissionToSDK()
            },
            willMergeRemoteState: { [weak manager] in
                manager?.prepareForConsentSynchronizationMerge()
            },
            didMergeRemoteState: { [weak manager] result, userId in
                manager?.applySynchronizationMerge(result, for: userId)
            },
            failureHandler: { [weak self] error, userId, generation in
                self?.restorationCoordinator.handleSynchronizationFailure(
                    error,
                    for: userId,
                    generation: generation
                )
            }
        )
        realtimeCoordinator.setHandlers(
            currentUserIdProvider: { [weak manager] in
                manager?.currentSessionUserId
            },
            synchronizationHandler: { [weak manager] userId in
                guard let manager else { return }
                try? await manager.synchronize(for: userId)
            }
        )
    }
}
