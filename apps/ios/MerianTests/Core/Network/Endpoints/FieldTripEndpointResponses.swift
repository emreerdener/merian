import Foundation

/// Synthetic wire fixtures. DTO edge cases remain in FieldTripAPIModelsTests.
enum FieldTripEndpointResponses {
    static let empty = #"{"data":[]}"#
    static let achievement = #"{"data":null}"#
    static let profile = #"{"data":{"active":[],"pinned":[],"published":[],"challenge_badges":[]}}"#
    static let hashtags = #"{"data":["fieldnotes"]}"#

    static let template = """
    {"data":{
      "template_id":"template","slug":"outing","title":"Outing",
      "region_tags":[],"season_tags":[],"habitat_tags":[],"difficulty":"easy",
      "is_pro_only":false,"is_rotating_free":true,"viewer_has_access":true,
      "access_kind":"free","levels":[]
    }}
    """

    static let challenge = """
    {"data":{
      "challenge_id":"event","template_id":"template","slug":"event","title":"Event",
      "starts_at":"2026-09-01T00:00:00Z","ends_at":"2026-10-01T00:00:00Z","status":"live"
    }}
    """

    // The two publication DTOs share these fields but keep distinct IDs and types.
    static let publication = """
    {"data":{
      "publication_id":"publication","user_field_trip_id":"trip",
      "entry_id":"entry","participation_id":"participation",
      "challenge_id":"event","challenge_slug":"event","challenge_title":"Event",
      "template_id":"template","template_slug":"outing","template_title":"Outing",
      "title":"Observation","published_at":"2026-09-01T00:00:00Z",
      "author_user_id":"author","author_name":"Observer",
      "like_count":7,"comment_count":3,"viewer_has_liked":true,
      "is_owned_by_viewer":true,"items":[]
    }}
    """

    static let like = """
    {"publication_id":"publication","entry_id":"entry",
     "viewer_has_liked":true,"like_count":7,"comment_count":3}
    """

    static let comment = """
    {"comment":{
      "comment_id":"comment","post_id":"publication","author_user_id":"author",
      "author_name":"Observer","body":"Note","created_at":"2026-09-01T00:00:00Z",
      "viewer_can_delete":true,"viewer_can_moderate":false,"viewer_can_report":false
    },"comment_count":3}
    """

    static let progress = """
    {"data":[],"challenge_updates":[],"first_field_trip_achievement":{
      "kind":"standard_outing","completed_at":"2026-09-01T00:00:00Z","template_slug":"outing"
    },"first_field_trip_achievement_newly_unlocked":true}
    """
}
