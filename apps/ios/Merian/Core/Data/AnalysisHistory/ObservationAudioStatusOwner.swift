import Foundation
import SwiftData

/// Bounded explicit reads, retained until their active account leases finish. No idle lease or execution wake.
@MainActor
final class ObservationAudioStatusOwner {
    enum Failure: Error { case capacity, busy, draining }
    static let maximumActiveReads = 4
    private struct Scope: Equatable {
        let owner: UUID
        let observation: UUID
        let session: AuthTransitionSession
        let generation: UInt64
        let container: ObjectIdentifier
        let cursor: ObservationAudioSavedStatus.Cursor?
        let limit: Int
    }
    private struct Entry {
        let scope: Scope
        let task: Task<ObservationAudioSavedStatus.Page, Error>
        var cancelled = false
    }
    private var entries: [UUID: Entry] = [:]
    private var drains = 0
    private var invalidation: UUID?
    var activeCount: Int { entries.count }

    /// Common account/session/generation/container scope only; each waiter fences its own presentation afterward.
    func page(ownerID: UUID, observationID: UUID, session: AuthTransitionSession, generation: UInt64,
              after cursor: ObservationAudioSavedStatus.Cursor? = nil, limit: Int = 20, container: ModelContainer,
              reader: ObservationAudioSavedStatus, account: ObservationHistoryCloudClient,
              isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationAudioSavedStatus.Page {
        try Task.checkCancellation()
        guard drains == 0, invalidation == nil else { throw Failure.draining }
        guard (1...20).contains(limit) else { throw ObservationHistoryError.invalidPage }
        guard ownerID == session.userID, isCurrent() else { throw ObservationHistoryError.accountChanged }
        let scope = Scope(owner: ownerID, observation: observationID, session: session, generation: generation,
            container: ObjectIdentifier(container), cursor: cursor, limit: limit)
        let task: Task<ObservationAudioSavedStatus.Page, Error>
        if let existing = entries.values.first(where: { $0.scope == scope }) {
            guard !existing.cancelled else { throw Failure.busy }
            task = existing.task
        } else {
            guard entries.count < Self.maximumActiveReads else { throw Failure.capacity }
            let token = UUID()
            task = Task { @MainActor [self] in
                defer { entries[token] = nil }
                try Task.checkCancellation()
                guard entries[token]?.cancelled == false, isCurrent() else { throw ObservationHistoryError.accountChanged }
                let lease = try account.begin(ownerID)
                defer { account.finish(lease) }
                let current: @MainActor @Sendable () -> Bool = { [self] in
                    entries[token]?.cancelled == false && invalidation == nil && isCurrent() && lease.session == session && account.isCurrent(lease)
                }
                guard current() else { throw ObservationHistoryError.accountChanged }
                let page = try await reader.page(ownerID: ownerID, observationID: observationID, after: cursor,
                    limit: limit, container: container, isCurrent: current)
                try Task.checkCancellation()
                guard current() else { throw ObservationHistoryError.accountChanged }
                return page
            }
            entries[token] = Entry(scope: scope, task: task)
        }
        // Slot has exited by now. One waiter's cancellation must not cancel other joined callers.
        let result = await task.result
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        return try result.get()
    }

    /// Common scope cancellation only; closing one joined presentation must not call this.
    func cancel(ownerID: UUID, observationID: UUID, session: AuthTransitionSession, generation: UInt64, in container: ModelContainer) {
        let tokens = entries.compactMap { token, entry in
            entry.scope.owner == ownerID && entry.scope.observation == observationID && entry.scope.session == session &&
                entry.scope.generation == generation && entry.scope.container == ObjectIdentifier(container) ? token : nil
        }
        for token in tokens { cancel(token) }
    }

    /// Close admission immediately, including while another Auth owner is being awaited.
    func invalidate() {
        invalidation = UUID()
        for token in Array(entries.keys) { cancel(token) }
    }

    func invalidateAndAwait() async {
        drains += 1
        invalidate()
        let token = invalidation
        defer {
            drains -= 1
            if invalidation == token { invalidation = nil }
        }
        let active = Array(entries.values)
        for entry in active { _ = await entry.task.result }
    }

    private func cancel(_ token: UUID) {
        entries[token]?.cancelled = true
        entries[token]?.task.cancel()
    }
}
