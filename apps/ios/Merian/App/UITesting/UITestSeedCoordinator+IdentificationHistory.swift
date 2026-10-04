#if DEBUG
import Foundation
import SwiftData

extension UITestSeedCoordinator {
    @MainActor static var identificationHistoryAccess: IdentificationHistoryAccess? {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains("-seedIdentificationHistory") else { return nil }
        return IdentificationHistoryAccess(hasMultiple: { id, _ in id == "private_map_bird" }, open: { _, _ in
            let fixture = IdentificationHistoryUIFixture()
            return fixture.dependencies
        })
    }
}

/// Domain-value fixture for the production sheet/state machine. No live account,
/// provider, photo URL, history writer or rollout switch is involved.
@MainActor private final class IdentificationHistoryUIFixture {
    let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let a = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    let b = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    var selected = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    var target: UUID?
    var operation: UUID?
    var receipt: UUID?
    var revision = 1
    var closed = false
    var context: ObservationHistoryListingService.Context {
        .init(owner: owner, selected: selected, revision: revision, pendingOperation: operation, undoOperation: receipt)
    }
    var rows: [IdentificationHistoryRow] {
        [a, b].map { .init(id: $0, title: $0 == a ? "First identification" : "Second identification", scientificName: nil,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000), confidence: "Possible match", review: "Not confirmed", isImported: false) }
    }
    var dependencies: IdentificationHistoryDependencies {
        .init(context: { [self] in context }, page: { [self] _ in .init(rows: rows, nextBeforeOrdinal: nil, context: context) },
            preview: { [self] id in
                guard let row = rows.first(where: { $0.id == id }) else { throw ObservationHistoryError.unavailable }
                return .init(row: row, reasoning: "Synthetic saved analysis used only for UI verification.", alternatives: [], evidenceDescription: "Synthetic observation.", photoIDs: [], canRestore: id != selected, isCached: false)
            }, prepare: { [self] id in target = id; operation = UUID() },
            prepareUndo: { [self] id in
                guard id == receipt else { throw ObservationHistorySelectionIntent.Failure.staleUndo }
                target = selected == a ? b : a; operation = UUID()
            }, sendPending: { [self] in
                guard let target, let operation else { throw ObservationHistoryError.unavailable }
                let previous = selected; selected = target; revision += 1; receipt = operation
                self.operation = nil; self.target = nil
                return .selected(.init(schema_version: 1, operation_id: operation.uuidString.lowercased(), observation_id: owner.uuidString.lowercased(),
                    previous_analysis_id: previous.uuidString.lowercased(), selected_analysis_id: selected.uuidString.lowercased(), observation_revision: revision, review_revision: 0))
            }, photo: { _, _ in throw ObservationHistoryError.unavailable }, isCurrent: { [self] in !closed }, close: { [self] in closed = true })
    }
}
#endif
