import Foundation

/// Direct publication requests. Local-row recovery and media restoration live
/// in `Recovery/` and `Media/`; this owner only maps and validates endpoint IO.
extension MerianNetworkClient {
    func shareScanToExplore(
        scanId: String,
        restoredObjectKeys: [String]? = nil,
        restoredVideoObjectKeys: [String]? = nil,
        restoredAudioObjectKeys: [String]? = nil,
        speciesCommonName: String? = nil,
        fieldNotes: String? = nil,
        hashtags: [String] = [],
        locationSharing: ExplorePostLocationSharing? = nil,
        mediaItems: [ExplorePostMediaSelection]? = nil,
        idempotencyKey: String? = nil,
        recoveryScan: OwnedScanRecoveryPayload? = nil
    ) async throws -> ExploreShareResponse {
        try validateEndpointConfiguration("share-scan-to-explore")
        let resolvedIdempotencyKey = idempotencyKey
            ?? UUID().uuidString.lowercased()
        var payload: [String: Any] = [
            "scan_id": scanId,
            "field_notes": fieldNotes ?? NSNull(),
            "hashtags": hashtags
        ]
        if let mediaItems {
            payload["media_items"] = mediaItems.map(\.jsonObject)
        }
        if let locationSharing {
            payload["location_sharing"] = locationSharing.rawValue
        }
        let trimmedCommonName = speciesCommonName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedCommonName, !trimmedCommonName.isEmpty {
            payload["species_common_name"] = trimmedCommonName
        }
        if let restoredObjectKeys, !restoredObjectKeys.isEmpty {
            payload["restored_object_keys"] = restoredObjectKeys
        }
        if let restoredVideoObjectKeys, !restoredVideoObjectKeys.isEmpty {
            payload["restored_video_object_keys"] = restoredVideoObjectKeys
        }
        if let restoredAudioObjectKeys, !restoredAudioObjectKeys.isEmpty {
            payload["restored_audio_object_keys"] = restoredAudioObjectKeys
        }
        if let recoveryScan {
            let recoveryData = try JSONEncoder().encode(recoveryScan)
            guard let recoveryObject = try JSONSerialization.jsonObject(
                with: recoveryData
            ) as? [String: Any] else {
                throw MerianError.invalidResponse
            }
            payload["recovery_scan"] = recoveryObject
        }

        let decoded: ExploreShareResponse = try await performAuthenticatedJSONPost(
            function: "share-scan-to-explore",
            payload: payload,
            responseType: ExploreShareResponse.self,
            idempotencyKey: resolvedIdempotencyKey,
            decodingFailure: .invalidResponse
        )
        guard decoded.success,
              decoded.scanId.caseInsensitiveCompare(scanId) == .orderedSame,
              UUID(uuidString: decoded.postId) != nil,
              (
                DateUtilities.iso8601FractionalFormatter.date(
                    from: decoded.sharedAt
                )
                    ?? DateUtilities.iso8601Formatter.date(
                        from: decoded.sharedAt
                    )
              ) != nil,
              decoded.locationSharing != nil,
              locationSharing == nil
                || decoded.locationSharing == locationSharing,
              decoded.publicationStatus == "published" else {
            throw MerianError.invalidResponse
        }
        return decoded
    }

    func requestCommunityIdentification(
        scanId: String,
        restoredObjectKeys: [String]? = nil,
        restoredVideoObjectKeys: [String]? = nil,
        restoredAudioObjectKeys: [String]? = nil,
        speciesCommonName: String? = nil,
        note: String? = nil,
        locationSharing: ExplorePostLocationSharing? = nil,
        idempotencyKey: String? = nil
    ) async throws -> CommunityIdentificationRequest {
        try validateEndpointConfiguration("request-community-identification")
        let resolvedIdempotencyKey = idempotencyKey
            ?? UUID().uuidString.lowercased()
        var payload: [String: Any] = [
            "scan_id": scanId,
            "note": note ?? NSNull()
        ]
        if let locationSharing {
            payload["location_sharing"] = locationSharing.rawValue
        }
        let trimmedCommonName = speciesCommonName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedCommonName, !trimmedCommonName.isEmpty {
            payload["species_common_name"] = trimmedCommonName
        }
        if let restoredObjectKeys, !restoredObjectKeys.isEmpty {
            payload["restored_object_keys"] = restoredObjectKeys
        }
        if let restoredVideoObjectKeys, !restoredVideoObjectKeys.isEmpty {
            payload["restored_video_object_keys"] = restoredVideoObjectKeys
        }
        if let restoredAudioObjectKeys, !restoredAudioObjectKeys.isEmpty {
            payload["restored_audio_object_keys"] = restoredAudioObjectKeys
        }

        let decoded: CommunityIdentificationRequestResponse =
            try await performAuthenticatedJSONPost(
                function: "request-community-identification",
                payload: payload,
                responseType: CommunityIdentificationRequestResponse.self,
                idempotencyKey: resolvedIdempotencyKey,
                decodingFailure: .invalidResponse
            )
        let request = decoded.data
        guard decoded.success,
              request.scanId.caseInsensitiveCompare(scanId) == .orderedSame,
              UUID(uuidString: request.id) != nil,
              UUID(uuidString: request.postId) != nil,
              UUID(uuidString: request.requestedBy) != nil,
              request.initialTaxonNodeId.flatMap({
                  UUID(uuidString: $0)
              }) != nil,
              request.taxonomyVersionId.flatMap({
                  UUID(uuidString: $0)
              }) != nil,
              (
                DateUtilities.iso8601FractionalFormatter.date(
                    from: request.requestedAt
                )
                    ?? DateUtilities.iso8601Formatter.date(
                        from: request.requestedAt
                    )
              ) != nil,
              request.status == .needsId,
              request.consensusIdentificationCount >= 0 else {
            throw MerianError.invalidResponse
        }
        return request
    }
}
