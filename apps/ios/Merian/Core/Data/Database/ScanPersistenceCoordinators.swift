import Foundation

/// Serializes local record finalization for one scan across independent
/// SwiftData contexts.
///
/// Live visual, live non-visual, and background inference can complete the
/// same scan concurrently. Ordering their `LocalScanRecord` writes avoids
/// relying on unique-constraint merge recovery for relationships without
/// inverses.
actor ScanFinalizationCoordinator {
    static let shared = ScanFinalizationCoordinator()

    private var activeScanIds: Set<String> = []
    private var waitersByScanId: [String: [CheckedContinuation<Void, Never>]] = [:]

    private init() {}

    @discardableResult
    func acquire(scanId: String) async -> Bool {
        if activeScanIds.insert(scanId).inserted {
            return false
        }

        await withCheckedContinuation { continuation in
            waitersByScanId[scanId, default: []].append(continuation)
        }
        return true
    }

    func release(scanId: String) {
        guard var waiters = waitersByScanId[scanId], !waiters.isEmpty else {
            activeScanIds.remove(scanId)
            waitersByScanId[scanId] = nil
            return
        }

        let next = waiters.removeFirst()
        waitersByScanId[scanId] = waiters.isEmpty ? nil : waiters
        next.resume()
    }
}

/// Serializes inference claims, recovery retreats, finalization validation,
/// and deletion across actor instances.
///
/// Durable generation metadata remains authoritative; this process-local gate
/// closes independent-`ModelContext` fetch-to-save windows around that proof.
actor ScanInferencePersistenceCoordinator {
    static let shared = ScanInferencePersistenceCoordinator()

    private var activeScanIds: Set<String> = []
    private var waitersByScanId: [String: [CheckedContinuation<Void, Never>]] = [:]

    private init() {}

    func acquire(scanId: String) async {
        if activeScanIds.insert(scanId).inserted {
            return
        }

        await withCheckedContinuation { continuation in
            waitersByScanId[scanId, default: []].append(continuation)
        }
    }

    func release(scanId: String) {
        guard var waiters = waitersByScanId[scanId], !waiters.isEmpty else {
            activeScanIds.remove(scanId)
            waitersByScanId[scanId] = nil
            return
        }

        let next = waiters.removeFirst()
        waitersByScanId[scanId] = waiters.isEmpty ? nil : waiters
        next.resume()
    }
}
