import Foundation
@testable import Merian

enum CommunityIdentificationTestError: Error {
    case expected
}

enum CommunityIdentificationTestFixtures {
    static func requestItem(
        index: Int = 0,
        requestedAt: String? = nil
    ) throws -> CommunityIdentificationFeedItem {
        let data = try JSONSerialization.data(withJSONObject: [
            "request_id": "request-\(index)",
            "post_id": "post-\(index)",
            "scan_id": "scan-\(index)",
            "hero_image_url": "https://media.merian.app/request-\(index).webp",
            "requested_at": requestedAt ?? "2026-08-25T12:\(minute(index)):00Z",
            "author_user_id": "author-\(index)",
            "author_name": "Explorer \(index)",
            "identification_count": index,
            "viewer_has_identified": false
        ])
        return try decoder.decode(CommunityIdentificationFeedItem.self, from: data)
    }

    static func activityItem(
        index: Int = 0,
        activityAt: String? = nil
    ) throws -> CommunityIdentificationActivityItem {
        let data = try JSONSerialization.data(withJSONObject: [
            "activity_id": "activity-\(index)",
            "activity_type": "suggestion_burst",
            "request_id": "request-\(index)",
            "post_id": "post-\(index)",
            "scan_id": "scan-\(index)",
            "activity_at": activityAt ?? "2026-08-25T13:\(minute(index)):00Z",
            "suggestion_count": 1,
            "recent_actor_names": ["Explorer \(index)"],
            "media_items": []
        ])
        return try decoder.decode(CommunityIdentificationActivityItem.self, from: data)
    }

    static func detail(
        requestId: String = "request-1",
        authorUserId: String = "author-1"
    ) throws -> CommunityIdentificationDetail {
        let data = try JSONSerialization.data(withJSONObject: [
            "request_id": requestId,
            "post_id": "post-1",
            "scan_id": "scan-1",
            "hero_image_url": "https://media.merian.app/request.webp",
            "requested_at": "2026-08-25T12:00:00Z",
            "status": "needs_id",
            "author_user_id": authorUserId,
            "author_name": "Avery",
            "current_common_name": "Red-tailed Hawk",
            "current_scientific_name": "Buteo jamaicensis",
            "current_rank": "species",
            "current_path": "animalia.chordata.aves.buteo.buteo_jamaicensis",
            "identification_count": 0,
            "identifications": []
        ])
        return try decoder.decode(CommunityIdentificationDetail.self, from: data)
    }

    static func taxon(
        id: String = "taxon-1",
        rank: String = "species"
    ) -> CommunityTaxonSearchResult {
        CommunityTaxonSearchResult(
            taxonId: id,
            taxonomyVersionId: "taxonomy-v1",
            commonName: "Red-tailed Hawk",
            scientificName: "Buteo jamaicensis",
            rank: rank,
            path: "animalia.chordata.aves.buteo.buteo_jamaicensis",
            speciesId: "species-1"
        )
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static func minute(_ index: Int) -> String {
        String(format: "%02d", index % 60)
    }
}
