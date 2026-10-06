import SwiftUI

/// One immutable optional installation; a host cannot enable only part of history.
@MainActor
struct InsightHistoryReanalysisAccesses {
    let history: IdentificationHistoryAccess
    let status: ReanalysisStatusAccess
    let reanalyze: SavedIdentificationReanalysisAccess
    var selectedReview: SelectedAnalysisReviewAccess?

    func applying(to dependencies: InsightShellDependencies) -> InsightShellDependencies {
        // Preserve complete fixture ownership, including Debug fixtures supplied by .live.
        guard dependencies.historyAccess == nil, dependencies.reanalysisStatusAccess == nil,
              dependencies.savedReanalysisAccess == nil, dependencies.selectedReviewAccess == nil else { return dependencies }
        var result = dependencies
        result.historyAccess = history
        result.reanalysisStatusAccess = status
        result.savedReanalysisAccess = reanalyze
        result.selectedReviewAccess = selectedReview
        return result
    }
}

private struct InsightHistoryReanalysisAccessesKey: EnvironmentKey {
    static let defaultValue: InsightHistoryReanalysisAccesses? = nil
}

extension EnvironmentValues {
    var insightHistoryReanalysisAccesses: InsightHistoryReanalysisAccesses? {
        get { self[InsightHistoryReanalysisAccessesKey.self] }
        set { self[InsightHistoryReanalysisAccessesKey.self] = newValue }
    }
}
