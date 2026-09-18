import Foundation

/// A target's optimistic baseline is captured only after earlier writes finish.
@MainActor
final class ExploreReactionMutationQueue {
    private var occupied = Set<String>()
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(_ key: String) async {
        if occupied.insert(key).inserted { return }
        await withCheckedContinuation { waiters[key, default: []].append($0) }
    }

    func release(_ key: String) {
        if var pending = waiters[key], !pending.isEmpty {
            let next = pending.removeFirst()
            waiters[key] = pending.isEmpty ? nil : pending
            next.resume()
        } else {
            occupied.remove(key)
        }
    }
}
