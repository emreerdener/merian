import Foundation
import Testing
@testable import Merian

struct FieldTripAPIModelsTests {
    @Test func catalogDecodesActiveProgressAndChecklistItems() throws {
        let json = """
        {
          "data": [
            {
              "template_id": "template-1",
              "slug": "backyard_safari",
              "title": "Backyard Safari",
              "subtitle": "A starter trip.",
              "description": "Find nearby species.",
              "cover_image_url": "https://example.com/backyard.jpg",
              "estimated_duration_minutes": 30,
              "guide_where_to_look": "Look near flowers.",
              "guide_why_it_matters": "Neighborhoods have biodiversity.",
              "guide_safety_ethics": "Stay on public paths.",
              "region_tags": ["global"],
              "season_tags": ["spring"],
              "habitat_tags": ["yard"],
              "difficulty": "starter",
              "is_pro_only": false,
              "is_rotating_free": true,
              "viewer_has_access": true,
              "access_kind": "rotating_free",
              "active_progress": {
                "user_field_trip_id": "trip-1",
                "started_at": "2026-07-08T00:00:00Z",
                "current_level_number": 1,
                "completed_at": null,
                "is_profile_visible": true,
                "completed_count": 1,
                "target_count": 4
              },
              "levels": [
                {
                  "level_id": "level-1",
                  "level_number": 1,
                  "title": "Level 1",
                  "description": null,
                  "items": [
                    {
                      "item_id": "item-1",
                      "prompt": "Bird",
                      "match_type": "taxonomy",
                      "guide_tip": "Listen before scanning.",
                      "is_completed": true,
                      "completed_at": "2026-07-08T00:10:00Z",
                      "completed_common_name": "Northern Cardinal",
                      "completed_scientific_name": "Cardinalis cardinalis"
                    }
                  ]
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(FieldTripsCatalogResponse.self, from: json)

        #expect(response.data.count == 1)
        #expect(response.data[0].coverImageUrl == "https://example.com/backyard.jpg")
        #expect(response.data[0].estimatedDurationMinutes == 30)
        #expect(response.data[0].guideWhereToLook == "Look near flowers.")
        #expect(response.data[0].activeProgress?.completedCount == 1)
        #expect(response.data[0].activeProgress?.fractionComplete == 0.25)
        #expect(response.data[0].levels[0].items[0].guideTip == "Listen before scanning.")
        #expect(response.data[0].levels[0].items[0].completedCommonName == "Northern Cardinal")
    }

    @Test func communityPublicationsDecodeAuthorRankingAndCursorFields() throws {
        let json = """
        {
          "data": [
            {
              "publication_id": "publication-1",
              "template_id": "template-1",
              "title": "Backyard Safari",
              "description": "A morning walk.",
              "published_at": "2026-07-08T01:00:00Z",
              "like_count": 2,
              "comment_count": 1,
              "slug": "backyard_safari",
              "template_title": "Backyard Safari",
              "region_tags": ["global", "neighborhood"],
              "season_tags": ["spring"],
              "habitat_tags": ["yard"],
              "cover_image_url": "https://example.com/backyard.jpg",
              "item_count": 4,
              "viewer_has_liked": false,
              "author_user_id": "author-1",
              "author_name": "Ari",
              "author_username": "ari",
              "author_avatar_url": null,
              "is_pinned": false,
              "pin_position": null,
              "rank_bucket": 0,
              "community_reason": "following",
              "viewer_is_following_author": true
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(FieldTripCommunityPublicationsResponse.self, from: json)

        #expect(response.data.count == 1)
        #expect(response.data[0].publicationId == "publication-1")
        #expect(response.data[0].publicAuthorDisplayName == "@ari")
        #expect(response.data[0].publishedAt == "2026-07-08T01:00:00Z")
        #expect(response.data[0].rankBucket == 0)
        #expect(response.data[0].communityReasonLabel == "Following")
    }

    @Test func fieldTripActivityNotificationDecodesPublicationRoute() throws {
        let json = """
        {
          "data": [
            {
              "notification_id": "notification-1",
              "post_id": null,
              "community_request_id": null,
              "field_trip_publication_id": "publication-1",
              "type": "field_trip_comment",
              "comment_id": "comment-1",
              "parent_comment_id": null,
              "reaction_emoji": null,
              "triggering_user_id": "author-2",
              "triggering_user_name": "Mina",
              "comment_body": "Great finds.",
              "recent_actor_names": [],
              "action_count": 1,
              "is_read": false,
              "is_reply_to_viewer_comment": false,
              "community_taxon_common_name": null,
              "community_taxon_scientific_name": null,
              "community_request_display_name": null,
              "created_at": "2026-07-08T01:00:00Z",
              "updated_at": "2026-07-08T01:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ExploreNotificationsResponse.self, from: json)

        #expect(response.data[0].fieldTripPublicationId == "publication-1")
        #expect(response.data[0].type == .fieldTripComment)
        #expect(response.data[0].type.isFieldTripNotification)
    }

    @Test func profileSummariesDecodePinnedTripsAndFallbackWhenMissing() throws {
        let v2Json = """
        {
          "data": {
            "active": [],
            "pinned": [
              {
                "publication_id": "publication-1",
                "title": "Pinned Trip",
                "description": null,
                "published_at": "2026-07-08T01:00:00Z",
                "like_count": 2,
                "comment_count": 1,
                "slug": "backyard_safari",
                "template_title": "Backyard Safari",
                "cover_image_url": null,
                "item_count": 4,
                "viewer_has_liked": false,
                "is_pinned": true,
                "pin_position": 1
              }
            ],
            "published": []
          }
        }
        """.data(using: .utf8)!

        let legacyJson = """
        {
          "data": {
            "active": [],
            "published": []
          }
        }
        """.data(using: .utf8)!

        let v2Response = try decoder.decode(FieldTripProfileSummariesResponse.self, from: v2Json)
        let legacyResponse = try decoder.decode(FieldTripProfileSummariesResponse.self, from: legacyJson)

        #expect(v2Response.data.pinned.count == 1)
        #expect(v2Response.data.pinned[0].isPinned)
        #expect(v2Response.data.pinned[0].pinPosition == 1)
        #expect(legacyResponse.data.pinned.isEmpty)
    }

    @Test func publicationDetailDoesNotRequireRawScanIds() throws {
        let json = """
        {
          "data": {
            "publication_id": "publication-1",
            "user_field_trip_id": "trip-1",
            "template_id": "template-1",
            "template_slug": "backyard_safari",
            "template_title": "Backyard Safari",
            "title": "Backyard Safari",
            "description": "A morning walk.",
            "ai_summary": null,
            "published_at": "2026-07-08T01:00:00Z",
            "author_user_id": "author-1",
            "author_name": "Ari",
            "author_username": "ari",
            "author_avatar_url": null,
            "like_count": 2,
            "comment_count": 1,
            "viewer_has_liked": true,
            "items": [
              {
                "publication_item_id": "snapshot-1",
                "item_id": "item-1",
                "prompt": "Butterfly",
                "common_name": "Monarch",
                "scientific_name": "Danaus plexippus",
                "hero_image_url": "https://example.com/monarch.webp",
                "reference_image_url": null,
                "taxonomy": { "class": "Insecta" }
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(FieldTripPublicationDetailResponse.self, from: json)

        #expect(response.data.publicationId == "publication-1")
        #expect(response.data.items[0].publicationItemId == "snapshot-1")
        #expect(response.data.items[0].displayName == "Monarch")
        #expect(response.data.viewerHasLiked)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
