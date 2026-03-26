#if canImport(UIKit)
import UIKit

/// Thread-safe wrapper around `UIBackgroundTaskIdentifier` for Swift 6 strict concurrency.
///
/// `UIBackgroundTaskIdentifier` is not `Sendable`, so direct use across actor boundaries
/// produces warnings. This wrapper uses `NSLock` to gate access, satisfying `@unchecked Sendable`.
///
/// Typical usage is via the static `execute` factory, which begins a background task, runs an
/// async operation, and ends the task on completion or expiration.
public final class BackgroundTaskWrapper: @unchecked Sendable {

    private let lock = NSLock()
    private var _id: UIBackgroundTaskIdentifier = .invalid

    /// The underlying background task identifier. Thread-safe via `NSLock`.
    public var id: UIBackgroundTaskIdentifier {
        get { lock.withLock { _id } }
        set { lock.withLock { _id = newValue } }
    }

    public init() {}

    /// Ends the background task if it is currently active. Safe to call from any thread.
    public func safeEnd() {
        let idToEnd: UIBackgroundTaskIdentifier = lock.withLock {
            guard _id != .invalid else { return .invalid }
            let oldId = _id
            _id = .invalid
            return oldId
        }
        
        guard idToEnd != .invalid else { return }
        #if os(iOS)
        UIApplication.shared.endBackgroundTask(idToEnd)
        #endif
    }

    /// Begins a named background task, runs `operation`, then ends the task.
    ///
    /// - Parameters:
    ///   - name: A human-readable name for the background task (visible in crash reports).
    ///   - expirationHandler: Called by iOS if the background time limit is reached before the operation finishes.
    ///   - operation: The async work to perform within the background execution window.
    /// - Returns: The underlying `Task`, discardable if fire-and-forget behaviour is intended.
    @discardableResult
    public static func execute(
        name: String,
        expirationHandler: (@Sendable () -> Void)? = nil,
        operation: @escaping @Sendable (BackgroundTaskWrapper) async -> Void
    ) -> Task<Void, Never> {
        let task = BackgroundTaskWrapper()
        #if os(iOS)
        let taskId = UIApplication.shared.beginBackgroundTask(withName: name) {
            expirationHandler?()
            task.safeEnd()
        }
        task.id = taskId
        #endif
        return Task(priority: .background) {
            await operation(task)
            task.safeEnd()
        }
    }
}
#endif
