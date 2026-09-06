import Foundation

@MainActor
final class ConsentSynchronizationCoordinator {
    typealias SynchronizationOperation = @MainActor (
        UUID,
        UInt
    ) async throws -> Void

    struct CancelledWork {
        fileprivate let scheduledTasks: [Task<Void, Never>]
        fileprivate let activeTasks: [Task<Void, Error>]

        func wait() async {
            for scheduledTask in scheduledTasks {
                await scheduledTask.value
            }
            for activeTask in activeTasks {
                _ = try? await activeTask.value
            }
        }
    }

    private let ledgerRepository: ConsentLedgerRepository
    private let remoteService: ConsentRemoteService
    private let customSynchronizationOperation: SynchronizationOperation?

    private var observedUserIdProvider: @MainActor () -> UUID? = { nil }
    private var sdkUserIdProvider: @MainActor () -> UUID? = { nil }
    private var didBindUnownedRecords: @MainActor () -> Void = {}
    private var willMergeRemoteState: @MainActor () -> Void = {}
    private var didMergeRemoteState: @MainActor (
        ConsentSynchronizationMergePolicy.Result,
        UUID
    ) -> Void = { _, _ in }
    private var failureHandler: @MainActor (Error, UUID, UInt) -> Void = { _, _, _ in }

    // Superseded and invalidated entries stay registered until their task's
    // completion defer removes them. Auth drains therefore cannot lose an
    // older cancellation-uncooperative task after current identity is cleared.
    private var scheduledTasks: [UUID: Task<Void, Never>] = [:]
    private var currentScheduledTaskId: UUID?
    private var activeTasks: [UUID: Task<Void, Error>] = [:]
    private var currentActiveTaskId: UUID?
    private var activeUserId: UUID?
    private var activeGeneration: UInt?
    private(set) var generation: UInt = 0

    init(
        ledgerRepository: ConsentLedgerRepository,
        remoteService: ConsentRemoteService,
        customSynchronizationOperation: SynchronizationOperation? = nil
    ) {
        self.ledgerRepository = ledgerRepository
        self.remoteService = remoteService
        self.customSynchronizationOperation = customSynchronizationOperation
    }

    deinit {
        for task in scheduledTasks.values {
            task.cancel()
        }
        for task in activeTasks.values {
            task.cancel()
        }
    }

    func setHandlers(
        observedUserIdProvider: @escaping @MainActor () -> UUID?,
        sdkUserIdProvider: @escaping @MainActor () -> UUID?,
        didBindUnownedRecords: @escaping @MainActor () -> Void,
        willMergeRemoteState: @escaping @MainActor () -> Void,
        didMergeRemoteState: @escaping @MainActor (
            ConsentSynchronizationMergePolicy.Result,
            UUID
        ) -> Void,
        failureHandler: @escaping @MainActor (Error, UUID, UInt) -> Void
    ) {
        self.observedUserIdProvider = observedUserIdProvider
        self.sdkUserIdProvider = sdkUserIdProvider
        self.didBindUnownedRecords = didBindUnownedRecords
        self.willMergeRemoteState = willMergeRemoteState
        self.didMergeRemoteState = didMergeRemoteState
        self.failureHandler = failureHandler
    }

    func schedule(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        if let currentScheduledTaskId,
           let currentTask = scheduledTasks[currentScheduledTaskId] {
            currentTask.cancel()
        }

        let taskId = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.finishScheduledTask(id: taskId) }
            guard !Task.isCancelled else { return }
            await operation()
        }
        scheduledTasks[taskId] = task
        currentScheduledTaskId = taskId
    }

    func synchronize(for userId: UUID) async throws {
        let generation = generation
        if let currentActiveTaskId,
           let activeTask = activeTasks[currentActiveTaskId],
           activeUserId == userId,
           activeGeneration == generation {
            try await activeTask.value
            return
        }

        if activeUserId != userId || activeGeneration != generation {
            if let currentActiveTaskId,
               let activeTask = activeTasks[currentActiveTaskId] {
                activeTask.cancel()
            }
        }

        let ledgerRepository = ledgerRepository
        let remoteService = remoteService
        let customSynchronizationOperation = customSynchronizationOperation
        let didBindUnownedRecords = didBindUnownedRecords
        let willMergeRemoteState = willMergeRemoteState
        let didMergeRemoteState = didMergeRemoteState
        let failureHandler = failureHandler
        let validateSynchronization: ConsentRemoteService
            .SynchronizationValidator = { [weak self] in
                guard let self else { throw CancellationError() }
                try self.validateSynchronization(
                    for: userId,
                    generation: generation
                )
            }

        let taskId = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.finishActiveTask(id: taskId) }
            do {
                if let customSynchronizationOperation {
                    try await customSynchronizationOperation(userId, generation)
                } else {
                    try await Self.performSynchronization(
                        for: userId,
                        ledgerRepository: ledgerRepository,
                        remoteService: remoteService,
                        validateSynchronization: validateSynchronization,
                        didBindUnownedRecords: didBindUnownedRecords,
                        willMergeRemoteState: willMergeRemoteState,
                        didMergeRemoteState: didMergeRemoteState
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failureHandler(error, userId, generation)
                throw error
            }
        }
        activeTasks[taskId] = task
        currentActiveTaskId = taskId
        activeUserId = userId
        activeGeneration = generation

        do {
            try await task.value
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw error
        }
    }

    func merge(
        _ remoteState: ConsentManager.RemoteState,
        for userId: UUID,
        generation: UInt
    ) throws {
        try validateSynchronization(for: userId, generation: generation)
        try Self.merge(
            remoteState,
            for: userId,
            ledgerRepository: ledgerRepository,
            validateSynchronization: {
                try self.validateSynchronization(
                    for: userId,
                    generation: generation
                )
            },
            willMergeRemoteState: willMergeRemoteState,
            didMergeRemoteState: didMergeRemoteState
        )
    }

    @discardableResult
    func invalidate() -> CancelledWork {
        generation &+= 1
        let cancelledWork = CancelledWork(
            scheduledTasks: Array(scheduledTasks.values),
            activeTasks: Array(activeTasks.values)
        )
        for task in scheduledTasks.values {
            task.cancel()
        }
        for task in activeTasks.values {
            task.cancel()
        }
        currentScheduledTaskId = nil
        currentActiveTaskId = nil
        activeUserId = nil
        activeGeneration = nil
        return cancelledWork
    }

    func cancelAndAwait() async {
        await invalidate().wait()
    }

    private func finishScheduledTask(id: UUID) {
        scheduledTasks[id] = nil
        if currentScheduledTaskId == id {
            currentScheduledTaskId = nil
        }
    }

    private func finishActiveTask(id: UUID) {
        activeTasks[id] = nil
        if currentActiveTaskId == id {
            currentActiveTaskId = nil
            activeUserId = nil
            activeGeneration = nil
        }
    }

    private func validateSynchronization(
        for userId: UUID,
        generation: UInt
    ) throws {
        guard ConsentRetryPolicy.isSynchronizationContextCurrent(
            expectedUserId: userId,
            expectedGeneration: generation,
            observedUserId: observedUserIdProvider(),
            sdkUserId: sdkUserIdProvider(),
            currentGeneration: self.generation,
            isCancelled: Task.isCancelled
        ) else {
            throw CancellationError()
        }
    }

    private static func performSynchronization(
        for userId: UUID,
        ledgerRepository: ConsentLedgerRepository,
        remoteService: ConsentRemoteService,
        validateSynchronization: ConsentRemoteService.SynchronizationValidator,
        didBindUnownedRecords: @MainActor () -> Void,
        willMergeRemoteState: @MainActor () -> Void,
        didMergeRemoteState: @MainActor (
            ConsentSynchronizationMergePolicy.Result,
            UUID
        ) -> Void
    ) async throws {
        try validateSynchronization()
        if ledgerRepository.hasPendingAnalyticsRevocationJournal {
            try ledgerRepository.recoverPendingAnalyticsRevocation()
        }

        if hasUnownedRecords(in: ledgerRepository.ledger) {
            try bindUnownedRecords(
                to: userId,
                ledgerRepository: ledgerRepository
            )
            didBindUnownedRecords()
        }

        try ledgerRepository.activateLedger(for: userId)
        try await pushPendingRecords(
            for: userId,
            ledgerRepository: ledgerRepository,
            remoteService: remoteService,
            validateSynchronization: validateSynchronization
        )
        let remoteState = try await remoteService.fetchRemoteState(
            for: userId,
            validateSynchronization: validateSynchronization
        )
        try merge(
            remoteState,
            for: userId,
            ledgerRepository: ledgerRepository,
            validateSynchronization: validateSynchronization,
            willMergeRemoteState: willMergeRemoteState,
            didMergeRemoteState: didMergeRemoteState
        )
    }

    private static func hasUnownedRecords(
        in ledger: ConsentManager.LocalLedger
    ) -> Bool {
        ledger.activeUserId == nil
            && (
                ledger.adultEligibilityReceipts.contains {
                    $0.ownerUserId == nil
                }
                    || ledger.termsReceipts.contains { $0.ownerUserId == nil }
                    || ledger.aiConsentEvents.contains { $0.ownerUserId == nil }
                    || ledger.analyticsConsentEvents.contains {
                        $0.ownerUserId == nil
                    }
            )
    }

    private static func bindUnownedRecords(
        to userId: UUID,
        ledgerRepository: ConsentLedgerRepository
    ) throws {
        var candidate = ledgerRepository.ledgerByApplyingPendingAnalyticsRevocation(
            to: ledgerRepository.ledger
        )
        candidate.activeUserId = userId
        for index in candidate.adultEligibilityReceipts.indices
        where candidate.adultEligibilityReceipts[index].ownerUserId == nil {
            candidate.adultEligibilityReceipts[index].ownerUserId = userId
        }
        for index in candidate.termsReceipts.indices
        where candidate.termsReceipts[index].ownerUserId == nil {
            candidate.termsReceipts[index].ownerUserId = userId
        }
        for index in candidate.aiConsentEvents.indices
        where candidate.aiConsentEvents[index].ownerUserId == nil {
            candidate.aiConsentEvents[index].ownerUserId = userId
        }
        for index in candidate.analyticsConsentEvents.indices
        where candidate.analyticsConsentEvents[index].ownerUserId == nil {
            candidate.analyticsConsentEvents[index].ownerUserId = userId
        }
        try ledgerRepository.persistLedger(candidate)
    }

    private static func pushPendingRecords(
        for userId: UUID,
        ledgerRepository: ConsentLedgerRepository,
        remoteService: ConsentRemoteService,
        validateSynchronization: ConsentRemoteService.SynchronizationValidator
    ) async throws {
        let adultReceipts = ledgerRepository.ledger.adultEligibilityReceipts
            .filter {
                $0.ownerUserId == userId && $0.syncedUserId != userId
            }
        for receipt in adultReceipts {
            try validateSynchronization()
            let synchronizedReceipt = try await remoteService
                .insertAdultEligibilityReceipt(
                    receipt,
                    for: userId,
                    validateSynchronization: validateSynchronization
                )
            try validateSynchronization()
            var candidate = ledgerRepository.ledger
            if let index = candidate.adultEligibilityReceipts.firstIndex(
                where: { $0.id == receipt.id }
            ) {
                candidate.adultEligibilityReceipts[index] = synchronizedReceipt
            }
            try ledgerRepository.persistLedger(candidate)
        }

        let termsReceipts = ledgerRepository.ledger.termsReceipts.filter {
            $0.ownerUserId == userId && $0.syncedUserId != userId
        }
        for receipt in termsReceipts {
            try validateSynchronization()
            let synchronizedReceipt = try await remoteService.insertTermsReceipt(
                receipt,
                for: userId,
                validateSynchronization: validateSynchronization
            )
            try validateSynchronization()
            var candidate = ledgerRepository.ledger
            if let index = candidate.termsReceipts.firstIndex(
                where: { $0.id == receipt.id }
            ) {
                candidate.termsReceipts[index] = synchronizedReceipt
            }
            try ledgerRepository.persistLedger(candidate)
        }

        let aiEvents = ledgerRepository.ledger.aiConsentEvents.filter {
            $0.ownerUserId == userId
                && $0.syncedUserId != userId
                && $0.supersededByEventId == nil
                && $0.supersededByRevision == nil
        }
        for event in aiEvents {
            try validateSynchronization()
            let synchronizedEvent = try await remoteService.insertAIConsentEvent(
                event,
                for: userId,
                validateSynchronization: validateSynchronization
            )
            try validateSynchronization()
            var candidate = ledgerRepository.ledger
            if let index = candidate.aiConsentEvents.firstIndex(
                where: { $0.id == event.id }
            ) {
                candidate.aiConsentEvents[index] = synchronizedEvent
            }
            try ledgerRepository.persistLedger(candidate)
        }

        let analyticsEvents = ledgerRepository.ledger.analyticsConsentEvents
            .filter {
                $0.ownerUserId == userId
                    && $0.syncedUserId != userId
                    && $0.supersededByEventId == nil
                    && $0.supersededByRevision == nil
            }
        for event in analyticsEvents {
            try validateSynchronization()
            let synchronizedEvent = try await remoteService
                .insertAnalyticsConsentEvent(
                    event,
                    for: userId,
                    validateSynchronization: validateSynchronization
                )
            try validateSynchronization()
            var candidate = ledgerRepository.ledger
            if let index = candidate.analyticsConsentEvents.firstIndex(
                where: { $0.id == event.id }
            ) {
                candidate.analyticsConsentEvents[index] = synchronizedEvent
            }
            try ledgerRepository.persistLedger(candidate)
        }
    }

    private static func merge(
        _ remoteState: ConsentManager.RemoteState,
        for userId: UUID,
        ledgerRepository: ConsentLedgerRepository,
        validateSynchronization: ConsentRemoteService.SynchronizationValidator,
        willMergeRemoteState: @MainActor () -> Void,
        didMergeRemoteState: @MainActor (
            ConsentSynchronizationMergePolicy.Result,
            UUID
        ) -> Void
    ) throws {
        try validateSynchronization()
        willMergeRemoteState()
        let result = ConsentSynchronizationMergePolicy.merging(
            remoteState,
            into: ledgerRepository.ledger,
            for: userId
        )
        try ledgerRepository.persistLedger(result.ledger)
        didMergeRemoteState(result, userId)
    }
}
