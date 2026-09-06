import Foundation

@MainActor
final class RequiredConsentRestorationCoordinator {
    typealias State = ConsentManager.RequiredConsentRestorationState

    struct CancelledWork {
        fileprivate let retryTasks: [Task<Void, Never>]

        func wait() async {
            for retryTask in retryTasks {
                await retryTask.value
            }
        }
    }

    struct Context {
        let synchronizationGeneration: UInt
        let observedUserId: UUID?
        let sdkUserId: UUID?
        let hasCurrentRequiredConsent: Bool
    }

    struct Dependencies {
        let shouldScheduleAutomaticRetry: @MainActor () -> Bool
        let sleep: @MainActor (Double) async throws -> Void
    }

    static let maximumAutomaticRetries = 3

    private(set) var state: State = .awaitingInitialSession

    private let dependencies: Dependencies
    private var retryAttempt = 0
    // Canceled retries remain registered until their completion defer removes
    // the exact task. Auth transitions can therefore drain even a timer whose
    // injected sleep does not cooperate with cancellation.
    private var retryTasks: [UUID: Task<Void, Never>] = [:]
    private var currentRetryTaskId: UUID?
    private var contextProvider: @MainActor () -> Context? = { nil }
    private var stateChangeHandler: @MainActor (State) -> Void = { _ in }
    private var synchronizationHandler: @MainActor () async throws -> Void = {
        throw CancellationError()
    }
    private var failureReporter: @MainActor (Error) -> Void = { _ in }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    deinit {
        for retryTask in retryTasks.values {
            retryTask.cancel()
        }
    }

    func setHandlers(
        contextProvider: @escaping @MainActor () -> Context?,
        stateChangeHandler: @escaping @MainActor (State) -> Void,
        synchronizationHandler: @escaping @MainActor () async throws -> Void,
        failureReporter: @escaping @MainActor (Error) -> Void
    ) {
        self.contextProvider = contextProvider
        self.stateChangeHandler = stateChangeHandler
        self.synchronizationHandler = synchronizationHandler
        self.failureReporter = failureReporter
        stateChangeHandler(state)
    }

    var canRetry: Bool {
        switch state {
        case .waitingToRetry, .retryRequired:
            return true
        case .awaitingInitialSession, .reconciling, .resolved:
            return false
        }
    }

    @discardableResult
    func observeSession(
        previousUserId: UUID?,
        userId: UUID?,
        hasCurrentRequiredConsent: Bool
    ) -> Bool {
        if let userId, !hasCurrentRequiredConsent {
            let alreadyResolvedThisSession = previousUserId == userId
                && state == .resolved
            let preservesPendingRetry = previousUserId == userId
                && isRetryPending(for: userId)
            if !alreadyResolvedThisSession, !preservesPendingRetry {
                transition(to: .reconciling(userId: userId))
            }
            return preservesPendingRetry
        }

        resetRetry()
        transition(to: .resolved)
        return false
    }

    @discardableResult
    func requestManualRetry() -> Bool {
        guard let context = contextProvider(),
              let userId = context.observedUserId,
              context.sdkUserId == userId,
              !context.hasCurrentRequiredConsent,
              canRetry,
              belongs(to: userId) else {
            return false
        }

        resetRetry()
        transition(to: .reconciling(userId: userId))
        return true
    }

    func beginReconciliation(for userId: UUID) {
        transition(to: .reconciling(userId: userId))
    }

    func resolveIfNeeded(for userId: UUID) {
        guard belongs(to: userId),
              contextProvider()?.observedUserId == userId else {
            return
        }
        resetRetry()
        transition(to: .resolved)
    }

    func handleSynchronizationFailure(
        _ error: Error,
        for userId: UUID,
        generation: UInt
    ) {
        guard let context = contextProvider(),
              generation == context.synchronizationGeneration,
              context.observedUserId == userId,
              context.sdkUserId == userId,
              !context.hasCurrentRequiredConsent,
              state == .reconciling(userId: userId) else {
            return
        }

        failureReporter(error)
        cancelRetryTasks()

        guard retryAttempt < Self.maximumAutomaticRetries else {
            transition(to: .retryRequired(userId: userId))
            return
        }

        retryAttempt += 1
        let attempt = retryAttempt
        transition(to: .waitingToRetry(userId: userId, attempt: attempt))
        scheduleRetry(
            for: userId,
            generation: generation,
            attempt: attempt
        )
    }

    @discardableResult
    func beginRetry(
        for userId: UUID,
        generation: UInt,
        attempt: Int
    ) -> Bool {
        guard !Task.isCancelled,
              let context = contextProvider(),
              generation == context.synchronizationGeneration,
              context.observedUserId == userId,
              context.sdkUserId == userId,
              !context.hasCurrentRequiredConsent,
              retryAttempt == attempt,
              state == .waitingToRetry(userId: userId, attempt: attempt) else {
            return false
        }

        transition(to: .reconciling(userId: userId))
        return true
    }

    func isRetryPending(for userId: UUID) -> Bool {
        switch state {
        case let .waitingToRetry(expectedUserId, _):
            return expectedUserId == userId
        case let .retryRequired(expectedUserId):
            return expectedUserId == userId
        case .awaitingInitialSession, .reconciling, .resolved:
            return false
        }
    }

    func belongs(to userId: UUID) -> Bool {
        switch state {
        case let .reconciling(expectedUserId):
            return expectedUserId == userId
        case let .waitingToRetry(expectedUserId, _):
            return expectedUserId == userId
        case let .retryRequired(expectedUserId):
            return expectedUserId == userId
        case .awaitingInitialSession, .resolved:
            return false
        }
    }

    @discardableResult
    func invalidate(
        currentUserId: UUID?,
        hasCurrentRequiredConsent: Bool
    ) -> CancelledWork {
        let cancelledWork = CancelledWork(
            retryTasks: Array(retryTasks.values)
        )
        let restorationUserId = currentUserId.flatMap { userId in
            isRetryPending(for: userId) && !hasCurrentRequiredConsent
                ? userId
                : nil
        }
        resetRetry()
        if let restorationUserId {
            transition(to: .reconciling(userId: restorationUserId))
        }
        return cancelledWork
    }

    private func scheduleRetry(
        for userId: UUID,
        generation: UInt,
        attempt: Int
    ) {
        guard dependencies.shouldScheduleAutomaticRetry() else { return }

        cancelRetryTasks()
        let delay = ConsentRetryPolicy.requiredConsentRestorationDelay(
            attempt: attempt
        )
        let sleep = dependencies.sleep
        let taskId = UUID()
        let task = Task { @MainActor [weak self] in
            defer { self?.finishRetryTask(id: taskId) }
            do {
                try await sleep(delay)
            } catch {
                return
            }
            guard let self,
                  self.beginRetry(
                    for: userId,
                    generation: generation,
                    attempt: attempt
                  ) else {
                return
            }

            do {
                try await self.synchronizationHandler()
            } catch is CancellationError {
                return
            } catch {
                // The synchronization owner reports the next retry transition.
            }
        }
        retryTasks[taskId] = task
        currentRetryTaskId = taskId
    }

    private func finishRetryTask(id: UUID) {
        retryTasks[id] = nil
        guard currentRetryTaskId == id else { return }
        currentRetryTaskId = nil
    }

    private func cancelRetryTasks() {
        for retryTask in retryTasks.values {
            retryTask.cancel()
        }
        currentRetryTaskId = nil
    }

    private func resetRetry() {
        cancelRetryTasks()
        retryAttempt = 0
    }

    private func transition(to state: State) {
        self.state = state
        stateChangeHandler(state)
    }
}
