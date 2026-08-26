import MapKit

extension ExploreMapViewModel {
    func focus(on target: ExploreMapFocusTarget) {
        debounceSearchTask?.cancel()
        debounceSearchTask = nil
        requestGeneration &+= 1
        responseCache.removeAll()

        selectedSpeciesCategories = []
        selectedMediaTypes = []
        appliedSpeciesCategories = []
        appliedMediaTypes = []

        let post = target.post
        let region = focusedRegion(for: post)
        focusedPost = post
        isAwaitingFocusedCameraCommit = true
        mode = .posts
        clusters = []
        posts = [post]
        selectedPostId = post.id
        visibleCount = 1
        categoryCounts = []
        mediaTypeCounts = []
        errorMessage = nil
        hasServiceUnavailableError = false
        isOffline = false
        needsSearchInArea = false
        visibleRegion = region
        lastCommittedRegion = region
        cameraPosition = .region(region)
    }

    func refreshFocusedArea() async {
        guard focusedPost != nil,
              let region = visibleRegion ?? lastCommittedRegion else { return }
        await fetchMapPoints(for: region, forceRefresh: true)
    }

    func selectPost(_ postId: String?) {
        selectedPostId = postId
    }

    func post(relativeTo postId: String?, by offset: Int) -> ExploreMapPost? {
        guard let postId,
              let currentIndex = visiblePosts.firstIndex(where: { $0.id == postId }) else {
            return nil
        }
        guard let targetIndex = wrappedPostIndex(from: currentIndex, offset: offset) else {
            return nil
        }
        return visiblePosts[targetIndex]
    }

    func post(relativeToSelectedBy offset: Int) -> ExploreMapPost? {
        post(relativeTo: selectedPostId, by: offset)
    }

    @discardableResult
    func selectAdjacentPost(by offset: Int) -> ExploreMapPost? {
        guard let nextPost = post(relativeToSelectedBy: offset) else { return nil }
        selectedPostId = nextPost.id
        return nextPost
    }

    func syncPosts(from canonicalPosts: [ExplorePost]) {
        let canonicalById = Dictionary(
            uniqueKeysWithValues: canonicalPosts.map { ($0.id, $0) }
        )
        let ineligiblePostIds = Set(canonicalPosts.compactMap { post -> String? in
            guard let locationSharing = post.locationSharing,
                  locationSharing != .open else { return nil }
            return post.id
        })

        if !ineligiblePostIds.isEmpty {
            posts.removeAll { ineligiblePostIds.contains($0.id) }
            if let focusedPost, ineligiblePostIds.contains(focusedPost.id) {
                invalidateFocusedPost()
            }
            if let selectedPostId, ineligiblePostIds.contains(selectedPostId) {
                self.selectedPostId = nil
            }
        }

        posts = posts.map { mapPost in
            guard let canonical = canonicalById[mapPost.id] else { return mapPost }
            return ExploreMapPost(
                postId: canonical.postId,
                scanId: canonical.scanId,
                latitude: mapPost.latitude,
                longitude: mapPost.longitude,
                coordinateVisibility: mapPost.coordinateVisibility,
                heroImageUrl: canonical.heroImageUrl,
                referenceThumbnailUrl: canonical.referenceThumbnailUrl ?? mapPost.referenceThumbnailUrl,
                sharedAt: canonical.sharedAt,
                authorUserId: canonical.authorUserId,
                authorName: canonical.authorName,
                authorUsername: canonical.authorUsername,
                authorAvatarUrl: canonical.authorAvatarUrl,
                authorIsPro: canonical.authorIsPro,
                speciesCommonName: canonical.speciesCommonName,
                speciesScientificName: canonical.speciesScientificName,
                petIdentification: canonical.petIdentification,
                taxonomyKingdom: mapPost.taxonomyKingdom,
                taxonomyClass: mapPost.taxonomyClass,
                publicLocationLabel: canonical.publicLocationLabel,
                locationSharing: canonical.locationSharing,
                timeOfDay: canonical.timeOfDay,
                currentMonth: canonical.currentMonth,
                weatherCondition: canonical.weatherCondition,
                weatherTemperatureF: canonical.weatherTemperatureF,
                likeCount: canonical.likeCount,
                commentCount: canonical.commentCount,
                viewerHasLiked: canonical.viewerHasLiked,
                isOwnedByViewer: canonical.isOwnedByViewer,
                mediaItems: canonical.mediaItems?.isEmpty == false
                    ? canonical.mediaItems
                    : mapPost.mediaItems
            )
        }

        if let focusedPost,
           let refreshedFocusedPost = posts.first(where: { $0.id == focusedPost.id }) {
            self.focusedPost = refreshedFocusedPost
        }

        if let selectedPostId,
           !visiblePosts.contains(where: { $0.id == selectedPostId }) {
            self.selectedPostId = nil
        }
    }

    func removePost(id: String) {
        posts.removeAll { $0.id == id }
        if focusedPost?.id == id {
            invalidateFocusedPost()
        }
        if selectedPostId == id {
            selectedPostId = nil
        }
    }

    func removePosts(byAuthorUserId authorUserId: String) {
        let removesSelectedPost = selectedPost?.authorUserId == authorUserId
        if focusedPost?.authorUserId == authorUserId {
            invalidateFocusedPost()
        }
        posts.removeAll { $0.authorUserId == authorUserId }
        if removesSelectedPost {
            selectedPostId = nil
        }
    }

    func invalidateFocusedPost() {
        guard focusedPost != nil else { return }
        focusedPost = nil
        isAwaitingFocusedCameraCommit = false
        requestGeneration &+= 1
        needsForcedRefreshAfterCurrentLoad = false
    }

    private func focusedRegion(for post: ExploreMapPost) -> MKCoordinateRegion {
        let delta = post.coordinateVisibility == .obscured ? 0.2 : 0.05
        return MKCoordinateRegion(
            center: post.coordinate,
            span: MKCoordinateSpan(latitudeDelta: delta, longitudeDelta: delta)
        )
    }

    private func wrappedPostIndex(from startIndex: Int, offset: Int) -> Int? {
        let filteredPosts = visiblePosts
        guard filteredPosts.indices.contains(startIndex) else { return nil }
        guard offset != 0 else { return startIndex }
        guard filteredPosts.count > 1 else { return nil }

        let count = filteredPosts.count
        let rawIndex = (startIndex + offset) % count
        return rawIndex >= 0 ? rawIndex : rawIndex + count
    }
}
