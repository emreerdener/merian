import Observation

@MainActor
@Observable
final class ConfidencePresentationViewModel {
    private(set) var isExplanationPresented = false
    private(set) var explanationSubject: IdentificationReviewSubject?
    private(set) var pendingDismissalAction:
        ConfidenceExplanationDismissalAction?

    private let dependencies: ConfidenceReviewDependencies

    init(dependencies: ConfidenceReviewDependencies) {
        self.dependencies = dependencies
    }

    var childDependencies: ConfidenceReviewDependencies {
        dependencies
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

    func presentExplanation(
        subject: IdentificationReviewSubject,
        in inferenceEngine: InferenceEngine
    ) -> Bool {
        guard isCurrent(subject, in: inferenceEngine) else { return false }
        dependencies.candidate.feedback.heavyImpact(1.0)
        pendingDismissalAction = nil
        explanationSubject = subject
        isExplanationPresented = true
        return true
    }

    func stageDismissalAction(_ action: ConfidenceExplanationDismissalAction) {
        guard action.context.subject.matches(explanationSubject) else { return }
        pendingDismissalAction = action
    }

    func dismissExplanation(ownedBy subject: IdentificationReviewSubject) {
        guard subject.matches(explanationSubject) else { return }
        isExplanationPresented = false
        explanationSubject = nil
    }

    func invalidateExplanation() {
        isExplanationPresented = false
        explanationSubject = nil
        pendingDismissalAction = nil
    }

    func takePendingDismissalAction(
        matching subject: IdentificationReviewSubject
    ) -> ConfidenceExplanationDismissalAction? {
        guard !isExplanationPresented,
              let action = pendingDismissalAction else { return nil }
        pendingDismissalAction = nil
        return action.context.subject.matches(subject) ? action : nil
    }

    func requestRefinementRoute(
        scanId: String,
        initialDescription: String?
    ) {
        dependencies.candidate.feedback.selection()
        dependencies.requestRefinementRoute(scanId, initialDescription)
    }
}
