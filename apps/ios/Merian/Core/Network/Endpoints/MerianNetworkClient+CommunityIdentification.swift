import Foundation

// Community request browsing and contributions share the authenticated JSON transport.
// Scan publication and its media-recovery orchestration remain in the main client.
extension MerianNetworkClient {
    func getCommunityIdentificationFeed(
        limit: Int = 30,
        scope: CommunityIdentificationFeedScope = .all,
        group: CommunityIdentificationRequestGroup = .all,
        latitude: Double? = nil,
        longitude: Double? = nil,
        cursor: CommunityIdentificationCursor? = nil
    ) async throws -> [CommunityIdentificationFeedItem] {
        var payload: [String: Any] = [
            "limit": limit,
            "scope": scope.rawValue,
            "group": group.rawValue
        ]

        if let latitude {
            payload["latitude"] = latitude
        }

        if let longitude {
            payload["longitude"] = longitude
        }

        if let cursor,
           let beforeRequestedAt = cursor.beforeRequestedAt,
           let beforeRequestId = cursor.beforeRequestId {
            payload["before_requested_at"] = beforeRequestedAt
            payload["before_request_id"] = beforeRequestId
        }

        return try await performAuthenticatedJSONPost(
            function: "get-community-identification-feed",
            payload: payload,
            responseType: CommunityIdentificationFeedResponse.self
        ).data
    }

    func getCommunityIdentificationActivity(
        limit: Int = 30,
        scope: CommunityIdentificationFeedScope = .all,
        group: CommunityIdentificationRequestGroup = .all,
        cursor: CommunityIdentificationActivityCursor? = nil
    ) async throws -> [CommunityIdentificationActivityItem] {
        var payload: [String: Any] = [
            "limit": limit,
            "scope": scope.rawValue,
            "group": group.rawValue
        ]

        if let cursor,
           let beforeActivityAt = cursor.beforeActivityAt,
           let beforeActivityId = cursor.beforeActivityId {
            payload["before_activity_at"] = beforeActivityAt
            payload["before_activity_id"] = beforeActivityId
        }

        return try await performAuthenticatedJSONPost(
            function: "get-community-identification-activity",
            payload: payload,
            responseType: CommunityIdentificationActivityResponse.self
        ).data
    }

    func getCommunityIdentificationDetail(requestId: String) async throws -> CommunityIdentificationDetail {
        let payload: [String: Any] = ["request_id": requestId]
        return try await performAuthenticatedJSONPost(
            function: "get-community-identification-detail",
            payload: payload,
            responseType: CommunityIdentificationDetailResponse.self
        ).data
    }

    func updateCommunityIdentificationRequest(
        requestId: String,
        note: String?,
        locationSharing: ExplorePostLocationSharing
    ) async throws -> CommunityRequestUpdate {
        let payload: [String: Any] = [
            "request_id": requestId,
            "note": note ?? NSNull(),
            "location_sharing": locationSharing.rawValue
        ]
        return try await performAuthenticatedJSONPost(
            function: "update-community-identification-request",
            payload: payload,
            responseType: CommunityRequestUpdateResponse.self
        ).data
    }

    func searchCommunityTaxa(
        query: String,
        limit: Int = 20,
        taxonomyVersionId: String? = nil
    ) async throws -> [CommunityTaxonSearchResult] {
        var payload: [String: Any] = [
            "query": query,
            "limit": limit
        ]
        if let taxonomyVersionId {
            payload["taxonomy_version_id"] = taxonomyVersionId
        }
        return try await performAuthenticatedJSONPost(
            function: "search-community-taxa",
            payload: payload,
            responseType: CommunityTaxonSearchResponse.self
        ).data
    }

    func submitCommunityIdentification(
        requestId: String,
        taxonId: String,
        disagreementMode: CommunityIdentificationDisagreementMode,
        reasoning: String?,
        isGenusBestPossible: Bool
    ) async throws -> CommunityIdentificationMutation {
        var payload: [String: Any] = [
            "request_id": requestId,
            "taxon_id": taxonId,
            "disagreement_mode": disagreementMode.rawValue,
            "is_genus_best_possible": isGenusBestPossible
        ]
        payload["reasoning"] = reasoning ?? NSNull()
        return try await performAuthenticatedJSONPost(
            function: "submit-community-identification",
            payload: payload,
            responseType: CommunityIdentificationMutationResponse.self
        ).data
    }

    func withdrawCommunityIdentification(identificationId: String) async throws -> CommunityIdentificationMutation {
        let payload: [String: Any] = ["identification_id": identificationId]
        return try await performAuthenticatedJSONPost(
            function: "withdraw-community-identification",
            payload: payload,
            responseType: CommunityIdentificationMutationResponse.self
        ).data
    }

    func restoreCommunityIdentification(identificationId: String) async throws -> CommunityIdentificationMutation {
        let payload: [String: Any] = ["identification_id": identificationId]
        return try await performAuthenticatedJSONPost(
            function: "restore-community-identification",
            payload: payload,
            responseType: CommunityIdentificationMutationResponse.self
        ).data
    }
}
