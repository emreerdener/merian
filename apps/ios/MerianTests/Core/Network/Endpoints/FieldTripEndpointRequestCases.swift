import Foundation
import Testing

@testable import Merian

/// Independent wire expectations; all request handlers use a private mock client.
struct FieldTripEndpointRequestCase: Sendable, CustomTestStringConvertible {
    let name: String
    let expectedJSON: String
    let responseJSON: String
    let timeout: TimeInterval
    let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void

    var testDescription: String { name }

    static var all: [Self] {
        [
            Self(
                name: "catalog defaults",
                expectedJSON: #"{"action":"catalog","limit":40}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTrips()
            },
            Self(
                name: "catalog region",
                expectedJSON: #"{"action":"catalog","limit":7,"user_region":"global"}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTrips(userRegion: "  global\n", limit: 7)
            },
            Self(
                name: "blank catalog region",
                expectedJSON: #"{"action":"catalog","limit":40}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTrips(userRegion: " \n")
            },
            Self(
                name: "capture context",
                expectedJSON: #"{"action":"capture_context"}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripCaptureContext()
            },
            Self(
                name: "achievement progress",
                expectedJSON: #"{"action":"achievement_progress"}"#,
                responseJSON: FieldTripEndpointResponses.achievement,
                timeout: 30
            ) { client in
                _ = try await client.getFirstFieldTripAchievementProgress()
            },
            Self(
                name: "template ID",
                expectedJSON: #"{"action":"template_detail","template_id":"template"}"#,
                responseJSON: FieldTripEndpointResponses.template,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripTemplate(templateId: "template")
            },
            Self(
                name: "template slug",
                expectedJSON: #"{"action":"template_detail","slug":"outing"}"#,
                responseJSON: FieldTripEndpointResponses.template,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripTemplate(slug: "outing")
            },
            Self(
                name: "start",
                expectedJSON: #"{"action":"start","template_id":"template"}"#,
                responseJSON: FieldTripEndpointResponses.template,
                timeout: 30
            ) { client in
                _ = try await client.startFieldTrip(templateId: "template")
            },
            Self(
                name: "stop",
                expectedJSON: #"{"action":"stop","user_field_trip_id":"trip"}"#,
                responseJSON: FieldTripEndpointResponses.template,
                timeout: 30
            ) { client in
                _ = try await client.stopFieldTrip(userFieldTripId: "trip")
            },
            Self(
                name: "reset",
                expectedJSON: #"{"action":"reset","user_field_trip_id":"trip"}"#,
                responseJSON: FieldTripEndpointResponses.template,
                timeout: 30
            ) { client in
                _ = try await client.resetFieldTrip(userFieldTripId: "trip")
            },
            Self(
                name: "events catalog",
                expectedJSON: #"{"action":"challenges_catalog","limit":20}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallenges()
            },
            Self(
                name: "events region",
                expectedJSON: #"{"action":"challenges_catalog","limit":5,"user_region":"global"}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallenges(userRegion: " global ", limit: 5)
            },
            Self(
                name: "event detail",
                expectedJSON: #"{"action":"challenge_detail","challenge_id":"event","entries_limit":12}"#,
                responseJSON: FieldTripEndpointResponses.challenge,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallenge(challengeId: "event")
            },
            Self(
                name: "event entry limit",
                expectedJSON: #"{"action":"challenge_detail","challenge_id":"event","entries_limit":3}"#,
                responseJSON: FieldTripEndpointResponses.challenge,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallenge(challengeId: "event", entriesLimit: 3)
            },
            Self(
                name: "join event",
                expectedJSON: #"{"action":"join_challenge","challenge_id":"event"}"#,
                responseJSON: FieldTripEndpointResponses.challenge,
                timeout: 30
            ) { client in
                _ = try await client.joinFieldTripChallenge(challengeId: "event")
            },
            Self(
                name: "recent defaults",
                expectedJSON: #"{"action":"community_publications","mode":"recent","limit":20}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getRecentFieldTripPublications()
            },
            Self(
                name: "recent cursor",
                expectedJSON: #"{"action":"community_publications","mode":"recent","limit":20,"before_rank_bucket":0,"before_published_at":"published","before_publication_id":"publication"}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getRecentFieldTripPublications(beforePublishedAt: "published", beforePublicationId: "publication")
            },
            Self(
                name: "community defaults",
                expectedJSON: #"{"action":"community_publications","mode":"smart","limit":20}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripCommunityPublications()
            },
            Self(
                name: "community filters",
                expectedJSON: #"{"action":"community_publications","mode":"following","limit":4,"template_id":"template","user_region":"global","habitat_tags":["garden","forest"],"season_tags":["summer"],"before_rank_bucket":2,"before_published_at":"published","before_publication_id":"publication"}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripCommunityPublications(
                    mode: .following, templateId: " template ", userRegion: " global ",
                    habitatTags: [" garden ", " ", "forest"], seasonTags: [" summer ", ""],
                    limit: 4, beforeRankBucket: 2,
                    beforePublishedAt: "published", beforePublicationId: "publication"
                )
            },
            Self(
                name: "community incomplete cursor",
                expectedJSON: #"{"action":"community_publications","mode":"smart","limit":20}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripCommunityPublications(
                    templateId: " ", userRegion: " ", habitatTags: [" "], seasonTags: [""],
                    beforeRankBucket: 2, beforePublishedAt: "published"
                )
            },
            Self(
                name: "progress",
                expectedJSON: #"{"action":"apply_scan_progress","scan_id":"scan"}"#,
                responseJSON: FieldTripEndpointResponses.progress,
                timeout: 15
            ) { client in
                _ = try await client.applyFieldTripProgress(scanId: "scan")
            },
            Self(
                name: "preferred goal",
                expectedJSON: #"{"action":"apply_scan_progress","scan_id":"scan","preferred_goal":{"user_field_trip_id":"trip","item_id":"goal"}}"#,
                responseJSON: FieldTripEndpointResponses.progress,
                timeout: 15
            ) { client in
                _ = try await client.applyFieldTripProgress(
                    scanId: "scan",
                    preferredGoal: FieldTripPreferredGoal(userFieldTripId: "trip", itemId: "goal")
                )
            },
            Self(
                name: "scan contributions",
                expectedJSON: #"{"action":"scan_contributions","scan_id":"scan"}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 15
            ) { client in
                _ = try await client.getFieldTripScanContributions(scanId: "scan")
            },
            Self(
                name: "event hashtags",
                expectedJSON: #"{"action":"scan_challenge_hashtags","scan_id":"scan"}"#,
                responseJSON: FieldTripEndpointResponses.hashtags,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallengeHashtags(scanId: "scan")
            },
            Self(
                name: "profile summaries",
                expectedJSON: #"{"action":"profile_summaries","author_user_id":"author","limit":6}"#,
                responseJSON: FieldTripEndpointResponses.profile,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripProfileSummaries(authorUserId: "author")
            },
            Self(
                name: "profile limit",
                expectedJSON: #"{"action":"profile_summaries","author_user_id":"author","limit":2}"#,
                responseJSON: FieldTripEndpointResponses.profile,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripProfileSummaries(authorUserId: "author", limit: 2)
            },
            Self(
                name: "pin cap",
                expectedJSON: #"{"action":"set_pinned_publications","publication_ids":["one","two","three"]}"#,
                responseJSON: FieldTripEndpointResponses.profile,
                timeout: 30
            ) { client in
                _ = try await client.setPinnedFieldTripPublications(publicationIds: ["one", "two", "three", "four"])
            },
            Self(
                name: "publish nulls",
                expectedJSON: #"{"action":"publish","user_field_trip_id":"trip","title":null,"description":null,"ai_summary":null}"#,
                responseJSON: FieldTripEndpointResponses.publication,
                timeout: 30
            ) { client in
                _ = try await client.publishFieldTrip(userFieldTripId: "trip")
            },
            Self(
                name: "publish text preserved",
                expectedJSON: #"{"action":"publish","user_field_trip_id":"trip","title":" Title ","description":"","ai_summary":" Summary "}"#,
                responseJSON: FieldTripEndpointResponses.publication,
                timeout: 30
            ) { client in
                _ = try await client.publishFieldTrip(userFieldTripId: "trip", title: " Title ", description: "", aiSummary: " Summary ")
            },
            Self(
                name: "event publications",
                expectedJSON: #"{"action":"challenge_publications","challenge_id":"event","limit":20}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallengePublications(challengeId: "event")
            },
            Self(
                name: "event publications cursor",
                expectedJSON: #"{"action":"challenge_publications","challenge_id":"event","limit":4,"before_published_at":"published","before_entry_id":"entry"}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallengePublications(
                    challengeId: "event", limit: 4,
                    beforePublishedAt: "published", beforeEntryId: "entry"
                )
            },
            Self(
                name: "event publications incomplete cursor",
                expectedJSON: #"{"action":"challenge_publications","challenge_id":"event","limit":20}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallengePublications(challengeId: "event", beforePublishedAt: "published")
            },
            Self(
                name: "publish event nulls",
                expectedJSON: #"{"action":"publish_challenge_entry","participation_id":"participation","title":null,"description":null}"#,
                responseJSON: FieldTripEndpointResponses.publication,
                timeout: 30
            ) { client in
                _ = try await client.publishFieldTripChallengeEntry(participationId: "participation")
            },
            Self(
                name: "publish event text",
                expectedJSON: #"{"action":"publish_challenge_entry","participation_id":"participation","title":" Title ","description":""}"#,
                responseJSON: FieldTripEndpointResponses.publication,
                timeout: 30
            ) { client in
                _ = try await client.publishFieldTripChallengeEntry(participationId: "participation", title: " Title ", description: "")
            },
            Self(
                name: "event entry detail",
                expectedJSON: #"{"action":"challenge_entry_detail","entry_id":"entry"}"#,
                responseJSON: FieldTripEndpointResponses.publication,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallengeEntry(entryId: "entry")
            },
            Self(
                name: "outing publication detail",
                expectedJSON: #"{"action":"detail","publication_id":"publication"}"#,
                responseJSON: FieldTripEndpointResponses.publication,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripPublication(publicationId: "publication")
            },
            Self(
                name: "outing like",
                expectedJSON: #"{"action":"set_like","publication_id":"publication","liked":true}"#,
                responseJSON: FieldTripEndpointResponses.like,
                timeout: 30
            ) { client in
                _ = try await client.setFieldTripLike(publicationId: "publication", liked: true)
            },
            Self(
                name: "event unlike",
                expectedJSON: #"{"action":"set_challenge_entry_like","entry_id":"entry","liked":false}"#,
                responseJSON: FieldTripEndpointResponses.like,
                timeout: 30
            ) { client in
                _ = try await client.setFieldTripChallengeEntryLike(entryId: "entry", liked: false)
            },
            Self(
                name: "outing comments",
                expectedJSON: #"{"action":"comments","publication_id":"publication","limit":100}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripComments(publicationId: "publication")
            },
            Self(
                name: "outing comments cursor",
                expectedJSON: #"{"action":"comments","publication_id":"publication","limit":4,"after_created_at":"created","after_comment_id":"comment"}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripComments(
                    publicationId: "publication", limit: 4,
                    afterCreatedAt: "created", afterCommentId: "comment"
                )
            },
            Self(
                name: "outing comments incomplete cursor",
                expectedJSON: #"{"action":"comments","publication_id":"publication","limit":100}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripComments(publicationId: "publication", afterCommentId: "comment")
            },
            Self(
                name: "event comments",
                expectedJSON: #"{"action":"challenge_entry_comments","entry_id":"entry","limit":100}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallengeEntryComments(entryId: "entry")
            },
            Self(
                name: "event comments cursor",
                expectedJSON: #"{"action":"challenge_entry_comments","entry_id":"entry","limit":4,"after_created_at":"created","after_comment_id":"comment"}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallengeEntryComments(
                    entryId: "entry", limit: 4,
                    afterCreatedAt: "created", afterCommentId: "comment"
                )
            },
            Self(
                name: "event comments incomplete cursor",
                expectedJSON: #"{"action":"challenge_entry_comments","entry_id":"entry","limit":100}"#,
                responseJSON: FieldTripEndpointResponses.empty,
                timeout: 30
            ) { client in
                _ = try await client.getFieldTripChallengeEntryComments(entryId: "entry", afterCreatedAt: "created")
            },
            Self(
                name: "outing comment text preserved",
                expectedJSON: #"{"action":"create_comment","publication_id":"publication","body":" Note "}"#,
                responseJSON: FieldTripEndpointResponses.comment,
                timeout: 30
            ) { client in
                _ = try await client.createFieldTripComment(publicationId: "publication", body: " Note ")
            },
            Self(
                name: "outing reply",
                expectedJSON: #"{"action":"create_comment","publication_id":"publication","body":"Note","parent_comment_id":"parent"}"#,
                responseJSON: FieldTripEndpointResponses.comment,
                timeout: 30
            ) { client in
                _ = try await client.createFieldTripComment(publicationId: "publication", body: "Note", parentCommentId: "parent")
            },
            Self(
                name: "event comment",
                expectedJSON: #"{"action":"create_challenge_entry_comment","entry_id":"entry","body":" Note "}"#,
                responseJSON: FieldTripEndpointResponses.comment,
                timeout: 30
            ) { client in
                _ = try await client.createFieldTripChallengeEntryComment(entryId: "entry", body: " Note ")
            },
            Self(
                name: "event reply",
                expectedJSON: #"{"action":"create_challenge_entry_comment","entry_id":"entry","body":"Note","parent_comment_id":"parent"}"#,
                responseJSON: FieldTripEndpointResponses.comment,
                timeout: 30
            ) { client in
                _ = try await client.createFieldTripChallengeEntryComment(entryId: "entry", body: "Note", parentCommentId: "parent")
            }
        ]
    }
}
