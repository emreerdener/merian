import Foundation

/// A source-qualified action. Resolve again after nested dismissal; never cache a
/// mutable selected-result projection or hold an account-work lease in the sheet.
@MainActor
struct IdentificationHistoryReanalysisAction {
    let resolve: () throws -> HistoricalReanalysisTarget
}

/// Shell owns this one-shot handoff until the exact nested sheet has dismissed.
@MainActor
struct IdentificationHistoryReanalysisHandoff {
    let scanID: String
    let generation: UInt64
    let action: IdentificationHistoryReanalysisAction
    let dispatch: (HistoricalReanalysisTarget) -> Void

    func resume(isPresented: (String, UInt64) -> Bool) throws {
        guard isPresented(scanID, generation) else { return }
        dispatch(try action.resolve())
    }
}
