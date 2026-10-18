import Foundation

/// One qualification account lifecycle. Register before opening, seal before
/// awaiting teardown, and never replace a registration or reopen a sealed one.
/// Live Auth installation remains a separate, currently disabled integration.
@MainActor
final class SharedMediaNativeOriginalDrain {
    struct Registration: Equatable {
        fileprivate let id: UUID
        fileprivate init() { id = UUID() }
    }

    private var registration: Registration?
    private var callback: (@MainActor () async -> Bool)?
    private var sealed = false
    private var shutdownTask: Task<Bool, Never>?

    func register(_ callback: @escaping @MainActor () async -> Bool) throws -> Registration {
        guard !sealed, registration == nil else { throw SharedMediaStorageFailure.closed }
        let value = Registration()
        registration = value; self.callback = callback
        return value
    }

    func isCurrent(_ value: Registration) -> Bool { !sealed && registration == value }

    func seal(_ value: Registration) {
        if registration == value { sealed = true }
    }

    func shutdown() async -> Bool {
        if let shutdownTask { return await shutdownTask.value }
        sealed = true
        let callback = callback
        let task = Task { @MainActor in await callback?() ?? true }
        shutdownTask = task
        let result = await task.value
        if result { self.callback = nil; registration = nil } else { shutdownTask = nil } // Explicit retry may reconcile settlement; admission stays sealed.
        return result
    }
}
