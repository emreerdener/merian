import Foundation
import Observation
import UIKit

/// Borrows one retained review. Local deck navigation never changes authority or
/// exhausts the saved analysis; only the final confirmation stages a decision.
@MainActor @Observable
final class AnalysisCandidateReviewModel: Identifiable {
    let id = UUID()
    let review: IdentificationHistoryReviewModel
    private(set) var remaining: [ObservationAnalysisCandidateChoice]
    private(set) var isClosed = false
    private var loadedPhoto: UIImage?
    private(set) var photoMessage: String?
    private var photoTask: Task<Void, Never>?
    private let loadPhoto: ((UUID, UUID) async throws -> UIImage)?
    private let isCurrent: () -> Bool
    private let confirm: (ObservationAnalysisCandidateReference) -> Void

    init(review: IdentificationHistoryReviewModel, isCurrent: @escaping () -> Bool,
         loadPhoto: ((UUID, UUID) async throws -> UIImage)? = nil,
         confirm: @escaping (ObservationAnalysisCandidateReference) -> Void) {
        self.review = review; self.isCurrent = isCurrent; self.confirm = confirm; self.loadPhoto = loadPhoto
        remaining = review.ticket.candidateChoices
    }
    var isScopeCurrent: Bool { !isClosed && isCurrent() && !review.isClosed }
    var evidencePhoto: UIImage? { isScopeCurrent ? loadedPhoto : nil }
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
    func loadEvidence() async {
        guard isScopeCurrent, loadedPhoto == nil else { return }
        if let task = photoTask { await task.value; return }
        guard let media = review.ticket.evidencePhotoID, let loadPhoto else {
            photoMessage = "Original evidence is unavailable for this identification."
            return
        }
        let analysis = review.ticket.analysisID
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.photoTask = nil }
            do {
                try Task.checkCancellation()
                guard self.isScopeCurrent else { return }
                let image = try await loadPhoto(analysis, media)
                try Task.checkCancellation()
                guard self.isScopeCurrent else { return }
                self.loadedPhoto = image; self.photoMessage = nil
            } catch {
                guard !Task.isCancelled, self.isScopeCurrent else { return }
                self.photoMessage = "This identification’s original evidence is unavailable right now."
            }
        }
        photoTask = task
        await task.value
    }
    func close() {
        isClosed = true; remaining = []; loadedPhoto = nil; photoMessage = nil
        photoTask?.cancel()
        // Do not close the borrowed review or discard its uncertain request.
    }
}
