import SwiftData
import XCTest

@testable import Merian

@MainActor
final class AchievementDetailViewModelTests: XCTestCase {
    private var modelContainer: ModelContainer!

    override func setUpWithError() throws {
        modelContainer = try ModelContainer(
            for: Schema([LocalScanRecord.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    override func tearDownWithError() throws {
        modelContainer = nil
    }

    func testForegroundLoadPublishesDetailAndTracksResolvedState() async {
        let fallback = award(type: .fungi, currentCount: 0)
        let resolved = award(type: .fungi, currentCount: 10)
        var trackedType: String?
        var trackedState: String?
        let viewModel = AchievementDetailViewModel(
            dependencies: makeDependencies(
                loadDetail: { _, _ in
                    AchievementDetailPayload(
                        award: resolved,
                        contributions: []
                    )
                },
                trackDetailOpened: { type, state in
                    trackedType = type
                    trackedState = state
                }
            )
        )

        let announced = await viewModel.load(
            award: fallback,
            modelContainer: modelContainer
        )

        XCTAssertEqual(announced, resolved)
        XCTAssertEqual(viewModel.resolvedAward(fallback: fallback), resolved)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(trackedType, AchievementType.fungi.rawValue)
        XCTAssertEqual(trackedState, "completed")
    }

    func testBackgroundReloadUpdatesDetailWithoutForegroundTelemetry() async {
        let fallback = award(type: .fungi, currentCount: 0)
        let resolved = award(type: .fungi, currentCount: 3)
        var telemetryCount = 0
        let viewModel = AchievementDetailViewModel(
            dependencies: makeDependencies(
                loadDetail: { _, _ in
                    AchievementDetailPayload(
                        award: resolved,
                        contributions: []
                    )
                },
                trackDetailOpened: { _, _ in telemetryCount += 1 }
            )
        )

        let announced = await viewModel.load(
            award: fallback,
            modelContainer: modelContainer,
            backgroundReload: true
        )

        XCTAssertNil(announced)
        XCTAssertEqual(viewModel.resolvedAward(fallback: fallback), resolved)
        XCTAssertEqual(telemetryCount, 0)
    }

    func testLateLoadCannotOverwriteNewerAchievement() async {
        let stale = award(type: .fungi, currentCount: 2)
        let current = award(type: .urban, currentCount: 4)
        var pendingFirstLoad:
            CheckedContinuation<AchievementDetailPayload?, Never>?
        let viewModel = AchievementDetailViewModel(
            dependencies: makeDependencies(
                loadDetail: { type, _ in
                    if type == .fungi {
                        return await withCheckedContinuation {
                            pendingFirstLoad = $0
                        }
                    }
                    return AchievementDetailPayload(
                        award: current,
                        contributions: []
                    )
                }
            )
        )

        let firstTask = Task {
            await viewModel.load(
                award: stale,
                modelContainer: modelContainer
            )
        }
        while pendingFirstLoad == nil {
            await Task.yield()
        }

        _ = await viewModel.load(
            award: current,
            modelContainer: modelContainer
        )
        pendingFirstLoad?.resume(
            returning: AchievementDetailPayload(
                award: stale,
                contributions: []
            )
        )
        _ = await firstTask.value

        XCTAssertEqual(viewModel.resolvedAward(fallback: stale), current)
    }

    func testCanceledForegroundLoadClearsLoadingState() async {
        let fallback = award(type: .fungi, currentCount: 0)
        var didStart = false
        let viewModel = AchievementDetailViewModel(
            dependencies: makeDependencies(
                loadDetail: { _, _ in
                    didStart = true
                    do {
                        try await Task.sleep(nanoseconds: 60_000_000_000)
                    } catch {
                        return nil
                    }
                    return nil
                }
            )
        )

        let loadTask = Task {
            await viewModel.load(
                award: fallback,
                modelContainer: modelContainer
            )
        }
        while !didStart {
            await Task.yield()
        }
        loadTask.cancel()
        _ = await loadTask.value

        XCTAssertFalse(viewModel.isLoading)
    }

    func testBackgroundReloadSupersedingForegroundLoadClearsLoadingState() async {
        let fallback = award(type: .fungi, currentCount: 0)
        let refreshed = award(type: .fungi, currentCount: 4)
        var callCount = 0
        var pendingForegroundLoad:
            CheckedContinuation<AchievementDetailPayload?, Never>?
        let viewModel = AchievementDetailViewModel(
            dependencies: makeDependencies(
                loadDetail: { _, _ in
                    callCount += 1
                    if callCount == 1 {
                        return await withCheckedContinuation {
                            pendingForegroundLoad = $0
                        }
                    }
                    return AchievementDetailPayload(
                        award: refreshed,
                        contributions: []
                    )
                }
            )
        )

        let foregroundTask = Task {
            await viewModel.load(
                award: fallback,
                modelContainer: modelContainer
            )
        }
        while pendingForegroundLoad == nil {
            await Task.yield()
        }

        _ = await viewModel.load(
            award: fallback,
            modelContainer: modelContainer,
            backgroundReload: true
        )

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.resolvedAward(fallback: fallback), refreshed)

        pendingForegroundLoad?.resume(returning: nil)
        _ = await foregroundTask.value
        XCTAssertFalse(viewModel.isLoading)
    }

    private func makeDependencies(
        loadDetail: @escaping @MainActor (
            AchievementType,
            ModelContainer
        ) async -> AchievementDetailPayload?,
        trackDetailOpened: @escaping @MainActor (
            String,
            String
        ) -> Void = { _, _ in }
    ) -> AchievementDetailDependencies {
        AchievementDetailDependencies(
            loadDetail: loadDetail,
            openGoalDestination: { _ in },
            resolveScanRoute: { _, _ in nil },
            selectionFeedback: {},
            errorFeedback: {},
            trackDetailOpened: trackDetailOpened,
            trackContributionOpened: { _ in }
        )
    }

    private func award(
        type: AchievementType,
        currentCount: Int
    ) -> AwardPayload {
        AwardPayload(
            type: type,
            currentCount: currentCount,
            lastInteractionDate: nil
        )
    }
}
