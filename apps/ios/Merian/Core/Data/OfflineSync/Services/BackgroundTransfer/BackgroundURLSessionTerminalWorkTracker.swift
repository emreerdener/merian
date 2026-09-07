import Foundation

/// Tracks asynchronous terminal persistence spawned by background URLSession
/// delegate callbacks. Registration is synchronous and lock-protected so
/// `urlSessionDidFinishEvents` cannot overtake a hop to the main actor.
final class BackgroundURLSessionTerminalWorkTracker: @unchecked Sendable {
    struct Token: Hashable, Sendable {
        fileprivate let id = UUID()
    }

    private let lock = NSLock()
    private var activeTokens: Set<Token> = []
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    func begin() -> Token {
        let token = Token()
        _ = lock.withLock { activeTokens.insert(token) }
        return token
    }

    func finish(_ token: Token) {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard activeTokens.remove(token) != nil,
                  activeTokens.isEmpty else {
                return []
            }
            let pending = idleWaiters
            idleWaiters.removeAll()
            return pending
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            let isAlreadyIdle = lock.withLock {
                guard !activeTokens.isEmpty else { return true }
                idleWaiters.append(continuation)
                return false
            }
            if isAlreadyIdle {
                continuation.resume()
            }
        }
    }
}

extension OfflineQueueManager {
    /// System-completion boundary shared by the URLSession delegate.
    /// The handler is taken only after every synchronously registered terminal
    /// processor has committed its durable state and released its Auth lease.
    static func invokeBackgroundSessionCompletionAfterTerminalWork(
        tracker: BackgroundURLSessionTerminalWorkTracker,
        takeHandler: @MainActor () -> (() -> Void)?
    ) async {
        await tracker.waitUntilIdle()
        takeHandler()?()
    }
}
