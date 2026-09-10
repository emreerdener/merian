import Foundation
import os

/// Versions only affected source URLs. Late decodes can finish under an old key,
/// but cannot populate the cache identity used after evidence changes.
final class LocalScanMediaRecoveryRevisions: Sendable {
    private struct Observer: Sendable {
        let keys: Set<String>
        let continuation: AsyncStream<Void>.Continuation
    }

    private struct State: Sendable {
        var clock: UInt64 = 0
        var resetRevision: UInt64 = 0
        var revisions: [String: UInt64] = [:]
        var observers: [UUID: Observer] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func revision(for keys: [String]) -> UInt64 {
        guard !keys.isEmpty else { return 0 }
        return state.withLock { state in
            keys.reduce(state.resetRevision) { max($0, state.revisions[$1] ?? 0) }
        }
    }

    func invalidate(_ key: String) {
        let continuations = state.withLock { state in
            state.clock += 1
            state.revisions[key] = state.clock
            return state.observers.values.compactMap {
                $0.keys.contains(key) ? $0.continuation : nil
            }
        }
        continuations.forEach { $0.yield(()) }
    }

    func reset() {
        let continuations = state.withLock { state in
            state.clock += 1
            state.resetRevision = state.clock
            state.revisions.removeAll()
            return state.observers.values.map(\.continuation)
        }
        continuations.forEach { $0.yield(()) }
    }

    func changes(for keys: [String]) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        guard !keys.isEmpty else {
            continuation.yield(())
            continuation.finish()
            return stream
        }
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.observers.removeValue(forKey: id) }
        }
        state.withLock {
            $0.observers[id] = Observer(keys: Set(keys), continuation: continuation)
        }
        // Signals carry no historical value: consumers read the current revision,
        // so concurrent publication can never move a subscriber back in time.
        continuation.yield(())
        return stream
    }
}

extension LocalScanMediaRecoveryResolver {
    static func cacheRevision(imagePath: String?, fallbackURL: String?) -> UInt64 {
        LocalScanMediaRecoveryRegistry.shared.cacheRevision(
            for: recoverySourceURLs(imagePath: imagePath, fallbackURL: fallbackURL)
        )
    }

    static func recoveryChanges(imagePath: String?, fallbackURL: String?) -> AsyncStream<Void> {
        LocalScanMediaRecoveryRegistry.shared.changes(
            for: recoverySourceURLs(imagePath: imagePath, fallbackURL: fallbackURL)
        )
    }

    private static func recoverySourceURLs(imagePath: String?, fallbackURL: String?) -> [URL] {
        [imagePath, fallbackURL]
            .flatMap { ExternalReferenceImagePolicy.allowedURLStrings(from: $0) }
            .compactMap(URL.init(string:))
    }
}
