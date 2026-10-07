import Foundation
import SwiftData

/// Retains foreground reads through cancellation until their account leases close.
/// This owner never creates or retries a durable review operation.
@MainActor
final class ObservationRejectionUndoOwner {
    enum Failure: Error { case busy, capacity, draining }
    static let maximumActiveLookups = 4

    private struct Scope: Equatable {
        let ticket: ObservationAnalysisReviewTicket
        let session: AuthTransitionSession
        let generation: UInt64
        let container: ObjectIdentifier
    }
    private struct Entry {
        let scope: Scope
        let task: Task<ObservationRejectionUndoEligibility.Resolution, Error>
        var cancelled = false
    }
    private var entries: [UUID: Entry] = [:]
    private var drains = 0
    var activeCount: Int { entries.count }

    /// isCurrent describes the common account/session/container environment, not one waiter's presentation.
    func prepare(ticket: ObservationAnalysisReviewTicket, session: AuthTransitionSession, generation: UInt64,
                 container: ModelContainer, service: ObservationRejectionUndoService,
                 isCurrent: @escaping @MainActor () -> Bool) async throws -> ObservationRejectionUndoEligibility.Resolution {
        try Task.checkCancellation()
        guard drains == 0 else { throw Failure.draining }
        guard ticket.ownerID == session.userID, isCurrent() else { throw ObservationHistoryError.accountChanged }
        let scope = Scope(ticket: ticket, session: session, generation: generation, container: ObjectIdentifier(container))
        let task: Task<ObservationRejectionUndoEligibility.Resolution, Error>
        if let existing = entries.values.first(where: { $0.scope == scope }) {
            guard !existing.cancelled else { throw Failure.busy }
            task = existing.task
        } else {
            guard entries.count < Self.maximumActiveLookups else { throw Failure.capacity }
            let token = UUID()
            task = Task { @MainActor [self] in
                defer { entries[token] = nil }
                let current = { [self] in entries[token]?.cancelled == false && isCurrent() }
                try Task.checkCancellation()
                guard current() else { throw ObservationHistoryError.accountChanged }
                var scopedService = service
                scopedService.cloud.isCurrent = { service.cloud.isCurrent($0) && $0.session == session && current() }
                let result = try await scopedService.prepare(ticket: ticket, container: container, isCurrent: current)
                try Task.checkCancellation()
                guard current() else { throw ObservationHistoryError.accountChanged }
                return result
            }
            entries[token] = Entry(scope: scope, task: task)
        }
        // Cancelling one joined waiter cannot cancel the shared read for another.
        // The task has removed its slot by now; only the waiter's own scope remains relevant.
        let result = await task.result
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        return try result.get()
    }

    /// A stale presentation cannot cancel another ticket, generation or container.
    func cancel(ticket: ObservationAnalysisReviewTicket, session: AuthTransitionSession, generation: UInt64,
                in container: ModelContainer) {
        let scope = Scope(ticket: ticket, session: session, generation: generation, container: ObjectIdentifier(container))
        let tokens = entries.compactMap { $0.value.scope == scope ? $0.key : nil }
        for token in tokens { cancel(token) }
    }

    func cancelAll() {
        for token in Array(entries.keys) { cancel(token) }
    }

    /// Overlapping drains keep admission closed until every captured task actually exits.
    func cancelAndAwaitAll() async {
        drains += 1
        defer { drains -= 1 }
        let active = Array(entries.values)
        cancelAll()
        for entry in active { _ = await entry.task.result }
    }

    private func cancel(_ token: UUID) {
        entries[token]?.cancelled = true
        entries[token]?.task.cancel()
    }
}
