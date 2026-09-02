import Testing

@testable import Merian

/// Independently written payload expectations, not generated from the endpoint code.
struct CommunityIdentificationEndpointRequestCase: Sendable, CustomTestStringConvertible {
    let name: String
    let function: String
    let expectedJSON: String
    let responseJSON: String
    let invoke: @MainActor @Sendable (MerianNetworkClient) async throws -> Void

    var testDescription: String { name }
    var path: String { "/\(function)" }

    // Mirrors the existing transport allowlist, including taxonomy search's
    // cache-enrichment side effects; these are not all pure reads.
    var isAmbiguousReplayAllowlisted: Bool {
        [
            "get-community-identification-feed",
            "get-community-identification-activity",
            "get-community-identification-detail",
            "search-community-taxa"
        ].contains(function)
    }

    static var all: [Self] {
        operations + requestFeedVariations + activityVariations + contentVariations
    }

    /// Exactly one representative of each callable operation for transport checks.
    static var operations: [Self] {
        [
            Self(
                name: "request feed defaults",
                function: "get-community-identification-feed",
                expectedJSON: #"{"limit":30,"scope":"all","group":"all"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.feed
            ) { client in
                _ = try await client.getCommunityIdentificationFeed()
            },
            Self(
                name: "activity defaults",
                function: "get-community-identification-activity",
                expectedJSON: #"{"limit":30,"scope":"all","group":"all"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.activity
            ) { client in
                _ = try await client.getCommunityIdentificationActivity()
            },
            Self(
                name: "request detail",
                function: "get-community-identification-detail",
                expectedJSON: #"{"request_id":"request"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.detail
            ) { client in
                _ = try await client.getCommunityIdentificationDetail(requestId: "request")
            },
            Self(
                name: "clear note with explicit null",
                function: "update-community-identification-request",
                expectedJSON: #"{"request_id":"request","note":null,"location_sharing":"private"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.update
            ) { client in
                _ = try await client.updateCommunityIdentificationRequest(
                    requestId: "request", note: nil, locationSharing: .privateLocation
                )
            },
            Self(
                name: "taxon search defaults",
                function: "search-community-taxa",
                expectedJSON: #"{"query":"Rosa","limit":20}"#,
                responseJSON: CommunityIdentificationEndpointResponses.taxa
            ) { client in
                _ = try await client.searchCommunityTaxa(query: "Rosa")
            },
            Self(
                name: "submit support with explicit null reasoning",
                function: "submit-community-identification",
                expectedJSON: """
                {"request_id":"request","taxon_id":"taxon","disagreement_mode":"implicit_support",
                 "reasoning":null,"is_genus_best_possible":false}
                """,
                responseJSON: CommunityIdentificationEndpointResponses.submittedMutation
            ) { client in
                _ = try await client.submitCommunityIdentification(
                    requestId: "request", taxonId: "taxon", disagreementMode: .implicitSupport,
                    reasoning: nil, isGenusBestPossible: false
                )
            },
            Self(
                name: "withdraw identification",
                function: "withdraw-community-identification",
                expectedJSON: #"{"identification_id":"identification"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.withdrawnMutation
            ) { client in
                _ = try await client.withdrawCommunityIdentification(identificationId: "identification")
            },
            Self(
                name: "restore identification",
                function: "restore-community-identification",
                expectedJSON: #"{"identification_id":"identification"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.restoredMutation
            ) { client in
                _ = try await client.restoreCommunityIdentification(identificationId: "identification")
            }
        ]
    }

    private static var requestFeedVariations: [Self] {
        // Nonzero, out-of-range sentinels detect dropped/swapped values without
        // representing a real location. Validation remains backend-owned.
        [
            Self(
                name: "filtered request preview with complete cursor and out-of-range sentinels",
                function: "get-community-identification-feed",
                expectedJSON: """
                {"limit":12,"scope":"mine","group":"plants","latitude":1234.5,"longitude":-6789.5,
                 "before_requested_at":"2026-01-01T12:00:00.000Z","before_request_id":"request-cursor"}
                """,
                responseJSON: CommunityIdentificationEndpointResponses.feed
            ) { client in
                _ = try await client.getCommunityIdentificationFeed(
                    limit: 12, scope: .mine, group: .plants, latitude: 1234.5, longitude: -6789.5,
                    cursor: .init(beforeRequestedAt: "2026-01-01T12:00:00.000Z", beforeRequestId: "request-cursor")
                )
            },
            Self(
                name: "latitude remains independently forwarded",
                function: "get-community-identification-feed",
                expectedJSON: #"{"limit":30,"scope":"all","group":"all","latitude":1234.5}"#,
                responseJSON: CommunityIdentificationEndpointResponses.feed
            ) { client in
                _ = try await client.getCommunityIdentificationFeed(latitude: 1234.5)
            },
            Self(
                name: "longitude remains independently forwarded",
                function: "get-community-identification-feed",
                expectedJSON: #"{"limit":30,"scope":"all","group":"all","longitude":-6789.5}"#,
                responseJSON: CommunityIdentificationEndpointResponses.feed
            ) { client in
                _ = try await client.getCommunityIdentificationFeed(longitude: -6789.5)
            },
            Self(
                name: "empty request cursor",
                function: "get-community-identification-feed",
                expectedJSON: #"{"limit":30,"scope":"all","group":"all"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.feed
            ) { client in
                _ = try await client.getCommunityIdentificationFeed(cursor: .empty)
            },
            Self(
                name: "timestamp-only request cursor omitted",
                function: "get-community-identification-feed",
                expectedJSON: #"{"limit":30,"scope":"all","group":"all"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.feed
            ) { client in
                _ = try await client.getCommunityIdentificationFeed(
                    cursor: .init(beforeRequestedAt: "2026-01-01T12:00:00Z", beforeRequestId: nil)
                )
            },
            Self(
                name: "ID-only request cursor omitted",
                function: "get-community-identification-feed",
                expectedJSON: #"{"limit":30,"scope":"all","group":"all"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.feed
            ) { client in
                _ = try await client.getCommunityIdentificationFeed(
                    cursor: .init(beforeRequestedAt: nil, beforeRequestId: "request-cursor")
                )
            },
            Self(
                name: "present blank request cursor is not normalized",
                function: "get-community-identification-feed",
                expectedJSON: """
                {"limit":30,"scope":"all","group":"all","before_requested_at":"","before_request_id":""}
                """,
                responseJSON: CommunityIdentificationEndpointResponses.feed
            ) { client in
                _ = try await client.getCommunityIdentificationFeed(
                    cursor: .init(beforeRequestedAt: "", beforeRequestId: "")
                )
            },
            Self(
                name: "request lower bound remains server-owned",
                function: "get-community-identification-feed",
                expectedJSON: #"{"limit":-1,"scope":"all","group":"all"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.feed
            ) { client in
                _ = try await client.getCommunityIdentificationFeed(limit: -1)
            },
            Self(
                name: "request upper bound and Herps wire name",
                function: "get-community-identification-feed",
                expectedJSON: #"{"limit":101,"scope":"all","group":"reptiles_amphibians"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.feed
            ) { client in
                _ = try await client.getCommunityIdentificationFeed(limit: 101, group: .reptilesAmphibians)
            }
        ]
    }

    private static var activityVariations: [Self] {
        [
            Self(
                name: "filtered activity preview with complete cursor",
                function: "get-community-identification-activity",
                expectedJSON: """
                {"limit":10,"scope":"mine","group":"plants",
                 "before_activity_at":"2026-01-01T12:00:00.000Z","before_activity_id":"activity-cursor"}
                """,
                responseJSON: CommunityIdentificationEndpointResponses.activity
            ) { client in
                _ = try await client.getCommunityIdentificationActivity(
                    limit: 10, scope: .mine, group: .plants,
                    cursor: .init(beforeActivityAt: "2026-01-01T12:00:00.000Z", beforeActivityId: "activity-cursor")
                )
            },
            Self(
                name: "empty activity cursor",
                function: "get-community-identification-activity",
                expectedJSON: #"{"limit":30,"scope":"all","group":"all"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.activity
            ) { client in
                _ = try await client.getCommunityIdentificationActivity(cursor: .empty)
            },
            Self(
                name: "timestamp-only activity cursor omitted",
                function: "get-community-identification-activity",
                expectedJSON: #"{"limit":30,"scope":"all","group":"all"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.activity
            ) { client in
                _ = try await client.getCommunityIdentificationActivity(
                    cursor: .init(beforeActivityAt: "2026-01-01T12:00:00Z", beforeActivityId: nil)
                )
            },
            Self(
                name: "ID-only activity cursor omitted",
                function: "get-community-identification-activity",
                expectedJSON: #"{"limit":30,"scope":"all","group":"all"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.activity
            ) { client in
                _ = try await client.getCommunityIdentificationActivity(
                    cursor: .init(beforeActivityAt: nil, beforeActivityId: "activity-cursor")
                )
            },
            Self(
                name: "present blank activity cursor is not normalized",
                function: "get-community-identification-activity",
                expectedJSON: """
                {"limit":30,"scope":"all","group":"all","before_activity_at":"","before_activity_id":""}
                """,
                responseJSON: CommunityIdentificationEndpointResponses.activity
            ) { client in
                _ = try await client.getCommunityIdentificationActivity(
                    cursor: .init(beforeActivityAt: "", beforeActivityId: "")
                )
            },
            Self(
                name: "activity lower bound remains server-owned",
                function: "get-community-identification-activity",
                expectedJSON: #"{"limit":-1,"scope":"all","group":"all"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.activity
            ) { client in
                _ = try await client.getCommunityIdentificationActivity(limit: -1)
            },
            Self(
                name: "activity upper bound and Herps wire name",
                function: "get-community-identification-activity",
                expectedJSON: #"{"limit":101,"scope":"all","group":"reptiles_amphibians"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.activity
            ) { client in
                _ = try await client.getCommunityIdentificationActivity(limit: 101, group: .reptilesAmphibians)
            }
        ]
    }

    private static var contentVariations: [Self] {
        [
            Self(
                name: "pinned taxon search preserves query whitespace",
                function: "search-community-taxa",
                expectedJSON: #"{"query":"  Rosa\n","limit":7,"taxonomy_version_id":"taxonomy-version"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.taxa
            ) { client in
                _ = try await client.searchCommunityTaxa(
                    query: "  Rosa\n", limit: 7, taxonomyVersionId: "taxonomy-version"
                )
            },
            Self(
                name: "empty search and present blank version are not normalized",
                function: "search-community-taxa",
                expectedJSON: #"{"query":"","limit":20,"taxonomy_version_id":""}"#,
                responseJSON: CommunityIdentificationEndpointResponses.taxa
            ) { client in
                _ = try await client.searchCommunityTaxa(query: "", taxonomyVersionId: "")
            },
            Self(
                name: "search lower bound remains server-owned",
                function: "search-community-taxa",
                expectedJSON: #"{"query":"Rosa","limit":-1}"#,
                responseJSON: CommunityIdentificationEndpointResponses.taxa
            ) { client in
                _ = try await client.searchCommunityTaxa(query: "Rosa", limit: -1)
            },
            Self(
                name: "search upper bound remains server-owned",
                function: "search-community-taxa",
                expectedJSON: #"{"query":"Rosa","limit":51}"#,
                responseJSON: CommunityIdentificationEndpointResponses.taxa
            ) { client in
                _ = try await client.searchCommunityTaxa(query: "Rosa", limit: 51)
            },
            Self(
                name: "note whitespace remains intact",
                function: "update-community-identification-request",
                expectedJSON: #"{"request_id":"request","note":"  Test request\n","location_sharing":"obscured"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.update
            ) { client in
                _ = try await client.updateCommunityIdentificationRequest(
                    requestId: "request", note: "  Test request\n", locationSharing: .obscured
                )
            },
            Self(
                name: "empty note is not null",
                function: "update-community-identification-request",
                expectedJSON: #"{"request_id":"request","note":"","location_sharing":"open"}"#,
                responseJSON: CommunityIdentificationEndpointResponses.update
            ) { client in
                _ = try await client.updateCommunityIdentificationRequest(
                    requestId: "request", note: "", locationSharing: .open
                )
            },
            Self(
                name: "explicit disagreement preserves reasoning and Boolean true",
                function: "submit-community-identification",
                expectedJSON: #"""
                {"request_id":"request","taxon_id":"taxon","disagreement_mode":"explicit_disagreement",
                 "reasoning":"  Test reasoning\n","is_genus_best_possible":true}
                """#,
                responseJSON: CommunityIdentificationEndpointResponses.submittedMutation
            ) { client in
                _ = try await client.submitCommunityIdentification(
                    requestId: "request", taxonId: "taxon", disagreementMode: .explicitDisagreement,
                    reasoning: "  Test reasoning\n", isGenusBestPossible: true
                )
            },
            Self(
                name: "maverick and empty reasoning",
                function: "submit-community-identification",
                expectedJSON: """
                {"request_id":"request","taxon_id":"taxon","disagreement_mode":"maverick",
                 "reasoning":"","is_genus_best_possible":false}
                """,
                responseJSON: CommunityIdentificationEndpointResponses.submittedMutation
            ) { client in
                _ = try await client.submitCommunityIdentification(
                    requestId: "request", taxonId: "taxon", disagreementMode: .maverick,
                    reasoning: "", isGenusBestPossible: false
                )
            }
        ]
    }
}
