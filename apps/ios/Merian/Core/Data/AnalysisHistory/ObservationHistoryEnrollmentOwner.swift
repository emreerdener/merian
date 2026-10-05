import Foundation
import SwiftData

/// Explicit requests only. Durable retry identity remains in EnrollmentIntent; this owner adds no scheduler.
@MainActor
final class ObservationHistoryEnrollmentOwner {
    enum Failure: Error { case busy, capacity, draining }
    static let maximumActiveObservations = 4

    private struct Scope: Equatable {
        let owner: UUID
        let generation: UInt64
        let container: ObjectIdentifier
    }
    private struct Entry {
        let token: UUID
        let scope: Scope
        let task: Task<UUID, Error>
        var cancelled = false
    }
    private var entries: [UUID: Entry] = [:]
    private var drains = 0

    func contains(_ observation: UUID) -> Bool { entries[observation] != nil }

    /// The supplied predicate owns current account/generation/container admission, independently of inference consent.
    func enroll(observation: UUID, owner: UUID, generation: UInt64, container: ModelContainer,
                cloud: ObservationHistoryCloudClient, isCurrent: @escaping @MainActor () -> Bool) async throws -> UUID {
        try Task.checkCancellation()
        guard drains == 0 else { throw Failure.draining }
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        let scope = Scope(owner: owner, generation: generation, container: ObjectIdentifier(container))
        let entry: Entry
        if let active = entries[observation] {
            guard active.scope == scope, !active.cancelled else { throw Failure.busy }
            entry = active
        } else {
            guard entries.count < Self.maximumActiveObservations else { throw Failure.capacity }
            let token = UUID()
            let task = Task { @MainActor [self] in
                defer { if entries[observation]?.token == token { entries[observation] = nil } }
                let current = { [self] in
                    entries[observation]?.token == token && entries[observation]?.cancelled == false && isCurrent()
                }
                try Task.checkCancellation()
                guard current() else { throw ObservationHistoryError.accountChanged }
                var scopedCloud = cloud
                scopedCloud.isCurrent = { cloud.isCurrent($0) && current() }
                let result = try await ObservationHistoryEnrollmentService(cloud: scopedCloud).enroll(
                    observationID: observation.uuidString, expectedOwnerID: owner, container: container)
                try Task.checkCancellation()
                guard current() else { throw ObservationHistoryError.accountChanged }
                return result
            }
            entry = Entry(token: token, scope: scope, task: task)
            entries[observation] = entry
        }
        // A dismissed waiter cannot cancel another caller's admission. Queue/Auth/deletion own the task.
        let result = await entry.task.result
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        return try result.get()
    }

    /// Call only after the matching container's deletion commits. Never alter the durable hold here.
    func cancel(_ observation: UUID, in container: ModelContainer) {
        guard let entry = entries[observation], entry.scope.container == ObjectIdentifier(container) else { return }
        cancel(observation, token: entry.token)
    }

    func cancelAll() {
        for (observation, entry) in entries { cancel(observation, token: entry.token) }
    }

    /// Coalesced drains keep admission closed until every captured task actually exits.
    func cancelAndAwaitAll() async {
        drains += 1
        defer { drains -= 1 }
        let active = Array(entries.values)
        cancelAll()
        for entry in active { _ = await entry.task.result }
    }

    private func cancel(_ observation: UUID, token: UUID) {
        guard entries[observation]?.token == token else { return }
        entries[observation]?.cancelled = true
        entries[observation]?.task.cancel()
    }
}
