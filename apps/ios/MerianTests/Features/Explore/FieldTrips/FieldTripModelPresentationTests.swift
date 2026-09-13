import Foundation
@testable import Merian
import Testing

struct FieldTripModelPresentationTests {
    @Test func communityModesRetainVisibleTitles() {
        #expect(FieldTripCommunityMode.smart.title == "For You")
        #expect(FieldTripCommunityMode.following.title == "Following")
        #expect(FieldTripCommunityMode.recent.title == "Recent")
    }

    @Test func guidePresentationPrefersStructuredContentAndFallsBackToLegacyTip() {
        let structured = checklistItem(
            guideTip: "Legacy tip",
            guide: FieldTripChecklistItemGuide(
                whereToLook: "  Check shrubs and tree canopies.  ",
                bestConditions: nil,
                whatToNotice: nil,
                scanSafely: nil
            )
        )
        let legacy = checklistItem(guideTip: "  Look near sunny flowers.  ")
        let blank = checklistItem(guideTip: " \n ")

        #expect(structured.hasGuide)
        #expect(structured.guidePreview == "Check shrubs and tree canopies.")
        #expect(legacy.hasGuide)
        #expect(legacy.guidePreview == "Look near sunny flowers.")
        #expect(!blank.hasGuide)
        #expect(blank.guidePreview == nil)
    }

    @Test func lifecyclePresentationRetainsProgressAndStoppedFallbacks() {
        let active = progress(
            id: "active",
            completedCount: 5,
            targetCount: 4,
            completedAt: "2026-07-18T14:00:00Z",
            publicationId: "publication-1"
        )
        let stopped = progress(
            id: "stopped",
            completedCount: 2,
            targetCount: 4,
            stoppedAt: "2026-07-18T13:00:00Z"
        )
        let activeTemplate = template(activeProgress: active)
        let stoppedTemplate = template(stoppedProgress: stopped)

        #expect(active.isComplete)
        #expect(active.isPublished)
        #expect(active.fractionComplete == 1)
        #expect(activeTemplate.viewerProgress == active)
        #expect(!activeTemplate.isStopped)
        #expect(stoppedTemplate.viewerProgress == stopped)
        #expect(stoppedTemplate.isStopped)
    }

    @Test func eventLifecyclePresentationRetainsStatusAndClampedProgress() throws {
        let participation = FieldTripChallengeParticipation(
            participationId: "participation-1",
            userFieldTripId: "outing-1",
            joinedAt: "2026-07-18T12:00:00Z",
            currentLevelNumber: 1,
            completedAt: nil,
            badgeAwardedAt: nil,
            completedCount: -1,
            targetCount: 4
        )
        let live = try challenge(status: "live")
        let upcoming = try challenge(status: "upcoming")
        let ended = try challenge(status: "ended")

        #expect(live.isLive)
        #expect(upcoming.isUpcoming)
        #expect(ended.isEnded)
        #expect(!participation.isComplete)
        #expect(participation.fractionComplete == 0)
    }

    @Test func publicationPresentationRetainsAuthorAndCommunityLabels() throws {
        let followed = try publication(
            authorName: "Ari",
            authorUsername: "ari",
            communityReason: "global",
            viewerIsFollowingAuthor: true
        )
        let nearby = try publication(
            authorName: "",
            authorUsername: "mina",
            communityReason: "near_you",
            viewerIsFollowingAuthor: false
        )
        let unknown = try publication(
            authorName: "Mina",
            authorUsername: nil,
            communityReason: "unexpected",
            viewerIsFollowingAuthor: false
        )

        #expect(followed.publicAuthorDisplayName == "Ari")
        #expect(followed.communityReasonLabel == "Following")
        #expect(nearby.publicAuthorDisplayName == "@mina")
        #expect(nearby.communityReasonLabel == "Near you")
        #expect(unknown.communityReasonLabel == nil)
    }

    @Test func profileSummaryEmptinessIncludesEventBadges() throws {
        let empty = try summaries()
        let withBadge = try summaries(includingBadge: true)

        #expect(empty.isEmpty)
        #expect(!withBadge.isEmpty)
    }

    private func checklistItem(
        guideTip: String?,
        guide: FieldTripChecklistItemGuide? = nil
    ) -> FieldTripChecklistItem {
        FieldTripChecklistItem(
            itemId: "item-1",
            prompt: "Butterfly",
            matchType: "taxonomy",
            guideTip: guideTip,
            guide: guide,
            referenceSpecies: nil,
            isCompleted: false,
            completedAt: nil,
            completedCommonName: nil,
            completedScientificName: nil,
            completedScanId: nil
        )
    }

    private func progress(
        id: String,
        completedCount: Int,
        targetCount: Int,
        completedAt: String? = nil,
        publicationId: String? = nil,
        stoppedAt: String? = nil
    ) -> FieldTripProgress {
        FieldTripProgress(
            userFieldTripId: id,
            startedAt: "2026-07-18T12:00:00Z",
            currentLevelNumber: 1,
            completedAt: completedAt,
            isProfileVisible: true,
            completedCount: completedCount,
            targetCount: targetCount,
            publicationId: publicationId,
            publishedAt: publicationId == nil ? nil : "2026-07-18T14:05:00Z",
            stoppedAt: stoppedAt
        )
    }

    private func template(
        activeProgress: FieldTripProgress? = nil,
        stoppedProgress: FieldTripProgress? = nil
    ) -> FieldTripTemplate {
        FieldTripTemplate(
            templateId: "template-1",
            slug: "backyard_safari",
            title: "Backyard Safari",
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
            isRotatingFree: true,
            viewerHasAccess: true,
            accessKind: "free",
            activeProgress: activeProgress,
            stoppedProgress: stoppedProgress,
            levels: []
        )
    }

    private func challenge(status: String) throws -> FieldTripChallenge {
        let data = Data("""
        {
          "challenge_id": "challenge-1",
          "template_id": "template-1",
          "template_slug": "park_pollinators",
          "template_title": "Park Pollinators",
          "slug": "summer_watch",
          "title": "Summer Watch",
          "starts_at": "2026-06-01T00:00:00Z",
          "ends_at": "2026-08-31T23:59:59Z",
          "status": "\(status)"
        }
        """.utf8)
        return try JSONDecoder.fieldTripTestDecoder.decode(
            FieldTripChallenge.self,
            from: data
        )
    }

    private func publication(
        authorName: String,
        authorUsername: String?,
        communityReason: String?,
        viewerIsFollowingAuthor: Bool
    ) throws -> FieldTripRecentPublication {
        let authorUsernameJSON = authorUsername.map { "\"\($0)\"" } ?? "null"
        let communityReasonJSON = communityReason.map { "\"\($0)\"" } ?? "null"
        let data = Data("""
        {
          "publication_id": "publication-1",
          "template_id": "template-1",
          "title": "Backyard Safari",
          "description": null,
          "published_at": "2026-07-18T14:00:00Z",
          "like_count": 0,
          "comment_count": 0,
          "slug": "backyard_safari",
          "template_title": "Backyard Safari",
          "region_tags": [],
          "season_tags": [],
          "habitat_tags": [],
          "cover_image_url": null,
          "item_count": 4,
          "viewer_has_liked": false,
          "author_user_id": "author-1",
          "author_name": "\(authorName)",
          "author_username": \(authorUsernameJSON),
          "author_avatar_url": null,
          "is_pinned": false,
          "pin_position": null,
          "rank_bucket": null,
          "community_reason": \(communityReasonJSON),
          "viewer_is_following_author": \(viewerIsFollowingAuthor)
        }
        """.utf8)
        return try JSONDecoder.fieldTripTestDecoder.decode(
            FieldTripRecentPublication.self,
            from: data
        )
    }

    private func summaries(
        includingBadge: Bool = false
    ) throws -> FieldTripProfileSummaries {
        let badgeJSON = includingBadge ? """
        [
          {
            "badge_id": "badge-1",
            "challenge_id": "challenge-1",
            "badge_key": "summer_watch",
            "title": "Summer Watch",
            "awarded_at": "2026-07-18T14:00:00Z",
            "challenge_slug": "summer_watch",
            "challenge_title": "Summer Watch",
            "cover_image_url": null,
            "region_tags": [],
            "season_tags": ["summer"],
            "habitat_tags": []
          }
        ]
        """ : "[]"
        let data = Data("""
        {
          "active": [],
          "pinned": [],
          "published": [],
          "challenge_badges": \(badgeJSON)
        }
        """.utf8)
        return try JSONDecoder.fieldTripTestDecoder.decode(
            FieldTripProfileSummaries.self,
            from: data
        )
    }
}

private extension JSONDecoder {
    static var fieldTripTestDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
