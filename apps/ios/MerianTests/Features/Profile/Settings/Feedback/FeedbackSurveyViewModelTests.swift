import XCTest

@testable import Merian

@MainActor
final class FeedbackSurveyViewModelTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

    func testRequiredRatingsFenceQuestionProgression() {
        let viewModel = FeedbackSurveyViewModel(
            dependencies: makeDependencies()
        )

        XCTAssertFalse(viewModel.shouldSubmitAfterAdvancing(from: 0))
        XCTAssertEqual(viewModel.step, .intro)
        XCTAssertEqual(
            viewModel.validationMessage,
            "Choose an overall satisfaction rating before continuing."
        )

        viewModel.satisfactionRating = 5
        XCTAssertFalse(viewModel.shouldSubmitAfterAdvancing(from: 0))
        XCTAssertEqual(viewModel.step, .question(1))
        XCTAssertNil(viewModel.validationMessage)

        XCTAssertFalse(viewModel.shouldSubmitAfterAdvancing(from: 1))
        XCTAssertEqual(
            viewModel.validationMessage,
            "Choose the recommendation option that feels closest."
        )
    }

    func testNotSureSelectionRemainsExclusive() {
        let viewModel = FeedbackSurveyViewModel(
            dependencies: makeDependencies()
        )

        viewModel.toggleMostUsefulFeature(.cameraIdentification)
        viewModel.toggleMostUsefulFeature(.insightSheet)
        XCTAssertEqual(
            viewModel.mostUsefulFeatures,
            [.cameraIdentification, .insightSheet]
        )

        viewModel.toggleMostUsefulFeature(.notSureYet)
        XCTAssertEqual(viewModel.mostUsefulFeatures, [.notSureYet])

        viewModel.toggleMostUsefulFeature(.explore)
        XCTAssertEqual(viewModel.mostUsefulFeatures, [.explore])
    }

    func testSubmissionMapsStableCaseOrderAndReturnsInjectedDate() async {
        let submittedAt = Date(timeIntervalSince1970: 1_234)
        var capturedSubmission: FeedbackSurveySubmission?
        let viewModel = FeedbackSurveyViewModel(
            dependencies: makeDependencies(
                submit: { capturedSubmission = $0 },
                now: { submittedAt }
            )
        )
        viewModel.satisfactionRating = 4
        viewModel.recommendationRating = 7
        viewModel.usedFeatures = [.browseExplore, .identifyFoundSubject]
        viewModel.mostUsefulFeatures = [.insightSheet, .cameraIdentification]
        viewModel.confusingOrDisappointing = "  Slow map.  "
        viewModel.wishedNext = "  More notes.\n"
        viewModel.bugStatus = .workaround
        viewModel.bugDetails = "  Reopened the app.  "

        let result = await viewModel.submit()
        let submission = try? XCTUnwrap(capturedSubmission)

        XCTAssertEqual(result, submittedAt)
        XCTAssertEqual(submission?.satisfactionRating, 4)
        XCTAssertEqual(submission?.recommendationRating, 7)
        XCTAssertEqual(
            submission?.usedFeatures,
            [.identifyFoundSubject, .browseExplore]
        )
        XCTAssertEqual(
            submission?.mostUsefulFeatures,
            [.cameraIdentification, .insightSheet]
        )
        XCTAssertEqual(submission?.confusingOrDisappointing, "Slow map.")
        XCTAssertEqual(submission?.wishedNext, "More notes.")
        XCTAssertEqual(submission?.bugDetails, "Reopened the app.")
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertNil(viewModel.submissionErrorMessage)
    }

    func testSubmissionFailureRestoresInteractionState() async {
        let viewModel = FeedbackSurveyViewModel(
            dependencies: makeDependencies(
                submit: { _ in throw StubError.failed }
            )
        )
        viewModel.satisfactionRating = 3
        viewModel.recommendationRating = 4

        let submittedAt = await viewModel.submit()
        XCTAssertNil(submittedAt)
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertEqual(
            viewModel.submissionErrorMessage,
            "Naturebook could not send your feedback. Please check your connection and try again."
        )
    }

    func testOverlappingSubmissionIsSingleFlight() async {
        var pendingSubmission: CheckedContinuation<Void, any Error>?
        var callCount = 0
        let viewModel = FeedbackSurveyViewModel(
            dependencies: makeDependencies(
                submit: { _ in
                    callCount += 1
                    try await withCheckedThrowingContinuation {
                        pendingSubmission = $0
                    }
                }
            )
        )
        viewModel.satisfactionRating = 5
        viewModel.recommendationRating = 10

        let firstTask = Task { await viewModel.submit() }
        while pendingSubmission == nil {
            await Task.yield()
        }

        let overlappingResult = await viewModel.submit()
        XCTAssertNil(overlappingResult)
        XCTAssertEqual(callCount, 1)

        pendingSubmission?.resume(returning: ())
        let firstResult = await firstTask.value
        XCTAssertNotNil(firstResult)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testExpiredSuccessStateResetsAllDraftFields() {
        let viewModel = FeedbackSurveyViewModel(
            dependencies: makeDependencies()
        )
        viewModel.satisfactionRating = 5
        viewModel.usedFeatures = [.other]
        viewModel.presentSuccess()

        viewModel.prepare(isSubmittedStateActive: false)

        XCTAssertEqual(viewModel.step, .intro)
        XCTAssertNil(viewModel.satisfactionRating)
        XCTAssertTrue(viewModel.usedFeatures.isEmpty)
    }

    private func makeDependencies(
        submit: @escaping @MainActor (
            FeedbackSurveySubmission
        ) async throws -> Void = { _ in },
        now: @escaping @MainActor () -> Date = Date.init
    ) -> FeedbackSurveyDependencies {
        FeedbackSurveyDependencies(submit: submit, now: now)
    }
}
