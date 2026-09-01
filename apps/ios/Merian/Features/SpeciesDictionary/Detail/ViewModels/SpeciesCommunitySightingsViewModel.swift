import Foundation
import Observation

@MainActor
@Observable
final class SpeciesCommunitySightingsViewModel {
    typealias PageLoader = @MainActor (
        _ speciesId: String,
        _ limit: Int,
        _ cursor: ExploreSpeciesPostCursor?
    ) async throws -> ExploreSpeciesPostsResponse

    struct Dependencies {
        let loadPage: PageLoader
    }

    private(set) var posts: [ExplorePost] = []
    private(set) var nextCursor: ExploreSpeciesPostCursor?
    private(set) var isLoadingInitial = false
    private(set) var isLoadingMore = false
    private(set) var didFail = false

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var loadedSpeciesId: String?
    @ObservationIgnored private var hasLoadedInitialPage = false
    @ObservationIgnored private var requestGeneration: UInt64 = 0

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    convenience init(loadPage: @escaping PageLoader) {
        self.init(dependencies: Dependencies(loadPage: loadPage))
    }

    var hasMore: Bool {
        nextCursor != nil
    }

    func loadInitial(
        speciesId: String,
        limit: Int = 6,
        force: Bool = false
    ) async {
        let normalizedSpeciesId = speciesId.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
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
            let response = try await dependencies.loadPage(
                normalizedSpeciesId,
                limit,
                nil
            )
            guard isCurrent(generation, speciesId: normalizedSpeciesId) else {
                return
            }

            posts = deduplicated(response.data)
            nextCursor = response.nextCursor
            hasLoadedInitialPage = true
            MerianLog.network.debug(
                "Loaded \(self.posts.count, privacy: .public) community sighting(s) for species \(normalizedSpeciesId, privacy: .private)."
            )
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(generation, speciesId: normalizedSpeciesId) else {
                return
            }

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
        await loadInitial(
            speciesId: loadedSpeciesId,
            limit: limit,
            force: true
        )
    }

    func loadMore(limit: Int = 30) async {
        guard !isLoadingInitial,
              !isLoadingMore,
              let loadedSpeciesId,
              let cursor = nextCursor
        else {
            return
        }

        let generation = requestGeneration
        isLoadingMore = true
        defer {
            if requestGeneration == generation {
                isLoadingMore = false
            }
        }

        do {
            let response = try await dependencies.loadPage(
                loadedSpeciesId,
                limit,
                cursor
            )
            guard isCurrent(generation, speciesId: loadedSpeciesId) else {
                return
            }

            posts = deduplicated(posts + response.data)
            nextCursor = response.nextCursor
            didFail = false
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(generation, speciesId: loadedSpeciesId) else {
                return
            }

            // Keep already loaded sightings useful and avoid an onAppear retry
            // loop.
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

    private func isCurrent(
        _ generation: UInt64,
        speciesId: String
    ) -> Bool {
        !Task.isCancelled
            && requestGeneration == generation
            && loadedSpeciesId == speciesId
    }

    private func deduplicated(_ input: [ExplorePost]) -> [ExplorePost] {
        var seenIds = Set<String>()
        return input.filter { seenIds.insert($0.id).inserted }
    }
}
