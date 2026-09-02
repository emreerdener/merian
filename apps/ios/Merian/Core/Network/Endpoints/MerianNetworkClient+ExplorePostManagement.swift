import Foundation

/// Owner-facing Explore reads and post edits. Feature state, publication,
/// uploads, and recovery stay with their existing owners.
extension MerianNetworkClient {
    func getExploreComposerMedia(scanId: String? = nil, postId: String? = nil) async throws -> ExploreComposerMediaPayload {
        var payload: [String: Any] = [:]
        if let scanId {
            payload["scan_id"] = scanId
        }
        if let postId {
            payload["post_id"] = postId
        }
        return try await performAuthenticatedJSONPost(
            function: "get-explore-composer-media",
            payload: payload,
            responseType: ExploreComposerMediaResponse.self
        ).data
    }

    func getExploreShareState(scanId: String) async throws -> ExploreScanShareState {
        let state = try await performAuthenticatedJSONPost(
            function: "get-scan-explore-share-state",
            payload: ["scan_id": scanId],
            responseType: ExploreScanShareStateResponse.self,
            decodingFailure: .invalidResponse
        ).data
        let postId = state.postId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let communityRequestId = state.communityRequestId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sharedAt = state.sharedAt.flatMap { value in
            DateUtilities.iso8601FractionalFormatter.date(from: value) ??
                DateUtilities.iso8601Formatter.date(from: value)
        }
        let hasPost = postId.flatMap { UUID(uuidString: $0) } != nil
        let hasCommunityRequest =
            communityRequestId.flatMap { UUID(uuidString: $0) } != nil
        let hasCommunityStatus = state.communityRequestStatus != nil

        // A valid post can be server-hidden without a Community request when
        // media is quarantined or the post is moderated. Visibility remains an
        // authoritative required field; only a visible-without-post claim is
        // structurally impossible.
        guard state.scanId.caseInsensitiveCompare(scanId) == .orderedSame,
              state.locationSharing != nil,
              hasPost == (state.postId != nil),
              hasPost == (state.sharedAt != nil),
              !hasPost || sharedAt != nil,
              hasCommunityRequest == (state.communityRequestId != nil),
              hasCommunityRequest == hasCommunityStatus,
              !hasCommunityRequest || hasPost,
              !state.isExploreFeedVisible || hasPost,
              !state.isExploreFeedVisible ||
                state.communityRequestStatus != .needsId,
              hasPost || (
                !state.isExploreFeedVisible &&
                !hasCommunityRequest
              ) else {
            throw MerianError.invalidResponse
        }
        return state
    }

    func getExploreMediaIncidents() async throws -> [ExploreMediaIncident] {
        try await performAuthenticatedJSONPost(
            function: "get-explore-media-incidents",
            payload: [:],
            responseType: ExploreMediaIncidentsResponse.self,
            decodingFailure: .invalidResponse
        ).data
    }

    func unshareExplorePost(postId: String) async throws {
        try await performAuthenticatedJSONPost(
            function: "unshare-explore-post",
            payload: ["post_id": postId]
        )
    }

    func updateExplorePostFieldNotes(postId: String, fieldNotes: String?) async throws -> ExploreUpdateFieldNotesResponse {
        let payload: [String: Any] = [
            "post_id": postId,
            "field_notes": fieldNotes ?? NSNull()
        ]
        return try await performAuthenticatedJSONPost(
            function: "update-explore-field-notes",
            payload: payload,
            responseType: ExploreUpdateFieldNotesResponse.self
        )
    }

    func updateExplorePostContent(
        postId: String,
        speciesCommonName: String? = nil,
        fieldNotes: String?,
        hashtags: [String],
        locationSharing: ExplorePostLocationSharing,
        mediaItems: [ExplorePostMediaSelection]? = nil
    ) async throws -> ExploreUpdateFieldNotesResponse {
        var payload: [String: Any] = [
            "post_id": postId,
            "field_notes": fieldNotes ?? NSNull(),
            "hashtags": hashtags,
            "location_sharing": locationSharing.rawValue
        ]
        if let mediaItems {
            payload["media_items"] = mediaItems.map(\.jsonObject)
        }
        let trimmedCommonName = speciesCommonName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedCommonName, !trimmedCommonName.isEmpty {
            payload["species_common_name"] = trimmedCommonName
        }
        return try await performAuthenticatedJSONPost(
            function: "update-explore-field-notes",
            payload: payload,
            responseType: ExploreUpdateFieldNotesResponse.self,
            idempotencyKey: UUID().uuidString.lowercased()
        )
    }
}
