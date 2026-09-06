import Foundation

@MainActor
final class ConsentRealtimeCoordinator {
    enum SubscriptionStatus {
        case subscribed
        case subscribing
        case inactive
    }

    @MainActor
    final class Subscription {
        private let statusOperation: @MainActor () -> SubscriptionStatus
        private let subscribeOperation: @MainActor () async throws -> Void
        private let nextChangeOperation: @MainActor () async -> Bool
        private let removeOperation: @MainActor () async -> Void
        private var removalTask: Task<Void, Never>?

        init(
            status: @escaping @MainActor () -> SubscriptionStatus,
            subscribe: @escaping @MainActor () async throws -> Void,
            nextChange: @escaping @MainActor () async -> Bool,
            remove: @escaping @MainActor () async -> Void
        ) {
            statusOperation = status
            subscribeOperation = subscribe
            nextChangeOperation = nextChange
            removeOperation = remove
        }

        func status() -> SubscriptionStatus {
            statusOperation()
        }

        func subscribe() async throws {
            try await subscribeOperation()
        }

        func nextChange() async -> Bool {
            await nextChangeOperation()
        }

        func remove() async {
            if let removalTask {
                await removalTask.value
                return
            }

            let removeOperation = self.removeOperation
            let removalTask = Task { @MainActor in
                await removeOperation()
            }
            self.removalTask = removalTask
            await removalTask.value
        }
    }

    struct Dependencies {
        let isEnabled: @MainActor () -> Bool
        let makeSubscription: @MainActor (UUID) -> Subscription
        let sleep: @MainActor (Double) async throws -> Void
        let reportFailure: @MainActor (Error) -> Void
    }

    private let dependencies: Dependencies
    private var currentUserIdProvider: @MainActor () -> UUID? = { nil }
    private var synchronizationHandler: @MainActor (UUID) async -> Void = { _ in }
    private var subscription: Subscription?
    private var subscriptionUserId: UUID?
    private var subscribedUserId: UUID?
    private var listenerTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryUserId: UUID?
    private var retryAttempt = 0
    private var subscriptionGeneration: UInt = 0
    private var teardownTasks: [UUID: Task<Void, Never>] = [:]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    deinit {
        let subscription = subscription
        listenerTask?.cancel()
        retryTask?.cancel()
        if let subscription {
            Task { @MainActor in
                await subscription.remove()
            }
        }
    }

    func setHandlers(
        currentUserIdProvider: @escaping @MainActor () -> UUID?,
        synchronizationHandler: @escaping @MainActor (UUID) async -> Void
    ) {
        self.currentUserIdProvider = currentUserIdProvider
        self.synchronizationHandler = synchronizationHandler
    }

    func ensureUpdates(for userId: UUID?) {
        guard let userId else {
            stopUpdates()
            return
        }
        guard dependencies.isEnabled() else { return }

        if subscriptionUserId == userId,
           let subscription,
           listenerTask != nil {
            if subscribedUserId == nil {
                // Initial subscription is still in flight.
                return
            }
            switch subscription.status() {
            case .subscribed, .subscribing:
                return
            case .inactive:
                break
            }
        }

        let isRetryingSameUser = retryUserId == userId
        let isReplacingSameUser = subscriptionUserId == userId
        startUpdates(
            for: userId,
            resetRetryAttempt: !isRetryingSameUser && !isReplacingSameUser
        )
    }

    func stopUpdates() {
        stopUpdates(resetRetryAttempt: true)
    }

    /// Waits for every subscription removal that was started before or during
    /// the drain. Cancellation of the caller does not abandon channel teardown.
    func awaitTeardown() async {
        while !teardownTasks.isEmpty {
            let tasks = Array(teardownTasks.values)
            for task in tasks {
                await task.value
            }
        }
    }

    private func stopUpdates(resetRetryAttempt: Bool) {
        subscriptionGeneration &+= 1
        retryTask?.cancel()
        retryTask = nil
        retryUserId = nil
        listenerTask?.cancel()
        listenerTask = nil
        subscribedUserId = nil
        subscriptionUserId = nil
        if resetRetryAttempt {
            retryAttempt = 0
        }

        if let subscription {
            self.subscription = nil
            beginTeardown(of: subscription)
        }
    }

    private func beginTeardown(of subscription: Subscription) {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await subscription.remove()
            self?.teardownTasks.removeValue(forKey: id)
        }
        teardownTasks[id] = task
    }

    private func startUpdates(
        for userId: UUID,
        resetRetryAttempt: Bool
    ) {
        stopUpdates(resetRetryAttempt: resetRetryAttempt)
        let generation = subscriptionGeneration
        let subscription = dependencies.makeSubscription(userId)
        self.subscription = subscription
        subscriptionUserId = userId
        subscribedUserId = nil

        listenerTask = Task { @MainActor [weak self] in
            var shouldRetry = false
            do {
                try await subscription.subscribe()
                guard self?.isCurrentSubscription(
                    subscription,
                    userId: userId,
                    generation: generation
                ) == true else {
                    await subscription.remove()
                    return
                }
                self?.subscribedUserId = userId
                self?.retryAttempt = 0

                while await subscription.nextChange() {
                    guard self?.isCurrentSubscription(
                        subscription,
                        userId: userId,
                        generation: generation
                    ) == true else {
                        break
                    }
                    if let synchronizationHandler = self?.synchronizationHandler {
                        await synchronizationHandler(userId)
                    }
                }
                shouldRetry = !Task.isCancelled
            } catch is CancellationError {
                shouldRetry = false
            } catch {
                shouldRetry = !Task.isCancelled
                self?.dependencies.reportFailure(error)
            }

            if let self {
                await self.finishSubscription(
                    subscription,
                    userId: userId,
                    generation: generation,
                    shouldRetry: shouldRetry
                )
            } else {
                await subscription.remove()
            }
        }
    }

    private func isCurrentSubscription(
        _ subscription: Subscription,
        userId: UUID,
        generation: UInt
    ) -> Bool {
        !Task.isCancelled
            && subscriptionGeneration == generation
            && self.subscription === subscription
            && subscriptionUserId == userId
            && currentUserIdProvider() == userId
    }

    private func finishSubscription(
        _ subscription: Subscription,
        userId: UUID,
        generation: UInt,
        shouldRetry: Bool
    ) async {
        await subscription.remove()
        guard subscriptionGeneration == generation,
              self.subscription === subscription,
              subscriptionUserId == userId else {
            return
        }

        self.subscription = nil
        subscriptionUserId = nil
        subscribedUserId = nil
        listenerTask = nil
        guard shouldRetry,
              currentUserIdProvider() == userId else {
            return
        }
        scheduleRetry(for: userId)
    }

    private func scheduleRetry(for userId: UUID) {
        retryAttempt += 1
        let delay = ConsentRetryPolicy.analyticsConsentDelay(
            attempt: retryAttempt
        )
        let generation = subscriptionGeneration
        retryUserId = userId
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            do {
                try await self?.dependencies.sleep(delay)
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.subscriptionGeneration == generation,
                  self.retryUserId == userId,
                  self.currentUserIdProvider() == userId else {
                return
            }
            self.retryTask = nil
            self.retryUserId = nil
            self.startUpdates(
                for: userId,
                resetRetryAttempt: false
            )
        }
    }
}
