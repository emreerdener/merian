import Foundation
import Testing

@testable import Merian

@Suite("Explore Browsing Endpoints")
@MainActor
struct ExploreBrowsingEndpointTests {
    @Test(arguments: ExploreBrowsingEndpointRequestCase.all)
    func requestMappingRemainsStable(_ testCase: ExploreBrowsingEndpointRequestCase) async throws {
        try await withResponse(
            function: testCase.function, requestJSON: testCase.expectedJSON, responseJSON: testCase.responseJSON
        ) { client in
            try await testCase.invoke(client)
        }
    }

    // Rehomed aggregate regressions retain their names and use per-test clients.
    @Test func testGetExploreMapPointsSendsMediaFiltersAndDecodesCounts() async throws {
        try await withResponse(
            function: "get-explore-map-points",
            requestJSON: """
            {"north_latitude":1234.5,"south_latitude":-2345.5,"east_longitude":3456.5,
             "west_longitude":-4567.5,"zoom_level":12,"limit":500,
             "species_categories":["birds"],"media_types":["audio","video"]}
            """, responseJSON: ExploreBrowsingEndpointResponses.map
        ) { client in
            let response = try await client.getExploreMapPoints(
                northLatitude: 1234.5, southLatitude: -2345.5, eastLongitude: 3456.5,
                westLongitude: -4567.5, zoomLevel: 12, speciesCategories: [.birds], mediaTypes: [.video, .audio]
            )
            #expect(response.mediaTypeCounts == [
                ExploreMapMediaTypeCount(mediaType: .image, count: 4),
                ExploreMapMediaTypeCount(mediaType: .audio, count: 2)
            ])
            #expect(response.mode == .posts && response.visibleCount == 1 && response.clusters.isEmpty)
            #expect(response.categoryCounts == [.init(category: .birds, count: 1)])
            let post = try #require(response.posts.first)
            #expect(response.posts.count == 1 && post.id == "map-post" && post.scanId == "scan")
            #expect(post.latitude == 1234.5 && post.longitude == -6789.5 && post.coordinateVisibility == .obscured)
            #expect(post.heroImageUrl.isEmpty && post.hasAudioMedia && post.asExplorePost.hasAudioMedia)
            #expect(post.mapThumbnailUrl == "https://media.example.test/reference.webp")
        }
    }

    @Test func testGetExploreFeedTrendingConstructsPayloadAndParsesResponse() async throws {
        try await withResponse(
            function: "get-explore-feed",
            requestJSON: """
            {"limit":10,"filter":"trending","before_ranking_value":4,
             "before_shared_at":"2026-01-01T12:00:00.000Z","before_post_id":"cursor-post"}
            """, responseJSON: ExploreBrowsingEndpointResponses.feed
        ) { client in
            let posts = try await client.getExploreFeed(
                limit: 10, filter: .trending,
                cursor: .init(beforeSharedAt: "2026-01-01T12:00:00.000Z", beforePostId: "cursor-post", beforeRankingValue: 4)
            )
            #expect(posts.count == 1 && posts.first?.id == "post" && posts.first?.rankingValue == 4)
        }
    }

    @Test func testGetExploreFeedNearbyConstructsPayloadWithCoordinates() async throws {
        try await withResponse(
            function: "get-explore-feed",
            requestJSON: #"{"limit":20,"filter":"nearby","latitude":1234.5,"longitude":-6789.5,"nearby_radius_miles":50}"#,
            responseJSON: #"{"data":[\#(ExploreBrowsingEndpointResponses.unrankedPost)]}"#
        ) { client in
            let posts = try await client.getExploreFeed(filter: .nearby, latitude: 1234.5, longitude: -6789.5)
            #expect(posts.count == 1 && posts.first?.id == "audio-post" && posts.first?.rankingValue == nil)
        }
    }

    @Test func testGetExploreFeedConstructsAdvancedFilterPayload() async throws {
        try await withResponse(
            function: "get-explore-feed",
            requestJSON: """
            {"limit":20,"filter":"nearby","latitude":1234.5,"longitude":-6789.5,"nearby_radius_miles":25,
             "species_categories":["birds","mammals"],"media_types":["audio","video"],"shared_since":"2026-07-08T18:00:00Z"}
            """, responseJSON: #"{"data":[]}"#
        ) { client in
            let referenceDate = try #require(DateUtilities.iso8601Formatter.date(from: "2026-07-15T18:00:00Z"))
            let filters = ExploreFeedAdvancedFilters(
                speciesCategories: [.mammals, .birds], mediaTypes: [.video, .audio], dateRange: .pastWeek, nearbyRadius: .twentyFive
            )
            let cutoff = try #require(filters.dateRange.sharedSince(referenceDate: referenceDate))
            let posts = try await client.getExploreFeed(
                filter: .nearby, latitude: 1234.5, longitude: -6789.5, advancedFilters: filters, sharedSince: cutoff
            )
            #expect(posts.isEmpty)
            #expect(filters.activeFilterCount(for: .recent) == 5 && filters.activeFilterCount(for: .nearby) == 6)
        }
    }

    @Test func testGetExploreFeedFollowingConstructsPayload() async throws {
        try await withResponse(
            function: "get-explore-feed", requestJSON: #"{"limit":20,"filter":"following"}"#,
            responseJSON: #"{"data":[]}"#
        ) { client in
            let posts = try await client.getExploreFeed(filter: .following)
            #expect(posts.isEmpty)
        }
    }

    @Test func testGetExploreAuthorProfileParsesProfilePayload() async throws {
        try await withResponse(
            function: "get-explore-author-profile", requestJSON: #"{"author_user_id":"author","preview_limit":9}"#,
            responseJSON: ExploreBrowsingEndpointResponses.profile
        ) { client in
            let profile = try await client.getExploreAuthorProfile(authorUserId: "author")
            #expect(profile.authorUserId == "author" && profile.authorName == "Test observer")
            #expect(profile.authorUsername == "test_observer" && profile.authorIsPro == true)
            #expect(profile.authorAvatarUrl == "https://media.example.test/avatar.webp")
            #expect(profile.speciesCount == 12 && profile.currentStreak == 4 && profile.publishedPostCount == 5)
            #expect(profile.followerCount == 7 && profile.followingCount == 3 && !profile.viewerIsFollowing)
            #expect(profile.viewerCanReport == false)
            #expect(profile.ownerPublicationSummary?.publicationIntentCount == 38)
            #expect(profile.ownerPublicationSummary?.visiblePostCount == 5)
            #expect(profile.ownerPublicationSummary?.recoveryNeededPostCount == 33)
            #expect(profile.ownerPublicationSummary?.degradedPostCount == 0)
            #expect(profile.ownerPublicationSummary?.quarantinedPostCount == 33)
            #expect(profile.profileHeatmapData.totalCaptures == 17 && profile.profileHeatmapData.weeks.count == 1)
            #expect(profile.heatmap.currentMonthCaptures == 3 && profile.heatmap.yearString == "2026")
            #expect(profile.heatmap.weeks.first?.days.map(\.count) == [1, 0])
            #expect(profile.awardPayloads.count == AchievementType.allCases.count)
            #expect(profile.awardPayloads.first { $0.type == .explorer }?.isCompleted == true)
            #expect(profile.awardPayloads.first { $0.type == .domesticCat }?.currentCount == 0)
            #expect(profile.awardPayloads.first { $0.type == .domesticDog }?.currentCount == 0)
            #expect(profile.awardPayloads.first { $0.type == .firstFieldTrip }?.isCompleted == true)
            #expect(profile.awardPayloads.first { $0.type == .firstFieldTrip }?.destination == nil)
            #expect(profile.previewPosts.map(\.id) == ["post"])
        }
    }

    @Test func testGetExploreAuthorPostsConstructsCursorPayload() async throws {
        try await withResponse(
            function: "get-explore-author-posts",
            requestJSON: """
            {"author_user_id":"author","limit":30,"before_shared_at":"2026-01-01T12:00:00.000Z","before_post_id":"cursor-post"}
            """, responseJSON: ExploreBrowsingEndpointResponses.authorPosts
        ) { client in
            let page = try await client.getExploreAuthorPosts(
                authorUserId: "author", cursor: .init(beforeSharedAt: "2026-01-01T12:00:00.000Z", beforePostId: "cursor-post")
            )
            #expect(page.data.count == 1 && page.data.first?.id == "post")
            #expect(page.nextCursor?.beforeSharedAt == "2026-01-01T12:00:00.000Z" && page.nextCursor?.beforePostId == "post")
        }
    }

    @Test func testGetExploreSpeciesPostsConstructsQualityCursorAndDecodesNextCursor() async throws {
        try await withResponse(
            function: "get-explore-species-posts",
            requestJSON: """
            {"species_id":"species","limit":6,"before_image_quality_score":91,
             "before_shared_at":"2026-01-01T12:00:00.000Z","before_post_id":"cursor-post"}
            """, responseJSON: ExploreBrowsingEndpointResponses.speciesPosts
        ) { client in
            let response = try await client.getExploreSpeciesPosts(
                speciesId: "species", limit: 6,
                cursor: .init(imageQualityScore: 91, sharedAt: "2026-01-01T12:00:00.000Z", postId: "cursor-post")
            )
            #expect(response.data.map(\.id) == ["audio-post"])
            let post = try #require(response.data.first)
            #expect(post.hasAudioMedia && post.heroImageUrl.isEmpty)
            #expect(post.gridThumbnailUrl == "https://media.example.test/reference.webp")
            #expect(post.mediaItems?.first?.durationSeconds == 4.2 && post.mediaItems?.first?.hasAudio == true)
            #expect(response.nextCursor?.imageQualityScore == nil && response.nextCursor?.postId == "audio-post")
            #expect(response.nextCursor?.sharedAt == "2026-01-01T11:00:00.000Z")
        }
    }

    @Test func testGetExploreSpeciesPostsOmitsQualityFieldForUnscoredCursor() async throws {
        try await withResponse(
            function: "get-explore-species-posts",
            requestJSON: """
            {"species_id":"species","limit":30,"before_shared_at":"2026-01-01T11:00:00.000Z","before_post_id":"audio-post"}
            """, responseJSON: #"{"data":[],"next_cursor":null}"#
        ) { client in
            let response = try await client.getExploreSpeciesPosts(
                speciesId: "species",
                cursor: .init(imageQualityScore: nil, sharedAt: "2026-01-01T11:00:00.000Z", postId: "audio-post")
            )
            #expect(response.data.isEmpty && response.nextCursor == nil)
        }
    }

    @Test func singlePostKeepsItsCardProjection() async throws {
        try await withResponse(
            function: "get-explore-post", requestJSON: #"{"post_id":"post"}"#,
            responseJSON: ExploreBrowsingEndpointResponses.singlePost
        ) { client in
            let post = try await client.getExplorePost(postId: "post")
            #expect(post.id == "post" && post.scanId == "scan" && post.authorUserId == "author")
            #expect(post.authorIsPro == true && post.authorUsername == "test_observer" && post.authorAvatarUrl == nil)
            #expect(post.heroImageUrl == "https://media.example.test/image.webp")
            #expect(post.sharedAt == "2026-01-01T12:00:00.000Z" && post.hashtags == ["test"])
            #expect(post.speciesCommonName == "Test bird" && post.speciesScientificName == "Avis test")
            #expect(post.publicLocationLabel == nil && post.locationSharing == .privateLocation)
            #expect(post.likeCount == 11 && post.commentCount == 2 && !post.viewerHasLiked && !post.isOwnedByViewer)
            #expect(post.weatherTemperatureF == 74 && post.timeOfDay == "day" && post.currentMonth == 1)
        }
    }

    @Test func feedAndHashtagPreserveCardOrderAndMediaOnlyPosts() async throws {
        let responseJSON = #"{"data":[\#(ExploreBrowsingEndpointResponses.unrankedPost),\#(ExploreBrowsingEndpointResponses.post)]}"#
        for function in ["get-explore-feed", "get-explore-hashtag-posts"] {
            let isFeed = function == "get-explore-feed"
            try await withResponse(
                function: function,
                requestJSON: isFeed ? #"{"limit":20,"filter":"recent"}"# : #"{"limit":30,"hashtag":"test"}"#,
                responseJSON: responseJSON
            ) { client in
                let posts = try await isFeed ? client.getExploreFeed() : client.getExploreHashtagPosts(hashtag: "test")
                #expect(posts.map(\.id) == ["audio-post", "post"])
                #expect(posts.first?.heroImageUrl.isEmpty == true && posts.first?.hasAudioMedia == true)
                #expect(posts.first?.rankingValue == nil && posts.last?.rankingValue == 4)
            }
        }
    }

    @Test func detailKeepsPrivacyAndDictionaryProjection() async throws {
        try await withResponse(
            function: "get-explore-post-detail", requestJSON: #"{"post_id":"post"}"#,
            responseJSON: ExploreBrowsingEndpointResponses.detail
        ) { client in
            let detail = try await client.getExplorePostDetail(postId: "post")
            #expect(detail.postId == "post" && detail.fieldNotes == "Test field notes" && detail.hashtags == ["test"])
            #expect(detail.locationSharing == .privateLocation && detail.mapPoint == nil)
            #expect(detail.speciesDictionaryId == "species" && detail.alternativeCommonNames == ["Test bird"])
            #expect(detail.taxonomyKingdom == "Animalia" && detail.taxonomyPhylum == "Chordata" && detail.taxonomyClass == "Aves")
            #expect(detail.taxonomyOrder == "Test order" && detail.taxonomyFamily == "Test family" && detail.taxonomyGenus == "Avis")
            #expect(detail.aiReasoning == "Test reasoning" && detail.habitatDescription == "Test habitat")
            #expect(detail.gbifTaxonKey == 3000001 && detail.iucnRedListStatus == "LC" && detail.hazardType == "none")
            #expect(detail.wikipediaUrl == "https://reference.example.test/bird" && detail.wikipediaOverview == "Test overview")
            #expect(detail.referenceImageUrl == "https://media.example.test/bird.webp" && detail.similarSpecies?.isEmpty == true)
        }
    }

    @Test func publicProfileDoesNotInventOwnerOnlyMetadata() async throws {
        try await withResponse(
            function: "get-explore-author-profile", requestJSON: #"{"author_user_id":"author","preview_limit":0}"#,
            responseJSON: ExploreBrowsingEndpointResponses.publicProfile
        ) { client in
            let profile = try await client.getExploreAuthorProfile(authorUserId: "author", previewLimit: 0)
            #expect(profile.ownerPublicationSummary == nil && profile.fieldTrips == nil && profile.previewPosts.isEmpty)
            #expect(profile.viewerCanReport == true && profile.authorIsPro == nil && profile.authorAvatarUrl == nil)
        }
    }

    @Test func clustersKeepModeCountsAndLegacyFacetDefaults() async throws {
        try await withResponse(
            function: "get-explore-map-points",
            requestJSON: """
            {"north_latitude":1234.5,"south_latitude":-2345.5,"east_longitude":3456.5,
             "west_longitude":-4567.5,"zoom_level":4,"limit":500}
            """, responseJSON: ExploreBrowsingEndpointResponses.clusters
        ) { client in
            let response = try await client.getExploreMapPoints(
                northLatitude: 1234.5, southLatitude: -2345.5, eastLongitude: 3456.5, westLongitude: -4567.5, zoomLevel: 4
            )
            #expect(response.mode == .clusters && response.visibleCount == 7 && response.posts.isEmpty)
            #expect(response.categoryCounts.isEmpty && response.mediaTypeCounts.isEmpty && response.clusters.count == 1)
            let cluster = try #require(response.clusters.first)
            #expect(cluster.id == "cluster" && cluster.postCount == 7 && cluster.latitude == 1234.5 && cluster.longitude == -6789.5)
        }
    }

    @Test(arguments: [false, true])
    func authorPageKeepsServerCursorEvenWhenEmpty(hasCursor: Bool) async throws {
        let cursor = hasCursor ? #"{"before_shared_at":"next-time","before_post_id":"next-post"}"# : "null"
        try await withResponse(
            function: "get-explore-author-posts", requestJSON: #"{"author_user_id":"author","limit":30}"#,
            responseJSON: #"{"data":[],"next_cursor":\#(cursor)}"#
        ) { client in
            let page = try await client.getExploreAuthorPosts(authorUserId: "author")
            #expect(page.data.isEmpty)
            #expect(page.nextCursor == (hasCursor ? .init(beforeSharedAt: "next-time", beforePostId: "next-post") : nil))
        }
    }

    @Test(arguments: [0, 91])
    func speciesPageKeepsScoredCursorEvenWhenEmpty(score: Int) async throws {
        try await withResponse(
            function: "get-explore-species-posts", requestJSON: #"{"species_id":"species","limit":30}"#,
            responseJSON: """
            {"data":[],"next_cursor":{"image_quality_score":\(score),"shared_at":"next-time","post_id":"next-post"}}
            """
        ) { client in
            let page = try await client.getExploreSpeciesPosts(speciesId: "species")
            #expect(page.data.isEmpty)
            #expect(page.nextCursor == .init(imageQualityScore: score, sharedAt: "next-time", postId: "next-post"))
        }
    }

    private func withResponse(
        function: String,
        requestJSON: String,
        responseJSON: String,
        body: (MerianNetworkClient) async throws -> Void
    ) async throws {
        let fixture = NetworkEndpointFixture()
        defer { fixture.close() }
        try await confirmation("Exactly one Explore browsing POST") { sent in
            fixture.transport.register(path: "/\(function)") { request in
                sent()
                try NetworkEndpointTestSupport.expectPOST(request, function: function, json: requestJSON)
                return try NetworkEndpointTestSupport.response(to: request, json: responseJSON)
            }
            try await body(fixture.client)
        }
    }
}
