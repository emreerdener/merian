import Foundation

@MainActor
enum OAuthSignInWorkflow {
    static func replacingSession<Value>(
        suspendAnalytics: () -> UInt,
        installSession: () async throws -> Value,
        currentSession: () -> Value?,
        reconcileSession: (
            UInt,
            Value?,
            OAuthSessionReplacementDisposition
        ) -> Void
    ) async throws -> Value {
        try Task.checkCancellation()
        let generation = suspendAnalytics()
        do {
            // Cancellation can be requested from another executor while the
            // synchronous suppression boundary runs. Reconcile that boundary
            // without installing a replacement SDK session.
            try Task.checkCancellation()
            let installedSession = try await installSession()
            try Task.checkCancellation()
            reconcileSession(generation, installedSession, .installed)
            return installedSession
        } catch {
            let wasCancelled = Task.isCancelled || error is CancellationError
            reconcileSession(
                generation,
                currentSession(),
                wasCancelled ? .cancelled : .failed
            )
            if wasCancelled {
                throw CancellationError()
            }
            throw error
        }
    }

    static func registerAppleCredential(
        maximumAttempts: Int = 2,
        invoke: () async throws -> Void,
        waitBeforeRetry: () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(350))
        }
    ) async throws {
        precondition(maximumAttempts > 0)
        try Task.checkCancellation()
        var lastError: Error?

        for attempt in 1...maximumAttempts {
            do {
                try Task.checkCancellation()
                try await invoke()
                try Task.checkCancellation()
                return
            } catch {
                if Task.isCancelled || error is CancellationError {
                    throw CancellationError()
                }
                lastError = error
                guard attempt < maximumAttempts else { break }
                try Task.checkCancellation()
                try await waitBeforeRetry()
                try Task.checkCancellation()
            }
        }

        throw lastError
            ?? OAuthSignInWorkflowError
            .invalidAppleCredentialRegistrationReceipt
    }
}
