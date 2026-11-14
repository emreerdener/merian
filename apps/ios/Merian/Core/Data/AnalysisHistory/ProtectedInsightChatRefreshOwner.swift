import Foundation
import SwiftData

/// Explicit read-only refreshes survive waiter dismissal until their account leases exit.
@MainActor
final class ProtectedInsightChatRefreshOwner {
    enum Failure: Error { case busy, capacity, draining, unchanged }
    static let maximumActiveRefreshes = 4
    private struct Scope: Equatable {
        let ticket: ProtectedInsightChatTicket
        let session: AuthTransitionSession
        let generation: UInt64
        let container: ObjectIdentifier
    }
    private struct Entry {
        let scope: Scope
        let task: Task<ProtectedInsightChatTicket, Error>
        var cancelled = false
    }
    private var entries: [UUID: Entry] = [:]
    private var drains = 0
    var activeCount: Int { entries.count }

    func refresh(ticket: ProtectedInsightChatTicket, session: AuthTransitionSession, generation: UInt64,
                 container: ModelContainer, cloud: ObservationHistoryCloudClient,
                 isCurrent: @escaping @MainActor () -> Bool) async throws -> ProtectedInsightChatTicket {
        try Task.checkCancellation()
        guard drains == 0 else { throw Failure.draining }
        guard ticket.ownerID == session.userID, isCurrent() else { throw ObservationHistoryError.accountChanged }
        let scope = Scope(ticket: ticket, session: session, generation: generation, container: ObjectIdentifier(container))
        let task: Task<ProtectedInsightChatTicket, Error>
        if let existing = entries.values.first(where: { $0.scope == scope }) {
            guard !existing.cancelled else { throw Failure.busy }
            task = existing.task
        } else {
            guard entries.count < Self.maximumActiveRefreshes else { throw Failure.capacity }
            let token = UUID()
            task = Task { @MainActor [self] in
                defer { entries[token] = nil }
                let current = { [self] in entries[token]?.cancelled == false && isCurrent() }
                try Task.checkCancellation()
                guard current() else { throw ObservationHistoryError.accountChanged }
                var scoped = cloud
                scoped.isCurrent = { cloud.isCurrent($0) && $0.session == session && current() }
                guard try Self.selectedTicket(ownerID: ticket.ownerID, observationID: ticket.observationID,
                    container: container, cloud: scoped) == ticket else { throw ObservationHistoryError.resultConflict }
                try Task.checkCancellation()
                guard current() else { throw ObservationHistoryError.accountChanged }
                _ = try await ObservationHistoryStateSyncService(cloud: scoped)
                    .syncSelected(observationID: ticket.observationID.uuidString, container: container)
                try Task.checkCancellation()
                guard current() else { throw ObservationHistoryError.accountChanged }
                let fresh = try Self.selectedTicket(ownerID: ticket.ownerID, observationID: ticket.observationID,
                                                    container: container, cloud: scoped)
                guard current() else { throw ObservationHistoryError.accountChanged }
                guard fresh.selection != ticket.selection else { throw Failure.unchanged }
                return fresh
            }
            entries[token] = Entry(scope: scope, task: task)
        }
        let result = await task.result
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        return try result.get()
    }

    /// Recheck immediately before presentation applies a returned ticket; this never fetches.
    static func selectedTicket(ownerID: UUID, observationID: UUID, container: ModelContainer,
                               cloud: ObservationHistoryCloudClient) throws -> ProtectedInsightChatTicket {
        let listing = ObservationHistoryListingService(cloud: cloud)
        let state = try listing.context(observationID: observationID.uuidString, container: container)
        guard state.owner == ownerID, state.pendingOperation == nil else {
            throw ObservationHistoryError.resultConflict
        }
        let entry = try listing.cached(observationID: observationID.uuidString, analysisID: state.selected, container: container)
        guard try listing.context(observationID: observationID.uuidString, container: container) == state else {
            throw ObservationHistoryError.resultConflict
        }
        _ = try ObservationHistoryStateSyncService.displayBaseline(observation: observationID, container: container)
        return try .init(entry: entry, context: state, observationID: observationID)
    }

    func cancelAll() {
        for token in Array(entries.keys) { entries[token]?.cancelled = true; entries[token]?.task.cancel() }
    }
    func cancelAndAwaitAll() async {
        drains += 1
        defer { drains -= 1 }
        let active = Array(entries.values)
        cancelAll()
        for entry in active { _ = await entry.task.result }
    }
}
