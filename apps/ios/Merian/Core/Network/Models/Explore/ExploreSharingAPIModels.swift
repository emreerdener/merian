import Foundation

struct ExploreScanShareStateResponse: Decodable {
    let data: ExploreScanShareState
}

struct ExploreShareResponse: Decodable {
    let success: Bool
    let postId: String
    let scanId: String
    let sharedAt: String
    let locationSharing: ExplorePostLocationSharing?
    let publicationStatus: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case postId
        case scanId
        case sharedAt
        case locationSharing
        case publicationStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        postId = try container.decode(String.self, forKey: .postId)
        scanId = try container.decode(String.self, forKey: .scanId)
        sharedAt = try container.decode(String.self, forKey: .sharedAt)
        publicationStatus = try container.decodeIfPresent(
            String.self,
            forKey: .publicationStatus
        )
        locationSharing = try Self.decodeStrictLocationSharing(
            from: container,
            forKey: .locationSharing
        )
    }

    private static func decodeStrictLocationSharing(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> ExplorePostLocationSharing? {
        guard let rawValue = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        if rawValue.caseInsensitiveCompare("hidden") == .orderedSame {
            return .privateLocation
        }
        guard let value = ExplorePostLocationSharing(rawValue: rawValue.lowercased()) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unknown Explore location-sharing value."
            )
        }
        return value
    }
}

struct ExploreScanShareState: Decodable, Equatable {
    let scanId: String
    let postId: String?
    let sharedAt: String?
    let communityRequestId: String?
    let communityRequestStatus: CommunityIdentificationRequestStatus?
    let isExploreFeedVisible: Bool
    let locationSharing: ExplorePostLocationSharing?

    private enum CodingKeys: String, CodingKey {
        case scanId
        case postId
        case sharedAt
        case communityRequestId
        case communityRequestStatus
        case isExploreFeedVisible
        case locationSharing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanId = try container.decode(String.self, forKey: .scanId)
        postId = try container.decodeIfPresent(String.self, forKey: .postId)
        sharedAt = try container.decodeIfPresent(String.self, forKey: .sharedAt)
        communityRequestId = try container.decodeIfPresent(String.self, forKey: .communityRequestId)
        communityRequestStatus = try container.decodeIfPresent(
            CommunityIdentificationRequestStatus.self,
            forKey: .communityRequestStatus
        )
        isExploreFeedVisible = try container.decode(
            Bool.self,
            forKey: .isExploreFeedVisible
        )
        guard let rawLocation = try container.decodeIfPresent(
            String.self,
            forKey: .locationSharing
        ) else {
            locationSharing = nil
            return
        }
        if rawLocation.caseInsensitiveCompare("hidden") == .orderedSame {
            locationSharing = .privateLocation
        } else if let value = ExplorePostLocationSharing(
            rawValue: rawLocation.lowercased()
        ) {
            locationSharing = value
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .locationSharing,
                in: container,
                debugDescription: "Unknown Explore location-sharing value."
            )
        }
    }
}

struct ExploreLikeResponse: Decodable {
    let success: Bool
    let postId: String
    let viewerHasLiked: Bool
    let likeCount: Int
}

struct ExploreCreateCommentResponse: Decodable {
    let success: Bool
    let comment: ExploreComment
    let commentCount: Int
}

struct ExploreDeleteCommentResponse: Decodable {
    let success: Bool
    let commentId: String
    let commentCount: Int
    let action: String
}

struct ExploreUpdateFieldNotesResponse: Decodable {
    let success: Bool
    let postId: String
    let fieldNotes: String?
    let hashtags: [String]?
    let speciesCommonName: String?
    let locationSharing: ExplorePostLocationSharing?
}
