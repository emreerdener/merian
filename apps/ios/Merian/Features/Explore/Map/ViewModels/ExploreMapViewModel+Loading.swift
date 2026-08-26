import Foundation
import MapKit

extension ExploreMapViewModel {
    func fetchMapPoints(
        for region: MKCoordinateRegion,
        forceRefresh: Bool = false
    ) async {
        guard !isLoading else {
            needsRefreshAfterCurrentLoad = true
            needsForcedRefreshAfterCurrentLoad = needsForcedRefreshAfterCurrentLoad || forceRefresh
            return
        }

        let now = dependencies.now()
        let fetchGeneration = requestGeneration
        let requestedSpeciesCategories = selectedSpeciesCategories
        let requestedMediaTypes = selectedMediaTypes

        if !forceRefresh,
           let cached = responseCache.cachedResponse(
               for: region,
               speciesCategories: requestedSpeciesCategories,
               mediaTypes: requestedMediaTypes,
               now: now
           ) {
            apply(
                response: cached.response,
                for: region,
                speciesCategories: cached.speciesCategories,
                mediaTypes: cached.mediaTypes
            )
            if cached.isFresh {
                return
            }
        }

        isLoading = true
        defer {
            isLoading = false

            if needsRefreshAfterCurrentLoad {
                needsRefreshAfterCurrentLoad = false
                let forceQueuedRefresh = needsForcedRefreshAfterCurrentLoad
                needsForcedRefreshAfterCurrentLoad = false
                let refreshRegion = visibleRegion ?? region
                Task { @MainActor [weak self] in
                    await self?.fetchMapPoints(
                        for: refreshRegion,
                        forceRefresh: forceQueuedRefresh
                    )
                }
            }
        }

        do {
            let response = try await dependencies.loadPoints(
                ExploreMapPointsRequest(
                    region: region,
                    zoomLevel: ExploreMapCameraPolicy.zoomLevel(for: region),
                    limit: maxPostLimit,
                    speciesCategories: requestedSpeciesCategories,
                    mediaTypes: requestedMediaTypes
                )
            )
            guard fetchGeneration == requestGeneration else { return }
            responseCache.store(
                response,
                for: region,
                speciesCategories: requestedSpeciesCategories,
                mediaTypes: requestedMediaTypes,
                now: now
            )
            apply(
                response: response,
                for: region,
                speciesCategories: requestedSpeciesCategories,
                mediaTypes: requestedMediaTypes
            )
        } catch let error as MerianError {
            guard fetchGeneration == requestGeneration else { return }
            applyMerianError(error)
        } catch let urlError as URLError {
            guard fetchGeneration == requestGeneration else { return }
            applyURLError(urlError)
        } catch let decodingError as DecodingError {
            guard fetchGeneration == requestGeneration else { return }
#if DEBUG
            MerianLog.network.error(
                "Explore map response decoding failed: \(String(describing: decodingError), privacy: .public)"
            )
#endif
            applyGenericLoadFailure(message: "Something went wrong. Please try again.")
        } catch {
            guard fetchGeneration == requestGeneration else { return }
            applyGenericLoadFailure(message: ExploreErrorFormatter.message(for: error))
        }
    }

    private func apply(
        response: ExploreMapPointsResponse,
        for region: MKCoordinateRegion,
        speciesCategories: Set<ExploreMapSpeciesCategory>,
        mediaTypes: Set<ExploreMediaKind>
    ) {
        mode = response.mode
        clusters = response.clusters
        var nextPosts = Array(response.posts.prefix(maxPostLimit))

        if let focusedPost {
            if response.mode == .clusters,
               region.containsForExploreMap(focusedPost.coordinate),
               !nextPosts.contains(where: { $0.id == focusedPost.id }) {
                if nextPosts.count == maxPostLimit {
                    nextPosts.removeLast()
                }
                nextPosts.append(focusedPost)
            } else if response.mode == .posts {
                if let authoritativePost = nextPosts.first(where: { $0.id == focusedPost.id }) {
                    self.focusedPost = authoritativePost
                } else {
                    let focusedPostId = focusedPost.id
                    invalidateFocusedPost()
                    if selectedPostId == focusedPostId {
                        selectedPostId = nil
                    }
                }
            }
        }

        posts = nextPosts
        visibleCount = max(response.visibleCount, nextPosts.count)
        categoryCounts = response.categoryCounts
        mediaTypeCounts = response.mediaTypeCounts
        appliedSpeciesCategories = speciesCategories
        appliedMediaTypes = mediaTypes
        errorMessage = nil
        hasServiceUnavailableError = false
        isOffline = false
        needsSearchInArea = false

        if focusedPost != nil,
           !isAwaitingFocusedCameraCommit,
           let visibleRegion {
            lastCommittedRegion = visibleRegion
        } else {
            lastCommittedRegion = region
        }

        if let selectedPostId,
           !visiblePosts.contains(where: { $0.id == selectedPostId }) {
            self.selectedPostId = nil
        }
    }

    private func applyMerianError(_ error: MerianError) {
        if case .httpError(let statusCode, _) = error, statusCode == 503 {
            hasServiceUnavailableError = true
            errorMessage = nil
        } else {
            hasServiceUnavailableError = false
            errorMessage = hasNoRenderedResults
                ? ExploreErrorFormatter.message(for: error)
                : nil
        }
        isOffline = false
    }

    private func applyURLError(_ error: URLError) {
        if isOfflineError(error) {
            isOffline = true
            hasServiceUnavailableError = false
            errorMessage = hasNoRenderedResults
                ? "You’re offline. Reconnect to load discoveries on the map."
                : nil
        } else {
            isOffline = false
            hasServiceUnavailableError = false
            errorMessage = hasNoRenderedResults
                ? ExploreErrorFormatter.message(for: error)
                : nil
        }
    }

    private func applyGenericLoadFailure(message: String) {
        isOffline = false
        hasServiceUnavailableError = false
        errorMessage = hasNoRenderedResults ? message : nil
    }

    private var hasNoRenderedResults: Bool {
        posts.isEmpty && clusters.isEmpty
    }

    private func isOfflineError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}
