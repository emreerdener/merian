@testable import Merian

enum ExploreAuthorProfileTestFixtures {
    static func post(
        id: String,
        sharedAt: String = "2026-08-01T12:00:00Z",
        mediaItems: [ExploreMediaItem]? = nil
    ) -> ExplorePost {
        ExplorePost(
            postId: id,
            scanId: "scan-\(id)",
            heroImageUrl: "https://example.com/\(id).jpg",
            sharedAt: sharedAt,
            authorUserId: "author-1",
            authorName: "Avery Explorer",
            authorUsername: "avery",
            authorAvatarUrl: nil,
            authorIsPro: false,
            hashtags: nil,
            speciesCommonName: "Northern Cardinal",
            speciesScientificName: "Cardinalis cardinalis",
            petIdentification: nil,
            publicLocationLabel: nil,
            locationSharing: nil,
            timeOfDay: nil,
            currentMonth: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            likeCount: 0,
            commentCount: 0,
            viewerHasLiked: false,
            isOwnedByViewer: false,
            rankingValue: nil,
            mediaItems: mediaItems
        )
    }

    static func profile(
        authorUserId: String = "author-1",
        authorName: String = "Avery Explorer",
        authorUsername: String? = "avery",
        authorIsPro: Bool? = false,
        followerCount: Int = 4,
        followingCount: Int = 7,
        viewerIsFollowing: Bool = false,
        previewPosts: [ExplorePost] = []
    ) -> ExploreAuthorProfile {
        ExploreAuthorProfile(
            authorUserId: authorUserId,
            authorName: authorName,
            authorUsername: authorUsername,
            authorIsPro: authorIsPro,
            authorAvatarUrl: nil,
            speciesCount: 12,
            currentStreak: 3,
            heatmap: ExploreAuthorProfileHeatmap(
                totalCaptures: 21,
                currentMonthCaptures: 5,
                yearString: "2026",
                weeks: []
            ),
            awards: [],
            publishedPostCount: previewPosts.count,
            followerCount: followerCount,
            followingCount: followingCount,
            viewerIsFollowing: viewerIsFollowing,
            viewerCanReport: true,
            previewPosts: previewPosts,
            fieldTrips: nil,
            ownerPublicationSummary: nil
        )
    }
}
