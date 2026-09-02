import Foundation
import Testing

@testable import Merian

/// Independent JSON expectations. Invalid sentinels test forwarding, not server acceptance.
struct ExploreInteractionEndpointRequestCase: Sendable, CustomTestStringConvertible {
    let name: String
    let function: String
    let expectedJSON: String
    let responseJSON: String
    let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void

    var testDescription: String { name }
    var path: String { "/\(function)" }

    static var all: [Self] {
        operations + cursorVariations + mentionVariations + interactionVariations + userReportVariations
    }

    static var operations: [Self] { typedOperations + voidOperations }
    static var typedOperations: [Self] { readOperations + typedMutations }
    static var mutations: [Self] { typedMutations + voidOperations }

    static var readOperations: [Self] {
        [
            Self(name: "comment defaults", function: "get-explore-comments",
                 expectedJSON: #"{"post_id":"post","limit":100}"#,
                 responseJSON: ExploreInteractionEndpointResponses.comments) { client in
                _ = try await client.getExploreComments(postId: "post")
            },
            Self(name: "reply defaults", function: "get-explore-comment-replies",
                 expectedJSON: #"{"parent_comment_id":"comment","limit":25}"#,
                 responseJSON: ExploreInteractionEndpointResponses.replies) { client in
                _ = try await client.getExploreCommentReplies(parentCommentId: "comment")
            },
            Self(name: "mention defaults", function: "get-explore-mention-suggestions",
                 expectedJSON: #"{"post_id":"post","query":"test","limit":8}"#,
                 responseJSON: ExploreInteractionEndpointResponses.mentions) { client in
                _ = try await client.getExploreMentionSuggestions(postId: "post", query: "test")
            }
        ]
    }

    private static var typedMutations: [Self] {
        [
            Self(name: "like", function: "set-explore-post-like",
                 expectedJSON: #"{"post_id":"post","liked":true}"#,
                 responseJSON: ExploreInteractionEndpointResponses.liked) { client in
                _ = try await client.setExplorePostLike(postId: "post", liked: true)
            },
            Self(name: "follow", function: "set-user-follow",
                 expectedJSON: #"{"author_user_id":"author","is_following":true}"#,
                 responseJSON: ExploreInteractionEndpointResponses.followed) { client in
                _ = try await client.setUserFollow(authorUserId: "author", isFollowing: true)
            },
            Self(name: "create top-level comment", function: "create-explore-comment",
                 expectedJSON: #"{"post_id":"post","body":"Fresh comment"}"#,
                 responseJSON: ExploreInteractionEndpointResponses.created) { client in
                _ = try await client.createExploreComment(postId: "post", body: "Fresh comment")
            },
            Self(name: "delete comment", function: "delete-explore-comment",
                 expectedJSON: #"{"comment_id":"comment"}"#,
                 responseJSON: ExploreInteractionEndpointResponses.deleted) { client in
                _ = try await client.deleteExploreComment(commentId: "comment")
            }
        ]
    }

    static var voidOperations: [Self] {
        [
            Self(name: "toggle reaction", function: "toggle-explore-comment-reaction",
                 expectedJSON: #"{"comment_id":"comment","emoji":"👍"}"#, responseJSON: "") { client in
                try await client.toggleExploreCommentReaction(commentId: "comment", emoji: "👍")
            },
            Self(name: "comment report defaults", function: "report-explore-comment",
                 expectedJSON: """
                 {"comment_id":"comment","reason":"Inappropriate content","details":"Reported from Explore comments"}
                 """, responseJSON: "") { client in
                try await client.reportExploreComment(commentId: "comment")
            },
            Self(name: "post report defaults", function: "report-explore-post",
                 expectedJSON: """
                 {"post_id":"post","reason":"Inappropriate content","details":"Reported from Explore feed"}
                 """, responseJSON: "") { client in
                try await client.reportExplorePost(postId: "post")
            },
            Self(name: "user report omits nil details", function: "report-user",
                 expectedJSON: #"{"reported_user_id":"author","reason":"Harassment"}"#,
                 responseJSON: "") { client in
                try await client.reportUser(reportedUserId: "author", reason: .harassment, details: nil)
            },
            Self(name: "block uses blocked_id", function: "block-user",
                 expectedJSON: #"{"blocked_id":"author"}"#, responseJSON: "") { client in
                try await client.blockUser(targetUserId: "author")
            }
        ]
    }

    private static var cursorVariations: [Self] {
        let values: [(String, String?, String?, String)] = [
            ("empty", nil, nil, ""),
            ("timestamp only", "cursor-time", nil, ""),
            ("comment ID only", nil, "cursor-comment", ""),
            ("complete", "cursor-time", "cursor-comment", #","after_created_at":"cursor-time","after_comment_id":"cursor-comment""#),
            ("blank strings", "", "", #","after_created_at":"","after_comment_id":"""#)
        ]
        return values.flatMap { name, time, comment, suffix in
            [
                Self(name: "comment cursor: \(name)", function: "get-explore-comments",
                     expectedJSON: #"{"post_id":" Post ","limit":0\#(suffix)}"#,
                     responseJSON: #"{"data":[]}"#) { client in
                    _ = try await client.getExploreComments(
                        postId: " Post ", limit: 0, afterCreatedAt: time, afterCommentId: comment
                    )
                },
                Self(name: "reply cursor: \(name)", function: "get-explore-comment-replies",
                     expectedJSON: #"{"parent_comment_id":" Parent ","limit":-1\#(suffix)}"#,
                     responseJSON: #"{"data":[]}"#) { client in
                    _ = try await client.getExploreCommentReplies(
                        parentCommentId: " Parent ", limit: -1, afterCreatedAt: time, afterCommentId: comment
                    )
                }
            ]
        }
    }

    private static var mentionVariations: [Self] {
        [
            Self(name: "scoped mention query remains raw", function: "get-explore-mention-suggestions",
                 expectedJSON: #"{"post_id":" Post ","parent_comment_id":" Parent ","query":" @MiXeD ","limit":101}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreMentionSuggestions(
                    postId: " Post ", parentCommentId: " Parent ", query: " @MiXeD ", limit: 101
                )
            },
            Self(name: "blank mention parent is not omitted", function: "get-explore-mention-suggestions",
                 expectedJSON: #"{"post_id":"","parent_comment_id":"","query":"","limit":0}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreMentionSuggestions(postId: "", parentCommentId: "", query: "", limit: 0)
            },
            Self(name: "mention whitespace query is forwarded", function: "get-explore-mention-suggestions",
                 expectedJSON: #"{"post_id":"post","query":" \n ","limit":8}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreMentionSuggestions(postId: "post", query: " \n ")
            }
        ]
    }

    private static var interactionVariations: [Self] {
        let longBody = String(repeating: "x", count: 501)
        return [
            Self(name: "unlike remains Boolean false", function: "set-explore-post-like",
                 expectedJSON: #"{"post_id":" Post ","liked":false}"#,
                 responseJSON: ExploreInteractionEndpointResponses.liked) { client in
                _ = try await client.setExplorePostLike(postId: " Post ", liked: false)
            },
            Self(name: "unfollow remains Boolean false", function: "set-user-follow",
                 expectedJSON: #"{"author_user_id":" Author ","is_following":false}"#,
                 responseJSON: ExploreInteractionEndpointResponses.followed) { client in
                _ = try await client.setUserFollow(authorUserId: " Author ", isFollowing: false)
            },
            Self(name: "reply body and IDs remain raw", function: "create-explore-comment",
                 expectedJSON: #"{"post_id":" Post ","body":"  Test @test_mentioned 🦋\n ","parent_comment_id":" Parent "}"#,
                 responseJSON: ExploreInteractionEndpointResponses.created) { client in
                _ = try await client.createExploreComment(
                    postId: " Post ", body: "  Test @test_mentioned 🦋\n ", parentCommentId: " Parent "
                )
            },
            Self(name: "blank comment body and parent are forwarded", function: "create-explore-comment",
                 expectedJSON: #"{"post_id":"","body":"","parent_comment_id":""}"#,
                 responseJSON: ExploreInteractionEndpointResponses.created) { client in
                _ = try await client.createExploreComment(postId: "", body: "", parentCommentId: "")
            },
            Self(name: "transport does not cap comment body", function: "create-explore-comment",
                 expectedJSON: #"{"post_id":"post","body":"\#(longBody)"}"#,
                 responseJSON: ExploreInteractionEndpointResponses.created) { client in
                _ = try await client.createExploreComment(postId: "post", body: longBody)
            },
            Self(name: "delete forwards empty ID", function: "delete-explore-comment",
                 expectedJSON: #"{"comment_id":""}"#,
                 responseJSON: ExploreInteractionEndpointResponses.deleted) { client in
                _ = try await client.deleteExploreComment(commentId: "")
            },
            Self(name: "reaction text remains raw", function: "toggle-explore-comment-reaction",
                 expectedJSON: #"{"comment_id":" Comment ","emoji":" 🦋 "}"#, responseJSON: "") { client in
                try await client.toggleExploreCommentReaction(commentId: " Comment ", emoji: " 🦋 ")
            },
            Self(name: "comment report does not trim caller text", function: "report-explore-comment",
                 expectedJSON: #"{"comment_id":" Comment ","reason":" Other ","details":" \n "}"#,
                 responseJSON: "") { client in
                try await client.reportExploreComment(commentId: " Comment ", reason: " Other ", details: " \n ")
            },
            Self(name: "post report does not trim caller text", function: "report-explore-post",
                 expectedJSON: #"{"post_id":" Post ","reason":" Spam ","details":"  Test details  "}"#,
                 responseJSON: "") { client in
                try await client.reportExplorePost(postId: " Post ", reason: " Spam ", details: "  Test details  ")
            },
            Self(name: "blank post report fields are not omitted", function: "report-explore-post",
                 expectedJSON: #"{"post_id":"","reason":"","details":""}"#, responseJSON: "") { client in
                try await client.reportExplorePost(postId: "", reason: "", details: "")
            },
            Self(name: "block target is not normalized", function: "block-user",
                 expectedJSON: #"{"blocked_id":" Author "}"#, responseJSON: "") { client in
                try await client.blockUser(targetUserId: " Author ")
            }
        ]
    }

    private static var userReportVariations: [Self] {
        let longDetails = String(repeating: "x", count: 1001)
        return [
            Self(name: "user report empty details are omitted", function: "report-user",
                 expectedJSON: #"{"reported_user_id":"author","reason":"Spam"}"#, responseJSON: "") { client in
                try await client.reportUser(reportedUserId: "author", reason: .spam, details: "")
            },
            Self(name: "user report whitespace details are omitted", function: "report-user",
                 expectedJSON: #"{"reported_user_id":"author","reason":"Harassment"}"#, responseJSON: "") { client in
                try await client.reportUser(reportedUserId: "author", reason: .harassment, details: " \n\t ")
            },
            Self(name: "user report trims details but not the target", function: "report-user",
                 expectedJSON: #"{"reported_user_id":" Author ","reason":"Impersonation","details":"Test details"}"#,
                 responseJSON: "") { client in
                try await client.reportUser(reportedUserId: " Author ", reason: .impersonation, details: " \nTest details\t ")
            },
            Self(name: "user report keeps interior whitespace", function: "report-user",
                 expectedJSON: #"{"reported_user_id":"author","reason":"Inappropriate profile","details":"Test  details\nhere"}"#,
                 responseJSON: "") { client in
                try await client.reportUser(
                    reportedUserId: "author", reason: .inappropriateProfile, details: "  Test  details\nhere  "
                )
            },
            Self(name: "transport does not cap report details", function: "report-user",
                 expectedJSON: #"{"reported_user_id":"author","reason":"Other","details":"\#(longDetails)"}"#,
                 responseJSON: "") { client in
                try await client.reportUser(reportedUserId: "author", reason: .other, details: longDetails)
            }
        ]
    }
}
