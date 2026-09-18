import Foundation
import XCTest

@testable import Merian

@MainActor
final class SpeciesDictionaryOverviewViewModelTests: XCTestCase {
    private enum StubError: Error {
        case expected
    }

    func testNavigationReusesFreshOverviewForNormalizedRegion() async throws {
        let response = try Self.overviewResponse(regionTitle: "United States")
        var now = Date(timeIntervalSince1970: 1_000)
        var requests = 0
        let viewModel = SpeciesDictionaryOverviewViewModel(dependencies: .init(
            loadOverview: { region in
                XCTAssertEqual(region, "US")
                requests += 1
                return response
            },
            errorMessage: { _ in "Expected error" },
            now: { now }
        ))

        await viewModel.loadIfNeeded(userRegion: " us ")
        now.addTimeInterval(299)
        await viewModel.loadIfNeeded(userRegion: "US")

        XCTAssertEqual(requests, 1)
        XCTAssertEqual(viewModel.overview, response.data)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testNavigationReusesOverviewWithoutRegion() async throws {
        let response = try Self.overviewResponse(regionTitle: "Global")
        var requests = 0
        let viewModel = SpeciesDictionaryOverviewViewModel(dependencies: .init(
            loadOverview: { region in
                XCTAssertNil(region)
                requests += 1
                return response
            },
            errorMessage: { _ in "Expected error" }
        ))

        await viewModel.loadIfNeeded(userRegion: nil)
        await viewModel.loadIfNeeded(userRegion: "  ")

        XCTAssertEqual(requests, 1)
    }

    func testExpiredOverviewRemainsVisibleDuringRefresh() async throws {
        let original = try Self.overviewResponse(regionTitle: "Original")
        let updated = try Self.overviewResponse(regionTitle: "Updated")
        var now = Date(timeIntervalSince1970: 1_000)
        var requests = 0
        let refreshStarted = expectation(description: "Refresh started")
        var pending: CheckedContinuation<SpeciesDictionaryOverviewResponse, any Error>?
        let viewModel = SpeciesDictionaryOverviewViewModel(dependencies: .init(
            loadOverview: { _ in
                requests += 1
                if requests == 1 { return original }
                return try await withCheckedThrowingContinuation {
                    pending = $0
                    refreshStarted.fulfill()
                }
            },
            errorMessage: { _ in "Expected error" },
            now: { now }
        ))

        await viewModel.loadIfNeeded(userRegion: "US")
        now.addTimeInterval(300)
        let refresh = Task { await viewModel.loadIfNeeded(userRegion: "US") }
        await fulfillment(of: [refreshStarted], timeout: 1)

        XCTAssertEqual(viewModel.overview, original.data)
        XCTAssertTrue(viewModel.isLoading)
        pending?.resume(returning: updated)
        await refresh.value
        await viewModel.loadIfNeeded(userRegion: "US")

        XCTAssertEqual(requests, 2)
        XCTAssertEqual(viewModel.overview, updated.data)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testExplicitRefreshBypassesFreshnessWindow() async throws {
        let response = try Self.overviewResponse(regionTitle: "United States")
        var requests = 0
        let viewModel = SpeciesDictionaryOverviewViewModel(dependencies: .init(
            loadOverview: { _ in
                requests += 1
                return response
            },
            errorMessage: { _ in "Expected error" }
        ))

        await viewModel.loadIfNeeded(userRegion: "US")
        await viewModel.load(userRegion: "US")

        XCTAssertEqual(requests, 2)
    }

    func testFailedStaleRefreshKeepsContentAndDoesNotRenewFreshness() async throws {
        let response = try Self.overviewResponse(regionTitle: "United States")
        var now = Date(timeIntervalSince1970: 1_000)
        var requests = 0
        let viewModel = SpeciesDictionaryOverviewViewModel(dependencies: .init(
            loadOverview: { _ in
                requests += 1
                if requests == 2 { throw StubError.expected }
                return response
            },
            errorMessage: { _ in "Expected error" },
            now: { now }
        ))

        await viewModel.loadIfNeeded(userRegion: "US")
        now.addTimeInterval(300)
        await viewModel.loadIfNeeded(userRegion: "US")
        XCTAssertEqual(viewModel.overview, response.data)
        XCTAssertEqual(viewModel.errorMessage, "Expected error")
        await viewModel.loadIfNeeded(userRegion: "US")

        XCTAssertEqual(requests, 3)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRegionChangeClearsPreviousRegionAndCanReturnAfterFailure() async throws {
        let response = try Self.overviewResponse(regionTitle: "United States")
        var requests = 0
        let viewModel = SpeciesDictionaryOverviewViewModel(dependencies: .init(
            loadOverview: { region in
                requests += 1
                if region == "CA" { throw StubError.expected }
                return response
            },
            errorMessage: { _ in "Expected error" }
        ))

        await viewModel.loadIfNeeded(userRegion: "US")
        await viewModel.loadIfNeeded(userRegion: "CA")
        XCTAssertNil(viewModel.overview)
        XCTAssertEqual(viewModel.errorMessage, "Expected error")
        await viewModel.loadIfNeeded(userRegion: "US")

        XCTAssertEqual(requests, 3)
        XCTAssertEqual(viewModel.overview, response.data)
    }

    func testCancelledLoadDoesNotBlockNavigationReloadOrPublishLateResult() async throws {
        let stale = try Self.overviewResponse(regionTitle: "Cancelled")
        let current = try Self.overviewResponse(regionTitle: "Current")
        let loadStarted = expectation(description: "Initial load started")
        var requests = 0
        var pending: CheckedContinuation<SpeciesDictionaryOverviewResponse, any Error>?
        let viewModel = SpeciesDictionaryOverviewViewModel(dependencies: .init(
            loadOverview: { _ in
                requests += 1
                if requests > 1 { return current }
                return try await withCheckedThrowingContinuation {
                    pending = $0
                    loadStarted.fulfill()
                }
            },
            errorMessage: { _ in "Expected error" }
        ))

        let firstLoad = Task { await viewModel.loadIfNeeded(userRegion: "US") }
        await fulfillment(of: [loadStarted], timeout: 1)
        firstLoad.cancel()
        await viewModel.loadIfNeeded(userRegion: "US")
        pending?.resume(returning: stale)
        await firstLoad.value
        await viewModel.loadIfNeeded(userRegion: "US")

        XCTAssertEqual(requests, 2)
        XCTAssertEqual(viewModel.overview, current.data)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadNormalizesRegionAndPublishesResponse() async throws {
        let response = try Self.overviewResponse(regionTitle: "United States")
        var capturedRegion: String?
        let viewModel = SpeciesDictionaryOverviewViewModel(
            dependencies: .init(
                loadOverview: { region in
                    capturedRegion = region
                    return response
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.load(userRegion: " US ")

        XCTAssertEqual(capturedRegion, "US")
        XCTAssertEqual(
            viewModel.overview?.regions.first?.title,
            "United States"
        )
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRefreshFailurePreservesLoadedContent() async throws {
        let response = try Self.overviewResponse(regionTitle: "United States")
        var shouldFail = false
        let viewModel = SpeciesDictionaryOverviewViewModel(
            dependencies: .init(
                loadOverview: { _ in
                    if shouldFail {
                        throw StubError.expected
                    }
                    return response
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        await viewModel.load(userRegion: "US")
        shouldFail = true
        await viewModel.load(userRegion: "US")

        XCTAssertEqual(viewModel.overview, response.data)
        XCTAssertEqual(viewModel.errorMessage, "Expected error")
        XCTAssertFalse(viewModel.isLoading)
    }

    func testNewRequestRejectsStaleCompletion() async throws {
        let stale = try Self.overviewResponse(regionTitle: "Stale")
        let current = try Self.overviewResponse(regionTitle: "Canada")
        let staleLoadStarted = expectation(description: "Old overview started")
        var pendingStaleLoad: CheckedContinuation<
            SpeciesDictionaryOverviewResponse,
            any Error
        >?
        let viewModel = SpeciesDictionaryOverviewViewModel(
            dependencies: .init(
                loadOverview: { region in
                    if region == "US" {
                        return try await withCheckedThrowingContinuation {
                            pendingStaleLoad = $0
                            staleLoadStarted.fulfill()
                        }
                    }
                    return current
                },
                errorMessage: { _ in "Expected error" }
            )
        )

        let staleTask = Task { await viewModel.load(userRegion: "US") }
        await fulfillment(of: [staleLoadStarted], timeout: 1)

        await viewModel.load(userRegion: "CA")
        pendingStaleLoad?.resume(returning: stale)
        _ = await staleTask.value

        XCTAssertEqual(viewModel.overview?.regions.first?.title, "Canada")
        XCTAssertFalse(viewModel.isLoading)
    }

    private static func overviewResponse(
        regionTitle: String
    ) throws -> SpeciesDictionaryOverviewResponse {
        let data = Data(
            """
            {
                "schema_version": 1,
                "data": {
                    "categories": [],
                    "groups": [],
                    "regions": [
                        {
                            "id": "region:test",
                            "title": "\(regionTitle)",
                            "count": 1,
                            "reference_image_url": null,
                            "code": "US"
                        }
                    ]
                }
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(
            SpeciesDictionaryOverviewResponse.self,
            from: data
        )
    }
}
