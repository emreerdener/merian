import Foundation
import Observation

/// Recorder-original custody survives presentation reset. Holds and borrowers
/// delay exact-file retirement; shutdown joins preview readers and every unlink.
@MainActor
@Observable
final class AudioCaptureDraftOriginalCustody {
    private(set) var isTransferringOriginal = false
    private var borrowedOriginals: Set<String> = []
    private var pendingOriginalRemoval: Set<String> = []
    private var draftOriginalHolds: Set<UUID> = []
    private var completedDraftOriginals: [UUID: (path: String, capturedAt: Date)] = [:]
    private var originalRetirements: [String: LegacyMediaFileRetirement] = [:]
    private var originalSnapshots: [String: LegacyMediaFileRetirement] = [:]
    private var originalRetirementTasks: [String: Task<Bool, Never>] = [:]

    private let retireReaders: () -> [Task<Void, Never>]
    init(retireReaders: @escaping () -> [Task<Void, Never>]) { self.retireReaders = retireReaders }

    func recordCompleted(path: String, recordingID: UUID?, capturedAt: Date?) {
        originalSnapshots[path] = LegacyMediaFileRetirement.temporaryFile(
            at: FileManager.default.temporaryDirectory.appendingPathComponent(path))
        if let recordingID, draftOriginalHolds.contains(recordingID), let capturedAt {
            completedDraftOriginals[recordingID] = (path, capturedAt)
        }
    }

    func prepareRetirement(path: String) { originalRetirements[path] = originalSnapshots[path] }
    func forgetTransferred(path: String) { originalSnapshots[path] = nil }

    /// Installed by the registered producer owner before recording starts.
    /// UI reset can revoke presentation, but cannot retire a completed original
    /// until that owner has preserved its bytes or explicitly discarded it.
    func holdOriginalForDraft(recordingID: UUID) { draftOriginalHolds.insert(recordingID) }

    func copyHeldDraftOriginal(recordingID: UUID, beforeRead: () -> Void) async throws -> (bytes: Data, capturedAt: Date)? {
        guard draftOriginalHolds.contains(recordingID) else { throw AudioCaptureError.recordingBusy }
        beforeRead()
        for task in retireReaders() { await task.value }
        guard let original = completedDraftOriginals[recordingID] else { return nil }
        guard let receipt = originalSnapshots[original.path],
              let bytes = await FileIOActor.shared.readRetainedOriginal(receipt, maximumBytes: 2_700_000) else {
            throw AudioCaptureError.recordingBusy
        }
        return (bytes, original.capturedAt)
    }

    func releaseOriginalForDraft(recordingID: UUID) {
        draftOriginalHolds.remove(recordingID)
        if let original = completedDraftOriginals.removeValue(forKey: recordingID),
           pendingOriginalRemoval.contains(original.path) { deleteTemporaryFile(named: original.path) }
    }

    /// The recorder retains its exact temporary original across the durable
    /// copy. Reset/discard may revoke presentation immediately, but cannot
    /// unlink a source still borrowed by that copy or preview preparation.
    func withSubmittedOriginal<Value: Sendable>(
        path: String, isCurrent: () -> Bool, beforeRead: () -> Void,
        operation: @MainActor (URL) async throws -> Value
    ) async throws -> Value {
        guard !isTransferringOriginal, isCurrent() else {
            throw AudioCaptureError.recordingBusy
        }
        isTransferringOriginal = true
        borrowedOriginals.insert(path)
        defer {
            borrowedOriginals.remove(path)
            isTransferringOriginal = false
            if pendingOriginalRemoval.remove(path) != nil { deleteTemporaryFile(named: path) }
        }
        beforeRead()
        for task in retireReaders() { await task.value }
        guard isCurrent() else { throw CancellationError() }
        try Task.checkCancellation()
        let result = try await operation(FileManager.default.temporaryDirectory.appendingPathComponent(path))
        guard isCurrent() else { throw CancellationError() }
        try Task.checkCancellation()
        return result
    }

    func deleteTemporaryFile(named fileName: String) {
        guard !borrowedOriginals.contains(fileName),
              !completedDraftOriginals.values.contains(where: { $0.path == fileName }) else {
            pendingOriginalRemoval.insert(fileName)
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        guard originalRetirementTasks[fileName] == nil else { return }
        guard let receipt = originalRetirements[fileName] ?? originalSnapshots[fileName]
            ?? LegacyMediaFileRetirement.temporaryFile(at: url) else {
            // Never turn an unqualified/replaced path into deletion authority.
            pendingOriginalRemoval.insert(fileName)
            return
        }
        originalRetirements[fileName] = receipt
        let readers = retireReaders()
        originalRetirementTasks[fileName] = Task { [self] in
            defer { originalRetirementTasks[fileName] = nil }
            for task in readers { await task.value }
            let removed = await FileIOActor.shared.retireDisposableFiles([receipt])
            if removed {
                originalRetirements[fileName] = nil
                originalSnapshots[fileName] = nil
                pendingOriginalRemoval.remove(fileName)
            }
            return removed
        }
    }

    /// Joins exact-file cleanup. Failure retains the receipt for a later retry;
    /// a replacement at the old filename is never removed by that retry.
    func drainOriginalRetirements() async -> Bool {
        let readers = retireReaders()
        for task in readers { await task.value }
        for name in Array(originalRetirements.keys) { deleteTemporaryFile(named: name) }
        let tasks = Array(originalRetirementTasks.values)
        var complete = true
        for task in tasks where !(await task.value) { complete = false }
        return complete && originalRetirements.isEmpty && pendingOriginalRemoval.isEmpty
    }

}
