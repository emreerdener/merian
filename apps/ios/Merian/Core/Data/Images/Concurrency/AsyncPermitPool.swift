import Foundation

actor AsyncPermitPool {
    private var availablePermits: Int
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    init(limit: Int) {
        availablePermits = max(1, limit)
    }

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        if availablePermits > 0 {
            availablePermits -= 1
            return true
        }

        let id = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiterOrder.append(id)
                waiters[id] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id)
            }
        }

        guard acquired else { return false }
        guard !Task.isCancelled else {
            // Cancellation and release can race after a waiter is resumed. Return
            // the granted slot instead of making every caller repair that race.
            release()
            return false
        }
        return true
    }

    func release() {
        while let id = waiterOrder.first {
            waiterOrder.removeFirst()
            guard let continuation = waiters.removeValue(forKey: id) else { continue }
            continuation.resume(returning: true)
            return
        }
        availablePermits += 1
    }

    private func cancelWaiter(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        waiterOrder.removeAll { $0 == id }
        continuation.resume(returning: false)
    }
}
