import Foundation
import Observation

@MainActor
@Observable
final class FeedbackSurveyViewModel {
    var step: FeedbackSurveyStep = .intro
    var satisfactionRating: Int?
    var recommendationRating: Int?
    var usedFeatures: Set<FeedbackSurveyFeatureUse> = []
    var mostUsefulFeatures: Set<FeedbackSurveyUsefulFeature> = []
    var confusingOrDisappointing = ""
    var wishedNext = ""
    var bugStatus: FeedbackSurveyBugStatus = .no
    var bugDetails = ""
    private(set) var validationMessage: String?
    var submissionErrorMessage: String?
    private(set) var isSubmitting = false

    private let dependencies: FeedbackSurveyDependencies

    init(dependencies: FeedbackSurveyDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    var navigationTitle: String {
        switch step {
        case .intro:
            "Feedback"
        case .question(let index):
            "\(index + 1) of \(FeedbackSurveyPresentation.questionCount)"
        case .success:
            "Thank you"
        }
    }

    func prepare(isSubmittedStateActive: Bool) {
        if isSubmittedStateActive {
            step = .success
        } else if step == .success {
            reset()
        }
    }

    func begin() {
        step = .question(0)
    }

    func goToQuestion(_ index: Int) {
        validationMessage = nil
        step = .question(
            max(0, min(index, FeedbackSurveyPresentation.questionCount - 1))
        )
    }

    func shouldSubmitAfterAdvancing(from index: Int) -> Bool {
        guard validateQuestion(index) else { return false }
        guard index == FeedbackSurveyPresentation.questionCount - 1 else {
            goToQuestion(index + 1)
            return false
        }
        return true
    }

    func toggleFeature(_ feature: FeedbackSurveyFeatureUse) {
        if usedFeatures.contains(feature) {
            usedFeatures.remove(feature)
        } else {
            usedFeatures.insert(feature)
        }
    }

    func toggleMostUsefulFeature(_ feature: FeedbackSurveyUsefulFeature) {
        if mostUsefulFeatures.contains(feature) {
            mostUsefulFeatures.remove(feature)
            return
        }

        if feature == .notSureYet {
            mostUsefulFeatures = [.notSureYet]
        } else {
            mostUsefulFeatures.remove(.notSureYet)
            mostUsefulFeatures.insert(feature)
        }
    }

    func submit() async -> Date? {
        guard !isSubmitting else { return nil }
        guard let submission = makeSubmission() else { return nil }

        isSubmitting = true
        submissionErrorMessage = nil
        defer { isSubmitting = false }

        do {
            try await dependencies.submit(submission)
            return dependencies.now()
        } catch {
            submissionErrorMessage =
                "Naturebook could not send your feedback. Please check your connection and try again."
            return nil
        }
    }

    func presentSuccess() {
        step = .success
    }

    func reset() {
        step = .intro
        satisfactionRating = nil
        recommendationRating = nil
        usedFeatures = []
        mostUsefulFeatures = []
        confusingOrDisappointing = ""
        wishedNext = ""
        bugStatus = .no
        bugDetails = ""
        validationMessage = nil
        submissionErrorMessage = nil
        isSubmitting = false
    }

    private func validateQuestion(_ index: Int) -> Bool {
        switch index {
        case 0 where satisfactionRating == nil:
            validationMessage =
                "Choose an overall satisfaction rating before continuing."
            return false
        case 1 where recommendationRating == nil:
            validationMessage =
                "Choose the recommendation option that feels closest."
            return false
        default:
            validationMessage = nil
            return true
        }
    }

    private func makeSubmission() -> FeedbackSurveySubmission? {
        guard let satisfactionRating else {
            step = .question(0)
            validationMessage =
                "Choose an overall satisfaction rating before continuing."
            return nil
        }
        guard let recommendationRating else {
            step = .question(1)
            validationMessage =
                "Choose the recommendation option that feels closest."
            return nil
        }

        return FeedbackSurveySubmission(
            satisfactionRating: satisfactionRating,
            recommendationRating: recommendationRating,
            usedFeatures: FeedbackSurveyFeatureUse.allCases.filter {
                usedFeatures.contains($0)
            },
            mostUsefulFeatures: FeedbackSurveyUsefulFeature.allCases.filter {
                mostUsefulFeatures.contains($0)
            },
            confusingOrDisappointing: confusingOrDisappointing,
            wishedNext: wishedNext,
            bugStatus: bugStatus,
            bugDetails: bugDetails,
            mayFollowUp: false,
            contact: ""
        )
    }
}
