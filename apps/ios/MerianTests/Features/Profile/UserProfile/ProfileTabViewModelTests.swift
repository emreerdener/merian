import Combine
import SwiftData
import XCTest

@testable import Merian

@MainActor
final class ProfileTabViewModelTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

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

    func testSignedOutRefreshPublishesLocalStatsWithoutCallingRemote() async {
        var remoteCallCount = 0
        let viewModel = ProfileTabViewModel(
            dependencies: makeDependencies(
                refreshFieldTripProgress: {
                    remoteCallCount += 1
                    throw StubError.failed
                }
            )
        )
        let key = viewModel.refreshKey(
            isAuthenticated: false,
            accountID: nil
        )

        await viewModel.refresh(
            key: key,
            modelContainer: modelContainer,
            fieldTripsEnabled: true
        )

        XCTAssertEqual(remoteCallCount, 0)
        XCTAssertEqual(viewModel.uniqueSpeciesCount, 12)
        XCTAssertEqual(viewModel.currentStreak, 3)
        XCTAssertEqual(viewModel.totalCaptures, 21)
        XCTAssertEqual(viewModel.awards.map(\.type), [.explorer])
    }

    func testAuthenticatedRefreshUsesCacheThenSavesRemoteProgress() async {
        let cached = progress(slug: "cached")
        let refreshed = progress(slug: "refreshed")
        var loadedAccountID: String?
        var savedProgress: FirstFieldTripAchievementProgress?
        var savedAccountID: String?
        let viewModel = ProfileTabViewModel(
            dependencies: makeDependencies(
                loadCachedFieldTripProgress: { accountID in
                    loadedAccountID = accountID
                    return cached
                },
                refreshFieldTripProgress: { refreshed },
                saveFieldTripProgress: { progress, accountID in
                    savedProgress = progress
                    savedAccountID = accountID
                }
            )
        )
        let key = viewModel.refreshKey(
            isAuthenticated: true,
            accountID: "account-1"
        )

        await viewModel.refresh(
            key: key,
            modelContainer: modelContainer,
            fieldTripsEnabled: true
        )

        XCTAssertEqual(loadedAccountID, "account-1")
        XCTAssertEqual(savedProgress, refreshed)
        XCTAssertEqual(savedAccountID, "account-1")
        XCTAssertEqual(
            viewModel.awards.first { $0.type == .firstFieldTrip }?.destination,
            .fieldTripTemplate(slug: "refreshed")
        )
    }

    func testRemoteFailureKeepsCachedAchievementProgress() async {
        let cached = progress(slug: "cached")
        var loggedErrorCount = 0
        let viewModel = ProfileTabViewModel(
            dependencies: makeDependencies(
                loadCachedFieldTripProgress: { _ in cached },
                refreshFieldTripProgress: { throw StubError.failed },
                logProgressRefreshFailure: { _ in loggedErrorCount += 1 }
            )
        )
        let key = viewModel.refreshKey(
            isAuthenticated: true,
            accountID: "account-1"
        )

        await viewModel.refresh(
            key: key,
            modelContainer: modelContainer,
            fieldTripsEnabled: true
        )

        XCTAssertEqual(loggedErrorCount, 1)
        XCTAssertEqual(
            viewModel.awards.first { $0.type == .firstFieldTrip }?.destination,
            .fieldTripTemplate(slug: "cached")
        )
    }

    func testLateRemoteProgressCannotOverwriteNewAccount() async {
        let stale = progress(slug: "stale")
        let current = progress(slug: "current")
        var remoteCallCount = 0
        var pendingFirstRefresh:
            CheckedContinuation<FirstFieldTripAchievementProgress?, any Error>?
        var savedAccountIDs: [String] = []
        let viewModel = ProfileTabViewModel(
            dependencies: makeDependencies(
                refreshFieldTripProgress: {
                    remoteCallCount += 1
                    if remoteCallCount == 1 {
                        return try await withCheckedThrowingContinuation {
                            pendingFirstRefresh = $0
                        }
                    }
                    return current
                },
                saveFieldTripProgress: { _, accountID in
                    savedAccountIDs.append(accountID)
                }
            )
        )
        let firstKey = viewModel.refreshKey(
            isAuthenticated: true,
            accountID: "account-1"
        )
        let firstTask = Task {
            await viewModel.refresh(
                key: firstKey,
                modelContainer: modelContainer,
                fieldTripsEnabled: true
            )
        }
        while pendingFirstRefresh == nil {
            await Task.yield()
        }

        let secondKey = viewModel.refreshKey(
            isAuthenticated: true,
            accountID: "account-2"
        )
        await viewModel.refresh(
            key: secondKey,
            modelContainer: modelContainer,
            fieldTripsEnabled: true
        )
        pendingFirstRefresh?.resume(returning: stale)
        await firstTask.value

        XCTAssertEqual(savedAccountIDs, ["account-2"])
        XCTAssertEqual(
            viewModel.awards.first { $0.type == .firstFieldTrip }?.destination,
            .fieldTripTemplate(slug: "current")
        )
    }

    func testRefreshKeyChangesForRelevantEventsOnly() {
        let viewModel = ProfileTabViewModel(
            dependencies: makeDependencies()
        )
        let initial = viewModel.refreshKey(
            isAuthenticated: false,
            accountID: nil
        )
        let fieldTripEvents: [AppEvent] = [
            .fieldTripProgressInvalidated(templateIds: []),
            .fieldTripChallengeProgressInvalidated(challengeIds: []),
            .captureGoalContextInvalidated(source: .fieldTrip),
        ]

        for event in fieldTripEvents {
            viewModel.handle(event: event, fieldTripsEnabled: false)
            XCTAssertEqual(
                viewModel.refreshKey(isAuthenticated: false, accountID: nil),
                initial
            )
        }

        viewModel.handle(
            event: .scanLibraryChanged,
            fieldTripsEnabled: false
        )
        XCTAssertNotEqual(
            viewModel.refreshKey(isAuthenticated: false, accountID: nil),
            initial
        )

        var previous = viewModel.refreshKey(
            isAuthenticated: false,
            accountID: nil
        )
        for event in fieldTripEvents {
            viewModel.handle(event: event, fieldTripsEnabled: true)
            let current = viewModel.refreshKey(
                isAuthenticated: false,
                accountID: nil
            )
            XCTAssertNotEqual(current, previous)
            previous = current
        }
    }

    func testRefreshKeyDistinguishesAuthenticationRestoration() {
        let refreshToken = UUID()
        let signedOut = ProfileStatsRefreshKey(
            refreshToken: refreshToken,
            isAuthenticated: false,
            accountId: nil
        )
        let restored = ProfileStatsRefreshKey(
            refreshToken: refreshToken,
            isAuthenticated: true,
            accountId: "account-1"
        )

        XCTAssertNotEqual(signedOut, restored)
    }

    private func makeDependencies(
        loadCachedFieldTripProgress: @escaping @MainActor (
            String
        ) -> FirstFieldTripAchievementProgress? = { _ in nil },
        refreshFieldTripProgress: @escaping @MainActor () async throws
            -> FirstFieldTripAchievementProgress? = { nil },
        saveFieldTripProgress: @escaping @MainActor (
            FirstFieldTripAchievementProgress,
            String
        ) -> Void = { _, _ in },
        logProgressRefreshFailure: @escaping @MainActor (Error) -> Void = { _ in }
    ) -> ProfileTabDependencies {
        ProfileTabDependencies(
            calculateStats: { _ in
                ProfileAllStatsPayload(
                    speciesCount: 12,
                    streak: 3,
                    heatmap: ProfileHeatmapData(
                        totalCaptures: 21,
                        currentMonthCaptures: 5,
                        yearString: "2026",
                        weeks: []
                    ),
                    awards: [
                        AwardPayload(
                            type: .explorer,
                            currentCount: 1,
                            lastInteractionDate: nil
                        )
                    ]
                )
            },
            loadCachedFieldTripProgress: loadCachedFieldTripProgress,
            refreshFieldTripProgress: refreshFieldTripProgress,
            saveFieldTripProgress: saveFieldTripProgress,
            appEvents: Empty<AppEvent, Never>(
                completeImmediately: false
            ).eraseToAnyPublisher(),
            openFieldTrips: {},
            selectionFeedback: {},
            errorFeedback: {},
            resolveScanRoute: { _, _ in nil },
            logProgressRefreshFailure: logProgressRefreshFailure
        )
    }

    private func progress(
        slug: String
    ) -> FirstFieldTripAchievementProgress {
        FirstFieldTripAchievementProgress(
            kind: .standardOuting,
            completedAt: "2026-08-01T12:00:00Z",
            templateSlug: slug,
            challengeId: nil
        )
    }
}
