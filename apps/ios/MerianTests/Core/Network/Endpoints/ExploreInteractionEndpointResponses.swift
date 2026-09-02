/// Synthetic wire fixtures, never captured user comments or profile data.
enum ExploreInteractionEndpointResponses {
    static let comment = """
    {"comment_id":"comment","post_id":"post","author_user_id":"author","author_name":"Test observer",
     "author_username":"test_observer","author_avatar_url":"https://media.example.test/comment.webp",
     "body":"Test @test_mentioned comment","created_at":"2026-01-01T12:00:00.000Z",
     "viewer_can_delete":false,"viewer_can_moderate":true,"viewer_can_report":true,"reply_count":2,
     "reactions":[{"emoji":"👍","count":2,"viewer_has_reacted":false},
                  {"emoji":"🦋","count":1,"viewer_has_reacted":true}],
     "mentions":[{"user_id":"mentioned","username":"test_mentioned","display_name":"Test mention",
                  "avatar_url":null}]}
    """

    static let reply = """
    {"comment_id":"reply","post_id":"post","parent_comment_id":"comment","author_user_id":"reply-author",
     "author_name":"Test reply author","author_username":"test_reply",
     "author_avatar_url":"https://media.example.test/reply.webp",
     "body":"Test reply","created_at":"2026-01-01T12:01:00.000Z",
     "viewer_can_delete":false,"viewer_can_moderate":false,"viewer_can_report":true,
     "reply_count":0,"reactions":[],"mentions":[]}
    """

    static let legacyComment = """
    {"comment_id":"legacy-comment","post_id":"post","author_user_id":"author","author_name":"Test observer",
     "body":"Legacy comment","created_at":"2026-01-01T11:00:00Z",
     "viewer_can_delete":true,"viewer_can_moderate":false,"viewer_can_report":false}
    """

    static let createdComment = """
    {"comment_id":"created-comment","post_id":"post","author_user_id":"viewer","author_name":"Test viewer",
     "author_username":"test_viewer","author_avatar_url":"https://media.example.test/created.webp",
     "body":"Fresh comment","created_at":"2026-01-01T12:02:00.000Z",
     "viewer_can_delete":true,"viewer_can_moderate":false,"viewer_can_report":false}
    """

    static let comments = #"{"data":[\#(comment)]}"#
    static let replies = #"{"success":true,"data":[\#(reply)]}"#
    static let created = #"{"success":true,"comment":\#(createdComment),"comment_count":3}"#
    static let deleted = #"{"success":true,"comment_id":"comment","comment_count":0,"action":"deleted"}"#
    static let liked = #"{"success":true,"post_id":"post","viewer_has_liked":false,"like_count":0}"#
    static let followed = """
    {"success":true,"author_user_id":"author","follower_count":12,"following_count":4,"viewer_is_following":true}
    """
    static let mentions = """
    {"data":[
     {"user_id":"post-author","username":"test_author","display_name":"Test author",
      "avatar_url":"https://media.example.test/author.webp","source":"post_author"},
     {"user_id":"participant","username":"test_participant","display_name":"Test participant",
      "avatar_url":null,"source":"thread"},
     {"user_id":"followed","username":"test_followed","display_name":"Test followed",
      "avatar_url":null,"source":"following"}]}
    """
}
