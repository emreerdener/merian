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
                      "completed_scientific_name": "Cardinalis cardinalis"
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
    }

    @Test func checklistItemUsesLegacyGuideTipAsFallback() {
        let item = FieldTripChecklistItem(
            itemId: "item-legacy",
            prompt: "Butterfly",
            matchType: "taxonomy",
            guideTip: "Look near sunny flowers.",
            guide: nil,
            isCompleted: false,
            completedAt: nil,
            completedCommonName: nil,
            completedScientificName: nil
        )

        #expect(item.hasGuide)
        #expect(item.guidePreview == "Look near sunny flowers.")
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
        #expect(response.data[0].publicAuthorDisplayName == "@ari")
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
        #expect(response.data[0].entries[0].publicAuthorDisplayName == "@ari")
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

    @Test func backyardSafariPresentationUsesSentenceCaseAndBundledCover() {
        #expect(
            FieldTripTemplatePresentation.title(
                "Backyard Safari",
                slug: "backyard_safari"
            ) == "Backyard safari"
        )
        #expect(
            FieldTripTemplatePresentation.title(
                "My backyard discoveries",
                slug: "backyard_safari"
            ) == "My backyard discoveries"
        )
        #expect(
            FieldTripTemplatePresentation.bundledCoverImageName(for: "backyard_safari")
                == "fieldtrip-backyard-safari"
        )
        #expect(FieldTripTemplatePresentation.bundledCoverImageName(for: "park_pollinators") == nil)
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

    private func makeTemplate(id: String, difficulty: String) -> FieldTripTemplate {
        FieldTripTemplate(
            templateId: id,
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
            difficulty: difficulty,
            isProOnly: false,
            isRotatingFree: false,
            viewerHasAccess: true,
            accessKind: "free",
            activeProgress: nil,
            levels: []
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
              "outing_title": "Backyard safari",
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
        #expect(response.data[0].outingTitle == "Backyard safari")
        #expect(response.data[0].completedCount == 1)
        #expect(response.data[0].targets[0].prompt == "Butterfly")
        #expect(response.data[0].targets[0].hasGuide)
    }
}

@MainActor
struct ActiveCaptureGoalStoreTests {
    @Test func fieldTripProviderFlattensServerOrderIntoGenericGoals() async throws {
        let outings = [
            makeOuting(id: "recent", targetIds: ["butterfly", "bird"]),
            makeOuting(id: "older", targetIds: ["cat"])
        ]
        let provider = FieldTripCaptureGoalProvider { outings }

        let goals = try await provider.fetchCaptureGoals()

        #expect(goals.map(\.id) == [
            "field_trip:butterfly",
            "field_trip:bird",
            "field_trip:cat"
        ])
        #expect(goals[0].source.kind == .fieldTrip)
        #expect(goals[0].source.title == "Outing recent")
        #expect(goals[0].destination == .fieldTrip(
            templateId: "template-recent",
            checklistItemId: "butterfly"
        ))
        #expect(goals[0].artwork == .bundledImage(name: "fieldtrip-backyard-butterfly"))
    }

    @Test func preservesProviderOrderAndWrapsInBothDirections() async throws {
        let defaults = makeDefaults()
        let goals = [makeGoal(id: "a"), makeGoal(id: "b"), makeGoal(id: "c")]
        let store = ActiveCaptureGoalStore(userDefaults: defaults) { goals }

        await store.refresh(accountId: "ACCOUNT-A", force: true)

        #expect(store.goals.map(\.id) == ["a", "b", "c"])
        #expect(store.selectedGoal?.id == "a")
        store.selectPrevious()
        #expect(store.selectedGoal?.id == "c")
        store.selectNext()
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
        let writer = ActiveCaptureGoalStore(userDefaults: defaults) { cachedGoals }
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

    @Test func focusedRouteKeepsExistingCallSitesCompatible() {
        #expect(FieldTripTemplateRoute(templateId: "template").focusedChecklistItemId == nil)
        #expect(
            FieldTripTemplateRoute(
                templateId: "template",
                focusedChecklistItemId: "target"
            ).focusedChecklistItemId == "target"
        )
    }

    @Test func focusedTargetUsesTipsWhenAvailableAndObjectivesAsFallback() {
        #expect(FieldTripFocusedTargetPresentation.resolve(hasGuide: true) == .tips)
        #expect(FieldTripFocusedTargetPresentation.resolve(hasGuide: false) == .objectives)
    }

    @Test func captureIndicatorPolicyRequiresIdleVisualScanningAndRealData() {
        let visible = ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isVisualMode: true,
            hasTarget: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        )
        #expect(visible)

        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isVisualMode: true,
            hasTarget: false,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isVisualMode: false,
            hasTarget: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isVisualMode: true,
            hasTarget: true,
            stagedCaptureIsEmpty: false,
            isRefining: false,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isVisualMode: true,
            hasTarget: true,
            stagedCaptureIsEmpty: true,
            isRefining: true,
            isVideoRecording: false
        ))
        #expect(!ActiveCaptureGoalPresentationPolicy.shouldShow(
            goalsEnabled: true,
            isVisualMode: true,
            hasTarget: true,
            stagedCaptureIsEmpty: true,
            isRefining: false,
            isVideoRecording: true
        ))
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
                for: "Unknown future target",
                templateSlug: "backyard_safari"
            ) == nil
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
                title: "Backyard safari"
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

    private func makeOuting(
        id: String,
        completedCount: Int = 0,
        targetIds: [String]
    ) -> FieldTripCaptureOuting {
        FieldTripCaptureOuting(
            userFieldTripId: id,
            templateId: "template-\(id)",
            templateSlug: "backyard_safari",
            outingTitle: "Outing \(id)",
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

    private var values: [[CaptureGoal]]

    init(_ values: [[CaptureGoal]]) {
        self.values = values
    }

    func next() throws -> [CaptureGoal] {
        guard !values.isEmpty else { throw TestError.exhausted }
        return values.removeFirst()
    }
}
