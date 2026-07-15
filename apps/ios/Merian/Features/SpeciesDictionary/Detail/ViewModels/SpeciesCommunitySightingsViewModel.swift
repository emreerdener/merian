import Foundation
import Observation

@MainActor
@Observable
final class SpeciesCommunitySightingsViewModel {
    typealias PageLoader = (
        _ speciesId: String,
        _ limit: Int,
        _ cursor: ExploreSpeciesPostCursor?
    ) async throws -> ExploreSpeciesPostsResponse

    private(set) var posts: [ExplorePost] = []
    private(set) var nextCursor: ExploreSpeciesPostCursor?
    private(set) var isLoadingInitial = false
    private(set) var isLoadingMore = false
    private(set) var didFail = false

    @ObservationIgnored private let loadPage: PageLoader
    @ObservationIgnored private var loadedSpeciesId: String?
    @ObservationIgnored private var hasLoadedInitialPage = false
    @ObservationIgnored private var requestGeneration: UInt64 = 0

    init(loadPage: @escaping PageLoader = { speciesId, limit, cursor in
        try await MerianNetworkClient.shared.getExploreSpeciesPosts(
            speciesId: speciesId,
            limit: limit,
            cursor: cursor
        )
    }) {
        self.loadPage = loadPage
    }

    var hasMore: Bool {
        nextCursor != nil
    }

    func loadInitial(speciesId: String, limit: Int = 6, force: Bool = false) async {
        let normalizedSpeciesId = speciesId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSpeciesId.isEmpty else {
            reset()
            hasLoadedInitialPage = true
            return
        }

        if !force,
           loadedSpeciesId == normalizedSpeciesId,
           hasLoadedInitialPage {
            return
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        loadedSpeciesId = normalizedSpeciesId
        posts = []
        nextCursor = nil
        didFail = false
        hasLoadedInitialPage = false
        isLoadingInitial = true
        isLoadingMore = false
        defer {
            if requestGeneration == generation {
                isLoadingInitial = false
            }
        }

        do {
            let response = try await loadPage(normalizedSpeciesId, limit, nil)
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  loadedSpeciesId == normalizedSpeciesId else { return }

            posts = deduplicated(response.data)
            nextCursor = response.nextCursor
            hasLoadedInitialPage = true
            MerianLog.network.debug(
                "Loaded \(self.posts.count, privacy: .public) community sighting(s) for species \(normalizedSpeciesId, privacy: .private)."
            )
        } catch {
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  loadedSpeciesId == normalizedSpeciesId else { return }

            posts = []
            nextCursor = nil
            didFail = true
            hasLoadedInitialPage = true
            MerianLog.network.error(
                "Failed to load community sightings for species \(normalizedSpeciesId, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    func refresh(limit: Int = 30) async {
        guard let loadedSpeciesId else { return }
        await loadInitial(speciesId: loadedSpeciesId, limit: limit, force: true)
    }

    func loadMore(limit: Int = 30) async {
        guard !isLoadingInitial,
              !isLoadingMore,
              let loadedSpeciesId,
              let cursor = nextCursor else { return }

        let generation = requestGeneration
        isLoadingMore = true
        defer {
            if requestGeneration == generation {
                isLoadingMore = false
            }
        }

        do {
            let response = try await loadPage(loadedSpeciesId, limit, cursor)
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  self.loadedSpeciesId == loadedSpeciesId else { return }

            posts = deduplicated(posts + response.data)
            nextCursor = response.nextCursor
            didFail = false
        } catch {
            guard !Task.isCancelled,
                  requestGeneration == generation,
                  self.loadedSpeciesId == loadedSpeciesId else { return }

            // Keep already loaded sightings useful and avoid an onAppear retry loop.
            nextCursor = nil
            didFail = true
        }
    }

    private func reset() {
        requestGeneration &+= 1
        loadedSpeciesId = nil
        posts = []
        nextCursor = nil
        isLoadingInitial = false
        isLoadingMore = false
        didFail = false
    }

    private func deduplicated(_ input: [ExplorePost]) -> [ExplorePost] {
        var seenIds = Set<String>()
        return input.filter { seenIds.insert($0.id).inserted }
    }
}
