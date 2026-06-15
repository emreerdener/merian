import Foundation
import Testing
@testable import Merian

struct ExploreBadgePolicyTests {
    @Test func ownRecentPostsDoNotCreateUnseenExploreBadge() {
        let posts = [
            makePost(sharedAt: "2026-06-14T15:00:00Z", isOwnedByViewer: true)
        ]

        #expect(ExploreBadgePolicy.hasUnseenExternalPost(
            in: posts,
            lastSeenSharedAt: "2026-06-14T14:00:00Z"
        ) == false)
    }

    @Test func externalRecentPostsCreateUnseenExploreBadge() {
        let posts = [
            makePost(sharedAt: "2026-06-14T15:00:00Z", isOwnedByViewer: true),
            makePost(sharedAt: "2026-06-14T14:30:00Z", isOwnedByViewer: false)
        ]

        #expect(ExploreBadgePolicy.hasUnseenExternalPost(
            in: posts,
            lastSeenSharedAt: "2026-06-14T14:00:00Z"
        ) == true)
    }

    @Test func externalPostsAtOrBeforeLastSeenDoNotCreateUnseenExploreBadge() {
        let posts = [
            makePost(sharedAt: "2026-06-14T14:00:00Z", isOwnedByViewer: false),
            makePost(sharedAt: "2026-06-14T13:30:00Z", isOwnedByViewer: false)
        ]

        #expect(ExploreBadgePolicy.hasUnseenExternalPost(
            in: posts,
            lastSeenSharedAt: "2026-06-14T14:00:00Z"
        ) == false)
    }

    private func makePost(sharedAt: String, isOwnedByViewer: Bool) -> ExplorePost {
        ExplorePost(
            postId: UUID().uuidString,
            scanId: UUID().uuidString,
            heroImageUrl: "https://example.com/image.webp",
            sharedAt: sharedAt,
            authorUserId: UUID().uuidString,
            authorName: "Explorer",
            authorUsername: "explorer",
            authorAvatarUrl: nil,
            authorIsPro: false,
            hashtags: nil,
            speciesCommonName: "Common Milkweed",
            speciesScientificName: "Asclepias syriaca",
            publicLocationLabel: nil,
            timeOfDay: nil,
            currentMonth: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            isOwnedByViewer: isOwnedByViewer,
            rankingValue: nil
        )
    }
}
