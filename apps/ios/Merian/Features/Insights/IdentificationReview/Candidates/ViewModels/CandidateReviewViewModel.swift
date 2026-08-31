import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CandidateReviewViewModel {
    private(set) var isSwipeModalPresented = false
    private(set) var swipeModalSubject: IdentificationReviewSubject?
    private(set) var pendingDismissalRequest: CandidateSwipeDismissalRequest?
    private(set) var dismissedScanId: String?

    private let dependencies: CandidateReviewDependencies

    init(dependencies: CandidateReviewDependencies) {
        self.dependencies = dependencies
    }

    var feedback: IdentificationReviewFeedbackDependencies {
        dependencies.feedback
    }

    var imageDependencies: SimilarSpeciesImageDependencies {
        dependencies.imageDependencies
    }

    var childDependencies: CandidateReviewDependencies {
        dependencies
    }

    var isProActive: Bool {
        dependencies.isProActive()
    }

    func isCurrent(
        _ subject: IdentificationReviewSubject,
        in inferenceEngine: InferenceEngine
    ) -> Bool {
        subject.matches(
            scanId: inferenceEngine.speciesData?.scanId,
            presentationGeneration: inferenceEngine.scanPresentationGeneration
        )
    }

    func shouldHideCard(scanId: String?) -> Bool {
        guard let scanId, let dismissedScanId else { return false }
        return dismissedScanId.caseInsensitiveCompare(scanId) == .orderedSame
    }

    func dismissCard(subject: IdentificationReviewSubject) {
        dismissedScanId = subject.scanId
    }

    func presentSwipeModal(subject: IdentificationReviewSubject) {
        pendingDismissalRequest = nil
        swipeModalSubject = subject
        isSwipeModalPresented = true
    }

    func stageDismissalRequest(_ request: CandidateSwipeDismissalRequest) {
        guard request.subject.matches(swipeModalSubject) else { return }
        pendingDismissalRequest = request
    }

    func dismissSwipeModal(ownedBy subject: IdentificationReviewSubject) {
        guard subject.matches(swipeModalSubject) else { return }
        isSwipeModalPresented = false
        swipeModalSubject = nil
    }

    func invalidateSwipeModal() {
        isSwipeModalPresented = false
        swipeModalSubject = nil
        pendingDismissalRequest = nil
    }

    func takePendingDismissalRequest(
        matching subject: IdentificationReviewSubject
    ) -> CandidateSwipeDismissalRequest? {
        guard !isSwipeModalPresented,
              let request = pendingDismissalRequest else { return nil }
        pendingDismissalRequest = nil
        return request.subject.matches(subject) ? request : nil
    }

    func confirmOriginal(
        subject: IdentificationReviewSubject,
        inferenceEngine: InferenceEngine,
        modelContext: ModelContext
    ) async -> Bool {
        guard isCurrent(subject, in: inferenceEngine) else { return false }
        await dependencies.confirmOriginal(
            inferenceEngine,
            subject.scanId,
            modelContext
        )
        return isCurrent(subject, in: inferenceEngine)
    }

    func applyOverride(
        scientificName: String,
        subject: IdentificationReviewSubject,
        inferenceEngine: InferenceEngine,
        modelContext: ModelContext
    ) async {
        guard isCurrent(subject, in: inferenceEngine) else { return }
        await dependencies.applyOverride(
            inferenceEngine,
            scientificName,
            subject.scanId,
            modelContext
        )
    }

    func resetReview(
        subject: IdentificationReviewSubject,
        inferenceEngine: InferenceEngine,
        modelContext: ModelContext
    ) async {
        guard isCurrent(subject, in: inferenceEngine) else { return }
        await dependencies.resetReview(
            inferenceEngine,
            subject.scanId,
            modelContext
        )
    }

    func markAlternativesExhausted(
        subject: IdentificationReviewSubject,
        inferenceEngine: InferenceEngine
    ) {
        guard isCurrent(subject, in: inferenceEngine) else { return }
        dependencies.markAlternativesExhausted(
            inferenceEngine,
            subject.scanId
        )
    }
}
