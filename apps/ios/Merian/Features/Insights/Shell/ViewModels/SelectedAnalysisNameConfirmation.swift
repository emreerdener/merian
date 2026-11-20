import Foundation
import Observation

/// A form borrows the retained review; dismissing it never retires a saved request.
@MainActor @Observable
final class SelectedAnalysisNameConfirmation: Identifiable {
    let id = UUID()
    let review: IdentificationHistoryReviewModel
    var scientificName = ""
    private(set) var isClosed = false
    private let isCurrent: () -> Bool
    private let submitName: (String) -> Void

    init(review: IdentificationHistoryReviewModel, isCurrent: @escaping () -> Bool,
         submit: @escaping (String) -> Void) {
        self.review = review; self.isCurrent = isCurrent; submitName = submit
    }
    var canSubmit: Bool {
        !isClosed && isCurrent() && review.canSubmit && review.ticket.canConfirmName
            && (try? review.ticket.request(.confirmName(scientificName), operationID: review.ticket.analysisID)) != nil
    }
    func submit() {
        guard canSubmit else { return }
        submitName(scientificName)
    }
    func close() { isClosed = true; scientificName = "" }
}
