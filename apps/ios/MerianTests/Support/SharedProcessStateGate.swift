import Foundation

/// One test-only lease boundary for Swift Testing and XCTest. Claim all needed
/// resources together; nesting independent acquisitions can deadlock.
actor SharedProcessStateGate {
    static let shared = SharedProcessStateGate()

    struct Lease: Sendable {
        fileprivate let id = UUID()
        fileprivate let resources: Set<SharedProcessStateResource>
    }

    private struct Waiter {
        let lease: Lease
        let continuation: CheckedContinuation<Lease, Error>
    }

    private var active: [UUID: Set<SharedProcessStateResource>] = [:]
    private var waiters: [Waiter] = []
    var waitingCount: Int { waiters.count }

    func withResources(
        _ resources: Set<SharedProcessStateResource>,
        performing operation: @Sendable () async throws -> Void
    ) async throws {
        let lease = try await acquire(resources)
        defer { release(lease) }
        try Task.checkCancellation()
        try await operation()
    }

    /// Low-level XCTest lifecycle API. Every returned lease needs a release,
    /// including cancellation immediately after admission; prefer withResources.
    func acquire(_ resources: Set<SharedProcessStateResource>) async throws -> Lease {
        try Task.checkCancellation()
        let lease = Lease(resources: resources)
        if resources.isDisjoint(with: occupiedOrWaitingResources) {
            active[lease.id] = resources
            return lease
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(lease: lease, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaitingLease(lease.id) }
        }
    }

    func release(_ lease: Lease) {
        // An old/double release cannot unlock another test's resource.
        guard active.removeValue(forKey: lease.id) != nil else { return }
        admitWaiters()
    }

    private var occupiedOrWaitingResources: Set<SharedProcessStateResource> {
        active.values.reduce(into: Set<SharedProcessStateResource>()) { $0.formUnion($1) }
            .union(waiters.reduce(into: Set<SharedProcessStateResource>()) { $0.formUnion($1.lease.resources) })
    }

    private func cancelWaitingLease(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.lease.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
        admitWaiters()
    }

    private func admitWaiters() {
        var unavailable = active.values.reduce(into: Set<SharedProcessStateResource>()) { $0.formUnion($1) }
        var pending: [Waiter] = []
        for waiter in waiters {
            if waiter.lease.resources.isDisjoint(with: unavailable) {
                active[waiter.lease.id] = waiter.lease.resources
                waiter.continuation.resume(returning: waiter.lease)
            } else {
                pending.append(waiter)
            }
            // Preserve FIFO for overlapping sets; work disjoint from every
            // active or earlier queued resource set may still run concurrently.
            unavailable.formUnion(waiter.lease.resources)
        }
        waiters = pending
    }
}
