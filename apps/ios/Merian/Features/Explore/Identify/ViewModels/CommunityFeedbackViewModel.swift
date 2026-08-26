import Foundation
import Observation

@MainActor
@Observable
final class CommunityFeedbackViewModel {
    static let maxCharacterLimit = 4000

    struct Dependencies {
        let submit: @MainActor (String) async throws -> Void
        let successFeedback: @MainActor () -> Void
        let errorFeedback: @MainActor () -> Void
        let errorMessage: @MainActor (Error) -> String
    }

    var feedbackText = ""
    var isSubmitting = false
    var showSuccess = false
    var errorMessage: String?
    var validationError: String?

    private let dependencies: Dependencies
    private var preparedFeedback: String?

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func feedbackDidChange() {
        validationError = nil
    }

    func prepareSubmission() -> Bool {
        let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            validationError = "Feedback cannot be empty."
            dependencies.errorFeedback()
            return false
        }
        if feedbackText.count > Self.maxCharacterLimit {
            validationError = "Feedback is too long (maximum \(Self.maxCharacterLimit) characters)."
            dependencies.errorFeedback()
            return false
        }

        validationError = nil
        preparedFeedback = trimmed
        return true
    }

    func beginSubmission() {
        isSubmitting = true
        errorMessage = nil
    }

    func submitPreparedFeedback() async -> Bool {
        guard let preparedFeedback else { return false }

        do {
            try await dependencies.submit(preparedFeedback)
            isSubmitting = false
            self.preparedFeedback = nil
            dependencies.successFeedback()
            return true
        } catch {
            isSubmitting = false
            self.preparedFeedback = nil
            dependencies.errorFeedback()
            errorMessage = dependencies.errorMessage(error)
            return false
        }
    }

    func showSubmissionSuccess() {
        showSuccess = true
    }
}
