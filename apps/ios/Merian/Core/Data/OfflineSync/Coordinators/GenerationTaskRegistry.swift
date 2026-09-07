import Foundation

/// Main-actor task registry with compare-before-clear ownership.
///
/// Cancelling a Swift task is cooperative. A replaced task may therefore resume
/// after its successor has occupied the same key. Every task receives a unique
/// token and must still own that token before clearing the slot or performing
/// delayed work.
@MainActor
final class GenerationTaskRegistry<Key: Hashable> {
    private struct Entry {
        let token: UUID
        let ownerGeneration: UUID?
        let task: Task<Void, Never>
    }

    private var entries: [Key: Entry] = [:]

    var keys: Set<Key> {
        Set(entries.keys)
    }

    var count: Int {
        entries.count
    }

    @discardableResult
    func replace(
        for key: Key,
        ownerGeneration: UUID?,
        makeTask: (UUID) -> Task<Void, Never>
    ) -> UUID {
        let previous = entries.removeValue(forKey: key)
        previous?.task.cancel()

        let token = UUID()
        let task = makeTask(token)
        entries[key] = Entry(
            token: token,
            ownerGeneration: ownerGeneration,
            task: task
        )
        return token
    }

    func isCurrent(
        _ key: Key,
        token: UUID,
        ownerGeneration: UUID? = nil
    ) -> Bool {
        guard let entry = entries[key], entry.token == token else { return false }
        return ownerGeneration == nil || entry.ownerGeneration == ownerGeneration
    }

    func isOwned(_ key: Key, by ownerGeneration: UUID) -> Bool {
        entries[key]?.ownerGeneration == ownerGeneration
    }

    @discardableResult
    func clearIfCurrent(
        _ key: Key,
        token: UUID,
        cancel: Bool = false
    ) -> Bool {
        guard let entry = entries[key], entry.token == token else { return false }
        entries[key] = nil
        if cancel {
            entry.task.cancel()
        }
        return true
    }

    func cancel(_ key: Key) {
        let entry = entries.removeValue(forKey: key)
        entry?.task.cancel()
    }

    func cancel(_ key: Key, ifOwnedBy ownerGeneration: UUID) {
        guard entries[key]?.ownerGeneration == ownerGeneration else { return }
        cancel(key)
    }

    func cancelAll() {
        let tasks = entries.values.map(\.task)
        entries.removeAll()
        tasks.forEach { $0.cancel() }
    }
}
