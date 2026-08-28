import Combine
import Foundation
import XCTest

@testable import Merian

@MainActor
final class ScansShellViewModelTests: XCTestCase {
    func testDefaultPresentationStartsAtLibraryRoot() {
        let navigation = ScansSheetInitialNavigation(
            initiallyShowsNonBiologicalScans: false
        )

        XCTAssertEqual(navigation.activeTab, .library)
        XCTAssertTrue(navigation.routes.isEmpty)
    }

    func testNonBiologicalPresentationSeedsTypedCollectionRoute() {
        let navigation = ScansSheetInitialNavigation(
            initiallyShowsNonBiologicalScans: true
        )

        XCTAssertEqual(navigation.activeTab, .collections)
        XCTAssertEqual(navigation.routes, [.nonBiologicalScans])
    }

    func testIncidentSummaryDeduplicatesAndBuildsStableSignature() {
        let first = incident(postID: "post-1", scanID: "scan-1")
        let second = incident(postID: "post-2", scanID: "scan-2")

        let summary = ExploreMediaIncidentSummary(
            incidents: [second, first, first]
        )

        XCTAssertEqual(summary.unavailablePublishedScanIDs, ["scan-1", "scan-2"])
        XCTAssertEqual(summary.unavailablePublishedScanCount, 2)
        XCTAssertEqual(summary.overviewDismissalSignature, "6:scan-16:scan-2")
        XCTAssertNil(
            ExploreMediaIncidentSummary(
                incidents: [ExploreMediaIncident]()
            ).overviewDismissalSignature
        )
    }

    func testOverviewDismissalIsAccountScopedAndClearable() throws {
        let suiteName = "ScansShellOverviewTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstOwnerID = UUID().uuidString
        let secondOwnerID = UUID().uuidString
        let signature = "6:scan-16:scan-2"

        ExploreMediaOverviewPreferences.dismiss(
            signature: signature,
            ownerUserID: firstOwnerID,
            defaults: defaults
        )

        XCTAssertEqual(
            ExploreMediaOverviewPreferences.dismissedSignature(
                ownerUserID: firstOwnerID.uppercased(),
                defaults: defaults
            ),
            signature
        )
        XCTAssertNil(
            ExploreMediaOverviewPreferences.dismissedSignature(
                ownerUserID: secondOwnerID,
                defaults: defaults
            )
        )

        ExploreMediaOverviewPreferences.clear(
            ownerUserID: firstOwnerID,
            defaults: defaults
        )
        XCTAssertNil(
            ExploreMediaOverviewPreferences.dismissedSignature(
                ownerUserID: firstOwnerID,
                defaults: defaults
            )
        )
    }

    func testInitialRecoveryFilterIsAppliedOnlyOnce() {
        let viewModel = makeViewModel()
        let searchManager = ScansManager()
        let context = ExploreMediaRecoveryRouteContext(ownerUserId: "owner")

        viewModel.applyInitialRecoveryFilterIfNeeded(
            recoveryContext: context,
            searchManager: searchManager
        )
        XCTAssertTrue(
            searchManager.filters.explorePostFilters.contains(
                .unavailableMedia
            )
        )

        var clearedFilters = searchManager.filters
        clearedFilters.explorePostFilters.remove(.unavailableMedia)
        searchManager.filters = clearedFilters
        viewModel.applyInitialRecoveryFilterIfNeeded(
            recoveryContext: context,
            searchManager: searchManager
        )

        XCTAssertFalse(
            searchManager.filters.explorePostFilters.contains(
                .unavailableMedia
            )
        )
    }

    func testOfflineRefreshClearsStateWithoutCallingEndpoint() async {
        var loadCount = 0
        let viewModel = makeViewModel(
            loadIncidents: {
                loadCount += 1
                return [self.incident(postID: "post", scanID: "scan")]
            }
        )

        await viewModel.refreshExploreMediaIncidents(
            recoveryContext: nil,
            searchManager: ScansManager(),
            isOnline: { false }
        )

        XCTAssertEqual(loadCount, 0)
        XCTAssertTrue(viewModel.exploreMediaIncidents.isEmpty)
        XCTAssertFalse(viewModel.isExploreMediaIncidentRefreshRunning)
    }

    func testRecoveryOwnerMismatchDoesNotCallEndpoint() async {
        var loadCount = 0
        let viewModel = makeViewModel(
            loadIncidents: {
                loadCount += 1
                return []
            }
        )

        await viewModel.refreshExploreMediaIncidents(
            recoveryContext: ExploreMediaRecoveryRouteContext(
                ownerUserId: "another-owner"
            ),
            searchManager: ScansManager(),
            isOnline: { true }
        )

        XCTAssertEqual(loadCount, 0)
        XCTAssertTrue(viewModel.exploreMediaIncidents.isEmpty)
    }

    func testAccountChangeDiscardsInFlightIncidentResponse() async {
        var session = ScansShellSession(
            isAuthenticated: true,
            ownerUserID: "owner-1"
        )
        let loadStarted = expectation(description: "Incident load started")
        var pendingLoad: CheckedContinuation<
            [ExploreMediaIncident],
            any Error
        >?
        let viewModel = makeViewModel(
            session: { session },
            loadIncidents: {
                try await withCheckedThrowingContinuation { continuation in
                    pendingLoad = continuation
                    loadStarted.fulfill()
                }
            }
        )

        let refreshTask = Task {
            await viewModel.refreshExploreMediaIncidents(
                recoveryContext: nil,
                searchManager: ScansManager(),
                isOnline: { true }
            )
        }
        await fulfillment(of: [loadStarted], timeout: 1)

        session = ScansShellSession(
            isAuthenticated: true,
            ownerUserID: "owner-2"
        )
        pendingLoad?.resume(
            returning: [incident(postID: "stale", scanID: "stale")]
        )
        await refreshTask.value

        XCTAssertTrue(viewModel.exploreMediaIncidents.isEmpty)
        XCTAssertFalse(viewModel.isExploreMediaIncidentRefreshRunning)
    }

    func testCancelledRefreshPreservesLastIncidentState() async {
        let existingIncident = incident(postID: "existing", scanID: "existing")
        let staleIncident = incident(postID: "stale", scanID: "stale")
        let secondLoadStarted = expectation(description: "Second load started")
        var pendingSecondLoad: CheckedContinuation<
            [ExploreMediaIncident],
            any Error
        >?
        var loadCount = 0
        let viewModel = makeViewModel(
            loadIncidents: {
                loadCount += 1
                if loadCount == 1 {
                    return [existingIncident]
                }
                return try await withCheckedThrowingContinuation { continuation in
                    pendingSecondLoad = continuation
                    secondLoadStarted.fulfill()
                }
            }
        )
        let searchManager = ScansManager()
        await viewModel.refreshExploreMediaIncidents(
            recoveryContext: nil,
            searchManager: searchManager,
            isOnline: { true }
        )
        viewModel.resetExploreMediaIncidentRefreshThrottle()

        let cancelledRefresh = Task {
            await viewModel.refreshExploreMediaIncidents(
                recoveryContext: nil,
                searchManager: searchManager,
                isOnline: { true }
            )
        }
        await fulfillment(of: [secondLoadStarted], timeout: 1)
        cancelledRefresh.cancel()
        pendingSecondLoad?.resume(returning: [staleIncident])
        await cancelledRefresh.value

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(viewModel.exploreMediaIncidents, [existingIncident])
        XCTAssertFalse(viewModel.isExploreMediaIncidentRefreshRunning)
    }

    func testAccountReplacementPreservesTrailingRefresh() async {
        var session = ScansShellSession(
            isAuthenticated: true,
            ownerUserID: "owner-1"
        )
        let firstLoadStarted = expectation(description: "First load started")
        let trailingRefreshCommitted = expectation(
            description: "Trailing refresh committed"
        )
        var pendingFirstLoad: CheckedContinuation<
            [ExploreMediaIncident],
            any Error
        >?
        var loadCount = 0
        let viewModel = makeViewModel(
            session: { session },
            loadIncidents: {
                loadCount += 1
                if loadCount == 1 {
                    return try await withCheckedThrowingContinuation { continuation in
                        pendingFirstLoad = continuation
                        firstLoadStarted.fulfill()
                    }
                }
                return []
            },
            clearOverviewDismissal: { ownerUserID in
                XCTAssertEqual(ownerUserID, "owner-2")
                trailingRefreshCommitted.fulfill()
            }
        )
        let searchManager = ScansManager()
        let firstRefresh = Task {
            await viewModel.refreshExploreMediaIncidents(
                recoveryContext: nil,
                searchManager: searchManager,
                isOnline: { true }
            )
        }
        await fulfillment(of: [firstLoadStarted], timeout: 1)

        session = ScansShellSession(
            isAuthenticated: true,
            ownerUserID: "owner-2"
        )
        await viewModel.refreshExploreMediaIncidents(
            recoveryContext: nil,
            searchManager: searchManager,
            isOnline: { true }
        )
        pendingFirstLoad?.resume(
            returning: [incident(postID: "stale", scanID: "stale")]
        )
        await firstRefresh.value
        await fulfillment(of: [trailingRefreshCommitted], timeout: 1)

        XCTAssertEqual(loadCount, 2)
        XCTAssertTrue(viewModel.exploreMediaIncidents.isEmpty)
    }

    func testOverlappingRefreshRunsOneTrailingRequest() async {
        let firstLoadStarted = expectation(description: "First load started")
        var pendingFirstLoad: CheckedContinuation<
            [ExploreMediaIncident],
            any Error
        >?
        var loadCount = 0
        let firstIncident = incident(postID: "first", scanID: "first")
        let latestIncident = incident(postID: "latest", scanID: "latest")
        let viewModel = makeViewModel(
            loadIncidents: {
                loadCount += 1
                if loadCount == 1 {
                    return try await withCheckedThrowingContinuation { continuation in
                        pendingFirstLoad = continuation
                        firstLoadStarted.fulfill()
                    }
                }
                return [latestIncident]
            }
        )
        let searchManager = ScansManager()

        let firstRefresh = Task {
            await viewModel.refreshExploreMediaIncidents(
                recoveryContext: nil,
                searchManager: searchManager,
                isOnline: { true }
            )
        }
        await fulfillment(of: [firstLoadStarted], timeout: 1)

        await viewModel.refreshExploreMediaIncidents(
            recoveryContext: nil,
            searchManager: searchManager,
            isOnline: { true }
        )
        pendingFirstLoad?.resume(returning: [firstIncident])
        await firstRefresh.value

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(viewModel.exploreMediaIncidents, [latestIncident])
        XCTAssertFalse(viewModel.isExploreMediaIncidentRefreshRunning)
    }

    func testSuccessfulEmptyRefreshClearsUnavailableMediaFilter() async {
        let viewModel = makeViewModel(loadIncidents: { [] })
        let searchManager = ScansManager()
        var filters = searchManager.filters
        filters.explorePostFilters.insert(.unavailableMedia)
        searchManager.filters = filters

        await viewModel.refreshExploreMediaIncidents(
            recoveryContext: nil,
            searchManager: searchManager,
            isOnline: { true }
        )

        XCTAssertFalse(
            searchManager.filters.explorePostFilters.contains(
                .unavailableMedia
            )
        )
    }

    func testFailedRefreshPreservesLastIncidentState() async {
        let existingIncident = incident(postID: "post", scanID: "scan")
        var requestCount = 0
        let viewModel = makeViewModel(
            loadIncidents: {
                requestCount += 1
                if requestCount == 1 {
                    return [existingIncident]
                }
                throw TestError.expected
            }
        )
        let searchManager = ScansManager()

        await viewModel.refreshExploreMediaIncidents(
            recoveryContext: nil,
            searchManager: searchManager,
            isOnline: { true }
        )
        viewModel.resetExploreMediaIncidentRefreshThrottle()
        await viewModel.refreshExploreMediaIncidents(
            recoveryContext: nil,
            searchManager: searchManager,
            isOnline: { true }
        )

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(viewModel.exploreMediaIncidents, [existingIncident])
    }

    private func makeViewModel(
        session: @escaping @MainActor () -> ScansShellSession = {
            ScansShellSession(
                isAuthenticated: true,
                ownerUserID: "owner-1"
            )
        },
        loadIncidents: @escaping @MainActor () async throws
            -> [ExploreMediaIncident] = { [] },
        clearOverviewDismissal: @escaping @MainActor (_ ownerUserID: String)
            -> Void = { _ in }
    ) -> ScansShellViewModel {
        ScansShellViewModel(
            dependencies: ScansShellViewModel.Dependencies(
                events: Empty<AppEvent, Never>().eraseToAnyPublisher(),
                currentSession: session,
                loadExploreMediaIncidents: loadIncidents,
                dismissedOverviewSignature: { _ in nil },
                dismissOverview: { _, _ in },
                clearOverviewDismissal: clearOverviewDismissal,
                now: { Date(timeIntervalSinceReferenceDate: 1_000) },
                sleep: { _ in },
                updateAppIconBadge: { }
            )
        )
    }

    private func incident(
        postID: String,
        scanID: String
    ) -> ExploreMediaIncident {
        ExploreMediaIncident(
            postId: postID,
            scanId: scanID,
            speciesCommonName: "Species",
            mediaHealthStatus: .degraded,
            missingMediaCount: 1,
            totalMediaCount: 2,
            mediaQuarantinedAt: nil,
            mediaHealthUpdatedAt: "2026-08-27T12:00:00Z",
            missingMediaUrls: ["https://media.merian.app/missing.webp"]
        )
    }

    private enum TestError: Error {
        case expected
    }
}
