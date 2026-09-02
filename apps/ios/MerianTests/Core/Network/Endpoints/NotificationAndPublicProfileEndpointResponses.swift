/// Synthetic notification projections; never copied from an account or device.
enum NotificationAndPublicProfileEndpointResponses {
    static let notifications = """
    {"data":[
     {"notification_id":"reply","post_id":"post","type":"comment_reply",
      "comment_id":"comment","parent_comment_id":"parent","reaction_emoji":"🦋",
      "triggering_user_id":"actor","triggering_user_name":"Test actor","comment_body":"Test reply",
      "recent_actor_names":["Test newest","Test oldest"],"action_count":2,"is_read":false,
      "is_reply_to_viewer_comment":true,"created_at":"2026-01-01T12:00:00.000Z","updated_at":"2026-01-01T12:01:00.000Z"},
     {"notification_id":"follow","post_id":null,"type":"follow","triggering_user_id":"follower",
      "recent_actor_names":["Test follower"],"action_count":1,"is_read":true,
      "created_at":"2026-01-02T12:00:00Z","updated_at":"2026-01-02T12:01:00Z"},
     {"notification_id":"publication","post_id":null,"field_trip_publication_id":"field-trip",
      "type":"field_trip_followed_publication","recent_actor_names":[],"action_count":1,"is_read":false,
      "created_at":"2026-01-01T12:02:00Z","updated_at":"2026-01-01T12:03:00Z"},
     {"notification_id":"community","post_id":"community-post","community_request_id":"request",
      "type":"community_request_resolved","community_taxon_common_name":"Test bird",
      "community_taxon_scientific_name":"Testus example","community_request_display_name":"Test request",
      "recent_actor_names":[],"action_count":1,"is_read":true,
      "created_at":"2026-01-01T12:04:00Z","updated_at":"2026-01-01T12:05:00Z"},
     {"notification_id":"media","post_id":"media-post","type":"media_missing",
      "recent_actor_names":[],"action_count":0,"is_read":false,
      "created_at":"2026-01-01T12:06:00Z","updated_at":"2026-01-01T12:07:00Z"}
    ]}
    """
}
