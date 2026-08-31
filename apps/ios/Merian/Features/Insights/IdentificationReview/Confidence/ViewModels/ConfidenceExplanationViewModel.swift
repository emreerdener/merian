import Observation
import SwiftData

@MainActor
@Observable
final class ConfidenceExplanationViewModel {
    private(set) var refinementSnapshot:
        IdentificationReviewRefinementSnapshot?
    let candidateReview: CandidateReviewViewModel

    private let dependencies: ConfidenceReviewDependencies
    private var loadGeneration = 0

    init(dependencies: ConfidenceReviewDependencies) {
        self.dependencies = dependencies
        self.candidateReview = CandidateReviewViewModel(
            dependencies: dependencies.candidate
        )
    }

    var feedback: IdentificationReviewFeedbackDependencies {
        dependencies.candidate.feedback
    }

    var candidateDependencies: CandidateReviewDependencies {
        dependencies.candidate
    }

    func loadRefinementSnapshot(
        subject: IdentificationReviewSubject,
        modelContainer: ModelContainer
    ) async {
        loadGeneration += 1
        let generation = loadGeneration
        refinementSnapshot = nil

        let snapshot = await dependencies.loadRefinementSnapshot(
            subject.scanId,
            modelContainer
        )
        guard !Task.isCancelled,
              loadGeneration == generation,
              snapshot?.scanId.caseInsensitiveCompare(subject.scanId) ==
                .orderedSame else {
            return
        }
        refinementSnapshot = snapshot
    }

    func invalidate() {
        loadGeneration += 1
        refinementSnapshot = nil
        candidateReview.invalidateSwipeModal()
    }

    func openSettings() {
        dependencies.openSettings()
    }
}
