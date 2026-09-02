import Foundation
import Testing

@testable import Merian

/// Independent JSON expectations. Invalid sentinels test forwarding, not server acceptance.
struct ExploreBrowsingEndpointRequestCase: Sendable, CustomTestStringConvertible {
    let name: String
    let function: String
    let expectedJSON: String
    let responseJSON: String
    let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void

    var testDescription: String { name }
    var path: String { "/\(function)" }

    static var all: [Self] {
        operations + feedVariations + mapVariations + identityVariations + cursorVariations
    }

    /// One representative of every operation, including its caller-facing defaults.
    static var operations: [Self] {
        [
            Self(name: "feed defaults", function: "get-explore-feed",
                 expectedJSON: #"{"limit":20,"filter":"recent"}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.feed) { client in
                _ = try await client.getExploreFeed()
            },
            Self(name: "map defaults", function: "get-explore-map-points",
                 expectedJSON: """
                 {"north_latitude":1234.5,"south_latitude":-2345.5,"east_longitude":3456.5,
                  "west_longitude":-4567.5,"zoom_level":12.5,"limit":500}
                 """, responseJSON: ExploreBrowsingEndpointResponses.map) { client in
                _ = try await client.getExploreMapPoints(
                    northLatitude: 1234.5, southLatitude: -2345.5, eastLongitude: 3456.5,
                    westLongitude: -4567.5, zoomLevel: 12.5
                )
            },
            Self(name: "single post", function: "get-explore-post", expectedJSON: #"{"post_id":"post"}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.singlePost) { client in
                _ = try await client.getExplorePost(postId: "post")
            },
            Self(name: "post detail", function: "get-explore-post-detail", expectedJSON: #"{"post_id":"post"}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.detail) { client in
                _ = try await client.getExplorePostDetail(postId: "post")
            },
            Self(name: "author profile defaults", function: "get-explore-author-profile",
                 expectedJSON: #"{"author_user_id":"author","preview_limit":9}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.profile) { client in
                _ = try await client.getExploreAuthorProfile(authorUserId: "author")
            },
            Self(name: "author posts defaults", function: "get-explore-author-posts",
                 expectedJSON: #"{"author_user_id":"author","limit":30}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.authorPosts) { client in
                _ = try await client.getExploreAuthorPosts(authorUserId: "author")
            },
            Self(name: "hashtag posts defaults", function: "get-explore-hashtag-posts",
                 expectedJSON: #"{"hashtag":"test","limit":30}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.feed) { client in
                _ = try await client.getExploreHashtagPosts(hashtag: "test")
            },
            Self(name: "species posts defaults", function: "get-explore-species-posts",
                 expectedJSON: #"{"species_id":"species","limit":30}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.speciesPosts) { client in
                _ = try await client.getExploreSpeciesPosts(speciesId: "species")
            }
        ]
    }

    private static var feedVariations: [Self] {
        [
            Self(name: "following omits radius even with a stored selection", function: "get-explore-feed",
                 expectedJSON: #"{"limit":20,"filter":"following"}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(
                    filter: .following, advancedFilters: .init(nearbyRadius: .ten)
                )
            },
            Self(name: "nearby radius without caller coordinates", function: "get-explore-feed",
                 expectedJSON: #"{"limit":20,"filter":"nearby","nearby_radius_miles":50}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(filter: .nearby)
            },
            Self(name: "independent latitude outside nearby", function: "get-explore-feed",
                 expectedJSON: #"{"limit":20,"filter":"recent","latitude":1234.5}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(latitude: 1234.5)
            },
            Self(name: "independent longitude outside nearby", function: "get-explore-feed",
                 expectedJSON: #"{"limit":20,"filter":"recent","longitude":-6789.5}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(longitude: -6789.5)
            },
            Self(name: "filter order and explicit ISO cutoff", function: "get-explore-feed",
                 expectedJSON: """
                 {"limit":0,"filter":"nearby","latitude":1234.5,"longitude":-6789.5,"nearby_radius_miles":100,
                  "species_categories":["birds","insects","plants","fungi","mammals","reptiles","amphibians","fish","arachnids","other"],
                  "media_types":["audio","image","video"],"shared_since":"1970-01-01T00:00:00Z"}
                 """, responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(
                    limit: 0, filter: .nearby, latitude: 1234.5, longitude: -6789.5,
                    advancedFilters: .init(speciesCategories: Set(ExploreMapSpeciesCategory.allCases),
                                           mediaTypes: Set(ExploreMediaKind.allCases), nearbyRadius: .oneHundred),
                    sharedSince: Date(timeIntervalSince1970: 0.75)
                )
            },
            Self(name: "date range does not derive a cutoff inside transport", function: "get-explore-feed",
                 expectedJSON: #"{"limit":-1,"filter":"recent"}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(
                    limit: -1, advancedFilters: .init(dateRange: .today, nearbyRadius: .ten)
                )
            }
        ]
    }

    private static var mapVariations: [Self] {
        [
            Self(name: "map sorts categories lexically and forwards bounds", function: "get-explore-map-points",
                 expectedJSON: """
                 {"north_latitude":1234.5,"south_latitude":-2345.5,"east_longitude":-3456.5,
                  "west_longitude":4567.5,"zoom_level":-1,"limit":0,
                  "species_categories":["amphibians","arachnids","birds","fish","fungi","insects","mammals","other","plants","reptiles"],
                  "media_types":["audio","image","video"]}
                 """, responseJSON: ExploreBrowsingEndpointResponses.clusters) { client in
                _ = try await client.getExploreMapPoints(
                    northLatitude: 1234.5, southLatitude: -2345.5, eastLongitude: -3456.5,
                    westLongitude: 4567.5, zoomLevel: -1, limit: 0,
                    speciesCategories: Set(ExploreMapSpeciesCategory.allCases), mediaTypes: Set(ExploreMediaKind.allCases)
                )
            }
        ]
    }

    private static var identityVariations: [Self] {
        [
            Self(name: "post ID is not normalized", function: "get-explore-post",
                 expectedJSON: #"{"post_id":" Post "}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.singlePost) { client in
                _ = try await client.getExplorePost(postId: " Post ")
            },
            Self(name: "detail forwards an empty ID", function: "get-explore-post-detail",
                 expectedJSON: #"{"post_id":""}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.detail) { client in
                _ = try await client.getExplorePostDetail(postId: "")
            },
            Self(name: "owner preview may be zero", function: "get-explore-author-profile",
                 expectedJSON: #"{"author_user_id":"author","preview_limit":0}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.publicProfile) { client in
                _ = try await client.getExploreAuthorProfile(authorUserId: "author", previewLimit: 0)
            },
            Self(name: "profile validation stays on the server", function: "get-explore-author-profile",
                 expectedJSON: #"{"author_user_id":" Author ","preview_limit":101}"#,
                 responseJSON: ExploreBrowsingEndpointResponses.publicProfile) { client in
                _ = try await client.getExploreAuthorProfile(authorUserId: " Author ", previewLimit: 101)
            },
            Self(name: "hashtag normalization stays on the server", function: "get-explore-hashtag-posts",
                 expectedJSON: #"{"hashtag":" #MiXeD ","limit":0}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreHashtagPosts(hashtag: " #MiXeD ", limit: 0)
            },
            Self(name: "species ID and limit are forwarded", function: "get-explore-species-posts",
                 expectedJSON: #"{"species_id":" Species ","limit":101}"#,
                 responseJSON: #"{"data":[],"next_cursor":null}"#) { client in
                _ = try await client.getExploreSpeciesPosts(speciesId: " Species ", limit: 101)
            }
        ]
    }

    private static var cursorVariations: [Self] {
        feedCursors + pairedCursors + speciesCursors
    }

    private static var feedCursors: [Self] {
        [
            Self(name: "full trending cursor", function: "get-explore-feed",
                 expectedJSON: """
                 {"limit":10,"filter":"trending","before_shared_at":"cursor-time",
                  "before_post_id":"cursor-post","before_ranking_value":4}
                 """, responseJSON: ExploreBrowsingEndpointResponses.feed) { client in
                _ = try await client.getExploreFeed(
                    limit: 10, filter: .trending,
                    cursor: .init(beforeSharedAt: "cursor-time", beforePostId: "cursor-post", beforeRankingValue: 4)
                )
            },
            Self(name: "empty feed cursor", function: "get-explore-feed",
                 expectedJSON: #"{"limit":20,"filter":"recent"}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(cursor: .empty)
            },
            Self(name: "timestamp alone is omitted but zero ranking survives", function: "get-explore-feed",
                 expectedJSON: #"{"limit":20,"filter":"recent","before_ranking_value":0}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(
                    cursor: .init(beforeSharedAt: "cursor-time", beforePostId: nil, beforeRankingValue: 0)
                )
            },
            Self(name: "post ID alone is omitted", function: "get-explore-feed",
                 expectedJSON: #"{"limit":20,"filter":"recent"}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(
                    cursor: .init(beforeSharedAt: nil, beforePostId: "cursor-post", beforeRankingValue: nil)
                )
            },
            Self(name: "ranking can be supplied independently", function: "get-explore-feed",
                 expectedJSON: #"{"limit":20,"filter":"trending","before_ranking_value":-1}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(
                    filter: .trending, cursor: .init(beforeSharedAt: nil, beforePostId: nil, beforeRankingValue: -1)
                )
            },
            Self(name: "paired empty strings are forwarded", function: "get-explore-feed",
                 expectedJSON: #"{"limit":20,"filter":"recent","before_shared_at":"","before_post_id":""}"#,
                 responseJSON: #"{"data":[]}"#) { client in
                _ = try await client.getExploreFeed(
                    cursor: .init(beforeSharedAt: "", beforePostId: "", beforeRankingValue: nil)
                )
            }
        ]
    }

    private static var pairedCursors: [Self] {
        // Explicit suffixes independently specify the omission/pairing contract.
        let values: [(String, String?, String?, String)] = [
            ("empty", nil, nil, ""),
            ("timestamp only", "cursor-time", nil, ""),
            ("post ID only", nil, "cursor-post", ""),
            ("complete", "cursor-time", "cursor-post", #", "before_shared_at":"cursor-time","before_post_id":"cursor-post""#),
            ("blank strings", "", "", #", "before_shared_at":"","before_post_id":"""#)
        ]
        return values.flatMap { name, time, post, suffix in
            [
                Self(name: "author cursor: \(name)", function: "get-explore-author-posts",
                     expectedJSON: #"{"author_user_id":" Author ","limit":101\#(suffix)}"#,
                     responseJSON: ExploreBrowsingEndpointResponses.authorPosts) { client in
                    _ = try await client.getExploreAuthorPosts(
                        authorUserId: " Author ", limit: 101, cursor: .init(beforeSharedAt: time, beforePostId: post)
                    )
                },
                Self(name: "hashtag cursor: \(name)", function: "get-explore-hashtag-posts",
                     expectedJSON: #"{"hashtag":"test","limit":10\#(suffix)}"#,
                     responseJSON: ExploreBrowsingEndpointResponses.feed) { client in
                    _ = try await client.getExploreHashtagPosts(
                        hashtag: "test", limit: 10, cursor: .init(beforeSharedAt: time, beforePostId: post)
                    )
                }
            ]
        }
    }

    private static var speciesCursors: [Self] {
        [
            Self(name: "scored species cursor", function: "get-explore-species-posts",
                 expectedJSON: """
                 {"species_id":"species","limit":6,"before_image_quality_score":91,
                  "before_shared_at":"cursor-time","before_post_id":"cursor-post"}
                 """, responseJSON: ExploreBrowsingEndpointResponses.speciesPosts) { client in
                _ = try await client.getExploreSpeciesPosts(
                    speciesId: "species", limit: 6,
                    cursor: .init(imageQualityScore: 91, sharedAt: "cursor-time", postId: "cursor-post")
                )
            },
            Self(name: "zero quality and blank species cursor are forwarded", function: "get-explore-species-posts",
                 expectedJSON: """
                 {"species_id":"species","limit":30,"before_image_quality_score":0,"before_shared_at":"","before_post_id":""}
                 """, responseJSON: #"{"data":[],"next_cursor":null}"#) { client in
                _ = try await client.getExploreSpeciesPosts(
                    speciesId: "species", cursor: .init(imageQualityScore: 0, sharedAt: "", postId: "")
                )
            },
            Self(name: "unscored species cursor omits quality", function: "get-explore-species-posts",
                 expectedJSON: #"{"species_id":"species","limit":30,"before_shared_at":"cursor-time","before_post_id":"cursor-post"}"#,
                 responseJSON: #"{"data":[],"next_cursor":null}"#) { client in
                _ = try await client.getExploreSpeciesPosts(
                    speciesId: "species", cursor: .init(imageQualityScore: nil, sharedAt: "cursor-time", postId: "cursor-post")
                )
            }
        ]
    }
}
