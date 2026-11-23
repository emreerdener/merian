import Foundation
import SwiftData

/// Paged reverse audit of receiving intents and terminal identities. This owner
/// reads values only; every page releases its context before suspension.
@MainActor
struct SharedMediaNativeReceivingReverseAudit {
    typealias ProjectionMemo = SharedMediaNativeReleaseSurvivorProjection.Memo
    let container: ModelContainer
    let appHeader: SharedMediaNativeAppEligibility.Header?
    let check: () throws -> Void
    let betweenPages: () async throws -> Void
    let fullBoundaryCheck: (() throws -> Void)?
    let header: (ModelContext, ProjectionMemo?) throws -> SharedMediaInventoryRecord
    #if DEBUG
    var inspectionTrace: SharedMediaNativeDebugHooks.InspectionTrace?
    #endif
    private func checkBoundary() throws { try (fullBoundaryCheck ?? check)() }
    private func freshContext() -> ModelContext {
        let context = ModelContext(container); context.autosaveEnabled = false; return context
    }
    func run() async throws {
        var offset = 0
        while true {
            try Task.checkCancellation(); try checkBoundary()
            let count = try receivingPage(offset: offset)
            // The synchronous page releases its context/models/snapshots first.
            try fullBoundaryCheck?()
            try await betweenPages(); try Task.checkCancellation(); try checkBoundary()
            _ = try header(freshContext(), nil)
            if count < SharedMediaStoragePolicy.pageSize { return }
            let (next, overflow) = offset.addingReportingOverflow(count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
    }

    private func receivingPage(offset: Int) throws -> Int {
        #if DEBUG
        inspectionTrace?.enter(.receivingRoots)
        #endif
        let projectionMemo = ProjectionMemo()
        let context = freshContext(), inventory = try header(context, projectionMemo)
        let roots = try SharedMediaNativeReceivingCleanGraph.pending(context, inventory: inventory,
            projectionMemo: projectionMemo, checkpoint: check)
        // No inventory predicate: foreign/orphan raw rows must fail closed.
        var query = FetchDescriptor<SharedMediaReceivingIntentRecord>(sortBy: [SortDescriptor(\.cursorKey)])
        query.fetchOffset = offset; query.fetchLimit = SharedMediaStoragePolicy.pageSize
        let rows = try context.fetch(query)
        var terminals: [SharedMediaNativeReceivingTerminal.Snapshot] = []
        var retained: [SharedMediaNativePhotoAllocationSnapshot.Applied] = []
        #if DEBUG
        inspectionTrace?.enter(.receivingLeaves)
        #endif
        for row in rows {
            try Task.checkCancellation(); try check()
            if row.phaseRaw == "released" {
                terminals.append(try SharedMediaNativeReceivingTerminal.read(row, context: context,
                    inventory: inventory, checkpoint: check))
            } else if let witness = roots[row.id] {
                let saved: SharedMediaNativeReceivingIntentGraph.Row
                switch witness {
                case .allocating(let value), .initial(let value): saved = value.row
                case .generic(let value): saved = value.row
                case .releasing(let value): saved = value.release.slot
                case .staged(let value): saved = value.origin.row
                }
                guard saved == SharedMediaNativeReceivingIntentGraph.Row(row) else { throw SharedMediaStorageFailure.stale }
            } else {
                // Missing roots are not sufficient: the explicit reader must
                // establish the complete retained original and reverse links.
                retained.append(try SharedMediaNativePhotoAllocationSnapshot.Applied.read(row,
                    inventory: inventory, context: context, checkpoint: check))
            }
        }
        #if DEBUG
        inspectionTrace?.enter(.receivingIdentities)
        #endif
        try SharedMediaNativeTerminalIdentity.auditPage(terminals, live: roots, context: context,
            expectedHeader: appHeader, checkpoint: check)
        try SharedMediaNativeTerminalIdentity.auditAppliedPage(retained, live: roots, context: context,
            expectedHeader: appHeader, checkpoint: check)
        // Fresh full pending-root/runway validation, not a header-only fence or
        // reuse of the page's projection memo, before any page suspension.
        #if DEBUG
        inspectionTrace?.enter(.receivingBoundary)
        #endif
        try check(); _ = try header(freshContext(), nil)
        return rows.count
    }

}
