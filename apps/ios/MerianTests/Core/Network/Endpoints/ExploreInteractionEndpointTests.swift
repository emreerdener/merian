import Foundation
import Testing

@testable import Merian

@Suite("Explore Interaction Endpoints")
@MainActor
struct ExploreInteractionEndpointTests {
    @Test func requestInventoryCoversEveryOperation() {
        let cases = ExploreInteractionEndpointRequestCase.operations
        #expect(cases.count == 12 && Set(cases.map(\.function)).count == 12)
        #expect(ExploreInteractionEndpointRequestCase.all.count == 41)
        #expect(ExploreInteractionEndpointRequestCase.typedOperations.count == 7)
        #expect(ExploreInteractionEndpointRequestCase.voidOperations.count == 5)
        #expect(ExploreInteractionEndpointRequestCase.mutations.count == 9)
        #expect(Set(ExploreInteractionEndpointRequestCase.readOperations.map(\.function)) == [
            "get-explore-comments", "get-explore-comment-replies", "get-explore-mention-suggestions"
        ])
    }

    @Test(arguments: ExploreInteractionEndpointRequestCase.all)
    func requestMappingRemainsStable(_ testCase: ExploreInteractionEndpointRequestCase) async throws {
        try await withResponse(
            function: testCase.function, requestJSON: testCase.expectedJSON, responseJSON: testCase.responseJSON
        ) { client in
            try await testCase.invoke(client)
        }
    }

    // Rehomed aggregate regressions retain their names and use per-test clients.
    @Test func testSetUserFollowConstructsPayloadAndParsesState() async throws {
        try await withResponse(
            function: "set-user-follow", requestJSON: #"{"author_user_id":"author","is_following":true}"#,
            responseJSON: ExploreInteractionEndpointResponses.followed
        ) { client in
            let state = try await client.setUserFollow(authorUserId: "author", isFollowing: true)
            #expect(state.success && state.authorUserId == "author")
            #expect(state.followerCount == 12 && state.followingCount == 4 && state.viewerIsFollowing)
        }
    }

    @Test func testGetExploreCommentsParsesAuthorAvatar() async throws {
        try await withResponse(
            function: "get-explore-comments", requestJSON: #"{"post_id":"post","limit":100}"#,
            responseJSON: ExploreInteractionEndpointResponses.comments
        ) { client in
            let comments = try await client.getExploreComments(postId: "post")
            #expect(comments.count == 1)
            let comment = try #require(comments.first)
            #expect(comment.id == "comment" && comment.postId == "post" && comment.parentCommentId == nil)
            #expect(comment.authorUserId == "author" && comment.authorName == "Test observer")
            #expect(comment.authorUsername == "test_observer")
            #expect(comment.authorAvatarUrl == "https://media.example.test/comment.webp")
            #expect(comment.body == "Test @test_mentioned comment" && comment.createdAt == "2026-01-01T12:00:00.000Z")
            #expect(!comment.viewerCanDelete && comment.viewerCanModerate && comment.viewerCanReport)
            #expect(comment.replyCount == 2)
            #expect(comment.reactions == [
                .init(emoji: "👍", count: 2, viewerHasReacted: false),
                .init(emoji: "🦋", count: 1, viewerHasReacted: true)
            ])
            #expect(comment.mentions == [
                .init(userId: "mentioned", username: "test_mentioned", displayName: "Test mention", avatarUrl: nil)
            ])
        }
    }

    @Test func testGetExploreCommentRepliesUsesParentCommentAndDecodesReply() async throws {
        try await withResponse(
            function: "get-explore-comment-replies", requestJSON: #"{"parent_comment_id":"comment","limit":25}"#,
            responseJSON: ExploreInteractionEndpointResponses.replies
        ) { client in
            let replies = try await client.getExploreCommentReplies(parentCommentId: "comment")
            #expect(replies.count == 1)
            let reply = try #require(replies.first)
            #expect(reply.id == "reply" && reply.postId == "post" && reply.parentCommentId == "comment")
            #expect(reply.authorUserId == "reply-author" && reply.authorName == "Test reply author")
            #expect(reply.authorUsername == "test_reply" && reply.authorAvatarUrl == "https://media.example.test/reply.webp")
            #expect(reply.body == "Test reply" && reply.createdAt == "2026-01-01T12:01:00.000Z")
            #expect(!reply.viewerCanDelete && !reply.viewerCanModerate && reply.viewerCanReport)
            #expect(reply.replyCount == 0 && reply.reactions == [] && reply.mentions == [])
        }
    }

    @Test func testCreateExploreCommentParsesAuthorAvatar() async throws {
        try await withResponse(
            function: "create-explore-comment", requestJSON: #"{"post_id":"post","body":"Fresh comment"}"#,
            responseJSON: ExploreInteractionEndpointResponses.created
        ) { client in
            let response = try await client.createExploreComment(postId: "post", body: "Fresh comment")
            #expect(response.success && response.commentCount == 3)
            #expect(response.comment.id == "created-comment" && response.comment.postId == "post")
            #expect(response.comment.authorUserId == "viewer" && response.comment.authorUsername == "test_viewer")
            #expect(response.comment.authorAvatarUrl == "https://media.example.test/created.webp")
            #expect(response.comment.body == "Fresh comment" && response.comment.parentCommentId == nil)
            #expect(response.comment.viewerCanDelete && !response.comment.viewerCanModerate && !response.comment.viewerCanReport)
        }
    }

    @Test func testReportExplorePost() async throws {
        try await withResponse(
            function: "report-explore-post",
            requestJSON: """
            {"post_id":"00000000-0000-4000-8000-000000000101","reason":"Inappropriate content",
             "details":"Reported from Community request"}
            """, responseJSON: ""
        ) { client in
            try await client.reportExplorePost(
                postId: "00000000-0000-4000-8000-000000000101",
                reason: "Inappropriate content", details: "Reported from Community request"
            )
        }
    }

    @Test func testBlockUser() async throws {
        try await withResponse(
            function: "block-user", requestJSON: #"{"blocked_id":"blocked-author"}"#, responseJSON: ""
        ) { client in
            try await client.blockUser(targetUserId: "blocked-author")
        }
    }

    @Test func likeResponseKeepsAuthoritativeStateInsteadOfEchoingTheRequest() async throws {
        try await withResponse(
            function: "set-explore-post-like", requestJSON: #"{"post_id":"post","liked":true}"#,
            responseJSON: ExploreInteractionEndpointResponses.liked
        ) { client in
            let state = try await client.setExplorePostLike(postId: "post", liked: true)
            #expect(state.success && state.postId == "post" && !state.viewerHasLiked && state.likeCount == 0)
        }
    }

    @Test func commentsKeepServerOrderAndLegacyOptionalFields() async throws {
        try await withResponse(
            function: "get-explore-comments", requestJSON: #"{"post_id":"post","limit":100}"#,
            responseJSON: #"{"data":[\#(ExploreInteractionEndpointResponses.comment),\#(ExploreInteractionEndpointResponses.legacyComment)]}"#
        ) { client in
            let comments = try await client.getExploreComments(postId: "post")
            #expect(comments.map(\.id) == ["comment", "legacy-comment"])
            let legacy = try #require(comments.last)
            #expect(legacy.parentCommentId == nil && legacy.authorUsername == nil && legacy.authorAvatarUrl == nil)
            #expect(legacy.reactions == nil && legacy.mentions == nil && legacy.replyCount == nil)
            #expect(legacy.createdAt == "2026-01-01T11:00:00Z")
        }
    }

    @Test func createdReplyRetainsParentAndServerCapabilities() async throws {
        try await withResponse(
            function: "create-explore-comment",
            requestJSON: #"{"post_id":"post","body":"Test reply","parent_comment_id":"comment"}"#,
            responseJSON: #"{"success":true,"comment":\#(ExploreInteractionEndpointResponses.reply),"comment_count":7}"#
        ) { client in
            let response = try await client.createExploreComment(postId: "post", body: "Test reply", parentCommentId: "comment")
            #expect(response.success && response.commentCount == 7)
            #expect(response.comment.id == "reply" && response.comment.parentCommentId == "comment")
            #expect(!response.comment.viewerCanDelete && !response.comment.viewerCanModerate && response.comment.viewerCanReport)
            #expect(response.comment.reactions == [] && response.comment.mentions == [])
        }
    }

    @Test(arguments: ["deleted", "moderated", "future-action"])
    func deletionRetainsCountsAndUnnormalizedAction(action: String) async throws {
        try await withResponse(
            function: "delete-explore-comment", requestJSON: #"{"comment_id":"comment"}"#,
            responseJSON: #"{"success":true,"comment_id":"comment","comment_count":7,"action":"\#(action)"}"#
        ) { client in
            let response = try await client.deleteExploreComment(commentId: "comment")
            #expect(response.success && response.commentId == "comment")
            #expect(response.commentCount == 7 && response.action == action)
        }
    }

    @Test func mentionSuggestionsKeepOrderSourcesAndPublicProjection() async throws {
        try await withResponse(
            function: "get-explore-mention-suggestions", requestJSON: #"{"post_id":"post","query":"test","limit":8}"#,
            responseJSON: ExploreInteractionEndpointResponses.mentions
        ) { client in
            let suggestions = try await client.getExploreMentionSuggestions(postId: "post", query: "test")
            #expect(suggestions.map(\.id) == ["post-author", "participant", "followed"])
            #expect(suggestions.map(\.username) == ["test_author", "test_participant", "test_followed"])
            #expect(suggestions.map(\.displayName) == ["Test author", "Test participant", "Test followed"])
            #expect(suggestions.map(\.source) == [.postAuthor, .thread, .following])
            #expect(suggestions.map(\.avatarUrl) == ["https://media.example.test/author.webp", nil, nil])
        }
    }

    @Test func typedMutationSuccessFlagsRemainCallerOwned() async throws {
        try await withResponse(
            function: "set-explore-post-like", requestJSON: #"{"post_id":"post","liked":false}"#,
            responseJSON: #"{"success":false,"post_id":"post","viewer_has_liked":true,"like_count":5}"#
        ) { client in
            let state = try await client.setExplorePostLike(postId: "post", liked: false)
            #expect(!state.success && state.postId == "post" && state.viewerHasLiked && state.likeCount == 5)
        }
        try await withResponse(
            function: "set-user-follow", requestJSON: #"{"author_user_id":"author","is_following":false}"#,
            responseJSON: """
            {"success":false,"author_user_id":"author","follower_count":0,"following_count":0,"viewer_is_following":false}
            """
        ) { client in
            let state = try await client.setUserFollow(authorUserId: "author", isFollowing: false)
            #expect(!state.success && state.authorUserId == "author" && !state.viewerIsFollowing)
            #expect(state.followerCount == 0 && state.followingCount == 0)
        }
        try await withResponse(
            function: "create-explore-comment", requestJSON: #"{"post_id":"post","body":"Fresh comment"}"#,
            responseJSON: #"{"success":false,"comment":\#(ExploreInteractionEndpointResponses.createdComment),"comment_count":0}"#
        ) { client in
            let response = try await client.createExploreComment(postId: "post", body: "Fresh comment")
            #expect(!response.success && response.comment.id == "created-comment" && response.commentCount == 0)
        }
        try await withResponse(
            function: "delete-explore-comment", requestJSON: #"{"comment_id":"comment"}"#,
            responseJSON: #"{"success":false,"comment_id":"comment","comment_count":0,"action":"unchanged"}"#
        ) { client in
            let response = try await client.deleteExploreComment(commentId: "comment")
            #expect(!response.success && response.commentId == "comment" && response.commentCount == 0 && response.action == "unchanged")
        }
    }

    private func withResponse(
        function: String,
        requestJSON: String,
        responseJSON: String,
        body: (MerianNetworkClient) async throws -> Void
    ) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("Exactly one Explore interaction POST") { sent in
            fixture.transport.register(path: "/\(function)") { request in
                sent()
                try NetworkEndpointTestSupport.expectPOST(request, function: function, json: requestJSON)
                return try NetworkEndpointTestSupport.response(to: request, json: responseJSON)
            }
            try await body(fixture.client)
        }
    }
}
