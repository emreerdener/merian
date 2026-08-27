import Foundation
import SwiftUI

private enum ExploreFeedRequestError: LocalizedError {
    case missingNearbyLocation

    var errorDescription: String? {
        switch self {
        case .missingNearbyLocation:
            return "We couldn’t determine your location right now."
        }
    }
}

private struct ExploreFeedRequestContext {
    let filter: ExploreFeedFilter
    let latitude: Double?
    let longitude: Double?
    let cursor: ExploreFeedCursor
    let advancedFilters: ExploreFeedAdvancedFilters
    let sharedSince: Date?
}

extension ExploreFeedViewModel {
    func selectFilter(
        _ filter: ExploreFeedFilter,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async {
        let nextNearbySnapshot = makeNearbyLocationSnapshot(
            filter: filter,
            latitude: latitude,
            longitude: longitude
        )

        let filterChanged = filter != activeFilter
        let locationChanged = nextNearbySnapshot != currentNearbySnapshot()

        guard filterChanged || locationChanged else { return }

        activeFilter = filter
        setNearbyLocationSnapshot(nextNearbySnapshot)
        resetFeedStateForFilterChange()
        await loadInitialFeed(force: true)
    }

    func applyAdvancedFilters(_ filters: ExploreFeedAdvancedFilters) async {
        guard filters != advancedFilters else { return }

        advancedFilters = filters
        resetFeedStateForFilterChange()
        await loadInitialFeed(force: true)
    }

    func resetAdvancedFilters() async {
        await applyAdvancedFilters(ExploreFeedAdvancedFilters())
    }

    func refreshFeed(latitude: Double? = nil, longitude: Double? = nil) async {
        if activeFilter == .nearby {
            setNearbyLocationSnapshot(
                makeNearbyLocationSnapshot(
                    filter: activeFilter,
                    latitude: latitude,
                    longitude: longitude
                )
            )
        }

        activeSharedSince = advancedFilters.dateRange.sharedSince(referenceDate: dependencies.feed.now())

        await loadInitialFeed(force: true)
    }

    func loadInitialFeed(force: Bool = false) async {
        guard force || !hasLoadedFeedOnce else { return }

        if !force, currentInitialFeedRequestId != nil {
            return
        }

        let requestId = UUID()
        activeFeedRequestId = requestId
        currentInitialFeedRequestId = requestId
        isLoadingInitialFeed = true
        if force {
            currentLoadMoreRequestId = nil
            isLoadingMore = false
            errorMessage = nil
        }

        defer {
            if currentInitialFeedRequestId == requestId {
                isLoadingInitialFeed = false
                currentInitialFeedRequestId = nil
            }
        }

        do {
            let request = try makeInitialFeedRequest()
            let freshPosts = try await dependencies.feed.loadPosts(
                feedPageSize,
                request.filter,
                request.latitude,
                request.longitude,
                request.cursor,
                request.advancedFilters,
                request.sharedSince
            )
            let freshFieldTripPublications = FeatureFlags.isEnabled(.fieldTrips)
                ? await loadFieldTripPublicationsForActiveFilter()
                : []

            guard activeFeedRequestId == requestId else { return }

            store.setFeedPosts(freshPosts)
            fieldTripPublications = freshFieldTripPublications
            hasLoadedFeedOnce = true
            hasReachedEndOfFeed = freshPosts.count < feedPageSize
            updateFeedCursor(using: freshPosts)
            errorMessage = nil
            reconcileActiveCommentsPost()

            markRecentFeedSeen(latestSharedAt: freshPosts.first?.sharedAt)
            if isCanonicalRecentFeed {
                ExploreWidgetSnapshotWriter.refreshRecentFeedSnapshot(from: freshPosts)
            }
        } catch is CancellationError {
            // Silently absorb cancellation
        } catch let error as URLError where error.code == .cancelled {
            // Silently absorb URLSession cancellation
        } catch {
            guard activeFeedRequestId == requestId else { return }
            if posts.isEmpty {
                errorMessage = dependencies.errorMessage(error)
            } else {
                toastMessage = .error(dependencies.errorMessage(error))
            }
        }
    }

    func loadMoreIfNeeded(currentPost: ExplorePost) async {
        guard currentInitialFeedRequestId == nil, currentLoadMoreRequestId == nil, !hasReachedEndOfFeed else { return }
        guard let currentIndex = posts.firstIndex(where: { $0.id == currentPost.id }) else { return }

        let triggerIndex = max(posts.count - 5, 0)
        guard currentIndex >= triggerIndex else { return }

        let requestId = activeFeedRequestId
        currentLoadMoreRequestId = requestId
        isLoadingMore = true
        defer {
            if currentLoadMoreRequestId == requestId {
                isLoadingMore = false
                currentLoadMoreRequestId = nil
            }
        }

        do {
            let request = try makePaginatedFeedRequest()
            guard !request.cursor.isEmpty else {
                hasReachedEndOfFeed = true
                return
            }

            let nextPage = try await dependencies.feed.loadPosts(
                feedPageSize,
                request.filter,
                request.latitude,
                request.longitude,
                request.cursor,
                request.advancedFilters,
                request.sharedSince
            )

            guard activeFeedRequestId == requestId else { return }

            appendUniquePosts(nextPage)
            hasReachedEndOfFeed = nextPage.count < feedPageSize
            updateFeedCursor(using: nextPage)
            reconcileActiveCommentsPost()
        } catch is CancellationError {
            // Absorb
        } catch let error as URLError where error.code == .cancelled {
            // Absorb
        } catch {
            guard activeFeedRequestId == requestId else { return }
            toastMessage = .error(dependencies.errorMessage(error))
        }
    }

    func updateFeedCursor(using page: [ExplorePost]) {
        nextFeedCursor = ExploreFeedCursor(
            beforeSharedAt: page.last?.sharedAt,
            beforePostId: page.last?.id,
            beforeRankingValue: activeFilter == .trending ? page.last?.rankingValue : nil
        )
    }

    func appendUniquePosts(_ nextPage: [ExplorePost]) {
        guard !nextPage.isEmpty else { return }

        store.appendUniqueFeedPosts(nextPage)
    }

    private func currentNearbySnapshot() -> ExploreNearbyLocationSnapshot? {
        guard let currentNearbyLatitude, let currentNearbyLongitude else { return nil }
        return ExploreNearbyLocationSnapshot(latitude: currentNearbyLatitude, longitude: currentNearbyLongitude)
    }

    private func makeNearbyLocationSnapshot(
        filter: ExploreFeedFilter,
        latitude: Double?,
        longitude: Double?
    ) -> ExploreNearbyLocationSnapshot? {
        guard filter == .nearby, let latitude, let longitude else { return nil }
        return ExploreNearbyLocationSnapshot(latitude: latitude, longitude: longitude)
    }

    private func setNearbyLocationSnapshot(_ snapshot: ExploreNearbyLocationSnapshot?) {
        nearbyLocationSnapshot = snapshot
    }

    private func resetFeedStateForFilterChange() {
        activeFeedRequestId = UUID()
        currentInitialFeedRequestId = nil
        currentLoadMoreRequestId = nil
        isLoadingInitialFeed = false
        isLoadingMore = false
        errorMessage = nil
        toastMessage = nil
        hasLoadedFeedOnce = false
        hasReachedEndOfFeed = false
        nextFeedCursor = .empty
        activeSharedSince = advancedFilters.dateRange.sharedSince(referenceDate: dependencies.feed.now())
        store.setFeedPosts([])
        fieldTripPublications = []
        dismissComments()
        reconcileActiveCommentsPost()
    }

    private func makeInitialFeedRequest() throws -> ExploreFeedRequestContext {
        if activeFilter == .nearby {
            guard let currentNearbyLatitude, let currentNearbyLongitude else {
                throw ExploreFeedRequestError.missingNearbyLocation
            }

            return ExploreFeedRequestContext(
                filter: .nearby,
                latitude: currentNearbyLatitude,
                longitude: currentNearbyLongitude,
                cursor: .empty,
                advancedFilters: advancedFilters,
                sharedSince: activeSharedSince
            )
        }

        return ExploreFeedRequestContext(
            filter: activeFilter,
            latitude: nil,
            longitude: nil,
            cursor: .empty,
            advancedFilters: advancedFilters,
            sharedSince: activeSharedSince
        )
    }

    private func makePaginatedFeedRequest() throws -> ExploreFeedRequestContext {
        let request = try makeInitialFeedRequest()
        return ExploreFeedRequestContext(
            filter: request.filter,
            latitude: request.latitude,
            longitude: request.longitude,
            cursor: nextFeedCursor,
            advancedFilters: request.advancedFilters,
            sharedSince: request.sharedSince
        )
    }

    private func loadFieldTripPublicationsForActiveFilter() async -> [FieldTripRecentPublication] {
        guard FeatureFlags.isEnabled(.fieldTrips) else { return [] }
        guard !advancedFilters.hasObservationFilters else { return [] }

        let mode: FieldTripCommunityMode
        switch activeFilter {
        case .recent:
            mode = .recent
        case .following:
            mode = .following
        case .trending, .nearby:
            return []
        }

        return (try? await dependencies.feed.loadFieldTripPublications(mode, feedPageSize)) ?? []
    }
}
