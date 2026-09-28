import Foundation
import Observation

/// A sheet-scoped snapshot; loading list rows never changes map clusters or the camera.
@MainActor
@Observable
final class ExploreMapDiscoveriesViewModel: Identifiable {
    let id = UUID()
    private(set) var posts: [ExploreMapPost]
    private(set) var totalCount: Int
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let request: ExploreMapPointsRequest?
    @ObservationIgnored private let loadPoints: ExploreMapViewModel.MapPointsLoader
    @ObservationIgnored private var hasLoaded: Bool
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var removedPostIDs = Set<String>()
    @ObservationIgnored private var removedAuthorIDs = Set<String>()

    init(mapViewModel: ExploreMapViewModel) {
        let canUseLoadedPosts = mapViewModel.mode == .posts
            && mapViewModel.lastCommittedRegion != nil
            && mapViewModel.appliedSpeciesCategories == mapViewModel.selectedSpeciesCategories
            && mapViewModel.appliedMediaTypes == mapViewModel.selectedMediaTypes
        posts = mapViewModel.visiblePosts
        totalCount = mapViewModel.visibleDiscoveryCount
        hasLoaded = canUseLoadedPosts
        loadPoints = mapViewModel.dependencies.loadPoints
        request = (mapViewModel.lastCommittedRegion ?? mapViewModel.visibleRegion).map { region in
            ExploreMapPointsRequest(
                region: region,
                // The existing endpoint uses zoom only to choose rows versus clusters.
                zoomLevel: ExploreMapCameraPolicy.maximumZoomLevel,
                limit: mapViewModel.maxPostLimit,
                speciesCategories: mapViewModel.selectedSpeciesCategories,
                mediaTypes: mapViewModel.selectedMediaTypes
            )
        }
    }

    var showsResultLimit: Bool { hasLoaded && totalCount > posts.count && !posts.isEmpty }
    var isAwaitingLoad: Bool { !hasLoaded && errorMessage == nil }

    func load() async {
        guard !hasLoaded, !isLoading else { return }
        guard let request else {
            errorMessage = "Return to the map and search this area to load discoveries."
            return
        }
        generation += 1
        let admittedGeneration = generation
        isLoading = true
        errorMessage = nil
        defer {
            if generation == admittedGeneration { isLoading = false }
        }
        do {
            let response = try await loadPoints(request)
            guard !Task.isCancelled, generation == admittedGeneration else { return }
            guard response.mode == .posts,
                  response.visibleCount == 0 || !response.posts.isEmpty else {
                errorMessage = "Discoveries couldn’t be loaded. Please try again."
                return
            }
            let eligible = response.posts.filter {
                !removedPostIDs.contains($0.id) && !removedAuthorIDs.contains($0.authorUserId)
            }
            posts = Array(eligible.prefix(request.limit))
            totalCount = max(posts.count, response.visibleCount - (response.posts.count - eligible.count))
            hasLoaded = true
        } catch {
            guard !Task.isCancelled, generation == admittedGeneration,
                  !ExploreErrorFormatter.isCancellation(error) else { return }
            errorMessage = "Couldn’t load discoveries. Check your connection and try again."
        }
    }

    func cancelLoading() {
        generation += 1
        isLoading = false
    }

    func removePost(id: String) {
        removedPostIDs.insert(id)
        removePosts { $0.id == id }
    }

    func removePosts(byAuthorUserId authorUserId: String) {
        removedAuthorIDs.insert(authorUserId)
        removePosts { $0.authorUserId == authorUserId }
    }

    func syncVisibility(from canonicalPosts: [ExplorePost]) {
        for post in canonicalPosts where post.locationSharing != nil && post.locationSharing != .open {
            removePost(id: post.id)
        }
    }

    private func removePosts(where shouldRemove: (ExploreMapPost) -> Bool) {
        let previousCount = posts.count
        posts.removeAll(where: shouldRemove)
        totalCount = max(posts.count, totalCount - (previousCount - posts.count))
    }
}
