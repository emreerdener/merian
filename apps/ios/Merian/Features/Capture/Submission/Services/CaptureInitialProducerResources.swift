import Foundation

/// Registered with the account lifetime before capture begins. A failed
/// original handoff can leave producer files in review; those files and their
/// recorder readers remain owned until explicit cleanup succeeds.
@MainActor
final class CaptureInitialProducerResources {
    private var leases: [ObjectIdentifier: CaptureScanTemporaryFileLease] = [:]
    private var recorders: [ObjectIdentifier: AudioCaptureManager] = [:]
    private var isClosing = false
    private var discardHandoffs: [UUID: @MainActor () -> Void] = [:]
    private var retryHandoffs: [UUID: @MainActor () async throws -> Void] = [:]

    func retain(_ lease: CaptureScanTemporaryFileLease) throws {
        guard !isClosing else { throw SharedMediaStorageFailure.closed }
        leases[ObjectIdentifier(lease)] = lease
    }

    func retainForRecovery(_ lease: CaptureScanTemporaryFileLease, itemID: UUID) throws {
        guard retryHandoffs[itemID] != nil else { throw SharedMediaStorageFailure.closed }
        leases[ObjectIdentifier(lease)] = lease
    }

    func retain(_ recorder: AudioCaptureManager) throws {
        guard !isClosing else { throw SharedMediaStorageFailure.closed }
        recorders[ObjectIdentifier(recorder)] = recorder
    }

    /// Before dropping a producer's only file, preserve its complete item in
    /// the existing bounded retry buffer. Cleanup failure keeps its receipt.
    func preserveBeforeRetirement(itemID: UUID, discard: @escaping @MainActor () -> Void = {}, _ handoff: @escaping @MainActor () async throws -> Void) throws {
        guard !isClosing else { throw SharedMediaStorageFailure.closed }
        retryHandoffs[itemID] = handoff
        discardHandoffs[itemID] = discard
    }

    func acknowledge(itemID: UUID) {
        retryHandoffs[itemID] = nil
        discardHandoffs.removeValue(forKey: itemID)?()
    }
    func discardRetryInputs() {
        for id in Array(retryHandoffs.keys) { acknowledge(itemID: id) }
    }

    func retire(_ lease: CaptureScanTemporaryFileLease) async throws {
        try await lease.discard()
        leases[ObjectIdentifier(lease)] = nil
    }

    func discard() async -> Bool {
        isClosing = true
        var complete = true
        for (id, handoff) in Array(retryHandoffs) {
            // Account shutdown may cancel its caller. This registered cleanup
            // still joins an uncancelled bounded copy before unlinking sources.
            let task = Task { @MainActor in try await handoff() }
            do { try await task.value; acknowledge(itemID: id) } catch { return false }
        }
        for (id, recorder) in Array(recorders) {
            recorder.reset()
            if await recorder.drainOriginalRetirements() { recorders[id] = nil } else { complete = false }
        }
        for (id, lease) in Array(leases) {
            do { try await lease.discard(); leases[id] = nil } catch { complete = false }
        }
        return complete && leases.isEmpty && recorders.isEmpty
    }
}
