import Foundation
import Observation

/// Borrows one retained review. Local deck navigation never changes authority or
/// exhausts the saved analysis; only the final confirmation stages a decision.
@MainActor @Observable
final class AnalysisCandidateReviewModel: Identifiable {
    let id = UUID()
    let review: IdentificationHistoryReviewModel
    private(set) var remaining: [ObservationAnalysisCandidateChoice]
    private(set) var isClosed = false
    private let isCurrent: () -> Bool
    private let confirm: (ObservationAnalysisCandidateReference) -> Void

    init(review: IdentificationHistoryReviewModel, isCurrent: @escaping () -> Bool,
         confirm: @escaping (ObservationAnalysisCandidateReference) -> Void) {
        self.review = review; self.isCurrent = isCurrent; self.confirm = confirm
        remaining = review.ticket.candidateChoices
    }
    var isScopeCurrent: Bool { !isClosed && isCurrent() && !review.isClosed }
    var canReview: Bool { isScopeCurrent && review.canSubmit }
    func submit(_ reference: ObservationAnalysisCandidateReference) {
        guard canReview, remaining.contains(where: { $0.reference == reference }),
              review.ticket.candidateChoices.contains(where: { $0.reference == reference }) else { return }
        // The callback must synchronously enter the retained review owner. Never
        // defer this behind an animation, Task or child-sheet dismissal.
        confirm(reference)
    }
    func dismissChoice(_ reference: ObservationAnalysisCandidateReference) {
        guard canReview else { return }
        remaining.removeAll { $0.reference == reference }
    }
    func skip() {
        guard canReview, remaining.count > 1 else { return }
        remaining.append(remaining.removeFirst())
    }
    func restart() {
        guard canReview else { return }
        remaining = review.ticket.candidateChoices
    }
    func close() {
        isClosed = true; remaining = []
        // Do not close the borrowed review or discard its uncertain request.
    }
}
