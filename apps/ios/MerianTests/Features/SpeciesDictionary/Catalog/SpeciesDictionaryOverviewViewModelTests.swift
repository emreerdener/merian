import Foundation
import XCTest

@testable import Merian

@MainActor
final class SpeciesDictionaryOverviewViewModelTests: XCTestCase {
    private enum StubError: Error {
        case expected
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
