import Foundation
@testable import Merian
import Testing
import UIKit

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
        #expect(response.data.items[0].displayName == "Monarch")
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

    @Test func seasonalAchievementDestinationCachesPerAccountAndMergesAward() throws {
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
        let suiteName = "FirstFieldTripAchievementProgressStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        FirstFieldTripAchievementProgressStore.save(
            progress,
            accountId: "ACCOUNT-A",
            userDefaults: defaults
        )

        #expect(progress.destination == .fieldTripChallenge(challengeId: "challenge-1"))
        #expect(
            FirstFieldTripAchievementProgressStore.load(
                accountId: "account-a",
                userDefaults: defaults
            ) == progress
        )
        #expect(
            FirstFieldTripAchievementProgressStore.load(
                accountId: "account-b",
                userDefaults: defaults
            ) == nil
        )

        let locked = AwardPayload(type: .firstFieldTrip, currentCount: 0, lastInteractionDate: nil)
        let merged = [locked].mergingFirstFieldTripAchievement(progress)
        #expect(merged.count == 1)
        #expect(merged[0].isCompleted)
        #expect(merged[0].destination == .fieldTripChallenge(challengeId: "challenge-1"))
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
        #expect(FieldTripProfilePresentation.hasContent(response.data))
        #expect(FieldTripProfilePresentation.itemCount(in: response.data) == 1)
    }

    @Test func difficultyNormalizesKnownValuesAndPreservesUnknownValues() {
        #expect(FieldTripDifficulty(apiValue: "starter") == .starter)
        #expect(FieldTripDifficulty(apiValue: " EASY ") == .easy)
        #expect(FieldTripDifficulty(apiValue: "Moderate") == .moderate)
        #expect(FieldTripDifficulty(apiValue: "HARD\n") == .hard)
        #expect(FieldTripDifficulty(apiValue: "expert") == nil)

        let unknownTemplate = makeTemplate(id: "expert", difficulty: "expert_level")
        #expect(unknownTemplate.resolvedDifficulty == nil)
        #expect(unknownTemplate.difficultyTitle == "Expert Level")
    }

    @Test func backyardSafariPresentationUsesCanonicalCopyAndBundledCover() {
        #expect(
            FieldTripTemplatePresentation.title(
                "Backyard Safari",
                slug: "backyard_safari"
            ) == "Backyard Safari"
        )
        #expect(
            FieldTripTemplatePresentation.title(
                "Backyard safari",
                slug: "backyard_safari"
            ) == "Backyard Safari"
        )
        #expect(
            FieldTripTemplatePresentation.title(
                "Park Pollinators",
                slug: "park_pollinators"
            ) == "Park Pollinators"
        )
        #expect(
            FieldTripTemplatePresentation.bundledCoverImageName(for: "backyard_safari")
                == "fieldtrip-backyard-safari"
        )
        #expect(FieldTripTemplatePresentation.bundledCoverImageName(for: "park_pollinators") == nil)
    }

    @Test func backyardSafariCardPresentationTracksCurrentLevelProgress() {
        let unstarted = makeCardTemplate()
        let activeLevelTwo = makeCardTemplate(
            activeProgress: makeCardProgress(
                currentLevelNumber: 2,
                completedCount: 2,
                targetCount: 6
            ),
            secondLevelPrompts: ["Flower", "Fungus", "Dog", "Bee", "Squirrel", "Moss"]
        )
        let stoppedLevelTwo = makeCardTemplate(
            stoppedProgress: makeCardProgress(
                currentLevelNumber: 2,
                completedCount: 3,
                targetCount: 6,
                stoppedAt: "2026-07-18T12:30:00Z"
            ),
            secondLevelPrompts: ["Flower", "Fungus", "Dog", "Bee", "Squirrel", "Moss"]
        )

        #expect(FieldTripTemplatePresentation.completedCount(for: unstarted) == 0)
        #expect(FieldTripTemplatePresentation.targetCount(for: unstarted) == 4)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: unstarted) == "Level 1")
        #expect(
            FieldTripTemplatePresentation.subtitle(for: unstarted) ==
                "Observe 4 local species often found in your own backyard."
        )

        #expect(FieldTripTemplatePresentation.completedCount(for: activeLevelTwo) == 2)
        #expect(FieldTripTemplatePresentation.targetCount(for: activeLevelTwo) == 6)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: activeLevelTwo) == "Level 2")
        #expect(
            FieldTripTemplatePresentation.subtitle(for: activeLevelTwo) ==
                "Observe 6 local species often found in your own backyard."
        )

        #expect(FieldTripTemplatePresentation.completedCount(for: stoppedLevelTwo) == 3)
        #expect(FieldTripTemplatePresentation.targetCount(for: stoppedLevelTwo) == 6)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: stoppedLevelTwo) == "Level 2")
    }

    @Test func fieldTripCardPresentationHandlesCompletionAndMissingLevels() {
        let completed = makeCardTemplate(
            activeProgress: makeCardProgress(
                isComplete: true,
                currentLevelNumber: 2,
                completedCount: 6,
                targetCount: 6
            ),
            secondLevelPrompts: ["Flower", "Fungus", "Dog", "Bee", "Squirrel", "Moss"]
        )
        let missingLevels = makeCardTemplate(
            activeProgress: makeCardProgress(
                currentLevelNumber: 2,
                completedCount: 1,
                targetCount: 6
            ),
            prompts: []
        )
        let empty = makeCardTemplate(prompts: [])
        let other = makeTemplate(
            id: "park_pollinators",
            difficulty: "easy",
            subtitle: "Flowers and their pollinators."
        )

        #expect(FieldTripTemplatePresentation.completedCount(for: completed) == 6)
        #expect(FieldTripTemplatePresentation.targetCount(for: completed) == 6)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: completed) == "Level 2")
        #expect(FieldTripTemplatePresentation.targetCount(for: missingLevels) == 6)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: missingLevels) == "Level 2")
        #expect(FieldTripTemplatePresentation.targetCount(for: empty) == 0)
        #expect(FieldTripTemplatePresentation.currentLevelTitle(for: empty) == "Level 1")
        #expect(
            FieldTripTemplatePresentation.subtitle(for: empty) ==
                FieldTripTemplatePresentation.backyardSafariSubtitle
        )
        #expect(
            FieldTripTemplatePresentation.subtitle(for: other) ==
                "Flowers and their pollinators."
        )
    }

    @Test func fieldTripCardTagsHidePublicationStateAndPreserveMetadata() {
        let locked = makeCardTemplate(viewerHasAccess: false, isProOnly: true)
        let privateActive = makeCardTemplate(
            activeProgress: makeCardProgress(completedCount: 0, targetCount: 4)
        )
        let stopped = makeCardTemplate(
            stoppedProgress: makeCardProgress(
                completedCount: 0,
                targetCount: 4,
                stoppedAt: "2026-07-18T12:30:00Z"
            )
        )
        let completed = makeCardTemplate(
            activeProgress: makeCardProgress(
                isComplete: true,
                completedCount: 4,
                targetCount: 4
            )
        )
        let published = makeCardTemplate(
            activeProgress: makeCardProgress(
                isComplete: true,
                completedCount: 4,
                targetCount: 4,
                publicationId: "publication-backyard"
            )
        )

        let locatedTags = FieldTripTemplatePresentation.cardTags(
            for: locked,
            locationLabel: " Austin, TX "
        )
        let unlocatedTags = FieldTripTemplatePresentation.cardTags(
            for: locked,
            locationLabel: "   "
        )

        let expectedLocatedKinds: [FieldTripTemplateTagPresentation.Kind] = [
            .status, .access, .difficulty, .level, .location
        ]
        let expectedUnlocatedKinds: [FieldTripTemplateTagPresentation.Kind] = [
            .status, .access, .difficulty, .level
        ]

        #expect(locatedTags.map(\.kind) == expectedLocatedKinds)
        #expect(
            locatedTags.map(\.title) == [
                "Not started", "Pro", "Starter", "Level 1", "Austin, TX"
            ]
        )
        #expect(
            locatedTags.first(where: { $0.kind == .access })?.systemImage ==
                "lock.fill"
        )
        #expect(unlocatedTags.map(\.kind) == expectedUnlocatedKinds)
        #expect(unlocatedTags.allSatisfy { $0.kind != .visibility })
        let privateActiveTags = FieldTripTemplatePresentation.cardTags(
            for: privateActive,
            locationLabel: nil
        )
        #expect(
            privateActiveTags.map(\.title) == [
                "Active", "Starter", "Level 1"
            ]
        )
        #expect(privateActiveTags.allSatisfy { $0.kind != .visibility })
        let stoppedTags = FieldTripTemplatePresentation.cardTags(
            for: stopped,
            locationLabel: nil
        )
        #expect(
            stoppedTags.map(\.title) == [
                "Stopped", "Starter", "Level 1"
            ]
        )
        #expect(stoppedTags.allSatisfy { $0.kind != .visibility })
        let completedTags = FieldTripTemplatePresentation.cardTags(
            for: completed,
            locationLabel: nil
        )
        #expect(
            completedTags.map(\.title) == [
                "Completed", "Starter", "Level 1"
            ]
        )
        #expect(completedTags.allSatisfy { $0.kind != .visibility })
        let publishedTags = FieldTripTemplatePresentation.cardTags(
            for: published,
            locationLabel: nil
        )
        #expect(
            publishedTags.map(\.title) == [
                "Completed", "Starter", "Level 1"
            ]
        )
        #expect(publishedTags.allSatisfy { $0.kind != .visibility })

        let sharingEnabledTags = FieldTripTemplatePresentation.cardTags(
            for: published,
            locationLabel: nil,
            sharingEnabled: true
        )
        #expect(
            sharingEnabledTags.first(where: { $0.kind == .visibility })?.systemImage ==
                "eye.fill"
        )
    }

    @Test func difficultyFilteringPreservesCatalogOrderAndKeepsUnknownValuesInAll() {
        let templates = [
            makeTemplate(id: "starter", difficulty: " STARTER "),
            makeTemplate(id: "unknown", difficulty: "expert"),
            makeTemplate(id: "easy", difficulty: "easy"),
            makeTemplate(id: "moderate", difficulty: "moderate"),
            makeTemplate(id: "hard", difficulty: "hard")
        ]

        #expect(templates.filtering(by: nil).map(\.templateId) == [
            "starter",
            "unknown",
            "easy",
            "moderate",
            "hard"
        ])
        #expect(templates.filtering(by: .starter).map(\.templateId) == ["starter"])
        #expect(templates.filtering(by: .easy).map(\.templateId) == ["easy"])
        #expect(templates.filtering(by: .moderate).map(\.templateId) == ["moderate"])
        #expect(templates.filtering(by: .hard).map(\.templateId) == ["hard"])
    }

    @Test func catalogStateDistinguishesUnstartedInProgressAndCompletedOutings() {
        let unstarted = makeTemplate(id: "unstarted", difficulty: "starter")
        let startedAtZero = makeTemplate(
            id: "started-zero",
            difficulty: "easy",
            activeProgress: makeProgress(id: "progress-zero", completedCount: 0)
        )
        let partiallyCompleted = makeTemplate(
            id: "partial",
            difficulty: "moderate",
            activeProgress: makeProgress(id: "progress-partial", completedCount: 2)
        )
        let completed = makeTemplate(
            id: "completed",
            difficulty: "hard",
            activeProgress: makeProgress(
                id: "progress-completed",
                completedCount: 4,
                completedAt: "2026-07-18T20:00:00Z"
            )
        )

        #expect(unstarted.catalogState == .incomplete)
        #expect(startedAtZero.catalogState == .inProgress)
        #expect(partiallyCompleted.catalogState == .inProgress)
        #expect(completed.catalogState == .completed)
    }

    @Test func lifecyclePresentationDistinguishesActiveStoppedAndTerminalOutings() {
        let unstarted = makeTemplate(id: "unstarted", difficulty: "starter")
        let activeProgress = makeProgress(id: "active", completedCount: 1)
        let active = makeTemplate(
            id: "active",
            difficulty: "starter",
            activeProgress: activeProgress
        )
        let stopped = makeTemplate(
            id: "stopped",
            difficulty: "starter",
            stoppedProgress: FieldTripProgress(
                userFieldTripId: "stopped",
                startedAt: activeProgress.startedAt,
                currentLevelNumber: activeProgress.currentLevelNumber,
                completedAt: nil,
                isProfileVisible: true,
                completedCount: 1,
                targetCount: 4,
                publicationId: nil,
                publishedAt: nil,
                stoppedAt: "2026-07-19T10:00:00Z"
            )
        )
        let completed = makeTemplate(
            id: "completed",
            difficulty: "starter",
            activeProgress: makeProgress(
                id: "completed",
                completedCount: 4,
                completedAt: "2026-07-19T10:00:00Z"
            )
        )

        #expect(FieldTripDetailLifecyclePresentation.primaryAction(for: unstarted) == .start)
        #expect(!FieldTripDetailLifecyclePresentation.showsOptionsMenu(unstarted))
        #expect(FieldTripDetailLifecyclePresentation.primaryAction(for: active) == .scan)
        #expect(FieldTripDetailLifecyclePresentation.canStop(active))
        #expect(FieldTripDetailLifecyclePresentation.canReset(active))
        #expect(FieldTripDetailLifecyclePresentation.primaryAction(for: stopped) == .resume)
        #expect(!FieldTripDetailLifecyclePresentation.canStop(stopped))
        #expect(FieldTripDetailLifecyclePresentation.canReset(stopped))
        #expect(FieldTripDetailLifecyclePresentation.primaryAction(for: completed) == nil)
        #expect(
            FieldTripDetailLifecyclePresentation.primaryAction(
                for: completed,
                sharingEnabled: true
            ) == .publish
        )
        #expect(!FieldTripDetailLifecyclePresentation.showsOptionsMenu(completed))
    }

    @Test func stateFilteringIsSingleSelectAndPreservesCatalogOrder() {
        let templates = [
            makeTemplate(id: "unstarted-1", difficulty: "starter"),
            makeTemplate(
                id: "started-zero",
                difficulty: "easy",
                activeProgress: makeProgress(id: "progress-zero", completedCount: 0)
            ),
            makeTemplate(
                id: "completed-1",
                difficulty: "moderate",
                activeProgress: makeProgress(
                    id: "progress-completed-1",
                    completedCount: 4,
                    completedAt: "2026-07-18T20:00:00Z"
                )
            ),
            makeTemplate(id: "unstarted-2", difficulty: "hard"),
            makeTemplate(
                id: "partial",
                difficulty: "starter",
                activeProgress: makeProgress(id: "progress-partial", completedCount: 2)
            ),
            makeTemplate(
                id: "completed-2",
                difficulty: "easy",
                activeProgress: makeProgress(
                    id: "progress-completed-2",
                    completedCount: 4,
                    completedAt: "2026-07-18T21:00:00Z"
                )
            )
        ]
        var filters = FieldTripCatalogFilters()

        #expect(templates.filtering(by: filters).map(\.templateId) == [
            "unstarted-1",
            "started-zero",
            "completed-1",
            "unstarted-2",
            "partial",
            "completed-2"
        ])

        filters.state = .incomplete
        #expect(templates.filtering(by: filters).map(\.templateId) == ["unstarted-1", "unstarted-2"])

        filters.state = .inProgress
        #expect(templates.filtering(by: filters).map(\.templateId) == ["started-zero", "partial"])

        filters.state = .completed
        #expect(templates.filtering(by: filters).map(\.templateId) == ["completed-1", "completed-2"])
    }

    @Test func catalogFiltersCombineWithAndSemanticsCountGroupsAndReset() {
        let templates = [
            makeTemplate(
                id: "starter-progress",
                difficulty: "starter",
                activeProgress: makeProgress(id: "starter-progress", completedCount: 1)
            ),
            makeTemplate(
                id: "easy-progress",
                difficulty: "easy",
                activeProgress: makeProgress(id: "easy-progress", completedCount: 0)
            ),
            makeTemplate(
                id: "easy-completed",
                difficulty: "easy",
                activeProgress: makeProgress(
                    id: "easy-completed",
                    completedCount: 4,
                    completedAt: "2026-07-18T22:00:00Z"
                )
            ),
            makeTemplate(id: "unknown-unstarted", difficulty: "expert")
        ]
        var filters = FieldTripCatalogFilters()

        #expect(filters.activeFilterCount == 0)
        #expect(!filters.hasActiveFilters)

        filters.difficulty = .easy
        #expect(filters.activeFilterCount == 1)
        #expect(filters.hasActiveFilters)

        filters.state = .inProgress
        #expect(filters.activeFilterCount == 2)
        #expect(templates.filtering(by: filters).map(\.templateId) == ["easy-progress"])

        filters.reset()
        #expect(filters == FieldTripCatalogFilters())
        #expect(filters.activeFilterCount == 0)
        #expect(templates.filtering(by: filters).map(\.templateId) == [
            "starter-progress",
            "easy-progress",
            "easy-completed",
            "unknown-unstarted"
        ])
    }

    private func makeCardTemplate(
        viewerHasAccess: Bool = true,
        isProOnly: Bool = false,
        activeProgress: FieldTripProgress? = nil,
        stoppedProgress: FieldTripProgress? = nil,
        prompts: [String] = ["Butterfly", "Bird", "Cat", "Spider"],
        secondLevelPrompts: [String] = []
    ) -> FieldTripTemplate {
        var levels: [FieldTripLevel] = []
        if !prompts.isEmpty {
            levels.append(makeCardLevel(number: 1, prompts: prompts))
        }
        if !secondLevelPrompts.isEmpty {
            levels.append(makeCardLevel(number: 2, prompts: secondLevelPrompts))
        }

        return FieldTripTemplate(
            templateId: "template-backyard-card",
            slug: "backyard_safari",
            title: "Backyard Safari",
            subtitle: FieldTripTemplatePresentation.backyardSafariSubtitle,
            description: "Find familiar animals and small wild neighbors.",
            coverImageUrl: nil,
            estimatedDurationMinutes: 30,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: ["global"],
            seasonTags: ["spring", "summer", "fall"],
            habitatTags: ["urban", "yard"],
            difficulty: "starter",
            isProOnly: isProOnly,
            isRotatingFree: !isProOnly,
            viewerHasAccess: viewerHasAccess,
            accessKind: viewerHasAccess ? "free" : (isProOnly ? "pro" : "locked"),
            activeProgress: activeProgress,
            stoppedProgress: stoppedProgress,
            levels: levels
        )
    }

    private func makeCardProgress(
        isComplete: Bool = false,
        currentLevelNumber: Int = 1,
        completedCount: Int,
        targetCount: Int,
        publicationId: String? = nil,
        stoppedAt: String? = nil
    ) -> FieldTripProgress {
        FieldTripProgress(
            userFieldTripId: "outing-backyard-card",
            startedAt: "2026-07-18T12:00:00Z",
            currentLevelNumber: currentLevelNumber,
            completedAt: isComplete ? "2026-07-18T13:00:00Z" : nil,
            isProfileVisible: false,
            completedCount: completedCount,
            targetCount: targetCount,
            publicationId: publicationId,
            publishedAt: publicationId == nil ? nil : "2026-07-18T13:00:00Z",
            stoppedAt: stoppedAt
        )
    }

    private func makeCardLevel(
        number: Int,
        prompts: [String]
    ) -> FieldTripLevel {
        FieldTripLevel(
            levelId: "card-level-\(number)",
            levelNumber: number,
            title: "Level \(number)",
            description: nil,
            items: prompts.enumerated().map { index, prompt in
                FieldTripChecklistItem(
                    itemId: "card-item-\(number)-\(index)",
                    prompt: prompt,
                    matchType: "taxonomy",
                    guideTip: nil,
                    guide: nil,
                    referenceSpecies: nil,
                    isCompleted: false,
                    completedAt: nil,
                    completedCommonName: nil,
                    completedScientificName: nil,
                    completedScanId: nil
                )
            }
        )
    }

    private func makeTemplate(
        id: String,
        difficulty: String,
        subtitle: String? = nil,
        activeProgress: FieldTripProgress? = nil,
        stoppedProgress: FieldTripProgress? = nil
    ) -> FieldTripTemplate {
        return FieldTripTemplate(
            templateId: id,
            slug: id,
            title: id.capitalized,
            subtitle: subtitle,
            description: nil,
            coverImageUrl: nil,
            estimatedDurationMinutes: nil,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: [],
            seasonTags: [],
            habitatTags: [],
            difficulty: difficulty,
            isProOnly: false,
            isRotatingFree: false,
            viewerHasAccess: true,
            accessKind: "free",
            activeProgress: activeProgress,
            stoppedProgress: stoppedProgress,
            levels: []
        )
    }

    private func makeProgress(
        id: String,
        completedCount: Int,
        targetCount: Int = 4,
        completedAt: String? = nil
    ) -> FieldTripProgress {
        FieldTripProgress(
            userFieldTripId: id,
            startedAt: "2026-07-18T19:00:00Z",
            currentLevelNumber: 1,
            completedAt: completedAt,
            isProfileVisible: true,
            completedCount: completedCount,
            targetCount: targetCount,
            publicationId: nil,
            publishedAt: nil,
            stoppedAt: nil
        )
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

struct ActiveFieldTripProfilePresentationTests {
    @Test func activeProfileOrdersOldestStartedFirstAndFiltersUnavailableOrCompletedTrips() {
        let templates = [
            makeTemplate(id: "pollinators", startedAt: "2026-07-18T20:00:00Z"),
            makeTemplate(id: "locked", viewerHasAccess: false),
            makeTemplate(id: "backyard", startedAt: "2026-07-18T18:00:00Z"),
            makeTemplate(id: "completed", isComplete: true),
            makeTemplate(id: "fungi", startedAt: "2026-07-18T22:00:00Z")
        ]

        let items = ActiveFieldTripProfilePresentation.items(
            templates: templates
        )

        #expect(items.map(\.id) == ["backyard", "pollinators", "fungi"])
        #expect(
            ActiveFieldTripProfilePresentation.previewItems(from: items).map(\.id) ==
                ["backyard"]
        )
        #expect(ActiveFieldTripProfilePresentation.shouldShowViewAll(for: items))
        #expect(!ActiveFieldTripProfilePresentation.shouldShowViewAll(for: Array(items.prefix(1))))
    }

    @Test func activeProfileUsesTheCurrentLevelItemsIncludingCompletedScanLinks() throws {
        let template = makeTemplate(
            id: "recent",
            levelNumber: 2,
            completedScanId: "scan-1"
        )

        let item = try #require(
            ActiveFieldTripProfilePresentation.items(
                templates: [template]
            ).first
        )

        #expect(item.currentLevelItems.map(\.prompt) == ["Bird"])
        #expect(item.currentLevelItems.first?.completedScanId == "scan-1")
    }

    @Test func activeCatalogProgressProducesCardsInStartedOrder() {
        let templates = [
            makeTemplate(id: "older", startedAt: "2026-07-18T18:00:00Z"),
            makeTemplate(id: "recent", startedAt: "2026-07-18T20:00:00Z")
        ]

        let items = ActiveFieldTripProfilePresentation.items(
            templates: templates
        )

        #expect(items.map(\.id) == ["older", "recent"])
        #expect(items.first?.completedCount == 1)
        #expect(items.first?.targetCount == 4)
        #expect(items.first?.currentLevelItems.map(\.prompt) == ["Bird"])
    }

    @Test func completedThumbnailFallsBackToTripWhenTheScanIsNotAvailableLocally() {
        #expect(
            FieldTripScanPreviewAction.resolve(
                completedScanId: "scan-1",
                hasLocalScan: false
            ) == .openTemplate
        )
        #expect(
            FieldTripScanPreviewAction.resolve(
                completedScanId: "scan-1",
                hasLocalScan: true
            ) == .openCompletedScan("scan-1")
        )
        #expect(
            FieldTripScanPreviewAction.resolve(
                completedScanId: nil,
                hasLocalScan: true
            ) == .openTemplate
        )
    }

    private func makeTemplate(
        id: String,
        viewerHasAccess: Bool = true,
        isComplete: Bool = false,
        levelNumber: Int = 1,
        completedScanId: String? = nil,
        startedAt: String = "2026-07-18T19:00:00Z"
    ) -> FieldTripTemplate {
        let outingId = id
        return FieldTripTemplate(
            templateId: "template-\(id)",
            slug: id,
            title: id.capitalized,
            subtitle: nil,
            description: nil,
            coverImageUrl: nil,
            estimatedDurationMinutes: nil,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: [],
            seasonTags: [],
            habitatTags: [],
            difficulty: "starter",
            isProOnly: false,
            isRotatingFree: false,
            viewerHasAccess: viewerHasAccess,
            accessKind: viewerHasAccess ? "free" : "locked",
            activeProgress: FieldTripProgress(
                userFieldTripId: outingId,
                startedAt: startedAt,
                currentLevelNumber: levelNumber,
                completedAt: isComplete ? "2026-07-18T20:00:00Z" : nil,
                isProfileVisible: true,
                completedCount: isComplete ? 4 : 1,
                targetCount: 4,
                publicationId: nil,
                publishedAt: nil,
                stoppedAt: nil
            ),
            stoppedProgress: nil,
            levels: [
                FieldTripLevel(
                    levelId: "level-\(levelNumber)",
                    levelNumber: levelNumber,
                    title: "Level \(levelNumber)",
                    description: nil,
                    items: [
                        FieldTripChecklistItem(
                            itemId: "item-bird",
                            prompt: "Bird",
                            matchType: "taxonomy",
                            guideTip: nil,
                            guide: nil,
                            referenceSpecies: nil,
                            isCompleted: completedScanId != nil,
                            completedAt: completedScanId == nil ? nil : "2026-07-18T19:30:00Z",
                            completedCommonName: completedScanId == nil ? nil : "Northern Cardinal",
                            completedScientificName: completedScanId == nil ? nil : "Cardinalis cardinalis",
                            completedScanId: completedScanId
                        )
                    ]
                )
            ]
        )
    }
}

struct EarnedFieldTripPatchPresentationTests {
    @Test func profilePatchesIncludeFinishedLevelsAndTheFinalCompletedLevel() {
        let templates = [
            makeTemplate(
                id: "unstarted",
                slug: FieldTripTemplatePresentation.backyardSafariSlug,
                currentLevelNumber: nil
            ),
            makeTemplate(
                id: "level-one-in-progress",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 1
            ),
            makeTemplate(
                id: "backyard",
                slug: FieldTripTemplatePresentation.backyardSafariSlug,
                currentLevelNumber: 2
            ),
            makeTemplate(
                id: "park",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 2,
                isComplete: true
            ),
            makeTemplate(
                id: "unbundled",
                slug: "forest_edges",
                currentLevelNumber: 2,
                isComplete: true
            )
        ]

        let patches = EarnedFieldTripPatchPresentation.items(templates: templates)

        #expect(
            patches.map(\.imageName) == [
                "fieldtrip-backyard-level-1-patch",
                "fieldtrip-park-level-1-patch",
                "fieldtrip-park-level-2-patch"
            ]
        )
        #expect(
            patches.map(\.title) == [
                "Backyard Safari · Level 1",
                "Park Pollinators · Level 1",
                "Park Pollinators · Level 2"
            ]
        )
        #expect(
            patches.map(\.templateId) == [
                "template-backyard",
                "template-park",
                "template-park"
            ]
        )
        #expect(patches.map(\.galleryItem.id) == patches.map(\.id))
    }

    @Test func stoppedOutingRetainsPatchesForLevelsItAlreadyFinished() {
        let template = makeTemplate(
            id: "stopped-backyard",
            slug: FieldTripTemplatePresentation.backyardSafariSlug,
            currentLevelNumber: 2,
            usesStoppedProgress: true
        )

        let patches = EarnedFieldTripPatchPresentation.items(templates: [template])

        #expect(patches.map(\.imageName) == ["fieldtrip-backyard-level-1-patch"])
    }

    @Test func publicProfileSummariesIncludeOnlyLevelsTheAuthorFinished() {
        let summaries = [
            makeProfileSummary(
                id: "level-one-in-progress",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 1
            ),
            makeProfileSummary(
                id: "backyard",
                slug: FieldTripTemplatePresentation.backyardSafariSlug,
                currentLevelNumber: 2
            ),
            makeProfileSummary(
                id: "park",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 2,
                isComplete: true
            ),
            makeProfileSummary(
                id: "unbundled",
                slug: "forest_edges",
                currentLevelNumber: 2,
                isComplete: true
            )
        ]

        let patches = EarnedFieldTripPatchPresentation.items(profileSummaries: summaries)

        #expect(
            patches.map(\.imageName) == [
                "fieldtrip-backyard-level-1-patch",
                "fieldtrip-park-level-1-patch",
                "fieldtrip-park-level-2-patch"
            ]
        )
        #expect(
            patches.map(\.title) == [
                "Backyard Safari · Level 1",
                "Park Pollinators · Level 1",
                "Park Pollinators · Level 2"
            ]
        )
        #expect(
            patches.map(\.templateId) == [
                "template-backyard",
                "template-park",
                "template-park"
            ]
        )
    }

    @Test func completedThreeLevelOutingsIncludeTheirFinalPatches() {
        let templates = [
            makeTemplate(
                id: "backyard-complete-three",
                slug: FieldTripTemplatePresentation.backyardSafariSlug,
                currentLevelNumber: 3,
                isComplete: true
            ),
            makeTemplate(
                id: "park-complete-three",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 3,
                isComplete: true
            )
        ]

        #expect(
            EarnedFieldTripPatchPresentation.items(templates: templates).map(\.imageName) == [
                "fieldtrip-backyard-level-1-patch",
                "fieldtrip-backyard-level-2-patch",
                "fieldtrip-backyard-level-3-patch",
                "fieldtrip-park-level-1-patch",
                "fieldtrip-park-level-2-patch",
                "fieldtrip-park-level-3-patch"
            ]
        )

        let summaries = [
            makeProfileSummary(
                id: "backyard-complete-three",
                slug: FieldTripTemplatePresentation.backyardSafariSlug,
                currentLevelNumber: 3,
                isComplete: true
            ),
            makeProfileSummary(
                id: "park-complete-three",
                slug: FieldTripTemplatePresentation.parkPollinatorsSlug,
                currentLevelNumber: 3,
                isComplete: true
            )
        ]

        #expect(
            EarnedFieldTripPatchPresentation.items(profileSummaries: summaries).map(\.imageName) == [
                "fieldtrip-backyard-level-1-patch",
                "fieldtrip-backyard-level-2-patch",
                "fieldtrip-backyard-level-3-patch",
                "fieldtrip-park-level-1-patch",
                "fieldtrip-park-level-2-patch",
                "fieldtrip-park-level-3-patch"
            ]
        )
    }

    private func makeProfileSummary(
        id: String,
        slug: String,
        currentLevelNumber: Int,
        isComplete: Bool = false
    ) -> FieldTripProfileActiveSummary {
        FieldTripProfileActiveSummary(
            userFieldTripId: "outing-\(id)",
            templateId: "template-\(id)",
            slug: slug,
            title: slug == FieldTripTemplatePresentation.parkPollinatorsSlug
                ? "Park Pollinators"
                : "Backyard Safari",
            startedAt: "2026-07-18T19:00:00Z",
            currentLevelNumber: currentLevelNumber,
            currentLevelTitle: "Level \(currentLevelNumber)",
            completedCount: isComplete ? 6 : 0,
            targetCount: isComplete ? 6 : 4,
            isComplete: isComplete
        )
    }

    private func makeTemplate(
        id: String,
        slug: String,
        currentLevelNumber: Int?,
        isComplete: Bool = false,
        usesStoppedProgress: Bool = false
    ) -> FieldTripTemplate {
        let progress = currentLevelNumber.map { levelNumber in
            FieldTripProgress(
                userFieldTripId: "outing-\(id)",
                startedAt: "2026-07-18T19:00:00Z",
                currentLevelNumber: levelNumber,
                completedAt: isComplete ? "2026-07-18T20:00:00Z" : nil,
                isProfileVisible: true,
                completedCount: isComplete ? 6 : 0,
                targetCount: isComplete ? 6 : 4,
                publicationId: nil,
                publishedAt: nil,
                stoppedAt: usesStoppedProgress ? "2026-07-18T20:30:00Z" : nil
            )
        }

        return FieldTripTemplate(
            templateId: "template-\(id)",
            slug: slug,
            title: slug == FieldTripTemplatePresentation.parkPollinatorsSlug
                ? "Park Pollinators"
                : "Backyard Safari",
            subtitle: nil,
            description: nil,
            coverImageUrl: nil,
            estimatedDurationMinutes: nil,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: [],
            seasonTags: [],
            habitatTags: [],
            difficulty: "starter",
            isProOnly: false,
            isRotatingFree: false,
            viewerHasAccess: true,
            accessKind: "free",
            activeProgress: usesStoppedProgress ? nil : progress,
            stoppedProgress: usesStoppedProgress ? progress : nil,
            levels: [1, 2, 3].map { levelNumber in
                FieldTripLevel(
                    levelId: "level-\(id)-\(levelNumber)",
                    levelNumber: levelNumber,
                    title: "Level \(levelNumber)",
                    description: nil,
                    items: []
                )
            }
        )
    }
}

@MainActor
struct ActiveCaptureGoalStoreTests {
    @Test func fieldTripsUsesOutingsAndEventsFeatureLabels() {
        #expect(FieldTripsSection.fieldTrips.title == "Outings")
        #expect(FieldTripsSection.seasonal.title == "Events")
        #expect(FieldTripsSection.allCases == [.fieldTrips, .seasonal])
    }

    @Test func fieldTripProviderFlattensServerOrderIntoGenericGoals() async throws {
        let outings = [
            makeOuting(id: "recent", targetIds: ["butterfly", "bird"]),
            makeOuting(id: "older", targetIds: ["cat"])
        ]
        let provider = FieldTripCaptureGoalProvider(
            fetchContext: { outings },
            fetchTemplate: { _ in throw CaptureGoalContextQueue.TestError.expected }
        )

        let context = try await provider.fetchCaptureGoalContext()
        let goals = context.goals

        #expect(context.introduction == nil)
        #expect(goals.map(\.id) == [
            "field_trip:butterfly",
            "field_trip:bird",
            "field_trip:cat"
        ])
        #expect(goals[0].source.kind == .fieldTrip)
        #expect(goals[0].source.title == "Field trip recent")
        #expect(goals[0].destination == .fieldTrip(
            templateId: "template-recent",
            checklistItemId: "butterfly"
        ))
        #expect(goals[0].artwork == .bundledImage(name: "fieldtrip-backyard-butterfly"))
    }

    @Test func fieldTripProviderBuildsBackyardIntroductionFromAnUnstartedTemplate() async throws {
        let provider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { slug in
                #expect(slug == "backyard_safari")
                return makeTemplate()
            }
        )

        let context = try await provider.fetchCaptureGoalContext()
        let introduction = try #require(context.introduction)

        #expect(context.goals.isEmpty)
        #expect(introduction.headline == "Start an outing")
        #expect(introduction.subheadline == "Backyard Safari · 2 goals")
        #expect(introduction.progress == CaptureGoalProgress(completedCount: 0, targetCount: 2))
        #expect(introduction.artworks == [
            .bundledImage(name: "fieldtrip-backyard-cardinal"),
            .bundledImage(name: "fieldtrip-backyard-dog")
        ])
        #expect(introduction.destination == .fieldTripTemplate(slug: "backyard_safari"))
        #expect(introduction.accessibilityLabel == "Start an outing. Backyard Safari, 2 goals.")
        #expect(introduction.accessibilityValue == "0 of 2 goals complete.")
        #expect(introduction.accessibilityHint == "Opens outing details.")
    }

    @Test func fieldTripProviderSuppressesIntroductionForUnavailableStartedStoppedOrEmptyTemplates() async throws {
        let unavailableProvider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in makeTemplate(viewerHasAccess: false) }
        )
        let startedProvider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in makeTemplate(activeProgress: makeProgress()) }
        )
        let completedProvider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in makeTemplate(activeProgress: makeProgress(isComplete: true)) }
        )
        let stoppedProvider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in
                makeTemplate(stoppedProgress: makeProgress(stoppedAt: "2026-07-19T10:00:00Z"))
            }
        )
        let emptyProvider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in makeTemplate(prompts: []) }
        )

        #expect(try await unavailableProvider.fetchCaptureGoalContext().introduction == nil)
        #expect(try await startedProvider.fetchCaptureGoalContext().introduction == nil)
        #expect(try await completedProvider.fetchCaptureGoalContext().introduction == nil)
        #expect(try await stoppedProvider.fetchCaptureGoalContext().introduction == nil)
        #expect(try await emptyProvider.fetchCaptureGoalContext().introduction == nil)
    }

    @Test func fieldTripProviderRequiresACompleteSuccessfulIntroductionLookup() async {
        let provider = FieldTripCaptureGoalProvider(
            fetchContext: { [] },
            fetchTemplate: { _ in throw CaptureGoalContextQueue.TestError.expected }
        )

        await #expect(throws: CaptureGoalContextQueue.TestError.self) {
            try await provider.fetchCaptureGoalContext()
        }
    }

    @Test func preservesProviderOrderAndWrapsInBothDirections() async throws {
        let defaults = makeDefaults()
        let goals = [makeGoal(id: "a"), makeGoal(id: "b"), makeGoal(id: "c")]
        let store = ActiveCaptureGoalStore(userDefaults: defaults) {
            CaptureGoalContextSnapshot(goals: goals, introduction: nil)
        }

        await store.refresh(accountId: "ACCOUNT-A", force: true)

        #expect(store.goals.map(\.id) == ["a", "b", "c"])
        #expect(store.selectedGoal?.id == "a")
        store.selectPrevious()
        #expect(store.selectedGoal?.id == "c")
        store.selectNext()
        #expect(store.selectedGoal?.id == "a")
    }

    @Test func overlappingStartupRefreshesShareOneProviderFetch() async {
        let defaults = makeDefaults()
        let fetcher = SuspendedCaptureGoalContextFetcher(
            snapshot: CaptureGoalContextSnapshot(
                goals: [makeGoal(id: "a")],
                introduction: nil
            )
        )
        let store = ActiveCaptureGoalStore(userDefaults: defaults) {
            await fetcher.fetch()
        }

        let firstRefresh = Task {
            await store.refreshIfStale(accountId: "account")
        }
        while !store.isLoading {
            await Task.yield()
        }
        while await fetcher.callCount == 0 {
            await Task.yield()
        }

        await store.refreshIfStale(accountId: "account")
        await fetcher.resume()
        await firstRefresh.value
        await Task.yield()

        #expect(await fetcher.callCount == 1)
        #expect(store.selectedGoal?.id == "a")
    }

    @Test func completionAdvancesToTheNextTargetAtTheSameFlattenedPosition() async throws {
        let defaults = makeDefaults()
        let queue = CaptureGoalContextQueue([
            [makeGoal(id: "a"), makeGoal(id: "b"), makeGoal(id: "c")],
            [makeGoal(id: "a", completedCount: 1), makeGoal(id: "c", completedCount: 1)]
        ])
        let store = ActiveCaptureGoalStore(userDefaults: defaults) {
            try await queue.next()
        }

        await store.refresh(accountId: "account", force: true)
        store.selectNext()
        #expect(store.selectedGoal?.id == "b")

        await store.refresh(accountId: "account", force: true)
        #expect(store.selectedGoal?.id == "c")
    }

    @Test func cacheIsAccountIsolatedAndSurvivesRefreshFailure() async throws {
        let defaults = makeDefaults()
        let cachedGoals = [makeGoal(id: "a"), makeGoal(id: "b")]
        let writer = ActiveCaptureGoalStore(userDefaults: defaults) {
            CaptureGoalContextSnapshot(goals: cachedGoals, introduction: nil)
        }
        await writer.refresh(accountId: "account-a", force: true)
        writer.selectNext()

        let reader = ActiveCaptureGoalStore(userDefaults: defaults) {
            throw CaptureGoalContextQueue.TestError.expected
        }
        reader.activate(accountId: "account-a")
        #expect(reader.selectedGoal?.id == "b")

        await reader.refresh(accountId: "account-a", force: true)
        #expect(reader.selectedGoal?.id == "b")
        #expect(reader.goals.map(\.id) == ["a", "b"])

        reader.activate(accountId: "account-b")
        #expect(reader.goals.isEmpty)
        #expect(reader.selectedGoal == nil)
    }

    @Test func introductionWaitsForSuccessCachesPerAccountAndSurvivesFailure() async throws {
        let defaults = makeDefaults()
        let introduction = makeIntroduction()
        let writer = ActiveCaptureGoalStore(userDefaults: defaults) {
            CaptureGoalContextSnapshot(goals: [], introduction: introduction)
        }

        writer.activate(accountId: "account-a")
        #expect(writer.presentation == nil)

        await writer.refresh(accountId: "account-a", force: true)
        #expect(writer.presentation == .introduction(introduction))

        let reader = ActiveCaptureGoalStore(userDefaults: defaults) {
            throw CaptureGoalContextQueue.TestError.expected
        }
        reader.activate(accountId: "ACCOUNT-A")
        #expect(reader.presentation == .introduction(introduction))

        await reader.refresh(accountId: "account-a", force: true)
        #expect(reader.presentation == .introduction(introduction))

        reader.activate(accountId: "account-b")
        #expect(reader.presentation == nil)
    }

    @Test func activeGoalsReplaceAnIntroductionSnapshot() async throws {
        let defaults = makeDefaults()
        let introduction = makeIntroduction()
        let queue = CaptureGoalContextQueue(snapshots: [
            CaptureGoalContextSnapshot(goals: [], introduction: introduction),
            CaptureGoalContextSnapshot(goals: [makeGoal(id: "a")], introduction: introduction)
        ])
        let store = ActiveCaptureGoalStore(userDefaults: defaults) {
            try await queue.next()
        }

        await store.refresh(accountId: "account", force: true)
        #expect(store.presentation == .introduction(introduction))

        await store.refresh(accountId: "account", force: true)
        #expect(store.presentation == .goal(makeGoal(id: "a")))
        #expect(store.introduction == nil)
    }

    @Test func legacyGoalOnlyCacheStillDecodesWithoutAnIntroduction() throws {
        let defaults = makeDefaults()
        let accountId = "legacy-account"
        let cachedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let envelope = LegacyCaptureGoalCacheEnvelope(
            goals: [makeGoal(id: "legacy")],
            selectedGoalId: "legacy",
            refreshedAt: cachedAt
        )
        defaults.set(
            try JSONEncoder().encode(envelope),
            forKey: UserDefaultsKeys.captureGoalContextPrefix + accountId
        )
        let store = ActiveCaptureGoalStore(userDefaults: defaults) {
            throw CaptureGoalContextQueue.TestError.expected
        }

        store.activate(accountId: accountId)

        #expect(store.selectedGoal?.id == "legacy")
        #expect(store.introduction == nil)
        #expect(store.lastSuccessfulRefreshAt == cachedAt)
    }

    @Test func focusedRouteKeepsExistingCallSitesCompatible() {
        #expect(FieldTripTemplateRoute(templateId: "template").focusedChecklistItemId == nil)
        #expect(
            FieldTripTemplateRoute(
                templateId: "template",
                focusedChecklistItemId: "target"
            ).focusedChecklistItemId == "target"
        )
        #expect(FieldTripTemplateRoute(slug: "backyard_safari").reference == .slug("backyard_safari"))
    }

    @Test func inlineTipsAppearOnlyForTheCurrentIncompleteLevel() {
        #expect(FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: 2,
            currentLevelNumber: 2,
            isTripComplete: false,
            hasGuide: true
        ))
        #expect(!FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: 1,
            currentLevelNumber: 2,
            isTripComplete: false,
            hasGuide: true
        ))
        #expect(!FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: 3,
            currentLevelNumber: 2,
            isTripComplete: false,
            hasGuide: true
        ))
        #expect(!FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: 2,
            currentLevelNumber: 2,
            isTripComplete: true,
            hasGuide: true
        ))
        #expect(!FieldTripInlineTipsPresentation.shouldShow(
            levelNumber: 2,
            currentLevelNumber: 2,
            isTripComplete: false,
            hasGuide: false
        ))
    }

    @Test func captureIndicatorPolicyRequiresIdleVisualScanningAndRealData() {
        let visible = ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            hasPresentation: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        )
        #expect(visible)

        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            hasPresentation: false,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: false,
            hasPresentation: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            hasPresentation: true,
            stagedCaptureIsEmpty: false,
            isRefining: false,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            hasPresentation: true,
            stagedCaptureIsEmpty: true,
            isRefining: true,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            hasPresentation: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: true
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isUserVisible: false,
            isVisualMode: true,
            hasPresentation: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        ))
    }

    @Test func selectedStandardGoalRemainsPreferredAfterCameraMediaIsStaged() {
        let goal = makeGoal(id: "butterfly")

        let preferred = CaptureGoalPreferencePolicy.preferredGoal(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            isRefining: false,
            selectedGoal: goal
        )

        #expect(preferred == FieldTripPreferredGoal(
            userFieldTripId: "outing",
            itemId: "butterfly"
        ))
        #expect(CaptureGoalPreferencePolicy.preferredGoal(
            goalsEnabled: true,
            isUserVisible: false,
            isVisualMode: true,
            isRefining: false,
            selectedGoal: goal
        ) == nil)
        #expect(CaptureGoalPreferencePolicy.preferredGoal(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            isRefining: true,
            selectedGoal: goal
        ) == nil)

        let challengeGoal = CaptureGoal(
            id: "challenge",
            source: goal.source,
            prompt: goal.prompt,
            progress: goal.progress,
            artwork: goal.artwork,
            destination: .fieldTripChallenge(challengeId: "challenge")
        )
        #expect(CaptureGoalPreferencePolicy.preferredGoal(
            goalsEnabled: true,
            isUserVisible: true,
            isVisualMode: true,
            isRefining: false,
            selectedGoal: challengeGoal
        ) == nil)
    }

    @Test func captureIndicatorOnlyClaimsHorizontalDominantSwipes() {
        #expect(ActiveCaptureGoalSwipeDirection.resolve(horizontal: -60, vertical: 8) == .next)
        #expect(ActiveCaptureGoalSwipeDirection.resolve(horizontal: 60, vertical: 8) == .previous)
        #expect(ActiveCaptureGoalSwipeDirection.resolve(horizontal: 20, vertical: 2) == nil)
        #expect(ActiveCaptureGoalSwipeDirection.resolve(horizontal: 50, vertical: 60) == nil)
    }

    @Test func captureIndicatorUsesOnlyExactBundledObjectiveArtwork() {
        #expect(
            FieldTripObjectiveArtwork.exactImageName(
                for: "Butterfly",
                templateSlug: "backyard_safari"
            ) == "fieldtrip-backyard-butterfly"
        )
        #expect(
            FieldTripObjectiveArtwork.exactImageName(
                for: "Dog",
                templateSlug: "backyard_safari"
            ) == "fieldtrip-backyard-dog"
        )
        #expect(
            FieldTripObjectiveArtwork.exactImageName(
                for: "Spider",
                templateSlug: "park_pollinators"
            ) == "fieldtrip-park-spider"
        )
        #expect(
            FieldTripObjectiveArtwork.exactImageName(
                for: "Meadow plant",
                templateSlug: "park_pollinators"
            ) == "fieldtrip-park-habitat"
        )
        #expect(
            FieldTripObjectiveArtwork.exactImageName(
                for: "Unknown future target",
                templateSlug: "backyard_safari"
            ) == nil
        )
    }

    @Test func captureIntroductionArtworkAssetsAreBundled() {
        let appBundle = Bundle(for: AppDelegate.self)
        let imageNames = [
            "fieldtrip-backyard-cardinal",
            "fieldtrip-backyard-dog"
        ]

        for imageName in imageNames {
            #expect(
                UIImage(
                    named: imageName,
                    in: appBundle,
                    compatibleWith: nil
                ) != nil
            )
        }
    }

    @Test func captureIntroductionArtworkRotationAlwaysResolvesAVisibleItem() {
        let bird = CaptureGoalArtwork.bundledImage(name: "fieldtrip-backyard-cardinal")
        let dog = CaptureGoalArtwork.bundledImage(name: "fieldtrip-backyard-dog")
        let artworks = [bird, dog]

        #expect(CaptureGoalArtworkRotation.artwork(at: 0, in: artworks) == bird)
        #expect(CaptureGoalArtworkRotation.artwork(at: 1, in: artworks) == dog)
        #expect(CaptureGoalArtworkRotation.artwork(at: 2, in: artworks) == bird)
        #expect(CaptureGoalArtworkRotation.artwork(at: -1, in: artworks) == dog)
        #expect(CaptureGoalArtworkRotation.nextIndex(after: 0, count: 2) == 1)
        #expect(CaptureGoalArtworkRotation.nextIndex(after: 1, count: 2) == 0)
        #expect(
            CaptureGoalArtworkRotation.artwork(at: 4, in: [])
                == .systemSymbol(name: "binoculars.fill")
        )
    }

    @Test func levelArtworkMapsBundledPatchesByOutingAndLevel() {
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "backyard_safari",
                levelNumber: 1
            ) == "fieldtrip-backyard-level-1-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "backyard_safari",
                levelNumber: 2
            ) == "fieldtrip-backyard-level-2-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "backyard_safari",
                levelNumber: 3
            ) == "fieldtrip-backyard-level-3-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "park_pollinators",
                levelNumber: 1
            ) == "fieldtrip-park-level-1-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "park_pollinators",
                levelNumber: 2
            ) == "fieldtrip-park-level-2-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "park_pollinators",
                levelNumber: 3
            ) == "fieldtrip-park-level-3-patch"
        )
        #expect(
            FieldTripLevelArtwork.imageName(
                templateSlug: "forest_edges",
                levelNumber: 1
            ) == nil
        )
    }

    @Test func captureIndicatorFramesExactPromptsAsOutingGoals() {
        #expect(
            ["Bird", "Butterfly or moth", "Moss or lichen"].map(
                ActiveCaptureGoalIndicatorCopy.instruction(for:)
            ) == [
                "Goal: Bird",
                "Goal: Butterfly or moth",
                "Goal: Moss or lichen"
            ]
        )
        #expect(
            ActiveCaptureGoalIndicatorCopy.accessibilityLabel(for: "Fungus") ==
                "Outing goal. Fungus."
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "merian.tests.capture-goal-context.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeGoal(
        id: String,
        completedCount: Int = 0
    ) -> CaptureGoal {
        CaptureGoal(
            id: id,
            source: CaptureGoalSource(
                kind: .fieldTrip,
                id: "outing",
                title: "Backyard Safari"
            ),
            prompt: id.uppercased(),
            progress: CaptureGoalProgress(
                completedCount: completedCount,
                targetCount: 3
            ),
            artwork: .systemSymbol(name: "binoculars.fill"),
            destination: .fieldTrip(
                templateId: "template",
                checklistItemId: id
            )
        )
    }

    private func makeIntroduction() -> CaptureGoalIntroduction {
        CaptureGoalIntroduction(
            id: "field_trip_introduction:backyard_safari",
            sourceKind: .fieldTrip,
            headline: "Start an outing",
            subheadline: "Backyard Safari · 2 goals",
            progress: CaptureGoalProgress(completedCount: 0, targetCount: 2),
            artworks: [
                .bundledImage(name: "fieldtrip-backyard-cardinal"),
                .bundledImage(name: "fieldtrip-backyard-dog")
            ],
            destination: .fieldTripTemplate(slug: "backyard_safari"),
            accessibilityLabel: "Start an outing. Backyard Safari, 2 goals.",
            accessibilityValue: "0 of 2 goals complete.",
            accessibilityHint: "Opens outing details."
        )
    }

    nonisolated private func makeTemplate(
        viewerHasAccess: Bool = true,
        activeProgress: FieldTripProgress? = nil,
        stoppedProgress: FieldTripProgress? = nil,
        prompts: [String] = ["Bird", "Dog"]
    ) -> FieldTripTemplate {
        FieldTripTemplate(
            templateId: "template-backyard",
            slug: "backyard_safari",
            title: "Backyard Safari",
            subtitle: FieldTripTemplatePresentation.backyardSafariSubtitle,
            description: "Find familiar animals and small wild neighbors.",
            coverImageUrl: nil,
            estimatedDurationMinutes: 30,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: ["global"],
            seasonTags: ["spring", "summer", "fall"],
            habitatTags: ["urban", "yard"],
            difficulty: "starter",
            isProOnly: false,
            isRotatingFree: true,
            viewerHasAccess: viewerHasAccess,
            accessKind: viewerHasAccess ? "free" : "locked",
            activeProgress: activeProgress,
            stoppedProgress: stoppedProgress,
            levels: prompts.isEmpty ? [] : [
                FieldTripLevel(
                    levelId: "level-1",
                    levelNumber: 1,
                    title: "Level 1",
                    description: "A compact neighborhood checklist.",
                    items: prompts.enumerated().map { index, prompt in
                        FieldTripChecklistItem(
                            itemId: "item-\(index)",
                            prompt: prompt,
                            matchType: "taxonomy",
                            guideTip: nil,
                            guide: nil,
                            referenceSpecies: nil,
                            isCompleted: false,
                            completedAt: nil,
                            completedCommonName: nil,
                            completedScientificName: nil,
                            completedScanId: nil
                        )
                    }
                )
            ]
        )
    }

    nonisolated private func makeProgress(
        isComplete: Bool = false,
        stoppedAt: String? = nil
    ) -> FieldTripProgress {
        FieldTripProgress(
            userFieldTripId: "outing-backyard",
            startedAt: "2026-07-18T12:00:00Z",
            currentLevelNumber: 1,
            completedAt: isComplete ? "2026-07-18T13:00:00Z" : nil,
            isProfileVisible: false,
            completedCount: isComplete ? 4 : 0,
            targetCount: 4,
            publicationId: nil,
            publishedAt: nil,
            stoppedAt: stoppedAt
        )
    }

    private func makeOuting(
        id: String,
        completedCount: Int = 0,
        targetIds: [String]
    ) -> FieldTripCaptureOuting {
        FieldTripCaptureOuting(
            userFieldTripId: id,
            templateId: "template-\(id)",
            templateSlug: "backyard_safari",
            outingTitle: "Field trip \(id)",
            lastEngagedAt: "2026-07-17T18:00:00Z",
            levelNumber: 1,
            levelTitle: "Level 1",
            completedCount: completedCount,
            targetCount: completedCount + targetIds.count,
            targets: targetIds.enumerated().map { index, itemId in
                FieldTripCaptureTarget(
                    itemId: itemId,
                    prompt: itemId.uppercased(),
                    sortOrder: (index + 1) * 10,
                    hasGuide: true
                )
            }
        )
    }
}

private actor CaptureGoalContextQueue {
    enum TestError: Error {
        case expected
        case exhausted
    }

    private var values: [CaptureGoalContextSnapshot]

    init(_ values: [[CaptureGoal]]) {
        self.values = values.map {
            CaptureGoalContextSnapshot(goals: $0, introduction: nil)
        }
    }

    init(snapshots: [CaptureGoalContextSnapshot]) {
        values = snapshots
    }

    func next() throws -> CaptureGoalContextSnapshot {
        guard !values.isEmpty else { throw TestError.exhausted }
        return values.removeFirst()
    }
}

private actor SuspendedCaptureGoalContextFetcher {
    private(set) var callCount = 0
    private let snapshot: CaptureGoalContextSnapshot
    private var continuation: CheckedContinuation<Void, Never>?

    init(snapshot: CaptureGoalContextSnapshot) {
        self.snapshot = snapshot
    }

    func fetch() async -> CaptureGoalContextSnapshot {
        callCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return snapshot
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private struct LegacyCaptureGoalCacheEnvelope: Codable {
    let goals: [CaptureGoal]
    let selectedGoalId: String?
    let refreshedAt: Date
}
