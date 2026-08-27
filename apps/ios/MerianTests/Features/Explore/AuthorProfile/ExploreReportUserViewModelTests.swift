import XCTest

@testable import Merian

@MainActor
final class ExploreReportUserViewModelTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

    func testDetailsAreCappedAndSuccessfulSubmissionUsesTypedValues() async {
        var reportedUserId: String?
        var reportedReason: ExploreUserReportReason?
        var reportedDetails: String?
        var successFeedbackCount = 0
        let viewModel = ExploreReportUserViewModel(dependencies: .init(
            reportUser: { userId, reason, details in
                reportedUserId = userId
                reportedReason = reason
                reportedDetails = details
            },
            successFeedback: { successFeedbackCount += 1 },
            errorFeedback: {},
            errorMessage: { _ in "stub error" }
        ))
        viewModel.reason = .impersonation
        viewModel.updateDetails(String(repeating: "a", count: 1_005))

        let succeeded = await viewModel.submit(reportedUserId: "author-1")

        XCTAssertTrue(succeeded)
        XCTAssertEqual(reportedUserId, "author-1")
        XCTAssertEqual(reportedReason, .impersonation)
        XCTAssertEqual(reportedDetails?.count, ExploreReportUserViewModel.detailsLimit)
        XCTAssertEqual(successFeedbackCount, 1)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testSubmissionFailureRetainsFormAndExposesError() async {
        var errorFeedbackCount = 0
        let viewModel = ExploreReportUserViewModel(dependencies: .init(
            reportUser: { _, _, _ in throw StubError.failed },
            successFeedback: {},
            errorFeedback: { errorFeedbackCount += 1 },
            errorMessage: { _ in "Report failed" }
        ))
        viewModel.reason = .harassment
        viewModel.updateDetails("context")

        let succeeded = await viewModel.submit(reportedUserId: "author-1")

        XCTAssertFalse(succeeded)
        XCTAssertEqual(viewModel.reason, .harassment)
        XCTAssertEqual(viewModel.details, "context")
        XCTAssertEqual(viewModel.errorMessage, "Report failed")
        XCTAssertEqual(errorFeedbackCount, 1)
        XCTAssertFalse(viewModel.isSubmitting)
    }
}
