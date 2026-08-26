import Foundation
@testable import Merian

enum FieldTripTestFixtures {
    static func template(
        id: String = "template-1",
        slug: String = "backyard_safari",
        title: String = "Backyard Safari",
        viewerHasAccess: Bool = true,
        activeProgress: FieldTripProgress? = nil,
        stoppedProgress: FieldTripProgress? = nil,
        levelCount: Int = 2
    ) -> FieldTripTemplate {
        FieldTripTemplate(
            templateId: id,
            slug: slug,
            title: title,
            subtitle: nil,
            description: "Explore nearby nature.",
            coverImageUrl: nil,
            estimatedDurationMinutes: 30,
            guideWhereToLook: nil,
            guideWhyItMatters: nil,
            guideSafetyEthics: nil,
            regionTags: ["global"],
            seasonTags: ["summer"],
            habitatTags: ["yard"],
            difficulty: "starter",
            isProOnly: false,
            isRotatingFree: false,
            viewerHasAccess: viewerHasAccess,
            accessKind: viewerHasAccess ? "free" : "locked",
            activeProgress: activeProgress,
            stoppedProgress: stoppedProgress,
            levels: (1...max(1, levelCount)).map { levelNumber in
                FieldTripLevel(
                    levelId: "level-\(levelNumber)",
                    levelNumber: levelNumber,
                    title: "Level \(levelNumber)",
                    description: nil,
                    items: [
                        FieldTripChecklistItem(
                            itemId: "item-\(levelNumber)",
                            prompt: "Bird",
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
                    ]
                )
            }
        )
    }

    static func progress(
        id: String = "outing-1",
        currentLevelNumber: Int = 1,
        completedCount: Int = 0,
        targetCount: Int = 2,
        isComplete: Bool = false,
        publicationId: String? = nil,
        stoppedAt: String? = nil
    ) -> FieldTripProgress {
        FieldTripProgress(
            userFieldTripId: id,
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

    static func challenge(
        id: String = "event-1",
        entryCount: Int = 0,
        participation: Bool = false
    ) throws -> FieldTripChallenge {
        var payload: [String: Any] = [
            "challenge_id": id,
            "template_id": "template-1",
            "template_slug": "backyard_safari",
            "template_title": "Backyard Safari",
            "slug": "summer-event",
            "title": "Summer Event",
            "starts_at": "2026-07-01T00:00:00Z",
            "ends_at": "2026-08-01T00:00:00Z",
            "status": "live",
            "entries": (0..<entryCount).map(entryPayload)
        ]
        if participation {
            payload["viewer_participation"] = [
                "participation_id": "participation-1",
                "user_field_trip_id": "outing-1",
                "joined_at": "2026-07-02T00:00:00Z",
                "current_level_number": 1,
                "completed_count": 1,
                "target_count": 2
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FieldTripChallenge.self, from: data)
    }

    static func challengeEntry(index: Int = 0) -> FieldTripChallengeEntry {
        FieldTripChallengeEntry(
            entryId: "entry-\(index)",
            challengeId: "event-1",
            challengeSlug: "summer-event",
            challengeTitle: "Summer Event",
            templateId: "template-1",
            templateSlug: "backyard_safari",
            templateTitle: "Backyard Safari",
            title: "Entry \(index)",
            description: nil,
            publishedAt: "2026-07-\(String(format: "%02d", index + 1))T12:00:00Z",
            likeCount: 0,
            commentCount: 0,
            regionTags: [],
            seasonTags: [],
            habitatTags: [],
            coverImageUrl: nil,
            itemCount: 1,
            viewerHasLiked: false,
            authorUserId: "author-1",
            authorName: "Nature Friend",
            authorUsername: "naturefriend",
            authorAvatarUrl: nil
        )
    }

    static func publicationDetail(
        description: String? = "A nearby adventure.",
        aiSummary: String? = nil,
        likeCount: Int = 2,
        commentCount: Int = 1,
        viewerHasLiked: Bool = false
    ) -> FieldTripPublicationDetail {
        FieldTripPublicationDetail(
            publicationId: "publication-1",
            userFieldTripId: "outing-1",
            templateId: "template-1",
            templateSlug: "backyard_safari",
            templateTitle: "Backyard Safari",
            title: "Backyard Finds",
            description: description,
            aiSummary: aiSummary,
            publishedAt: "2026-07-18T13:00:00Z",
            authorUserId: "author-1",
            authorName: "Nature Friend",
            authorUsername: "naturefriend",
            authorAvatarUrl: nil,
            likeCount: likeCount,
            commentCount: commentCount,
            viewerHasLiked: viewerHasLiked,
            items: [publicationItem()]
        )
    }

    static func eventEntryDetail(
        likeCount: Int = 3,
        commentCount: Int = 2,
        viewerHasLiked: Bool = true
    ) -> FieldTripChallengeEntryDetail {
        FieldTripChallengeEntryDetail(
            entryId: "entry-1",
            participationId: "participation-1",
            challengeId: "event-1",
            challengeSlug: "summer-event",
            challengeTitle: "Summer Event",
            templateId: "template-1",
            templateSlug: "backyard_safari",
            templateTitle: "Backyard Safari",
            title: "Event Finds",
            description: "A seasonal adventure.",
            publishedAt: "2026-07-18T13:00:00Z",
            authorUserId: "author-1",
            authorName: "Nature Friend",
            authorUsername: "naturefriend",
            authorAvatarUrl: nil,
            likeCount: likeCount,
            commentCount: commentCount,
            viewerHasLiked: viewerHasLiked,
            isOwnedByViewer: false,
            items: [eventEntryItem()]
        )
    }

    static func comment(body: String = "Lovely find!") -> ExploreComment {
        ExploreComment(
            commentId: "comment-1",
            postId: "publication-1",
            parentCommentId: nil,
            authorUserId: "author-2",
            authorName: "Observer",
            authorUsername: "observer",
            authorAvatarUrl: nil,
            body: body,
            createdAt: "2026-07-18T14:00:00Z",
            viewerCanDelete: false,
            viewerCanModerate: false,
            viewerCanReport: true,
            replyCount: 0,
            reactions: [],
            mentions: []
        )
    }

    private static func entryPayload(index: Int) -> [String: Any] {
        [
            "entry_id": "entry-\(index)",
            "challenge_id": "event-1",
            "challenge_slug": "summer-event",
            "challenge_title": "Summer Event",
            "template_id": "template-1",
            "template_slug": "backyard_safari",
            "template_title": "Backyard Safari",
            "title": "Entry \(index)",
            "published_at": "2026-07-\(String(format: "%02d", index + 1))T12:00:00Z",
            "like_count": 0,
            "comment_count": 0,
            "region_tags": [],
            "season_tags": [],
            "habitat_tags": [],
            "item_count": 1,
            "viewer_has_liked": false,
            "author_user_id": "author-1",
            "author_name": "Nature Friend"
        ]
    }

    private static func publicationItem() -> FieldTripPublicationItem {
        FieldTripPublicationItem(
            publicationItemId: "publication-item-1",
            itemId: "goal-1",
            prompt: "Bird",
            commonName: "  Northern Cardinal  ",
            scientificName: "Cardinalis cardinalis",
            heroImageUrl: nil,
            referenceImageUrl: "https://media.merian.app/cardinal.webp",
            taxonomy: nil
        )
    }

    private static func eventEntryItem() -> FieldTripChallengeEntryItem {
        FieldTripChallengeEntryItem(
            entryItemId: "entry-item-1",
            itemId: "goal-1",
            prompt: "Bee",
            commonName: nil,
            scientificName: "Bombus impatiens",
            heroImageUrl: "https://media.merian.app/bee.webp",
            referenceImageUrl: nil,
            taxonomy: nil
        )
    }
}

enum FieldTripTestError: Error {
    case expected
}
