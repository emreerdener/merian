enum DetachedWorkCategory: String {
    case thirdPartyBootstrap
    case imagePreparation
    case audioPreparation
    case inferenceRequestPreparation
    case fileSystemCleanup
    case backgroundDatabaseMutation
}

enum DetachedWork {
    @discardableResult
    static func fireAndForget(
        priority: TaskPriority = .userInitiated,
        category _: DetachedWorkCategory,
        operation: @Sendable @escaping () async -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: priority) {
            await operation()
        }
    }

    static func value<Success: Sendable>(
        priority: TaskPriority = .userInitiated,
        category _: DetachedWorkCategory,
        operation: @Sendable @escaping () async throws -> Success
    ) async throws -> Success {
        let task = Task.detached(priority: priority) {
            try await operation()
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let value = try await task.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            task.cancel()
        }
    }
}
