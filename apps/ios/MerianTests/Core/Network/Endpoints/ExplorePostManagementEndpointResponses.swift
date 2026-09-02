import Foundation

/// Synthetic wire fixtures only; no URLs are fetched by these tests.
enum ExplorePostManagementEndpointResponses {
    static let scanID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    static let postID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    static let requestID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

    static let composer = """
    {"data":{"scan_id":"server-scan","post_id":"server-post","media_items":[
      {"source_media_id":"audio-source","kind":"audio","url":"https://media.example.test/clip.wav",
       "thumbnail_url":"","order_index":8,"is_selected":false,"selection_order_index":null},
      {"source_media_id":"video-source","kind":"video","url":"https://media.example.test/clip.mp4",
       "thumbnail_url":"https://media.example.test/poster.webp","order_index":2,
       "is_selected":true,"selection_order_index":0},
      {"source_media_id":"image-source","kind":"image","url":"https://media.example.test/image.webp",
       "thumbnail_url":"https://media.example.test/image.webp","order_index":4}
    ]}}
    """

    static let edit = """
    {"success":false,"post_id":"server-post","field_notes":"  Server notes  ",
     "hashtags":["server","tags"],"species_common_name":"Server name","location_sharing":"private"}
    """

    static let incidentsArray = """
    [
      {"post_id":"quarantined-post","scan_id":"quarantined-scan","species_common_name":"Test species",
       "media_health_status":"quarantined","missing_media_count":2,"total_media_count":2,
       "media_quarantined_at":"2026-07-26T12:00:00Z","media_health_updated_at":"2026-07-26T12:01:00Z",
       "missing_media_urls":["https://media.example.test/two.webp","https://media.example.test/one.webp"]},
      {"post_id":"degraded-post","scan_id":"degraded-scan","species_common_name":null,
       "media_health_status":"degraded","missing_media_count":1,"total_media_count":3,
       "media_quarantined_at":null,"media_health_updated_at":"2026-07-26T11:00:00Z",
       "missing_media_urls":["https://media.example.test/missing.wav"]}
    ]
    """

    static let incidents = #"{"data":\#(incidentsArray)}"#

    static func shareState(
        scanID: String = scanID,
        postID: String? = postID,
        sharedAt: String? = "2026-04-29T22:18:03.000Z",
        requestID: String? = nil,
        requestStatus: String? = nil,
        visible: Bool = true,
        location: String? = "open"
    ) throws -> String {
        // Build independent response variants without weakening production DTOs.
        let values: [String: Any] = [
            "scan_id": scanID, "post_id": postID ?? NSNull(), "shared_at": sharedAt ?? NSNull(),
            "community_request_id": requestID ?? NSNull(), "community_request_status": requestStatus ?? NSNull(),
            "is_explore_feed_visible": visible, "location_sharing": location ?? NSNull()
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["data": values]), as: UTF8.self)
    }

    static let shared = """
    {"data":{"scan_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "post_id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","shared_at":"2026-04-29T22:18:03.000Z",
      "community_request_id":null,"community_request_status":null,
      "is_explore_feed_visible":true,"location_sharing":"open"}}
    """
}
