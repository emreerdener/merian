import Observation

@MainActor
@Observable
final class IdentifyRequestsFeedViewModel {
    struct Dependencies {
        let loadPage: @MainActor (IdentifyRequestPageRequest) async throws
            -> [CommunityIdentificationFeedItem]
        let errorMessage: @MainActor (Error) -> String
    }

    var filter: CommunityIdentificationRequestFilter
    var items: [CommunityIdentificationFeedItem] = []
    var isLoadingInitialPage = true
    var isLoadingMore = false
    var errorMessage: String?

    private(set) var hasReachedEnd = false
    private let dependencies: Dependencies
    private var cursor = CommunityIdentificationCursor.empty
    private var loadGeneration = 0

    init(
        initialFilter: CommunityIdentificationRequestFilter,
        dependencies: Dependencies = .live
    ) {
        filter = initialFilter
        self.dependencies = dependencies
    }

    func reload(latitude: Double?, longitude: Double?) async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedFilter = filter

        items = []
        cursor = .empty
        hasReachedEnd = false
        errorMessage = nil
        isLoadingInitialPage = true
        isLoadingMore = false

        do {
            let page = try await loadPage(
                filter: requestedFilter,
                latitude: latitude,
                longitude: longitude,
                cursor: .empty
            )
            guard generation == loadGeneration, requestedFilter == filter else { return }
            items = page
            updateCursor(using: page)
            hasReachedEnd = page.count < CommunityIdentificationDashboardPolicy.fullPageSize
            isLoadingInitialPage = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, requestedFilter == filter else { return }
            errorMessage = dependencies.errorMessage(error)
            isLoadingInitialPage = false
        }
    }

    func shouldLoadMore(after item: CommunityIdentificationFeedItem) -> Bool {
        guard !isLoadingInitialPage, !isLoadingMore, !hasReachedEnd else { return false }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return false }
        return index >= max(items.count - 6, 0)
    }

    func loadMore(latitude: Double?, longitude: Double?) async {
        guard !isLoadingInitialPage, !isLoadingMore, !hasReachedEnd else { return }
        let generation = loadGeneration
        let requestedFilter = filter
        let currentCursor = cursor
        isLoadingMore = true
        errorMessage = nil

        do {
            let page = try await loadPage(
                filter: requestedFilter,
                latitude: latitude,
                longitude: longitude,
                cursor: currentCursor
            )
            guard generation == loadGeneration, requestedFilter == filter else { return }
            let existingIds = Set(items.map(\.id))
            items.append(contentsOf: page.filter { !existingIds.contains($0.id) })
            updateCursor(using: page)
            hasReachedEnd = page.count < CommunityIdentificationDashboardPolicy.fullPageSize
            isLoadingMore = false
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, requestedFilter == filter else { return }
            errorMessage = dependencies.errorMessage(error)
            isLoadingMore = false
        }
    }

    private func loadPage(
        filter: CommunityIdentificationRequestFilter,
        latitude: Double?,
        longitude: Double?,
        cursor: CommunityIdentificationCursor
    ) async throws -> [CommunityIdentificationFeedItem] {
        try await dependencies.loadPage(
            IdentifyRequestPageRequest(
                limit: CommunityIdentificationDashboardPolicy.fullPageSize,
                filter: filter,
                latitude: latitude,
                longitude: longitude,
                cursor: cursor
            )
        )
    }

    private func updateCursor(using page: [CommunityIdentificationFeedItem]) {
        guard let lastItem = page.last else { return }
        cursor = CommunityIdentificationCursor(
            beforeRequestedAt: lastItem.requestedAt,
            beforeRequestId: lastItem.requestId
        )
    }
}
