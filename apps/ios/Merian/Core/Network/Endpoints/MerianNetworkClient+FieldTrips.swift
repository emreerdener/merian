import Foundation

/// Wire operations shared by Field Trips and its cross-feature consumers.
/// Feature Services retain presentation policy; the client retains transport.
extension MerianNetworkClient {

    // MARK: - Outings

    func getFieldTrips(userRegion: String? = nil, limit: Int = 40) async throws -> [FieldTripTemplate] {
        var payload: [String: Any] = [
            "action": "catalog",
            "limit": limit
        ]
        if let userRegion = userRegion?.trimmedNonEmptyValue {
            payload["user_region"] = userRegion
        }

        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripsCatalogResponse.self
        ).data
    }

    func getFieldTripCaptureContext() async throws -> [FieldTripCaptureOuting] {
        let payload: [String: Any] = [
            "action": "capture_context"
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripCaptureContextResponse.self
        ).data
    }

    func getFirstFieldTripAchievementProgress() async throws -> FirstFieldTripAchievementProgress? {
        let payload: [String: Any] = [
            "action": "achievement_progress"
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FirstFieldTripAwardResponse.self
        ).data
    }

    func getFieldTripTemplate(templateId: String) async throws -> FieldTripTemplate {
        try await getFieldTripTemplate(identifier: ["template_id": templateId])
    }

    func getFieldTripTemplate(slug: String) async throws -> FieldTripTemplate {
        try await getFieldTripTemplate(identifier: ["slug": slug])
    }

    private func getFieldTripTemplate(identifier: [String: String]) async throws -> FieldTripTemplate {
        var payload = identifier
        payload["action"] = "template_detail"
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripTemplateDetailResponse.self
        ).data
    }

    func startFieldTrip(templateId: String) async throws -> FieldTripTemplate {
        let payload: [String: Any] = [
            "action": "start",
            "template_id": templateId
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripStartResponse.self
        ).data
    }

    func stopFieldTrip(userFieldTripId: String) async throws -> FieldTripTemplate {
        try await updateFieldTripLifecycle(
            action: "stop",
            userFieldTripId: userFieldTripId
        )
    }

    func resetFieldTrip(userFieldTripId: String) async throws -> FieldTripTemplate {
        try await updateFieldTripLifecycle(
            action: "reset",
            userFieldTripId: userFieldTripId
        )
    }

    private func updateFieldTripLifecycle(
        action: String,
        userFieldTripId: String
    ) async throws -> FieldTripTemplate {
        let payload: [String: Any] = [
            "action": action,
            "user_field_trip_id": userFieldTripId
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripTemplateDetailResponse.self
        ).data
    }

    // MARK: - Events

    func getFieldTripChallenges(userRegion: String? = nil, limit: Int = 20) async throws -> [FieldTripChallenge] {
        var payload: [String: Any] = [
            "action": "challenges_catalog",
            "limit": limit
        ]
        if let userRegion = userRegion?.trimmedNonEmptyValue {
            payload["user_region"] = userRegion
        }

        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripChallengesCatalogResponse.self
        ).data
    }

    func getFieldTripChallenge(challengeId: String, entriesLimit: Int = 12) async throws -> FieldTripChallenge {
        let payload: [String: Any] = [
            "action": "challenge_detail",
            "challenge_id": challengeId,
            "entries_limit": entriesLimit
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripChallengeDetailResponse.self
        ).data
    }

    func joinFieldTripChallenge(challengeId: String) async throws -> FieldTripChallenge {
        let payload: [String: Any] = [
            "action": "join_challenge",
            "challenge_id": challengeId
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripChallengeDetailResponse.self
        ).data
    }

    // MARK: - Community Publications

    func getRecentFieldTripPublications(
        userRegion: String? = nil,
        habitatTags: [String] = [],
        limit: Int = 20,
        beforePublishedAt: String? = nil,
        beforePublicationId: String? = nil
    ) async throws -> [FieldTripRecentPublication] {
        try await getFieldTripCommunityPublications(
            mode: .recent,
            userRegion: userRegion,
            habitatTags: habitatTags,
            limit: limit,
            beforeRankBucket: beforePublishedAt == nil ? nil : 0,
            beforePublishedAt: beforePublishedAt,
            beforePublicationId: beforePublicationId
        )
    }

    func getFieldTripCommunityPublications(
        mode: FieldTripCommunityMode = .smart,
        templateId: String? = nil,
        userRegion: String? = nil,
        habitatTags: [String] = [],
        seasonTags: [String] = [],
        limit: Int = 20,
        beforeRankBucket: Int? = nil,
        beforePublishedAt: String? = nil,
        beforePublicationId: String? = nil
    ) async throws -> [FieldTripRecentPublication] {
        var payload: [String: Any] = [
            "action": "community_publications",
            "mode": mode.rawValue,
            "limit": limit
        ]
        if let templateId = templateId?.trimmedNonEmptyValue {
            payload["template_id"] = templateId
        }
        if let userRegion = userRegion?.trimmedNonEmptyValue {
            payload["user_region"] = userRegion
        }
        let trimmedHabitatTags = habitatTags.compactMap {
            $0.trimmedNonEmptyValue
        }
        if !trimmedHabitatTags.isEmpty {
            payload["habitat_tags"] = trimmedHabitatTags
        }
        let trimmedSeasonTags = seasonTags.compactMap {
            $0.trimmedNonEmptyValue
        }
        if !trimmedSeasonTags.isEmpty {
            payload["season_tags"] = trimmedSeasonTags
        }
        if let beforeRankBucket, let beforePublishedAt, let beforePublicationId {
            payload["before_rank_bucket"] = beforeRankBucket
            payload["before_published_at"] = beforePublishedAt
            payload["before_publication_id"] = beforePublicationId
        }

        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripCommunityPublicationsResponse.self
        ).data
    }

    // MARK: - Scan Progress

    func applyFieldTripProgress(
        scanId: String,
        preferredGoal: FieldTripPreferredGoal? = nil
    ) async throws -> FieldTripProgressResult {
        var payload: [String: Any] = [
            "action": "apply_scan_progress",
            "scan_id": scanId
        ]
        if let preferredGoal {
            payload["preferred_goal"] = [
                "user_field_trip_id": preferredGoal.userFieldTripId,
                "item_id": preferredGoal.itemId
            ]
        }
        let response = try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripProgressUpdatesResponse.self,
            timeoutInterval: 15.0
        )
        return FieldTripProgressResult(
            fieldTripUpdates: response.data,
            challengeUpdates: response.challengeUpdates,
            firstFieldTripAchievement: response.firstFieldTripAchievement,
            firstFieldTripAchievementNewlyUnlocked:
                response.firstFieldTripAchievementNewlyUnlocked
        )
    }

    func getFieldTripScanContributions(scanId: String) async throws -> [FieldTripScanContribution] {
        let payload: [String: Any] = [
            "action": "scan_contributions",
            "scan_id": scanId
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripScanContributionsResponse.self,
            timeoutInterval: 15.0
        )
            .data
    }

    func getFieldTripChallengeHashtags(scanId: String) async throws -> [String] {
        let payload: [String: Any] = [
            "action": "scan_challenge_hashtags",
            "scan_id": scanId
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripChallengeHashtagsResponse.self
        ).data
    }

    // MARK: - Profile

    func getFieldTripProfileSummaries(authorUserId: String, limit: Int = 6) async throws -> FieldTripProfileSummaries {
        let payload: [String: Any] = [
            "action": "profile_summaries",
            "author_user_id": authorUserId,
            "limit": limit
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripProfileSummariesResponse.self
        ).data
    }

    func setPinnedFieldTripPublications(publicationIds: [String]) async throws -> FieldTripProfileSummaries {
        let payload: [String: Any] = [
            "action": "set_pinned_publications",
            "publication_ids": Array(publicationIds.prefix(3))
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripSetPinnedPublicationsResponse.self
        ).data
    }

    // MARK: - Publication and Entry Interactions

    func publishFieldTrip(
        userFieldTripId: String,
        title: String? = nil,
        description: String? = nil,
        aiSummary: String? = nil
    ) async throws -> FieldTripPublicationDetail {
        var payload: [String: Any] = [
            "action": "publish",
            "user_field_trip_id": userFieldTripId
        ]
        payload["title"] = title ?? NSNull()
        payload["description"] = description ?? NSNull()
        payload["ai_summary"] = aiSummary ?? NSNull()

        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripPublicationDetailResponse.self
        ).data
    }

    func getFieldTripChallengePublications(
        challengeId: String,
        limit: Int = 20,
        beforePublishedAt: String? = nil,
        beforeEntryId: String? = nil
    ) async throws -> [FieldTripChallengeEntry] {
        var payload: [String: Any] = [
            "action": "challenge_publications",
            "challenge_id": challengeId,
            "limit": limit
        ]
        if let beforePublishedAt, let beforeEntryId {
            payload["before_published_at"] = beforePublishedAt
            payload["before_entry_id"] = beforeEntryId
        }

        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripChallengePublicationsResponse.self
        ).data
    }

    func publishFieldTripChallengeEntry(
        participationId: String,
        title: String? = nil,
        description: String? = nil
    ) async throws -> FieldTripChallengeEntryDetail {
        var payload: [String: Any] = [
            "action": "publish_challenge_entry",
            "participation_id": participationId
        ]
        payload["title"] = title ?? NSNull()
        payload["description"] = description ?? NSNull()

        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripChallengeEntryDetailResponse.self
        ).data
    }

    func getFieldTripChallengeEntry(entryId: String) async throws -> FieldTripChallengeEntryDetail {
        let payload: [String: Any] = [
            "action": "challenge_entry_detail",
            "entry_id": entryId
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripChallengeEntryDetailResponse.self
        ).data
    }

    func getFieldTripPublication(publicationId: String) async throws -> FieldTripPublicationDetail {
        let payload: [String: Any] = [
            "action": "detail",
            "publication_id": publicationId
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripPublicationDetailResponse.self
        ).data
    }

    func setFieldTripLike(publicationId: String, liked: Bool) async throws -> FieldTripLikeResponse {
        let payload: [String: Any] = [
            "action": "set_like",
            "publication_id": publicationId,
            "liked": liked
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripLikeResponse.self
        )
    }

    func setFieldTripChallengeEntryLike(entryId: String, liked: Bool) async throws -> FieldTripChallengeEntryLikeResponse {
        let payload: [String: Any] = [
            "action": "set_challenge_entry_like",
            "entry_id": entryId,
            "liked": liked
        ]
        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripChallengeEntryLikeResponse.self
        )
    }

    func getFieldTripComments(
        publicationId: String,
        limit: Int = 100,
        afterCreatedAt: String? = nil,
        afterCommentId: String? = nil
    ) async throws -> [ExploreComment] {
        var payload: [String: Any] = [
            "action": "comments",
            "publication_id": publicationId,
            "limit": limit
        ]

        if let afterCreatedAt, let afterCommentId {
            payload["after_created_at"] = afterCreatedAt
            payload["after_comment_id"] = afterCommentId
        }

        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripCommentsResponse.self
        ).data
    }

    func getFieldTripChallengeEntryComments(
        entryId: String,
        limit: Int = 100,
        afterCreatedAt: String? = nil,
        afterCommentId: String? = nil
    ) async throws -> [ExploreComment] {
        var payload: [String: Any] = [
            "action": "challenge_entry_comments",
            "entry_id": entryId,
            "limit": limit
        ]

        if let afterCreatedAt, let afterCommentId {
            payload["after_created_at"] = afterCreatedAt
            payload["after_comment_id"] = afterCommentId
        }

        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripCommentsResponse.self
        ).data
    }

    func createFieldTripComment(
        publicationId: String,
        body: String,
        parentCommentId: String? = nil
    ) async throws -> FieldTripCreateCommentResponse {
        var payload: [String: Any] = [
            "action": "create_comment",
            "publication_id": publicationId,
            "body": body
        ]
        if let parentCommentId {
            payload["parent_comment_id"] = parentCommentId
        }

        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripCreateCommentResponse.self
        )
    }

    func createFieldTripChallengeEntryComment(
        entryId: String,
        body: String,
        parentCommentId: String? = nil
    ) async throws -> FieldTripCreateCommentResponse {
        var payload: [String: Any] = [
            "action": "create_challenge_entry_comment",
            "entry_id": entryId,
            "body": body
        ]
        if let parentCommentId {
            payload["parent_comment_id"] = parentCommentId
        }

        return try await performAuthenticatedJSONPost(
            function: "field-trips",
            payload: payload,
            responseType: FieldTripCreateCommentResponse.self
        )
    }
}
