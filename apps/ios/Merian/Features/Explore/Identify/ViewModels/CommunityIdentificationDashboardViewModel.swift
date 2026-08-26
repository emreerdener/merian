import Observation

@MainActor
@Observable
final class IdentifyDashboardViewModel {
    struct Dependencies {
        let loadRequests: @MainActor (IdentifyRequestPageRequest) async throws
            -> [CommunityIdentificationFeedItem]
        let loadActivity: @MainActor (IdentifyActivityPageRequest) async throws
            -> [CommunityIdentificationActivityItem]
        let requestErrorMessage: @MainActor (Error) -> String
        let activityErrorMessage: @MainActor (Error) -> String
    }

    var requestItems: [CommunityIdentificationFeedItem] = []
    var activityItems: [CommunityIdentificationActivityItem] = []
    var loadState = IdentifyDashboardLoadState()
    var filter: CommunityIdentificationRequestFilter = .all

    private let dependencies: Dependencies
    private var loadGeneration = 0

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func reload(
        filter: CommunityIdentificationRequestFilter,
        latitude: Double?,
        longitude: Double?,
        clearExisting: Bool
    ) async {
        self.filter = filter
        loadGeneration += 1
        let generation = loadGeneration

        if clearExisting {
            requestItems = []
            activityItems = []
        }
        loadState.beginBoth()

        async let requestLoad: Void = loadRequestPreview(
            filter: filter,
            latitude: latitude,
            longitude: longitude,
            generation: generation
        )
        async let activityLoad: Void = loadActivityPreview(
            filter: filter,
            generation: generation
        )
        await requestLoad
        await activityLoad
    }

    func reloadRequests(
        filter: CommunityIdentificationRequestFilter,
        latitude: Double?,
        longitude: Double?
    ) async {
        loadState.begin(.requests)
        await loadRequestPreview(
            filter: filter,
            latitude: latitude,
            longitude: longitude,
            generation: loadGeneration
        )
    }

    func reloadActivity(filter: CommunityIdentificationRequestFilter) async {
        loadState.begin(.activity)
        await loadActivityPreview(filter: filter, generation: loadGeneration)
    }

    func contains(requestId: String) -> Bool {
        requestItems.contains { $0.requestId == requestId }
            || activityItems.contains { $0.requestId == requestId }
    }

    private func loadRequestPreview(
        filter: CommunityIdentificationRequestFilter,
        latitude: Double?,
        longitude: Double?,
        generation: Int
    ) async {
        do {
            let page = try await dependencies.loadRequests(
                IdentifyRequestPageRequest(
                    limit: CommunityIdentificationDashboardPolicy.requestPreviewLimit,
                    filter: filter,
                    latitude: latitude,
                    longitude: longitude,
                    cursor: .empty
                )
            )
            guard generation == loadGeneration, filter == self.filter else { return }
            requestItems = page
            loadState.succeed(.requests)
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, filter == self.filter else { return }
            loadState.fail(
                .requests,
                message: dependencies.requestErrorMessage(error)
            )
        }
    }

    private func loadActivityPreview(
        filter: CommunityIdentificationRequestFilter,
        generation: Int
    ) async {
        do {
            let page = try await dependencies.loadActivity(
                IdentifyActivityPageRequest(
                    limit: CommunityIdentificationDashboardPolicy.activityPreviewLimit,
                    filter: filter,
                    cursor: .empty
                )
            )
            guard generation == loadGeneration, filter == self.filter else { return }
            activityItems = page
            loadState.succeed(.activity)
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration, filter == self.filter else { return }
            loadState.fail(
                .activity,
                message: dependencies.activityErrorMessage(error)
            )
        }
    }
}
