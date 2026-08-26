import Foundation
@testable import Merian
import Testing

struct FieldTripAPIModelsTests {
    @Test func catalogDecodesActiveProgressAndChecklistItems() throws {
        let json = Data("""
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
                      "guide": {
                        "where_to_look": "Check shrubs, feeders, and tree canopies.",
                        "best_conditions": "Pause quietly in early morning.",
                        "what_to_notice": "Listen for calls and watch for movement.",
                        "scan_safely": "Use zoom and stay away from nests."
                      },
                      "is_completed": true,
                      "completed_at": "2026-07-08T00:10:00Z",
                      "completed_common_name": "Northern Cardinal",
                      "completed_scientific_name": "Cardinalis cardinalis",
                      "completed_scan_id": "scan-1"
                    }
                  ]
                }
              ]
            }
          ]
        }
        """.utf8)

        let response = try decoder.decode(FieldTripsCatalogResponse.self, from: json)

        #expect(response.data.count == 1)
        #expect(response.data[0].coverImageUrl == "https://example.com/backyard.jpg")
        #expect(response.data[0].estimatedDurationMinutes == 30)
        #expect(response.data[0].guideWhereToLook == "Look near flowers.")
        #expect(response.data[0].activeProgress?.completedCount == 1)
        #expect(response.data[0].activeProgress?.fractionComplete == 0.25)
        #expect(response.data[0].levels[0].items[0].guideTip == "Listen before scanning.")
        #expect(response.data[0].levels[0].items[0].guide?.whereToLook == "Check shrubs, feeders, and tree canopies.")
        #expect(response.data[0].levels[0].items[0].guide?.scanSafely == "Use zoom and stay away from nests.")
        #expect(response.data[0].levels[0].items[0].hasGuide)
        #expect(response.data[0].levels[0].items[0].guidePreview == "Check shrubs, feeders, and tree canopies.")
        #expect(response.data[0].levels[0].items[0].completedCommonName == "Northern Cardinal")
        #expect(response.data[0].levels[0].items[0].completedScanId == "scan-1")
    }

    @Test func templateDetailDecodesPublishedStatus() throws {
        let json = Data("""
        {
          "data": {
            "template_id": "template-1",
            "slug": "backyard_safari",
            "title": "Backyard Safari",
            "subtitle": null,
            "description": null,
            "cover_image_url": null,
            "estimated_duration_minutes": null,
            "guide_where_to_look": null,
            "guide_why_it_matters": null,
            "guide_safety_ethics": null,
            "region_tags": [],
            "season_tags": [],
            "habitat_tags": [],
            "difficulty": "starter",
            "is_pro_only": false,
            "is_rotating_free": true,
            "viewer_has_access": true,
            "access_kind": "starter",
            "active_progress": {
              "user_field_trip_id": "trip-1",
              "started_at": "2026-07-08T00:00:00Z",
              "current_level_number": 1,
              "completed_at": "2026-07-08T01:00:00Z",
              "is_profile_visible": true,
              "completed_count": 4,
              "target_count": 4,
              "publication_id": "publication-1",
              "published_at": "2026-07-08T01:05:00Z"
            },
            "levels": []
          }
        }
        """.utf8)

        let response = try decoder.decode(FieldTripTemplateDetailResponse.self, from: json)

        #expect(response.data.activeProgress?.publicationId == "publication-1")
        #expect(response.data.activeProgress?.publishedAt == "2026-07-08T01:05:00Z")
        #expect(response.data.activeProgress?.isPublished == true)
    }

    @Test func templateDetailDecodesStoppedProgressAsSavedViewerProgress() throws {
        let json = Data("""
        {
          "data": {
            "template_id": "template-1",
            "slug": "backyard_safari",
            "title": "Backyard Safari",
            "subtitle": null,
            "description": null,
            "cover_image_url": null,
            "estimated_duration_minutes": null,
            "guide_where_to_look": null,
            "guide_why_it_matters": null,
            "guide_safety_ethics": null,
            "region_tags": [],
            "season_tags": [],
            "habitat_tags": [],
            "difficulty": "starter",
            "is_pro_only": false,
            "is_rotating_free": true,
            "viewer_has_access": true,
            "access_kind": "starter",
            "active_progress": null,
            "stopped_progress": {
              "user_field_trip_id": "trip-1",
              "started_at": "2026-07-08T00:00:00Z",
              "current_level_number": 1,
              "completed_at": null,
              "is_profile_visible": true,
              "completed_count": 2,
              "target_count": 4,
              "publication_id": null,
              "published_at": null,
              "stopped_at": "2026-07-08T00:30:00Z"
            },
            "levels": []
          }
        }
        """.utf8)

        let response = try decoder.decode(FieldTripTemplateDetailResponse.self, from: json)

        #expect(response.data.activeProgress == nil)
        #expect(response.data.isStopped)
        #expect(response.data.viewerProgress?.completedCount == 2)
        #expect(response.data.viewerProgress?.stoppedAt == "2026-07-08T00:30:00Z")
        #expect(response.data.catalogState == .inProgress)
    }

    @Test func legacyProgressWithoutPublicationStatusDecodesAsPrivate() throws {
        let json = Data("""
        {
          "user_field_trip_id": "trip-1",
          "started_at": "2026-07-08T00:00:00Z",
          "current_level_number": 1,
          "completed_at": null,
          "is_profile_visible": true,
          "completed_count": 0,
          "target_count": 4
        }
        """.utf8)

        let progress = try decoder.decode(FieldTripProgress.self, from: json)

        #expect(progress.publicationId == nil)
        #expect(progress.publishedAt == nil)
        #expect(!progress.isPublished)
    }

    @Test func checklistItemUsesLegacyGuideTipAsFallback() {
        let item = FieldTripChecklistItem(
            itemId: "item-legacy",
            prompt: "Butterfly",
            matchType: "taxonomy",
            guideTip: "Look near sunny flowers.",
            guide: nil,
            referenceSpecies: nil,
            isCompleted: false,
            completedAt: nil,
            completedCommonName: nil,
            completedScientificName: nil,
            completedScanId: nil
        )

        #expect(item.hasGuide)
        #expect(item.guidePreview == "Look near sunny flowers.")
    }

    @Test func checklistItemDecodesOrderedReferenceSpeciesCandidates() throws {
        let json = Data("""
        {
          "item_id": "item-bird",
          "prompt": "Bird",
          "match_type": "taxonomy",
          "guide_tip": null,
          "guide": null,
          "reference_species": {
            "scientific_name": "Passer domesticus",
            "common_name": "House Sparrow",
            "reference_images": [
              {
                "url": "https://media.merian.app/sparrow.webp",
                "source": "merian",
                "license": null,
                "attribution": null,
                "width": 1200,
                "height": 800
              },
              {
                "url": "https://upload.wikimedia.org/sparrow.jpg",
                "source": "wikipedia",
                "license": "CC BY-SA 4.0",
                "attribution": "Example Photographer",
                "width": 1000,
                "height": 750
              }
            ]
          },
          "is_completed": false,
          "completed_at": null,
          "completed_common_name": null,
          "completed_scientific_name": null,
          "completed_scan_id": null
        }
        """.utf8)

        let item = try decoder.decode(FieldTripChecklistItem.self, from: json)

        #expect(item.referenceSpecies?.scientificName == "Passer domesticus")
        #expect(item.referenceSpecies?.commonName == "House Sparrow")
        #expect(item.referenceSpecies?.referenceImages.map(\.source) == [.merian, .wikipedia])
    }

    @Test func communityPublicationsDecodeAuthorRankingAndCursorFields() throws {
        let json = Data("""
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
        """.utf8)

        let response = try decoder.decode(FieldTripCommunityPublicationsResponse.self, from: json)

        #expect(response.data.count == 1)
        #expect(response.data[0].publicationId == "publication-1")
        #expect(response.data[0].publicAuthorDisplayName == "Ari")
        #expect(response.data[0].publishedAt == "2026-07-08T01:00:00Z")
        #expect(response.data[0].rankBucket == 0)
        #expect(response.data[0].communityReasonLabel == "Following")
    }

    @Test func fieldTripActivityNotificationDecodesPublicationRoute() throws {
        let json = Data("""
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
        """.utf8)

        let response = try decoder.decode(ExploreNotificationsResponse.self, from: json)

        #expect(response.data[0].fieldTripPublicationId == "publication-1")
        #expect(response.data[0].type == .fieldTripComment)
        #expect(response.data[0].type.isFieldTripNotification)
    }

    @Test func profileSummariesDecodePinnedTripsAndFallbackWhenMissing() throws {
        let v2Json = Data("""
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
        """.utf8)

        let legacyJson = Data("""
        {
          "data": {
            "active": [],
            "published": []
          }
        }
        """.utf8)

        let v2Response = try decoder.decode(FieldTripProfileSummariesResponse.self, from: v2Json)
        let legacyResponse = try decoder.decode(FieldTripProfileSummariesResponse.self, from: legacyJson)

        #expect(v2Response.data.pinned.count == 1)
        #expect(v2Response.data.pinned[0].isPinned)
        #expect(v2Response.data.pinned[0].pinPosition == 1)
        #expect(legacyResponse.data.pinned.isEmpty)
    }

    @Test func publicationDetailDoesNotRequireRawScanIds() throws {
        let json = Data("""
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
        """.utf8)

        let response = try decoder.decode(FieldTripPublicationDetailResponse.self, from: json)

        #expect(response.data.publicationId == "publication-1")
        #expect(response.data.items[0].publicationItemId == "snapshot-1")
        #expect(response.data.items[0].commonName == "Monarch")
        #expect(response.data.viewerHasLiked)
    }

    @Test func challengeCatalogDecodesParticipationAndEntries() throws {
        let json = Data("""
        {
          "data": [
            {
              "challenge_id": "challenge-1",
              "template_id": "template-1",
              "template_slug": "park_pollinators",
              "template_title": "Park Pollinators",
              "slug": "summer_pollinator_watch",
              "title": "Summer Pollinator Watch",
              "subtitle": "A seasonal pollinator challenge.",
              "description": "Find pollinators during summer.",
              "cover_image_url": "https://example.com/pollinators.jpg",
              "starts_at": "2026-06-01T00:00:00Z",
              "ends_at": "2026-08-31T23:59:59Z",
              "status": "live",
              "region_tags": ["global"],
              "season_tags": ["summer"],
              "habitat_tags": ["park"],
              "suggested_hashtags": ["summerpollinators"],
              "is_pro_only": false,
              "is_temporarily_free": true,
              "viewer_has_access": true,
              "access_kind": "temporarily_free",
              "participant_count": 12,
              "completion_count": 4,
              "published_entry_count": 2,
              "viewer_participation": {
                "participation_id": "participation-1",
                "user_field_trip_id": "trip-1",
                "joined_at": "2026-07-08T00:00:00Z",
                "current_level_number": 1,
                "completed_at": null,
                "badge_awarded_at": null,
                "completed_count": 1,
                "target_count": 4
              },
              "template": null,
              "entries": [
                {
                  "entry_id": "entry-1",
                  "challenge_id": "challenge-1",
                  "challenge_slug": "summer_pollinator_watch",
                  "challenge_title": "Summer Pollinator Watch",
                  "template_id": "template-1",
                  "template_slug": "park_pollinators",
                  "template_title": "Park Pollinators",
                  "title": "My Pollinator Watch",
                  "description": null,
                  "published_at": "2026-07-08T01:00:00Z",
                  "like_count": 3,
                  "comment_count": 1,
                  "region_tags": ["global"],
                  "season_tags": ["summer"],
                  "habitat_tags": ["park"],
                  "cover_image_url": null,
                  "item_count": 4,
                  "viewer_has_liked": false,
                  "author_user_id": "author-1",
                  "author_name": "Ari",
                  "author_username": "ari",
                  "author_avatar_url": null
                }
              ]
            }
          ]
        }
        """.utf8)

        let response = try decoder.decode(FieldTripChallengesCatalogResponse.self, from: json)

        #expect(response.data[0].isLive)
        #expect(response.data[0].viewerParticipation?.fractionComplete == 0.25)
        #expect(response.data[0].suggestedHashtags == ["summerpollinators"])
        #expect(response.data[0].entries[0].publicAuthorDisplayName == "Ari")
    }

    @Test func challengeProgressResponseDecodesOptionalChallengeUpdates() throws {
        let json = Data("""
        {
          "data": [],
          "challenge_updates": [
            {
              "participation_id": "participation-1",
              "challenge_id": "challenge-1",
              "slug": "summer_pollinator_watch",
              "title": "Summer Pollinator Watch",
              "current_level_number": 1,
              "current_level_title": "Level 1",
              "completed_count": 2,
              "target_count": 4,
              "is_complete": false,
              "badge_awarded_at": null,
              "suggested_hashtags": ["summerpollinators"],
              "newly_completed_items": [
                {
                  "item_id": "item-1",
                  "prompt": "Butterfly",
                  "common_name": "Monarch",
                  "scientific_name": "Danaus plexippus",
                  "completed_at": "2026-07-08T01:00:00Z"
                }
              ]
            }
          ]
        }
        """.utf8)

        let response = try decoder.decode(FieldTripProgressUpdatesResponse.self, from: json)

        #expect(response.data.isEmpty)
        #expect(response.challengeUpdates.count == 1)
        #expect(response.challengeUpdates[0].suggestedHashtags == ["summerpollinators"])
        #expect(response.challengeUpdates[0].newlyCompletedItems[0].commonName == "Monarch")
        #expect(response.challengeUpdates[0].creditedCompletedCount == nil)
        #expect(response.challengeUpdates[0].toastCompletedCount == 2)
        #expect(response.challengeUpdates[0].toastTargetCount == 4)
    }

    @Test func progressResponseUsesCreditedLevelCountsAfterAdvancement() throws {
        let json = Data("""
        {
          "data": [
            {
              "user_field_trip_id": "trip-1",
              "template_id": "template-1",
              "slug": "backyard_safari",
              "title": "Backyard Safari",
              "current_level_number": 2,
              "current_level_title": "Level 2",
              "completed_count": 0,
              "target_count": 6,
              "is_complete": false,
              "credited_level_number": 1,
              "credited_level_title": "Level 1",
              "credited_completed_count": 4,
              "credited_target_count": 4,
              "newly_completed_items": [
                {
                  "item_id": "item-1",
                  "prompt": "Butterfly or moth",
                  "common_name": "Vine Sphinx",
                  "scientific_name": "Eumorpha vitis",
                  "completed_at": "2026-07-18T14:00:00Z"
                }
              ]
            }
          ],
          "challenge_updates": []
        }
        """.utf8)

        let response = try decoder.decode(FieldTripProgressUpdatesResponse.self, from: json)
        let update = try #require(response.data.first)

        #expect(update.currentLevelNumber == 2)
        #expect(update.completedCount == 0)
        #expect(update.creditedLevelNumber == 1)
        #expect(update.creditedLevelTitle == "Level 1")
        #expect(update.toastCompletedCount == 4)
        #expect(update.toastTargetCount == 4)
    }

    @Test func progressResponseDecodesCorrectionInvalidationMetadata() throws {
        let json = Data("""
        {
          "data": [
            {
              "user_field_trip_id": "trip-1",
              "template_id": "template-1",
              "slug": "park_pollinators",
              "title": "Park Pollinators",
              "current_level_number": 1,
              "current_level_title": "Level 1",
              "completed_count": 0,
              "target_count": 4,
              "is_complete": false,
              "credited_level_number": 1,
              "credited_level_title": "Level 1",
              "credited_completed_count": 0,
              "credited_target_count": 4,
              "newly_completed_items": [],
              "removed_item_ids": ["item-before-correction"]
            }
          ],
          "challenge_updates": []
        }
        """.utf8)

        let response = try decoder.decode(FieldTripProgressUpdatesResponse.self, from: json)

        #expect(response.data.first?.removedItemIds == ["item-before-correction"])
    }

    @Test func scanContributionsDecodeTypedStandardAndEventDestinations() throws {
        let json = Data("""
        {
          "data": [
            {
              "source_kind": "standard_outing",
              "source_id": "trip-1",
              "user_field_trip_id": "trip-1",
              "participation_id": null,
              "template_id": "template-1",
              "challenge_id": null,
              "title": "Park Pollinators",
              "slug": "park_pollinators",
              "item_id": "item-1",
              "prompt": "Butterfly or moth",
              "level_number": 1,
              "level_title": "Level 1",
              "completed_count": 3,
              "target_count": 4,
              "is_complete": false,
              "artwork_prompt": "Butterfly or moth",
              "artwork_template_slug": "park_pollinators",
              "destination_kind": "field_trip",
              "destination_template_id": "template-1",
              "destination_checklist_item_id": "item-1",
              "destination_challenge_id": null
            },
            {
              "source_kind": "event",
              "source_id": "participation-1",
              "user_field_trip_id": "trip-2",
              "participation_id": "participation-1",
              "template_id": "template-2",
              "challenge_id": "challenge-1",
              "title": "Summer Bird Count",
              "slug": "summer_bird_count",
              "item_id": "item-2",
              "prompt": "Bird",
              "level_number": 1,
              "level_title": null,
              "completed_count": 2,
              "target_count": 6,
              "is_complete": false,
              "artwork_prompt": "Bird",
              "artwork_template_slug": "bird_count",
              "destination_kind": "field_trip_challenge",
              "destination_template_id": null,
              "destination_checklist_item_id": null,
              "destination_challenge_id": "challenge-1"
            }
          ]
        }
        """.utf8)

        let response = try decoder.decode(FieldTripScanContributionsResponse.self, from: json)

        #expect(response.data.count == 2)
        #expect(
            response.data[0].destination == .fieldTrip(
                templateId: "template-1",
                checklistItemId: "item-1"
            )
        )
        #expect(
            response.data[1].destination == .fieldTripChallenge(challengeId: "challenge-1")
        )
    }

    @Test func progressResponseDecodesStandardAchievementDestination() throws {
        let json = Data("""
        {
          "data": [],
          "challenge_updates": [],
          "first_field_trip_achievement": {
            "kind": "standard_outing",
            "completed_at": "2026-07-18T14:00:00Z",
            "template_slug": "backyard_safari",
            "challenge_id": null
          },
          "first_field_trip_achievement_newly_unlocked": true
        }
        """.utf8)

        let response = try decoder.decode(FieldTripProgressUpdatesResponse.self, from: json)
        let progress = try #require(response.firstFieldTripAchievement)

        #expect(response.firstFieldTripAchievementNewlyUnlocked)
        #expect(progress.destination == .fieldTripTemplate(slug: "backyard_safari"))
        #expect(progress.awardPayload?.type == .firstFieldTrip)
        #expect(progress.awardPayload?.currentCount == 1)
    }

    @Test func seasonalAchievementDestinationDecodes() throws {
        let json = Data("""
        {
          "data": {
            "kind": "seasonal_challenge",
            "completed_at": "2026-07-18T14:00:00.123Z",
            "template_slug": null,
            "challenge_id": "challenge-1"
          }
        }
        """.utf8)
        let response = try decoder.decode(FirstFieldTripAwardResponse.self, from: json)
        let progress = try #require(response.data)

        #expect(progress.destination == .fieldTripChallenge(challengeId: "challenge-1"))
    }

    @Test func publicFirstFieldTripAwardDecodesWithoutPrivateDestination() throws {
        let json = Data("""
        {
          "type": "first_field_trip",
          "current_count": 1,
          "last_interaction_at": "2026-07-18T14:00:00Z"
        }
        """.utf8)

        let publicAward = try decoder.decode(ExploreAuthorProfileAward.self, from: json)
        let award = try #require(publicAward.awardPayload)

        #expect(award.type == .firstFieldTrip)
        #expect(award.isCompleted)
        #expect(award.destination == nil)
    }

    @Test func profileSummariesDecodeChallengeBadges() throws {
        let json = Data("""
        {
          "data": {
            "active": [],
            "pinned": [],
            "published": [],
            "challenge_badges": [
              {
                "badge_id": "badge-1",
                "challenge_id": "challenge-1",
                "badge_key": "summer_pollinator_watch_complete",
                "title": "Summer Pollinator Watch",
                "awarded_at": "2026-07-08T01:00:00Z",
                "challenge_slug": "summer_pollinator_watch",
                "challenge_title": "Summer Pollinator Watch",
                "cover_image_url": null,
                "region_tags": ["global"],
                "season_tags": ["summer"],
                "habitat_tags": ["park"]
              }
            ]
          }
        }
        """.utf8)

        let response = try decoder.decode(FieldTripProfileSummariesResponse.self, from: json)

        #expect(response.data.challengeBadges.count == 1)
        #expect(!response.data.isEmpty)
        #expect(response.data.challengeBadges[0].challengeTitle == "Summer Pollinator Watch")
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

struct FieldTripCaptureContextModelsTests {
    @Test func captureContextDecodesFocusedPublicContract() throws {
        let json = Data("""
        {
          "data": [
            {
              "user_field_trip_id": "trip-1",
              "template_id": "template-1",
              "template_slug": "backyard_safari",
              "outing_title": "Backyard Safari",
              "last_engaged_at": "2026-07-17T18:00:00Z",
              "level_number": 1,
              "level_title": "Level 1",
              "completed_count": 1,
              "target_count": 4,
              "targets": [
                {
                  "item_id": "butterfly",
                  "prompt": "Butterfly",
                  "sort_order": 10,
                  "has_guide": true
                }
              ]
            }
          ]
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(FieldTripCaptureContextResponse.self, from: json)

        #expect(response.data.count == 1)
        #expect(response.data[0].outingTitle == "Backyard Safari")
        #expect(response.data[0].completedCount == 1)
        #expect(response.data[0].targets[0].prompt == "Butterfly")
        #expect(response.data[0].targets[0].hasGuide)
    }
}
