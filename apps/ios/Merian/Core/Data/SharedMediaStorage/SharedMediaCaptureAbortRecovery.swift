import Foundation
import SwiftData

/// Descriptive, abort-only discovery. An unrecorded empty partial cannot be
/// exposed through normal draft discovery or converted into readable bytes.
@MainActor
enum SharedMediaCaptureAbortRecovery {
    struct Handle: Equatable, Sendable {
        fileprivate let receipt: SharedMediaCaptureDraftJournalReceipt.Snapshot
        var scanID: UUID { receipt.value.scanID }
        var generation: UUID { receipt.value.generation }
        var planSHA256: String? { receipt.value.preparation?.observation.sha256 }
    }

    static func discover(container: ModelContainer, authority: SharedMediaNativeAppOperationAuthority,
                         files: SharedMediaCaptureArtifactFiles) async throws -> [Handle] {
        let before = try authority.header(container)
        let context = ModelContext(container); context.autosaveEnabled = false
        var query = FetchDescriptor<SharedMediaCaptureDraftJournalRecord>(sortBy: [SortDescriptor(\.cursorKey)])
        query.fetchLimit = 16
        var result: [Handle] = [], cleanupTarget: UUID?, unfinished = 0
        while true {
            try Task.checkCancellation()
            let rows = try context.fetch(query)
            for row in rows {
                let saved = try SharedMediaCaptureDraftJournalReceipt.decode(row), value = saved.value
                guard value.profile == authority.profile, value.rootBindingSHA256 == files.rootBindingSHA256 else {
                    throw SharedMediaStorageFailure.conflict
                }
                if value.phase != .accepted && value.phase != .released { unfinished += 1 }
                guard value.phase == .preparing || value.phase == .abortingPreparation else { continue }
                guard result.count < PhotoPreparationPolicy.maximumPackages, value.preparation != nil,
                      try SharedMediaCaptureSubmissionReceipt.matching(scanID: value.scanID,
                        generation: value.generation, in: context) == nil else { throw SharedMediaStorageFailure.closed }
                try SharedMediaCaptureDraftSourceBinding.requireUnclaimed(scan: value.scanID, context: context)
                if let target = try SharedMediaCapturePreparationAbort.ambiguousTarget(saved, container: container, files: files) {
                    guard cleanupTarget == nil else { throw SharedMediaStorageFailure.closed }
                    cleanupTarget = target
                }
                result.append(.init(receipt: saved))
            }
            if rows.count < 16 { break }
            let (next, overflow) = (query.fetchOffset ?? 0).addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            query.fetchOffset = next
        }
        _ = try await SharedMediaCaptureBudget.evaluate(container, authority: authority, files: files, cleanupTarget: cleanupTarget)
        guard try authority.header(container) == before else { throw SharedMediaStorageFailure.stale }
        guard result.isEmpty || unfinished == 1 else { throw SharedMediaStorageFailure.closed }
        return result
    }

    static func expected(_ handle: Handle) -> SharedMediaCaptureDraftJournalReceipt.Snapshot {
        // The abort owner rechecks the exact current or finished successor.
        // Retaining this value permits lost-ack replay without a generic read.
        handle.receipt
    }
}
