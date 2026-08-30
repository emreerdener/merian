import XCTest

@testable import Merian

@MainActor
final class ExportScansViewModelTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

    func testSuccessfulRequestRequiresExplicitPresentationTransition() async {
        var requestCount = 0
        let viewModel = ExportScansViewModel(
            dependencies: SettingsExportDependencies(
                requestPersonalExport: { requestCount += 1 },
                logUnexpectedFailure: { _ in }
            )
        )

        let didRequest = await viewModel.requestExport()
        XCTAssertTrue(didRequest)
        XCTAssertEqual(requestCount, 1)
        XCTAssertFalse(viewModel.hasRequestedExport)

        viewModel.presentSuccessfulRequest()

        XCTAssertTrue(viewModel.hasRequestedExport)
    }

    func testRateLimitPreservesTwentyFourHourCopy() async {
        let viewModel = ExportScansViewModel(
            dependencies: SettingsExportDependencies(
                requestPersonalExport: {
                    throw MerianError.httpError(
                        statusCode: 429,
                        message: "rate_limited"
                    )
                },
                logUnexpectedFailure: { _ in }
            )
        )

        let didRequest = await viewModel.requestExport()
        XCTAssertFalse(didRequest)
        XCTAssertEqual(
            viewModel.errorMessage,
            "You can only generate one Darwin Core Archive every 24 hours. Your most recent export was already emailed to you."
        )
    }

    func testUnexpectedFailureIsLoggedAndUsesGenericCopy() async {
        var loggedFailureCount = 0
        let viewModel = ExportScansViewModel(
            dependencies: SettingsExportDependencies(
                requestPersonalExport: { throw StubError.failed },
                logUnexpectedFailure: { _ in loggedFailureCount += 1 }
            )
        )

        let didRequest = await viewModel.requestExport()
        XCTAssertFalse(didRequest)
        XCTAssertEqual(loggedFailureCount, 1)
        XCTAssertEqual(
            viewModel.errorMessage,
            "An unexpected error occurred."
        )
    }

    func testRequestIsSingleFlight() async {
        var pendingRequest: CheckedContinuation<Void, any Error>?
        var requestCount = 0
        let viewModel = ExportScansViewModel(
            dependencies: SettingsExportDependencies(
                requestPersonalExport: {
                    requestCount += 1
                    try await withCheckedThrowingContinuation {
                        pendingRequest = $0
                    }
                },
                logUnexpectedFailure: { _ in }
            )
        )

        let firstTask = Task { await viewModel.requestExport() }
        while pendingRequest == nil {
            await Task.yield()
        }

        XCTAssertTrue(viewModel.isRequesting)
        let overlappingResult = await viewModel.requestExport()
        XCTAssertFalse(overlappingResult)
        XCTAssertEqual(requestCount, 1)

        pendingRequest?.resume(returning: ())
        let firstResult = await firstTask.value
        XCTAssertTrue(firstResult)
        XCTAssertFalse(viewModel.isRequesting)
    }
}
