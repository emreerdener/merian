import RevenueCat
import XCTest

@testable import Merian

@MainActor
final class PlanViewModelTests: XCTestCase {
    private struct StubError: LocalizedError {
        var errorDescription: String? { "Stub purchase failure" }
    }

    func testComplimentaryPlanDetailsAreLimitedToResultsAndSettings() {
        XCTAssertFalse(ComplimentaryPlanDetailContext.hidden.showsDetails)
        XCTAssertTrue(ComplimentaryPlanDetailContext.results.showsDetails)
        XCTAssertTrue(ComplimentaryPlanDetailContext.settings.showsDetails)
    }

    func testPaywallRestoreDismissesOnlyForActiveSubscription() async {
        var restoreCount = 0
        var isSubscribed = false
        let viewModel = PaywallViewModel(
            dependencies: makePaywallDependencies(
                restorePurchases: { restoreCount += 1 },
                isSubscribed: { isSubscribed }
            )
        )

        let firstResult = await viewModel.restorePurchases()
        XCTAssertFalse(firstResult)
        isSubscribed = true
        let secondResult = await viewModel.restorePurchases()
        XCTAssertTrue(secondResult)

        XCTAssertEqual(restoreCount, 2)
        XCTAssertFalse(viewModel.isRestoring)
        XCTAssertNil(viewModel.operationErrorMessage)
    }

    func testPaywallRestoreFailureRestoresStateAndReportsProviderMessage() async {
        var logCount = 0
        let viewModel = PaywallViewModel(
            dependencies: makePaywallDependencies(
                restorePurchases: { throw StubError() },
                logRestoreFailure: { _ in logCount += 1 }
            )
        )

        let result = await viewModel.restorePurchases()
        XCTAssertFalse(result)
        XCTAssertFalse(viewModel.isRestoring)
        XCTAssertEqual(logCount, 1)
        XCTAssertEqual(
            viewModel.operationErrorMessage,
            "Stub purchase failure"
        )
    }

    func testPaywallRestoreIsSingleFlight() async {
        var pendingRestore: CheckedContinuation<Void, any Error>?
        var restoreCount = 0
        let viewModel = PaywallViewModel(
            dependencies: makePaywallDependencies(
                restorePurchases: {
                    restoreCount += 1
                    try await withCheckedThrowingContinuation {
                        pendingRestore = $0
                    }
                }
            )
        )

        let firstTask = Task { await viewModel.restorePurchases() }
        while pendingRestore == nil {
            await Task.yield()
        }

        let overlappingResult = await viewModel.restorePurchases()
        XCTAssertFalse(overlappingResult)
        XCTAssertEqual(restoreCount, 1)

        pendingRestore?.resume(returning: ())
        _ = await firstTask.value
        XCTAssertFalse(viewModel.isRestoring)
    }

    func testManagePlanSurfacesRestoreAndRedemptionFailures() async {
        var restoreLogCount = 0
        var redemptionLogCount = 0
        let viewModel = ManagePlanViewModel(
            dependencies: ManagePlanDependencies(
                restorePurchases: { throw StubError() },
                presentCodeRedemption: { throw StubError() },
                logRestoreFailure: { _ in restoreLogCount += 1 },
                logRedemptionFailure: { _ in redemptionLogCount += 1 }
            )
        )

        await viewModel.restorePurchases()
        XCTAssertEqual(restoreLogCount, 1)
        XCTAssertEqual(
            viewModel.operationErrorMessage,
            "Stub purchase failure"
        )

        viewModel.operationErrorMessage = nil
        viewModel.presentCodeRedemption()
        XCTAssertEqual(redemptionLogCount, 1)
        XCTAssertEqual(
            viewModel.operationErrorMessage,
            "Stub purchase failure"
        )
    }

    func testManagePlanBlocksRedemptionDuringRestore() async {
        var pendingRestore: CheckedContinuation<Void, any Error>?
        var redemptionCount = 0
        let viewModel = ManagePlanViewModel(
            dependencies: ManagePlanDependencies(
                restorePurchases: {
                    try await withCheckedThrowingContinuation {
                        pendingRestore = $0
                    }
                },
                presentCodeRedemption: { redemptionCount += 1 },
                logRestoreFailure: { _ in },
                logRedemptionFailure: { _ in }
            )
        )

        let restoreTask = Task {
            await viewModel.restorePurchases()
        }
        while pendingRestore == nil {
            await Task.yield()
        }

        viewModel.presentCodeRedemption()
        XCTAssertEqual(redemptionCount, 0)

        pendingRestore?.resume(returning: ())
        await restoreTask.value
        viewModel.presentCodeRedemption()
        XCTAssertEqual(redemptionCount, 1)
    }

    private func makePaywallDependencies(
        fetchOfferings: @escaping @MainActor () async -> Void = {},
        purchase: @escaping @MainActor (Package) async throws -> Void = {
            _ in
        },
        restorePurchases: @escaping @MainActor () async throws -> Void = {},
        isSubscribed: @escaping @MainActor () -> Bool = { false },
        logPurchaseFailure: @escaping @MainActor (Error) -> Void = { _ in },
        logRestoreFailure: @escaping @MainActor (Error) -> Void = { _ in }
    ) -> PaywallDependencies {
        PaywallDependencies(
            fetchOfferings: fetchOfferings,
            purchase: purchase,
            restorePurchases: restorePurchases,
            isSubscribed: isSubscribed,
            logPurchaseFailure: logPurchaseFailure,
            logRestoreFailure: logRestoreFailure
        )
    }
}
