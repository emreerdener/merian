@testable import Merian
import Testing

@MainActor
@Suite("Community Feedback View Model")
struct CommunityFeedbackViewModelTests {
    @Test func validationRejectsEmptyAndOversizedFeedback() {
        var errorFeedbackCount = 0
        let viewModel = CommunityFeedbackViewModel(
            dependencies: CommunityFeedbackViewModel.Dependencies(
                submit: { _ in },
                successFeedback: {},
                errorFeedback: { errorFeedbackCount += 1 },
                errorMessage: { _ in "expected error" }
            )
        )

        viewModel.feedbackText = "   "
        #expect(!viewModel.prepareSubmission())
        #expect(viewModel.validationError == "Feedback cannot be empty.")

        viewModel.feedbackDidChange()
        viewModel.feedbackText = String(
            repeating: "x",
            count: CommunityFeedbackViewModel.maxCharacterLimit + 1
        )
        #expect(!viewModel.prepareSubmission())
        #expect(
            viewModel.validationError
                == "Feedback is too long (maximum 4000 characters)."
        )
        #expect(errorFeedbackCount == 2)
        #expect(!viewModel.isSubmitting)
    }

    @Test func submissionTrimsFeedbackAndReportsSuccess() async {
        var submittedFeedback: [String] = []
        var successFeedbackCount = 0
        var observedSubmittingDuringFeedback: Bool?
        var subject: CommunityFeedbackViewModel?
        let viewModel = CommunityFeedbackViewModel(
            dependencies: CommunityFeedbackViewModel.Dependencies(
                submit: { submittedFeedback.append($0) },
                successFeedback: {
                    successFeedbackCount += 1
                    observedSubmittingDuringFeedback = subject?.isSubmitting
                },
                errorFeedback: {},
                errorMessage: { _ in "expected error" }
            )
        )
        subject = viewModel

        viewModel.feedbackText = "  More visible filter state, please.  "
        #expect(viewModel.prepareSubmission())
        viewModel.beginSubmission()
        #expect(viewModel.isSubmitting)

        let didSubmit = await viewModel.submitPreparedFeedback()
        viewModel.showSubmissionSuccess()

        #expect(didSubmit)
        #expect(submittedFeedback == ["More visible filter state, please."])
        #expect(successFeedbackCount == 1)
        #expect(observedSubmittingDuringFeedback == false)
        #expect(!viewModel.isSubmitting)
        #expect(viewModel.showSuccess)
    }

    @Test func failedSubmissionSurfacesFormattedError() async {
        var errorFeedbackCount = 0
        var observedSubmittingDuringFeedback: Bool?
        var subject: CommunityFeedbackViewModel?
        let viewModel = CommunityFeedbackViewModel(
            dependencies: CommunityFeedbackViewModel.Dependencies(
                submit: { _ in throw CommunityIdentificationTestError.expected },
                successFeedback: {},
                errorFeedback: {
                    errorFeedbackCount += 1
                    observedSubmittingDuringFeedback = subject?.isSubmitting
                },
                errorMessage: { _ in "submission failed" }
            )
        )
        subject = viewModel

        viewModel.feedbackText = "Useful feedback"
        #expect(viewModel.prepareSubmission())
        viewModel.beginSubmission()
        let didSubmit = await viewModel.submitPreparedFeedback()

        #expect(!didSubmit)
        #expect(viewModel.errorMessage == "submission failed")
        #expect(errorFeedbackCount == 1)
        #expect(observedSubmittingDuringFeedback == false)
        #expect(!viewModel.isSubmitting)
        #expect(!viewModel.showSuccess)
    }
}
