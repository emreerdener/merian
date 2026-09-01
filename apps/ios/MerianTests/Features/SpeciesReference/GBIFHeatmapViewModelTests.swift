import Foundation
import Testing

@testable import Merian

@MainActor
struct GBIFHeatmapViewModelTests {
    @Test func missingTaxonKeyDoesNotStartARequest() async {
        var requestedKeys: [Int] = []
        let viewModel = GBIFHeatmapViewModel(
            dependencies: .init { key in
                requestedKeys.append(key)
                return .failed
            }
        )

        await viewModel.load(taxonKey: nil)

        #expect(requestedKeys.isEmpty)
        #expect(viewModel.loadState == .noTaxonKey)
        #expect(viewModel.tileImage == nil)
    }

    @Test(arguments: [
        (GBIFHeatmapLoadResult.noData, GBIFHeatmapLoadState.noData),
        (.serviceUnavailable, .serviceUnavailable),
        (.failed, .failed)
    ])
    func serviceOutcomesMapToPresentationState(
        result: GBIFHeatmapLoadResult,
        expectedState: GBIFHeatmapLoadState
    ) async {
        let viewModel = GBIFHeatmapViewModel(
            dependencies: .init { _ in result }
        )

        await viewModel.load(taxonKey: 48_662)

        #expect(viewModel.loadState == expectedState)
        #expect(viewModel.tileImage == nil)
    }

    @Test func lateTileResponseCannotOverwriteNewTaxonState() async {
        var pendingFirstLoad: CheckedContinuation<
            GBIFHeatmapLoadResult,
            Never
        >?
        let viewModel = GBIFHeatmapViewModel(
            dependencies: .init { key in
                if key == 1 {
                    return await withCheckedContinuation {
                        pendingFirstLoad = $0
                    }
                }
                return .noData
            }
        )

        let firstLoad = Task {
            await viewModel.load(taxonKey: 1)
        }
        while pendingFirstLoad == nil {
            await Task.yield()
        }

        await viewModel.load(taxonKey: 2)
        pendingFirstLoad?.resume(returning: .serviceUnavailable)
        await firstLoad.value

        #expect(viewModel.loadState == .noData)
        #expect(viewModel.tileImage == nil)
    }

    @Test func preCancelledLoadDoesNotClaimGenerationOwnership() async {
        var requestedKeys: [Int] = []
        let viewModel = GBIFHeatmapViewModel(
            dependencies: .init { key in
                requestedKeys.append(key)
                return .noData
            }
        )

        await viewModel.load(taxonKey: 1)
        let cancelledLoad = Task {
            await viewModel.load(taxonKey: 2)
        }
        cancelledLoad.cancel()
        await cancelledLoad.value

        #expect(requestedKeys == [1])
        #expect(viewModel.loadState == .noData)
        #expect(viewModel.tileImage == nil)
    }

    @Test func responsePolicySeparatesNoDataOutageAndInvalidPayloads() {
        #expect(GBIFHeatmapResponsePolicy.disposition(
            statusCode: 200,
            mimeType: "image/png",
            isBodyEmpty: false
        ) == .image)
        #expect(GBIFHeatmapResponsePolicy.disposition(
            statusCode: 204,
            mimeType: nil,
            isBodyEmpty: true
        ) == .noData)
        #expect(GBIFHeatmapResponsePolicy.disposition(
            statusCode: 404,
            mimeType: nil,
            isBodyEmpty: false
        ) == .noData)
        #expect(GBIFHeatmapResponsePolicy.disposition(
            statusCode: 503,
            mimeType: nil,
            isBodyEmpty: false
        ) == .serviceUnavailable)
        #expect(GBIFHeatmapResponsePolicy.disposition(
            statusCode: 200,
            mimeType: "application/json",
            isBodyEmpty: false
        ) == .failed)
        #expect(GBIFHeatmapResponsePolicy.disposition(
            statusCode: 500,
            mimeType: "image/png",
            isBodyEmpty: false
        ) == .failed)
    }

    @Test func tileAdapterBuildsTheExistingZoomZeroGBIFRequest() throws {
        let url = try #require(
            GBIFHeatmapTileService.tileURL(taxonKey: 48_662)
        )
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap {
                item in item.value.map { (item.name, $0) }
            }
        )

        #expect(components.scheme == "https")
        #expect(components.host == "api.gbif.org")
        #expect(components.path == "/v2/map/occurrence/density/0/0/0@2x.png")
        #expect(query["taxonKey"] == "48662")
        #expect(query["style"] == "classic.poly")
        #expect(query["bin"] == "hex")
        #expect(query["hexPerTile"] == "135")
    }
}
