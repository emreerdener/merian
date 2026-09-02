import Foundation

/// Stateless Explore browsing requests. Authentication, retries, and decoding
/// remain in the client's shared transport; feature state stays with callers.
extension MerianNetworkClient {
    func getExploreFeed(
        limit: Int = 20,
        filter: ExploreFeedFilter = .recent,
        latitude: Double? = nil,
        longitude: Double? = nil,
        cursor: ExploreFeedCursor? = nil,
        advancedFilters: ExploreFeedAdvancedFilters = ExploreFeedAdvancedFilters(),
        sharedSince: Date? = nil
    ) async throws -> [ExplorePost] {
        var payload: [String: Any] = [
            "limit": limit,
            "filter": filter.rawValue
        ]

        if let latitude {
            payload["latitude"] = latitude
        }

        if let longitude {
            payload["longitude"] = longitude
        }

        if !advancedFilters.speciesCategories.isEmpty {
            payload["species_categories"] = advancedFilters.speciesCategories
                .sorted { $0.sortPriority < $1.sortPriority }
                .map(\.rawValue)
        }

        if !advancedFilters.mediaTypes.isEmpty {
            payload["media_types"] = advancedFilters.mediaTypes
                .map(\.rawValue)
                .sorted()
        }

        if let sharedSince {
            payload["shared_since"] = DateUtilities.iso8601Formatter.string(from: sharedSince)
        }

        if filter == .nearby {
            payload["nearby_radius_miles"] = advancedFilters.nearbyRadius.rawValue
        }

        if let cursor {
            if let beforeSharedAt = cursor.beforeSharedAt,
               let beforePostId = cursor.beforePostId {
                payload["before_shared_at"] = beforeSharedAt
                payload["before_post_id"] = beforePostId
            }

            if let beforeRankingValue = cursor.beforeRankingValue {
                payload["before_ranking_value"] = beforeRankingValue
            }
        }

        return try await performAuthenticatedJSONPost(
            function: "get-explore-feed", payload: payload, responseType: ExploreFeedResponse.self
        ).data
    }

    func getExploreMapPoints(
        northLatitude: Double,
        southLatitude: Double,
        eastLongitude: Double,
        westLongitude: Double,
        zoomLevel: Double,
        limit: Int = 500,
        speciesCategories: Set<ExploreMapSpeciesCategory> = [],
        mediaTypes: Set<ExploreMediaKind> = []
    ) async throws -> ExploreMapPointsResponse {
        var payload: [String: Any] = [
            "north_latitude": northLatitude,
            "south_latitude": southLatitude,
            "east_longitude": eastLongitude,
            "west_longitude": westLongitude,
            "zoom_level": zoomLevel,
            "limit": limit
        ]
        if !speciesCategories.isEmpty {
            payload["species_categories"] = speciesCategories.map(\.rawValue).sorted()
        }
        if !mediaTypes.isEmpty {
            payload["media_types"] = mediaTypes.map(\.rawValue).sorted()
        }
        return try await performAuthenticatedJSONPost(
            function: "get-explore-map-points", payload: payload, responseType: ExploreMapPointsResponse.self
        )
    }

    func getExplorePost(postId: String) async throws -> ExplorePost {
        let payload: [String: Any] = ["post_id": postId]
        return try await performAuthenticatedJSONPost(
            function: "get-explore-post", payload: payload, responseType: ExplorePostResponse.self
        ).data
    }

    func getExplorePostDetail(postId: String) async throws -> ExplorePostDetail {
        let payload: [String: Any] = ["post_id": postId]
        return try await performAuthenticatedJSONPost(
            function: "get-explore-post-detail", payload: payload, responseType: ExplorePostDetailResponse.self
        ).data
    }

    func getExploreAuthorProfile(authorUserId: String, previewLimit: Int = 9) async throws -> ExploreAuthorProfile {
        let payload: [String: Any] = [
            "author_user_id": authorUserId,
            "preview_limit": previewLimit
        ]
        return try await performAuthenticatedJSONPost(
            function: "get-explore-author-profile", payload: payload, responseType: ExploreAuthorProfileResponse.self
        ).data
    }

    func getExploreAuthorPosts(
        authorUserId: String,
        limit: Int = 30,
        cursor: ExploreAuthorPostCursor? = nil
    ) async throws -> ExploreAuthorPostsResponse {
        var payload: [String: Any] = [
            "author_user_id": authorUserId,
            "limit": limit
        ]

        if let cursor,
           let beforeSharedAt = cursor.beforeSharedAt,
           let beforePostId = cursor.beforePostId {
            payload["before_shared_at"] = beforeSharedAt
            payload["before_post_id"] = beforePostId
        }

        return try await performAuthenticatedJSONPost(
            function: "get-explore-author-posts", payload: payload, responseType: ExploreAuthorPostsResponse.self
        )
    }

    func getExploreHashtagPosts(
        hashtag: String,
        limit: Int = 30,
        cursor: ExploreHashtagPostCursor? = nil
    ) async throws -> [ExplorePost] {
        var payload: [String: Any] = [
            "hashtag": hashtag,
            "limit": limit
        ]

        if let cursor,
           let beforeSharedAt = cursor.beforeSharedAt,
           let beforePostId = cursor.beforePostId {
            payload["before_shared_at"] = beforeSharedAt
            payload["before_post_id"] = beforePostId
        }

        return try await performAuthenticatedJSONPost(
            function: "get-explore-hashtag-posts", payload: payload, responseType: ExploreHashtagPostsResponse.self
        ).data
    }

    func getExploreSpeciesPosts(
        speciesId: String,
        limit: Int = 30,
        cursor: ExploreSpeciesPostCursor? = nil
    ) async throws -> ExploreSpeciesPostsResponse {
        var payload: [String: Any] = [
            "species_id": speciesId,
            "limit": limit
        ]

        if let cursor {
            if let imageQualityScore = cursor.imageQualityScore {
                payload["before_image_quality_score"] = imageQualityScore
            }
            payload["before_shared_at"] = cursor.sharedAt
            payload["before_post_id"] = cursor.postId
        }

        return try await performAuthenticatedJSONPost(
            function: "get-explore-species-posts", payload: payload, responseType: ExploreSpeciesPostsResponse.self
        )
    }
}
