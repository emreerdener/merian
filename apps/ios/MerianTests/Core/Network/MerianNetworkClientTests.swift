import Foundation
@testable import Merian
import Testing

private extension String {
    var utf8Data: Data { Data(utf8) }
}

private final class SendableCallbackProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func mark() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var wasMarked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class NetworkRequestProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var requestCount = 0
    private var idempotencyKeys: [String?] = []

    func record(idempotencyKey: String?) -> Int {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        idempotencyKeys.append(idempotencyKey)
        return requestCount
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return requestCount == 0
    }

    var recordedIdempotencyKeys: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return idempotencyKeys
    }
}

@Suite(
    "Network Client Tests",
    .serialized,
    .sharedProcessState(.networkClientOverrides)
)
@MainActor
struct MerianNetworkClientTests {

    init() {
        MockURLProtocol.mockEndpoints = [:]

        // Build an ephemeral URLSession configuration tailored exclusively for Mocking
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]

        // Inject so MerianNetworkClient hooks this instead of hitting live internet
        MerianNetworkClient.shared.overridingSession = URLSession(configuration: config)
        MerianNetworkClient.shared.overridingAuthUserID = UUID(
            uuidString: "11111111-1111-4111-8111-111111111111"
        )
        MerianNetworkClient.shared.overridingInferenceConsentCheck = {}
        MerianNetworkClient.shared.overridingAuthSessionRefresh = nil
        MerianNetworkClient.shared.resetSpeciesDictionaryCacheForTesting()
    }

    @Test func testScopedMockTransportsIsolateConcurrentSessions() async throws {
        let firstTransport = ScopedMockTransport()
        let secondTransport = ScopedMockTransport()
        let firstSession = firstTransport.makeSession()
        let secondSession = secondTransport.makeSession()
        let url = URL(string: "https://example.com/scoped-endpoint")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        firstTransport.register(path: "/scoped-endpoint") { _ in
            (response, Data("first".utf8))
        }
        secondTransport.register(path: "/scoped-endpoint") { _ in
            (response, Data("second".utf8))
        }

        async let firstResult = firstSession.data(from: url)
        async let secondResult = secondSession.data(from: url)
        let (firstData, _) = try await firstResult
        let (secondData, _) = try await secondResult

        #expect(String(bytes: firstData, encoding: .utf8) == "first")
        #expect(String(bytes: secondData, encoding: .utf8) == "second")
    }

    @Test func testMissingOwnerShareStateClearsStaleLocalPublication() async throws {
        let scanID = "019f7004-2a8f-77a3-8954-7a85a4a25418"
        let postID = "019f7004-2e80-7fc8-8db5-4a27a7bca2ab"
        let record = LocalScanRecord(
            id: scanID,
            speciesId: "missing_owner_share_state",
            scientificName: "Danaus plexippus",
            commonName: "Monarch",
            coverImagePath: "monarch.webp"
        )
        let engine = InferenceEngine()
        engine.activeMedia = ActiveScanMedia(items: [.image("monarch.webp")])
        engine.speciesData = SpeciesData(
            scanId: scanID,
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(
                aiReasoning: "Orange wings with black veins.",
                hazardType: "none"
            ),
            confidenceScore: 0.98,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        let viewModel = InsightSheetViewModel(inferenceEngine: engine)
        viewModel.activeLocalRecord = record
        viewModel.activeLocalRecordId = scanID
        viewModel.toolbarRecordSnapshot = InsightToolbarRecordSnapshot(
            record: record
        )
        viewModel.state.sharedExplorePostId = postID
        viewModel.state.sharedCommunityIdentificationRequestId =
            "019f7004-3226-7cdf-abfb-59dab91bb596"
        viewModel.state.sharedCommunityIdentificationStatus = .needsId
        viewModel.state.isExploreFeedVisible = true
        viewModel.state.sharedExploreHashtags = ["stale"]
        ExploreShareStateStore.setSharedPostId(postID, for: scanID)
        defer { ExploreShareStateStore.setSharedPostId(nil, for: scanID) }

        let missingResponse = try #require(
            HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["X-Merian-Handler": "1"]
            )
        )
        MockURLProtocol.mockEndpoints[
            "/get-scan-explore-share-state"
        ] = { _ in
            (
                missingResponse,
                Data(#"{"error":"Scan not found.","code":"not_found"}"#.utf8)
            )
        }

        await viewModel.refreshSharedExploreStateFromServer()

        #expect(viewModel.state.sharedExplorePostId == nil)
        #expect(viewModel.state.sharedCommunityIdentificationRequestId == nil)
        #expect(viewModel.state.sharedCommunityIdentificationStatus == nil)
        #expect(viewModel.state.isExploreFeedVisible == false)
        #expect(viewModel.state.sharedExploreHashtags.isEmpty)
        #expect(ExploreShareStateStore.sharedPostId(for: scanID) == nil)
        #expect(viewModel.canShareToExplore)
    }

    @Test func testExplorePostDetailDecodesSimilarSpecies() throws {
        let data = Data("""
        {
            "schema_version": 1,
            "data": {
                "post_id": "post-detail-123",
                "field_notes": null,
                "species_dictionary_id": "species-123",
                "alternative_common_names": ["Garden Rose", "Meadow Rose"],
                "taxonomy_kingdom": "Plantae",
                "taxonomy_phylum": "Tracheophyta",
                "taxonomy_class": "Magnoliopsida",
                "taxonomy_order": "Rosales",
                "taxonomy_family": "Rosaceae",
                "taxonomy_genus": "Rosa",
                "ai_reasoning": "Petal shape and thorn spacing match the subject.",
                "habitat_description": "Open meadows and garden edges.",
                "gbif_taxon_key": 42,
                "iucn_red_list_status": "least_concern",
                "hazard_type": "poisonous",
                "wikipedia_url": "https://en.wikipedia.org/wiki/Rosa_galeria",
                "reference_image_url": "https://media.merian.app/public_uploads/pro/rosa.webp,https://upload.wikimedia.org/rosa.jpg",
                "wikipedia_overview": "Rosa galeria is a test species with enough overview copy for Explore.",
                "similar_species": [
                    {
                        "species_id": "species-rosa-minor",
                        "scientific_name": "Rosa minor",
                        "common_name": "Small Rose",
                        "reference_image_url": "https://example.com/rosa-minor.jpg",
                        "iucn_red_list_status": "least_concern",
                        "reason": "Similar flower shape and thorn spacing.",
                        "visual_traits": ["pink flowers", "compound leaves"],
                        "confidence": 0.82,
                        "source": "model_enrichment",
                        "review_status": "unreviewed",
                        "is_bidirectional": false,
                        "sort_order": 0
                    }
                ]
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ExplorePostDetailResponse.self, from: data)
        let similar = try #require(response.data.similarSpeciesData)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.alternativeCommonNames == ["Garden Rose", "Meadow Rose"])
        #expect(response.data.hazardType == "poisonous")
        #expect(response.data.referenceGalleryImages.map(\.source) == [.merian, .wikipedia])
        #expect(response.data.referenceGalleryImages.first?.source.label == "Naturebook")
        let filteredReferences = response.data.referenceGalleryImages(excluding: [
            "https://media.merian.app/public_uploads/pro/rosa.webp?width=1200#capture"
        ])
        #expect(filteredReferences.map(\.url) == ["https://upload.wikimedia.org/rosa.jpg"])
        #expect(filteredReferences.map(\.source) == [.wikipedia])
        #expect(similar.entries.count == 1)
        #expect(similar.entries[0].speciesId == "species-rosa-minor")
        #expect(similar.entries[0].scientificName == "Rosa minor")
        #expect(similar.entries[0].commonName == "Small Rose")
        #expect(similar.entries[0].referenceImageUrl == "https://example.com/rosa-minor.jpg")
        #expect(similar.entries[0].similarityReason == "Similar flower shape and thorn spacing.")
        #expect(similar.entries[0].visualTraits == ["pink flowers", "compound leaves"])
        #expect(similar.entries[0].similarityConfidence == 0.82)
    }

    @Test func testExplorePostDetailDecodesLegacyPayloadWithoutSchemaVersion() throws {
        let data = """
        {
            "data": {
                "post_id": "post-detail-legacy-schema",
                "field_notes": null,
                "species_dictionary_id": null,
                "taxonomy_kingdom": null,
                "taxonomy_phylum": null,
                "taxonomy_class": null,
                "taxonomy_order": null,
                "taxonomy_family": null,
                "taxonomy_genus": null,
                "ai_reasoning": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "reference_image_url": null,
                "wikipedia_overview": null
            }
        }
        """.utf8Data

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ExplorePostDetailResponse.self, from: data)

        #expect(response.schemaVersion == nil)
        #expect(response.effectiveSchemaVersion == 0)
        #expect(response.data.postId == "post-detail-legacy-schema")
        #expect(response.data.mapPoint == nil)
        #expect(response.data.visibleMapPoint == nil)
    }

    @Test func testExplorePostDetailDecodesPrivacySafeMapPoints() throws {
        let exactData = Data("""
        {
            "data": {
                "post_id": "post-detail-exact-map",
                "location_sharing": "open",
                "map_point": {
                    "latitude": 12.3456,
                    "longitude": -45.6789,
                    "coordinate_visibility": "exact"
                }
            }
        }
        """.utf8)
        let obscuredData = Data("""
        {
            "data": {
                "post_id": "post-detail-obscured-map",
                "location_sharing": "open",
                "map_point": {
                    "latitude": -23.5,
                    "longitude": 67.9,
                    "coordinate_visibility": "obscured"
                }
            }
        }
        """.utf8)
        let hiddenData = Data("""
        {
            "data": {
                "post_id": "post-detail-hidden-map",
                "location_sharing": "private",
                "map_point": {
                    "latitude": 1.0,
                    "longitude": 1.0,
                    "coordinate_visibility": "exact"
                }
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let exact = try decoder.decode(ExplorePostDetailResponse.self, from: exactData)
        let obscured = try decoder.decode(ExplorePostDetailResponse.self, from: obscuredData)
        let hidden = try decoder.decode(ExplorePostDetailResponse.self, from: hiddenData)

        #expect(exact.data.visibleMapPoint?.coordinateVisibility == .exact)
        #expect(exact.data.visibleMapPoint?.coordinate?.latitude == 12.3456)
        #expect(obscured.data.visibleMapPoint?.coordinateVisibility == .obscured)
        #expect(obscured.data.visibleMapPoint?.coordinate?.longitude == 67.9)
        #expect(hidden.data.mapPoint != nil)
        #expect(hidden.data.visibleMapPoint == nil)
    }

    @Test func testExplorePostDetailDecodesWhenSimilarSpeciesIsMissing() throws {
        let data = """
        {
            "data": {
                "post_id": "post-detail-legacy",
                "field_notes": null,
                "species_dictionary_id": "species-legacy",
                "taxonomy_kingdom": null,
                "taxonomy_phylum": null,
                "taxonomy_class": null,
                "taxonomy_order": null,
                "taxonomy_family": null,
                "taxonomy_genus": null,
                "ai_reasoning": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "reference_image_url": null,
                "wikipedia_overview": null
            }
        }
        """.utf8Data

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ExplorePostDetailResponse.self, from: data)

        #expect(response.data.postId == "post-detail-legacy")
        #expect(response.data.similarSpecies == nil)
        #expect(response.data.similarSpeciesData == nil)
    }

    @Test func testExplorePostDecodesVideoMediaItemsAndLegacyFallback() throws {
        let videoData = """
        {
            "data": {
                "post_id": "post-video-123",
                "scan_id": "scan-video-123",
                "hero_image_url": "https://example.com/thumb.jpg",
                "shared_at": "2026-07-03T12:00:00.000Z",
                "author_user_id": "author-video-123",
                "author_name": "Video Author",
                "author_username": "video_author",
                "author_avatar_url": null,
                "author_is_pro": true,
                "hashtags": [],
                "species_common_name": "Monarch Butterfly",
                "species_scientific_name": "Danaus plexippus",
                "pet_identification": null,
                "public_location_label": "Austin, TX",
                "location_sharing": "open",
                "time_of_day": "afternoon",
                "current_month": 7,
                "weather_condition": "clear",
                "weather_temperature_f": 82.0,
                "like_count": 3,
                "comment_count": 1,
                "viewer_has_liked": false,
                "is_owned_by_viewer": false,
                "ranking_value": null,
                "media_items": [
                    {
                        "kind": "video",
                        "url": "https://example.com/video.mp4",
                        "thumbnail_url": "https://example.com/thumb.jpg",
                        "order_index": 0,
                        "duration_seconds": 4.7,
                        "has_audio": true
                    }
                ]
            }
        }
        """.utf8Data

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let videoResponse = try decoder.decode(ExplorePostResponse.self, from: videoData)

        #expect(videoResponse.data.hasVideoMedia)
        #expect(videoResponse.data.resolvedMediaItems.count == 1)
        #expect(videoResponse.data.resolvedMediaItems[0].kind == .video)
        #expect(videoResponse.data.resolvedMediaItems[0].thumbnailUrl == "https://example.com/thumb.jpg")
        #expect(videoResponse.data.resolvedMediaItems[0].hasAudio)

        let audioOnlyData = """
        {
            "data": {
                "post_id": "post-audio-123",
                "scan_id": "scan-audio-123",
                "hero_image_url": null,
                "reference_thumbnail_url": "https://images.merian.app/cardinal.jpg",
                "shared_at": "2026-07-11T12:00:00.000Z",
                "author_user_id": "author-audio-123",
                "author_name": "Audio Author",
                "author_username": "audio_author",
                "author_avatar_url": null,
                "author_is_pro": false,
                "hashtags": [],
                "species_common_name": "Northern Cardinal",
                "species_scientific_name": "Cardinalis cardinalis",
                "pet_identification": null,
                "public_location_label": null,
                "location_sharing": "obscured",
                "time_of_day": "morning",
                "current_month": 7,
                "weather_condition": null,
                "weather_temperature_f": null,
                "like_count": 0,
                "comment_count": 0,
                "viewer_has_liked": false,
                "is_owned_by_viewer": true,
                "ranking_value": null,
                "media_items": [
                    {
                        "kind": "audio",
                        "url": "https://media.merian.app/audio.wav",
                        "thumbnail_url": null,
                        "order_index": 0,
                        "duration_seconds": 8.2,
                        "has_audio": true
                    }
                ]
            }
        }
        """.utf8Data

        let audioOnlyResponse = try decoder.decode(ExplorePostResponse.self, from: audioOnlyData)

        #expect(audioOnlyResponse.data.heroImageUrl.isEmpty)
        #expect(audioOnlyResponse.data.hasAudioMedia)
        #expect(audioOnlyResponse.data.gridThumbnailUrl == "https://images.merian.app/cardinal.jpg")
        #expect(
            audioOnlyResponse.data.gridThumbnailUrl(localReferenceUrl: "https://local.merian.app/cardinal.jpg")
                == "https://images.merian.app/cardinal.jpg",
            "The server-projected reference should take precedence when available"
        )
        var legacyAudioPost = audioOnlyResponse.data
        legacyAudioPost.referenceThumbnailUrl = nil
        #expect(
            legacyAudioPost.gridThumbnailUrl(localReferenceUrl: "https://local.merian.app/cardinal.jpg")
                == "https://local.merian.app/cardinal.jpg",
            "Current-user profile grids should retain the local reference when the deployed payload predates the reference-thumbnail field"
        )
        #expect(audioOnlyResponse.data.resolvedMediaItems.count == 1)
        #expect(audioOnlyResponse.data.resolvedMediaItems[0].kind == .audio)
        #expect(audioOnlyResponse.data.resolvedMediaItems[0].posterImageUrl(fallback: "") == nil)
        #expect(audioOnlyResponse.data.resolvedMediaItems[0].audioSpectrogramPosterUrl == nil)

        let spectrogramAudio = ExploreMediaItem(
            kind: .audio,
            url: "https://media.merian.app/audio.wav",
            thumbnailUrl: "https://media.merian.app/spectrogram.webp",
            orderIndex: 0,
            durationSeconds: 8.2,
            hasAudio: true
        )
        #expect(spectrogramAudio.posterImageUrl(fallback: "") == "https://media.merian.app/spectrogram.webp")
        #expect(spectrogramAudio.audioSpectrogramPosterUrl == "https://media.merian.app/spectrogram.webp")

        let videoWithoutThumbnail = ExploreMediaItem(
            kind: .video,
            url: "https://media.merian.app/video.mp4",
            thumbnailUrl: nil,
            orderIndex: 0,
            durationSeconds: 4.2,
            hasAudio: true
        )
        #expect(videoWithoutThumbnail.posterImageUrl(fallback: "https://media.merian.app/fallback.webp") ==
            "https://media.merian.app/fallback.webp")

        let legacyData = """
        {
            "data": {
                "post_id": "post-image-123",
                "scan_id": "scan-image-123",
                "hero_image_url": "https://example.com/image.jpg",
                "shared_at": "2026-07-03T12:00:00.000Z",
                "author_user_id": "author-image-123",
                "author_name": "Image Author",
                "author_username": null,
                "author_avatar_url": null,
                "author_is_pro": null,
                "hashtags": null,
                "species_common_name": "Honey Bee",
                "species_scientific_name": "Apis mellifera",
                "pet_identification": null,
                "public_location_label": null,
                "location_sharing": null,
                "time_of_day": null,
                "current_month": null,
                "weather_condition": null,
                "weather_temperature_f": null,
                "like_count": 0,
                "comment_count": 0,
                "viewer_has_liked": false,
                "is_owned_by_viewer": false,
                "ranking_value": null
            }
        }
        """.utf8Data

        let legacyResponse = try decoder.decode(ExplorePostResponse.self, from: legacyData)

        #expect(!legacyResponse.data.hasVideoMedia)
        #expect(legacyResponse.data.resolvedMediaItems == [
            .legacyImage(url: "https://example.com/image.jpg")
        ])
    }

    @Test func testExploreMediaIncidentsAndLifecycleNotificationsDecode() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let incidentData = Data("""
        {
          "data": [
            {
              "post_id": "post-1",
              "scan_id": "scan-1",
              "species_common_name": "White-winged Dove",
              "media_health_status": "quarantined",
              "missing_media_count": 2,
              "total_media_count": 2,
              "media_quarantined_at": "2026-07-26T12:10:00Z",
              "media_health_updated_at": "2026-07-26T12:10:00Z",
              "missing_media_urls": [
                "https://media.merian.app/public_uploads/pro/user/one.webp",
                "https://media.merian.app/public_uploads/pro/user/two.webp"
              ]
            }
          ]
        }
        """.utf8)
        let incidentResponse = try decoder.decode(
            ExploreMediaIncidentsResponse.self,
            from: incidentData
        )

        #expect(incidentResponse.data[0].id == "post-1")
        #expect(incidentResponse.data[0].speciesCommonName == "White-winged Dove")
        #expect(incidentResponse.data[0].mediaHealthStatus == .quarantined)
        #expect(incidentResponse.data[0].missingMediaUrls.count == 2)

        let nullableSpeciesIncidentData = Data("""
        {
          "data": [
            {
              "post_id": "post-2",
              "scan_id": "scan-2",
              "species_common_name": null,
              "media_health_status": "degraded",
              "missing_media_count": 1,
              "total_media_count": 2,
              "media_quarantined_at": null,
              "media_health_updated_at": "2026-07-30T12:10:00Z",
              "missing_media_urls": [
                "https://media.merian.app/public_uploads/pro/user/missing.webp"
              ]
            }
          ]
        }
        """.utf8)
        let nullableSpeciesResponse = try decoder.decode(
            ExploreMediaIncidentsResponse.self,
            from: nullableSpeciesIncidentData
        )
        #expect(nullableSpeciesResponse.data[0].speciesCommonName == nil)
        let incidentObject = try #require(
            JSONSerialization.jsonObject(with: incidentData)
                as? [String: Any]
        )
        let legacyIncidentData = try JSONSerialization.data(
            withJSONObject: try #require(incidentObject["data"])
        )
        let populatedLegacyIncidentResponse = try decoder.decode(
            ExploreMediaIncidentsResponse.self,
            from: legacyIncidentData
        )
        #expect(populatedLegacyIncidentResponse.data == incidentResponse.data)

        let legacyIncidentResponse = try decoder.decode(
            ExploreMediaIncidentsResponse.self,
            from: Data("[]".utf8)
        )
        #expect(legacyIncidentResponse.data.isEmpty)

        let notificationData = Data("""
        {
          "data": [
            {
              "notification_id": "missing-1",
              "post_id": "post-1",
              "community_request_id": null,
              "field_trip_publication_id": null,
              "type": "media_missing",
              "comment_id": null,
              "parent_comment_id": null,
              "reaction_emoji": null,
              "triggering_user_id": null,
              "triggering_user_name": null,
              "comment_body": null,
              "recent_actor_names": [],
              "action_count": 1,
              "is_read": false,
              "is_reply_to_viewer_comment": false,
              "community_taxon_common_name": null,
              "community_taxon_scientific_name": null,
              "community_request_display_name": null,
              "created_at": "2026-07-26T12:10:00Z",
              "updated_at": "2026-07-26T12:10:00Z"
            },
            {
              "notification_id": "restored-1",
              "post_id": "post-1",
              "community_request_id": null,
              "field_trip_publication_id": null,
              "type": "media_restored",
              "comment_id": null,
              "parent_comment_id": null,
              "reaction_emoji": null,
              "triggering_user_id": null,
              "triggering_user_name": null,
              "comment_body": null,
              "recent_actor_names": [],
              "action_count": 1,
              "is_read": false,
              "is_reply_to_viewer_comment": false,
              "community_taxon_common_name": null,
              "community_taxon_scientific_name": null,
              "community_request_display_name": null,
              "created_at": "2026-07-26T12:20:00Z",
              "updated_at": "2026-07-26T12:20:00Z"
            }
          ]
        }
        """.utf8)
        let notificationResponse = try decoder.decode(
            ExploreNotificationsResponse.self,
            from: notificationData
        )

        #expect(notificationResponse.data.map(\.type) == [.mediaMissing, .mediaRestored])
    }

    @Test func testExploreMapResponseToleratesMediaOnlyPostsWithoutHeroImages() throws {
        let data = """
        {
            "mode": "posts",
            "visible_count": 2,
            "category_counts": [{ "category": "birds", "count": 2 }],
            "clusters": [],
            "posts": [
                {
                    "post_id": "audio-post",
                    "scan_id": "audio-scan",
                    "latitude": 30.2672,
                    "longitude": -97.7431,
                    "coordinate_visibility": "exact",
                    "hero_image_url": null,
                    "reference_thumbnail_url": "https://example.com/cardinal.webp",
                    "shared_at": "2026-07-11T20:00:00Z",
                    "author_user_id": "audio-author",
                    "author_name": "Audio Author",
                    "author_username": null,
                    "author_avatar_url": null,
                    "author_is_pro": false,
                    "species_common_name": "Northern Cardinal",
                    "species_scientific_name": "Cardinalis cardinalis",
                    "pet_identification": null,
                    "taxonomy_kingdom": "Animalia",
                    "taxonomy_class": "Aves",
                    "public_location_label": "Austin, TX",
                    "location_sharing": "open",
                    "time_of_day": null,
                    "current_month": 7,
                    "weather_condition": null,
                    "weather_temperature_f": null,
                    "like_count": 0,
                    "comment_count": 0,
                    "viewer_has_liked": false,
                    "is_owned_by_viewer": false,
                    "media_items": [{
                        "kind": "audio",
                        "url": "https://example.com/cardinal.wav",
                        "thumbnail_url": null,
                        "order_index": 0,
                        "duration_seconds": 8.0,
                        "has_audio": true
                    }]
                },
                {
                    "post_id": "video-post",
                    "scan_id": "video-scan",
                    "latitude": 30.268,
                    "longitude": -97.744,
                    "coordinate_visibility": "obscured",
                    "shared_at": "2026-07-11T19:00:00Z",
                    "author_user_id": "video-author",
                    "author_name": "Video Author",
                    "author_username": null,
                    "author_avatar_url": null,
                    "author_is_pro": true,
                    "species_common_name": "Monarch Butterfly",
                    "species_scientific_name": "Danaus plexippus",
                    "pet_identification": null,
                    "taxonomy_kingdom": "Animalia",
                    "taxonomy_class": "Insecta",
                    "public_location_label": null,
                    "location_sharing": "obscured",
                    "time_of_day": null,
                    "current_month": 7,
                    "weather_condition": null,
                    "weather_temperature_f": null,
                    "like_count": 1,
                    "comment_count": 2,
                    "viewer_has_liked": true,
                    "is_owned_by_viewer": false,
                    "media_items": [{
                        "kind": "video",
                        "url": "https://example.com/monarch.mp4",
                        "thumbnail_url": "https://example.com/monarch.webp",
                        "order_index": 0,
                        "duration_seconds": 4.0,
                        "has_audio": true
                    }]
                }
            ]
        }
        """.utf8Data

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(ExploreMapPointsResponse.self, from: data)

        #expect(response.posts.count == 2)
        #expect(response.posts[0].heroImageUrl.isEmpty)
        #expect(response.posts[0].hasAudioMedia)
        #expect(response.posts[0].mapThumbnailUrl == "https://example.com/cardinal.webp")
        #expect(response.posts[0].asExplorePost.referenceThumbnailUrl == "https://example.com/cardinal.webp")
        #expect(response.posts[0].asExplorePost.hasAudioMedia)
        #expect(response.posts[1].heroImageUrl.isEmpty)
        #expect(response.posts[1].hasVideoMedia)
        #expect(response.posts[1].mapThumbnailUrl == "https://example.com/monarch.webp")
        #expect(response.posts[1].asExplorePost.hasVideoMedia)
        #expect(response.mediaTypeCounts.isEmpty)
    }

    @Test func testEdgeFunctionSelfHealingRefreshesInvalidSessionBeforeRetry() async throws {
        let requestProbe = NetworkRequestProbe()
        let refreshProbe = SendableCallbackProbe()
        MockURLProtocol.mockEndpoints["/register-push-device"] = { request in
            let attempt = requestProbe.record(idempotencyKey: nil)
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: attempt == 1 ? 401 : 200,
                httpVersion: nil,
                headerFields: ["X-Merian-Handler": "1"]
            )!
            let data = attempt == 1
                ? Data(
                    #"{"code":"invalid_session_token","error":"Unauthorized: Invalid or expired session token."}"#.utf8
                )
                : Data("{}".utf8)
            return (response, data)
        }
        MerianNetworkClient.shared.overridingAuthSessionRefresh = {
            refreshProbe.mark()
            return true
        }
        defer {
            MerianNetworkClient.shared.overridingAuthSessionRefresh = nil
        }

        try await MerianNetworkClient.shared.registerPushDevice(
            deviceToken: "abc123",
            environment: "sandbox",
            exploreEnabled: true,
            commentMentionsEnabled: false,
            communityIdentificationsEnabled: true
        )

        #expect(refreshProbe.wasMarked)
        #expect(requestProbe.count == 2)
    }

    // MARK: - Endpoint URL structure

    /// Verifies that the Edge Function URL construction formula produces the correct path.
    /// Tests the pattern `"\(supabaseUrl)/functions/v1/\(function)"` directly without
    /// making a network call — any live call would require a valid auth session in CI.
    @Test func testEndpointURLPathContainsFunctionsV1Segment() throws {
        let baseUrl = MerianEnvironment.supabaseUrl
        // Mirror the formula used by MerianNetworkClient.endpointURL(_:)
        let constructed = URL(string: "\(baseUrl)/functions/v1/block-user")
        let url = try #require(constructed, "endpointURL formula must produce a valid URL from the configured supabaseUrl")
        #expect(url.path.contains("/functions/v1/"), "Edge Function URL must contain /functions/v1/ path segment")
        #expect(url.absoluteString.hasPrefix("https://"), "Edge Function URL must use HTTPS")
        #expect(url.lastPathComponent == "block-user", "Last path component must match the function name")
    }

}

private extension InputStream {
    func readData() -> Data {
        self.open()
        defer { self.close() }
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var data = Data()
        while self.hasBytesAvailable {
            let read = self.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return data
    }
}
