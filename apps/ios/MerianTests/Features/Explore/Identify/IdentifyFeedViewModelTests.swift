@testable import Merian
import Testing

@MainActor
@Suite("Identify Feed View Models")
struct IdentifyFeedViewModelTests {
    @Test func requestsPaginateWithLocationCursorAndDeduplicate() async throws {
        let firstPage = try (0..<30).map {
            try CommunityIdentificationTestFixtures.requestItem(index: $0)
        }
        let secondPage = [
            firstPage[29],
            try CommunityIdentificationTestFixtures.requestItem(
                index: 30,
                requestedAt: "2026-08-24T12:00:00Z"
            )
        ]
        var loads: [IdentifyRequestPageRequest] = []

        let viewModel = IdentifyRequestsFeedViewModel(
            initialFilter: .plants,
            dependencies: IdentifyRequestsFeedViewModel.Dependencies(
                loadPage: { request in
                    loads.append(request)
                    return request.cursor.isEmpty ? firstPage : secondPage
                },
                errorMessage: { _ in "failed" }
            )
        )

        await viewModel.reload(latitude: 30.25, longitude: -97.75)

        #expect(viewModel.items == firstPage)
        #expect(!viewModel.hasReachedEnd)
        #expect(viewModel.shouldLoadMore(after: firstPage[24]))
        #expect(loads.first?.limit == 30)
        #expect(loads.first?.filter == .plants)
        #expect(loads.first?.latitude == 30.25)
        #expect(loads.first?.longitude == -97.75)
        #expect(loads.first?.cursor == .empty)

        await viewModel.loadMore(latitude: 30.25, longitude: -97.75)

        #expect(viewModel.items.count == 31)
        #expect(viewModel.items.last?.requestId == "request-30")
        #expect(viewModel.hasReachedEnd)
        #expect(loads.last?.cursor.beforeRequestId == firstPage[29].requestId)
        #expect(loads.last?.cursor.beforeRequestedAt == firstPage[29].requestedAt)
        #expect(!viewModel.isLoadingMore)
    }

    @Test func activityPaginatesWithCursorAndDeduplicates() async throws {
        let firstPage = try (0..<30).map {
            try CommunityIdentificationTestFixtures.activityItem(index: $0)
        }
        let secondPage = [
            firstPage[29],
            try CommunityIdentificationTestFixtures.activityItem(
                index: 30,
                activityAt: "2026-08-24T13:00:00Z"
            )
        ]
        var loads: [IdentifyActivityPageRequest] = []

        let viewModel = IdentifyActivityFeedViewModel(
            initialFilter: .fungi,
            dependencies: IdentifyActivityFeedViewModel.Dependencies(
                loadPage: { request in
                    loads.append(request)
                    return request.cursor.isEmpty ? firstPage : secondPage
                },
                errorMessage: { _ in "failed" }
            )
        )

        await viewModel.reload()

        #expect(viewModel.items == firstPage)
        #expect(!viewModel.hasReachedEnd)
        #expect(viewModel.shouldLoadMore(after: firstPage[24]))
        #expect(loads.first?.limit == 30)
        #expect(loads.first?.filter == .fungi)
        #expect(loads.first?.cursor == .empty)

        await viewModel.loadMore()

        #expect(viewModel.items.count == 31)
        #expect(viewModel.items.last?.activityId == "activity-30")
        #expect(viewModel.hasReachedEnd)
        #expect(loads.last?.cursor.beforeActivityId == firstPage[29].activityId)
        #expect(loads.last?.cursor.beforeActivityAt == firstPage[29].activityAt)
        #expect(!viewModel.isLoadingMore)
    }

    @Test func initialAndPaginationErrorsKeepTheirPresentationIndependent() async {
        var loadCount = 0
        let viewModel = IdentifyRequestsFeedViewModel(
            initialFilter: .all,
            dependencies: IdentifyRequestsFeedViewModel.Dependencies(
                loadPage: { _ in
                    loadCount += 1
                    throw CommunityIdentificationTestError.expected
                },
                errorMessage: { _ in "expected error" }
            )
        )

        await viewModel.reload(latitude: nil, longitude: nil)

        #expect(viewModel.items.isEmpty)
        #expect(viewModel.errorMessage == "expected error")
        #expect(!viewModel.isLoadingInitialPage)
        #expect(loadCount == 1)
    }
}
