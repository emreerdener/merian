import CoreGraphics
import Foundation
@testable import Merian
import Testing

@Suite("Species Dictionary Tests")
@MainActor
struct SpeciesDictionaryTests {
    private let networkClient: MerianNetworkClient
    private let mockTransport: ScopedMockTransport

    init() {
        let mockTransport = ScopedMockTransport()
        let networkClient = MerianNetworkClient()
        networkClient.overridingSession = mockTransport.makeSession()
        networkClient.overridingAuthUserID = UUID(
            uuidString: "22222222-2222-4222-8222-222222222222"
        )
        networkClient.resetSpeciesDictionaryCacheForTesting()
        self.mockTransport = mockTransport
        self.networkClient = networkClient
    }

    @Test func testSpeciesDictionaryResponseDecodesReferenceImagesAndLookalikes() throws {
        let data = Data("""
        {
            "schema_version": 1,
            "data": {
                "id": "species-123",
                "scientific_name": "Testus floridus",
                "common_name": "Field Test",
                "content_quality": "complete",
                "alternative_common_names": ["Meadow Test"],
                "taxonomy": {
                    "kingdom": "Plantae",
                    "phylum": "Tracheophyta",
                    "class": "Magnoliopsida",
                    "order": "Testales",
                    "family": "Testaceae",
                    "genus": "Testus"
                },
                "hazard_type": "irritant",
                "iucn_red_list_status": "least concern",
                "wikipedia_url": "https://en.wikipedia.org/wiki/Testus_floridus",
                "wikipedia_overview": "A dictionary test species with enough text to be useful in the overview card.",
                "habitat_description": "Found in open test meadows.",
                "gbif_taxon_key": 42,
                "group_tags": ["plant", "flower"],
                "reference_images": [
                    {
                        "url": "https://media.merian.app/public_uploads/pro/test.webp",
                        "source": "merian",
                        "license": "Used with permission via Naturebook",
                        "attribution": "Explorer ABC123",
                        "author_user_id": "66a06afc-a56f-4d19-bfc3-07cf32c1f458",
                        "author_username": "ayla"
                    },
                    {
                        "url": "https://upload.wikimedia.org/test.jpg",
                        "source": "wikipedia",
                        "license": "CC BY-SA 4.0",
                        "attribution": "Example Photographer",
                        "width": 1200,
                        "height": 800
                    },
                    { "url": "https://static.inaturalist.org/photo.jpg", "source": "gbif" }
                ],
                "similar_species": [
                    {
                        "species_id": "species-minor",
                        "scientific_name": "Testus minor",
                        "common_name": "Small Test",
                        "reference_image_url": "https://example.com/minor.jpg",
                        "iucn_red_list_status": "least concern",
                        "reason": "Similar five-petaled flowers.",
                        "visual_traits": ["five petals", "serrated leaves"],
                        "confidence": 0.78,
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
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.scientificName == "Testus floridus")
        #expect(response.data.contentQuality == .complete)
        #expect(response.data.effectiveContentQuality == .complete)
        #expect(response.data.referenceImages.map(\.source) == [.merian, .wikipedia, .gbif])
        #expect(response.data.referenceImages[0].source.label == "Naturebook")
        #expect(response.data.referenceImages[0].authorUserId == "66a06afc-a56f-4d19-bfc3-07cf32c1f458")
        #expect(response.data.referenceImages[0].naturebookAuthorUsername == "ayla")
        #expect(response.data.referenceImages[0].fullscreenAttributionLabel == "@ayla · Naturebook")
        #expect(response.data.referenceImages[1].license == "CC BY-SA 4.0")
        #expect(response.data.referenceImages[1].attribution == "Example Photographer")
        #expect(
            response.data.referenceImages[1].fullscreenAttributionLabel ==
                "Example Photographer · CC BY-SA 4.0 · Wikipedia"
        )
        #expect(response.data.referenceImages[1].width == 1200)
        #expect(response.data.referenceImages[1].height == 800)
        #expect(response.data.taxonomyData?.genus == "Testus")
        #expect(response.data.similarSpeciesData?.entries.first?.speciesId == "species-minor")
        #expect(response.data.similarSpeciesData?.entries.first?.scientificName == "Testus minor")
        #expect(response.data.similarSpeciesData?.entries.first?.similarityReason == "Similar five-petaled flowers.")
        #expect(response.data.similarSpeciesData?.entries.first?.visualTraits == ["five petals", "serrated leaves"])
        #expect(response.data.similarSpeciesData?.entries.first?.similarityConfidence == 0.78)
    }

    @Test func testNaturebookFullscreenAttributionNeverFallsBackToDisplayName() {
        let image = SpeciesDictionaryReferenceImage(
            url: "https://media.merian.app/public_uploads/pro/test.webp",
            source: .merian,
            license: "Used with permission via Naturebook",
            attribution: "Ayla E.",
            width: nil,
            height: nil
        )

        #expect(image.fullscreenAttributionLabel == "Naturebook")
    }

    @Test func testAlternativeCommonNamesLineSanitizesNames() {
        let displayNames = AlternativeCommonNamesLine.displayNames(
            from: [
                "Field Test",
                " Meadow Test, Prairie Test ",
                "meadow test",
                "",
                "Garden Test"
            ],
            excluding: "Field Test"
        )

        #expect(displayNames == ["Meadow Test", "Prairie Test", "Garden Test"])
    }

    @Test func testAlternativeCommonNamesLineTreatsDashVariantsAsDuplicates() {
        let displayNames = AlternativeCommonNamesLine.displayNames(
            from: [
                "Desert-rose",
                "Desert–Rose",
                "Sabi Star",
                "Sabi-star"
            ],
            excluding: "Desert Rose"
        )

        #expect(displayNames == ["Sabi Star"])
    }

    @Test func testSpeciesDictionaryResponseDecodesLegacyPayloadWithoutSchemaVersion() throws {
        let data = Data("""
        {
            "data": {
                "id": "species-legacy",
                "scientific_name": "Legacy testus",
                "common_name": "Legacy Test",
                "alternative_common_names": [],
                "taxonomy": null,
                "hazard_type": null,
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "wikipedia_overview": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "group_tags": [],
                "reference_images": [],
                "similar_species": []
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.schemaVersion == nil)
        #expect(response.effectiveSchemaVersion == 0)
        #expect(response.data.scientificName == "Legacy testus")
        #expect(response.data.contentQuality == nil)
        #expect(response.data.effectiveContentQuality == .needsEnrichment)
    }

    @Test func testSpeciesDictionaryReferenceImageSourceFallbackIsResilient() throws {
        let data = Data("""
        {
            "data": {
                "id": "species-source",
                "scientific_name": "Source testus",
                "common_name": "Source Test",
                "alternative_common_names": [],
                "taxonomy": null,
                "hazard_type": null,
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "wikipedia_overview": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "group_tags": [],
                "reference_images": [
                    { "url": "https://example.com/future.jpg", "source": "future_source" }
                ],
                "similar_species": []
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.data.referenceImages.first?.source == .unknown("future_source"))
        #expect(response.data.referenceImages.first?.source.label == "Reference")
    }

    @Test func testSpeciesDictionaryImageGalleryPresentationMapsSelectedReferenceImage() throws {
        let images = [
            SpeciesDictionaryReferenceImage(
                url: "https://example.com/first.jpg",
                source: .wikipedia,
                license: "CC BY-SA",
                attribution: "First Photographer",
                width: 1200,
                height: 900
            ),
            SpeciesDictionaryReferenceImage(
                url: "https://example.com/second.jpg",
                source: .gbif,
                license: nil,
                attribution: nil,
                width: nil,
                height: nil
            )
        ]

        let presentation = try #require(SpeciesDictionaryImageGalleryBuilder.presentation(
            for: images,
            selectedImageID: images[1].id
        ))

        #expect(presentation.items.map(\.id) == [
            "species-reference-https://example.com/first.jpg",
            "species-reference-https://example.com/second.jpg"
        ])
        #expect(presentation.items.map(\.referenceAttributionLabel) == [
            "First Photographer · CC BY-SA · Wikipedia",
            "GBIF"
        ])
        #expect(presentation.initialSelectedIndex == 1)
        #expect(presentation.items.map(\.source) == [
            .referenceURL("https://example.com/first.jpg"),
            .referenceURL("https://example.com/second.jpg")
        ])
    }

    @Test func testSpeciesDictionaryImageGallerySkipsDeniedMediaAndPromotesNextImage() throws {
        let denied = SpeciesDictionaryReferenceImage(
            url: "https://inaturalist-open-data.s3.amazonaws.com/photos/605615444/original.jpg",
            source: .gbif,
            license: nil,
            attribution: nil,
            width: nil,
            height: nil
        )
        let safe = SpeciesDictionaryReferenceImage(
            url: "https://live.staticflickr.com/65535/55027456166_642323e641_b.jpg",
            source: .gbif,
            license: nil,
            attribution: nil,
            width: nil,
            height: nil
        )

        let presentation = try #require(SpeciesDictionaryImageGalleryBuilder.presentation(
            for: [denied, safe],
            selectedImageID: safe.id
        ))

        #expect(presentation.items.map(\.source) == [.referenceURL(safe.url)])
        #expect(presentation.initialSelectedIndex == 0)
        #expect(SpeciesDictionaryImageGalleryBuilder.presentation(
            for: [denied],
            selectedImageID: denied.id
        ) == nil)
    }

    @Test func testGetSpeciesDictionaryConstructsPayloadAndParsesResponse() async throws {
        let testData = Data("""
        {
            "data": {
                "id": "species-123",
                "scientific_name": "Testus floridus",
                "common_name": "Field Test",
                "alternative_common_names": [],
                "taxonomy": null,
                "hazard_type": "none",
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "wikipedia_overview": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "group_tags": [],
                "reference_images": [],
                "similar_species": []
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        mockTransport.register(path: "/species-dictionary") { request in
            #expect(request.url?.path.hasSuffix("/species-dictionary") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["scientific_name"] as? String == "Testus floridus")
            return (mockResponse, testData)
        }

        let species = try await networkClient.getSpeciesDictionary(scientificName: "Testus floridus")

        #expect(species.id == "species-123")
        #expect(species.commonName == "Field Test")
    }

    @Test func testSpeciesDictionaryRouteCarriesAnalyticsEntryPoint() {
        let route = SpeciesDictionaryRoute(
            scientificName: "Testus floridus",
            speciesId: " species-123 ",
            entryPoint: .exploreDetailSimilarSpecies
        )
        let defaultRoute = SpeciesDictionaryRoute(scientificName: "Testus floridus")

        #expect(route.speciesId == "species-123")
        #expect(route.entryPoint == .exploreDetailSimilarSpecies)
        #expect(defaultRoute.entryPoint == .unknown)
    }

    @Test func testSpeciesDictionaryShareContentUsesCanonicalPublicURL() throws {
        let url = try #require(
            SpeciesDictionaryShareContent.url(
                speciesId: " 1CF79982-E5EE-4E3D-8D65-274527E6AE01 ",
                commonName: "Mwanza flat-headed rock agama",
                scientificName: "Agama mwanzae"
            )
        )

        #expect(
            url.absoluteString ==
                "https://naturebook.earth/species/1cf79982-e5ee-4e3d-8d65-274527e6ae01/mwanza-flat-headed-rock-agama"
        )
        #expect(
            SpeciesDictionaryShareContent.url(
                speciesId: "not-a-uuid",
                commonName: "Field Test",
                scientificName: "Testus floridus"
            ) == nil
        )
        #expect(
            SpeciesDictionaryShareContent.slug(
                commonName: "Café-à-lait!",
                scientificName: "Testus floridus"
            ) == "cafe-a-lait"
        )
        #expect(
            SpeciesDictionaryShareContent.slug(
                commonName: "",
                scientificName: "Agama mwanzae"
            ) == "agama-mwanzae"
        )
        #expect(
            SpeciesDictionaryShareContent.slug(
                commonName: "東京",
                scientificName: "Agama mwanzae"
            ) == "agama-mwanzae"
        )
        #expect(
            SpeciesDictionaryShareContent.slug(commonName: "東京", scientificName: "") == "species"
        )
        #expect(
            SpeciesDictionaryShareContent.slug(
                commonName: String(repeating: "a ", count: 100),
                scientificName: ""
            ).count <= 80
        )
        #expect(
            SpeciesDictionaryShareContent.message(commonName: "Field Test") ==
                "Learn about Field Test on Naturebook."
        )
    }

    @Test func testSpeciesDictionaryFieldChatRequiresCanonicalLoadedSpeciesUUID() {
        #expect(
            SpeciesDictionaryChatPresentationPolicy.canonicalSpeciesID(
                " 019FB71A-94DE-7998-A4CE-F163B531D3E0 "
            ) == "019fb71a-94de-7998-a4ce-f163b531d3e0"
        )
        #expect(
            SpeciesDictionaryChatPresentationPolicy.canonicalSpeciesID(
                "species-external-key"
            ) == nil
        )
        #expect(
            SpeciesDictionaryChatPresentationPolicy.canonicalSpeciesID(nil) == nil
        )
        #expect(
            SpeciesDictionaryChatPresentationPolicy.destination(
                isProActive: false
            ) == .paywall
        )
        #expect(
            SpeciesDictionaryChatPresentationPolicy.destination(
                isProActive: true
            ) == .fieldChat
        )

        #expect(
            SpeciesDictionaryChatPresentationPolicy.canCommitAsyncPresentation(
                requestedSpeciesID: "019fb71a-94de-7998-a4ce-f163b531d3e0",
                currentSpeciesID: "019FB71A-94DE-7998-A4CE-F163B531D3E0",
                hasActivePresentation: false,
                isCancelled: false
            )
        )
        #expect(
            !SpeciesDictionaryChatPresentationPolicy.canCommitAsyncPresentation(
                requestedSpeciesID: "019fb71a-94de-7998-a4ce-f163b531d3e0",
                currentSpeciesID: "019fb71a-94de-7998-a4ce-f163b531d3e0",
                hasActivePresentation: true,
                isCancelled: false
            )
        )
        #expect(
            !SpeciesDictionaryChatPresentationPolicy.canCommitAsyncPresentation(
                requestedSpeciesID: "019fb71a-94de-7998-a4ce-f163b531d3e0",
                currentSpeciesID: "019fb71a-94de-7998-a4ce-f163b531d3e0",
                hasActivePresentation: false,
                isCancelled: true
            )
        )
    }

    @Test func testSpeciesDictionaryDeepLinkSelectsIdentifyIndex() {
        let route = SpeciesDictionaryRoute(
            scientificName: "",
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            entryPoint: .deepLink
        )

        #expect(
            ExploreInitialTabPolicy.resolve(
                requestedTab: .feed,
                speciesDictionaryRoute: route
            ) == .community
        )
        #expect(
            ExploreInitialIdentifyModePolicy.resolve(
                speciesDictionaryRoute: route,
                communityRequestId: nil
            ) == .index
        )
        #expect(
            ExploreInitialIdentifyModePolicy.resolve(
                speciesDictionaryRoute: nil,
                communityRequestId: "request-id"
            ) == .requests
        )
        #expect(
            ExploreInitialTabPolicy.resolve(
                requestedTab: .feed,
                speciesDictionaryRoute: nil,
                communityRequestId: "request-id"
            ) == .community
        )
        #expect(
            ExploreInitialTabPolicy.resolve(
                requestedTab: .community,
                speciesDictionaryRoute: nil
            ) == .community
        )
    }

    @Test func testExploreBottomNavigationHasExactlyThreeItems() {
        #expect(ExploreTab.allCases == [.feed, .fieldTrips, .community])
    }

    @Test func testSpeciesDictionaryTreeRemainsBehindReleaseFlag() {
        #expect(!FeatureFlag.speciesDictionaryTree.defaultValue)
    }

    @Test func testGetSpeciesDictionaryCanPreferSpeciesIdPayload() async throws {
        let testData = Data("""
        {
            "data": {
                "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                "scientific_name": "Testus floridus",
                "common_name": "Field Test",
                "alternative_common_names": [],
                "taxonomy": null,
                "hazard_type": "none",
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "wikipedia_overview": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "group_tags": [],
                "reference_images": [],
                "similar_species": []
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        mockTransport.register(path: "/species-dictionary") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["species_id"] as? String == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
            #expect(payload["scientific_name"] as? String == "Testus floridus")
            return (mockResponse, testData)
        }

        let species = try await networkClient.getSpeciesDictionary(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Testus floridus"
        )

        #expect(species.id == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
    }

    @Test func testGetSpeciesDictionaryMemoizesRecentResponseByScientificName() async throws {
        let testData = Data("""
        {
            "schema_version": 1,
            "data": {
                "id": "species-cache",
                "scientific_name": "Cache testus",
                "common_name": "Cache Test",
                "alternative_common_names": [],
                "taxonomy": null,
                "hazard_type": "none",
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "wikipedia_overview": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "group_tags": [],
                "reference_images": [],
                "similar_species": []
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var requestCount = 0

        mockTransport.register(path: "/species-dictionary") { request in
            requestCount += 1
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["scientific_name"] as? String == "Cache testus")
            return (mockResponse, testData)
        }

        let first = try await networkClient.getSpeciesDictionary(scientificName: "Cache testus")
        let second = try await networkClient.getSpeciesDictionary(scientificName: "  Cache   testus  ")

        #expect(first.id == "species-cache")
        #expect(second.id == "species-cache")
        #expect(requestCount == 1)
    }

    @Test func testSpeciesObservationStatsResponseDecodesPublicCharts() throws {
        let data = Data("""
        {
            "schema_version": 2,
            "data": {
                "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                "scientific_name": "Danaus plexippus",
                "source": {
                    "provider": "inaturalist",
                    "scope": "global",
                    "inaturalist_taxon_id": 48662,
                    "fetched_at": "2026-05-17T12:00:00.000Z"
                },
                "status": "partial",
                "total_observations": 450448,
                "last_observation_date": "2026-05-17",
                "fetched_at": "2026-05-17T12:00:00.000Z",
                "provider_errors": ["life stage bucket unavailable"],
                "seasonality": [
                    { "month": 1, "count": 10 },
                    { "month": 2, "count": 20 }
                ],
                "history": [
                    { "year": 2026, "month": 5, "count": 40 }
                ],
                "life_stage": [
                    {
                        "key": "adult",
                        "label": "Adult",
                        "values": [{ "month": 8, "count": 100 }]
                    }
                ],
                "sex": [
                    {
                        "key": "female",
                        "label": "Female",
                        "values": [{ "month": 8, "count": 12 }]
                    }
                ]
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesObservationStatsResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 2)
        #expect(response.data.scientificName == "Danaus plexippus")
        #expect(response.data.status == .partial)
        #expect(response.data.totalObservations == 450448)
        #expect(response.data.source.inaturalistTaxonId == 48662)
        #expect(response.data.lifeStage.first?.label == "Adult")
    }

    @Test func testGetSpeciesObservationStatsConstructsPayloadAndMemoizes() async throws {
        let testData = Data("""
        {
            "schema_version": 2,
            "data": {
                "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                "scientific_name": "Danaus plexippus",
                "source": {
                    "provider": "inaturalist",
                    "scope": "global",
                    "inaturalist_taxon_id": 48662,
                    "fetched_at": "2026-05-17T12:00:00.000Z"
                },
                "status": "fresh",
                "total_observations": 450448,
                "last_observation_date": "2026-05-17",
                "fetched_at": "2026-05-17T12:00:00.000Z",
                "provider_errors": [],
                "seasonality": [{ "month": 5, "count": 1200 }],
                "history": [{ "year": 2026, "month": 5, "count": 1200 }],
                "life_stage": [],
                "sex": []
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var requestCount = 0

        mockTransport.register(path: "/species-observation-stats") { request in
            requestCount += 1
            #expect(request.url?.path.hasSuffix("/species-observation-stats") == true)
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            #expect(queryItems["species_id"] == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
            #expect(queryItems["scientific_name"] == "Danaus plexippus")
            #expect(MockURLProtocol.bodyData(for: request) == nil)
            return (mockResponse, testData)
        }

        let first = try await networkClient.getSpeciesObservationStats(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Danaus plexippus"
        )
        let second = try await networkClient.getSpeciesObservationStats(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "  Danaus   plexippus  "
        )

        #expect(first.totalObservations == 450448)
        #expect(second.totalObservations == 450448)
        #expect(requestCount == 1)

        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "   "
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "not-a-uuid",
                scientificName: "Danaus plexippus"
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: String(repeating: "x", count: 161)
            )
        }
        #expect(requestCount == 1)
    }

    @Test func testGetSpeciesObservationStatsRejectsLegacyOrMismatchedResponses() async throws {
        func responseData(
            schemaVersion: Int,
            speciesId: String,
            scientificName: String
        ) -> Data {
            Data("""
            {
                "schema_version": \(schemaVersion),
                "data": {
                    "species_id": "\(speciesId)",
                    "scientific_name": "\(scientificName)",
                    "source": {
                        "provider": "inaturalist",
                        "scope": "global",
                        "inaturalist_taxon_id": 48662,
                        "fetched_at": "2026-05-17T12:00:00.000Z"
                    },
                    "status": "fresh",
                    "total_observations": 1,
                    "last_observation_date": "2026-05-17",
                    "fetched_at": "2026-05-17T12:00:00.000Z",
                    "provider_errors": [],
                    "seasonality": [],
                    "history": [],
                    "life_stage": [],
                    "sex": []
                }
            }
            """.utf8)
        }

        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var responses = [
            responseData(
                schemaVersion: 1,
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "Danaus plexippus"
            ),
            responseData(
                schemaVersion: 2,
                speciesId: "00000000-0000-4000-8000-000000000999",
                scientificName: "Danaus plexippus"
            )
        ]
        var requestCount = 0
        mockTransport.register(path: "/species-observation-stats") { _ in
            requestCount += 1
            return (mockResponse, responses.removeFirst())
        }

        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "Danaus plexippus"
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "Danaus plexippus"
            )
        }
        #expect(requestCount == 2)
    }

    @Test func testSpeciesDictionaryViewModelLoadsSpecies() async throws {
        mockTransport.register(path: "/species-dictionary") { _ in
            let data = Data("""
            {
                "data": {
                    "id": "species-123",
                    "scientific_name": "Testus floridus",
                    "common_name": "Field Test",
                    "alternative_common_names": [],
                    "taxonomy": null,
                    "hazard_type": "none",
                    "iucn_red_list_status": null,
                    "wikipedia_url": null,
                    "wikipedia_overview": null,
                    "habitat_description": null,
                    "gbif_taxon_key": null,
                    "group_tags": [],
                    "reference_images": [],
                    "similar_species": []
                }
            }
            """.utf8)
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let viewModel = SpeciesDictionaryPageViewModel(
            scientificName: "Testus floridus",
            networkClient: networkClient
        )
        await viewModel.load()

        guard case .loaded(let species) = viewModel.state else {
            Issue.record("Expected loaded species state")
            return
        }
        #expect(species.scientificName == "Testus floridus")
    }

    @Test func testSpeciesDictionaryViewModelMaps404ToNotFound() async {
        mockTransport.register(path: "/species-dictionary") { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":"Species not found"}"#.utf8))
        }

        let viewModel = SpeciesDictionaryPageViewModel(
            scientificName: "Missing species",
            networkClient: networkClient
        )
        await viewModel.load()

        #expect(viewModel.state == .notFound)
    }

    @Test func testSpeciesDictionaryHeroScrollEdgeEffectPolicyUsesClearanceHysteresis() {
        #expect(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: 45,
            isCurrentlyHidden: true
        ) == true)
        #expect(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: 44,
            isCurrentlyHidden: true
        ) == false)
        #expect(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: 47,
            isCurrentlyHidden: false
        ) == false)
        #expect(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: 48,
            isCurrentlyHidden: false
        ) == true)
        #expect(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: .infinity,
            isCurrentlyHidden: true
        ) == nil)
        #expect(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: .nan,
            isCurrentlyHidden: true
        ) == nil)
    }

    @Test func testCommunitySightingsViewModelLoadsPaginatesAndDeduplicates() async throws {
        let firstCursor = ExploreSpeciesPostCursor(
            imageQualityScore: 88,
            sharedAt: "2026-07-14T12:00:00.000Z",
            postId: "post-2"
        )
        let responses = [
            try makeCommunitySightingsResponse(
                postIds: ["post-1", "post-2"],
                nextCursor: firstCursor
            ),
            try makeCommunitySightingsResponse(
                postIds: ["post-2", "post-3"],
                nextCursor: nil
            )
        ]
        var requestedCursors: [ExploreSpeciesPostCursor?] = []
        let viewModel = SpeciesCommunitySightingsViewModel { speciesId, limit, cursor in
            #expect(speciesId == "species-123")
            #expect(limit == (cursor == nil ? 6 : 30))
            requestedCursors.append(cursor)
            return responses[requestedCursors.count - 1]
        }

        await viewModel.loadInitial(speciesId: "species-123")

        #expect(viewModel.posts.map(\.id) == ["post-1", "post-2"])
        #expect(viewModel.hasMore)
        #expect(!viewModel.didFail)

        await viewModel.loadMore()

        #expect(viewModel.posts.map(\.id) == ["post-1", "post-2", "post-3"])
        #expect(!viewModel.hasMore)
        #expect(requestedCursors == [nil, firstCursor])
    }

    @Test func testCommunitySightingsViewModelHidesFailedInitialLoad() async {
        let viewModel = SpeciesCommunitySightingsViewModel { _, _, _ in
            throw MerianError.invalidResponse
        }

        await viewModel.loadInitial(speciesId: "species-123")

        #expect(viewModel.posts.isEmpty)
        #expect(!viewModel.hasMore)
        #expect(viewModel.didFail)
        #expect(!viewModel.isLoadingInitial)
    }

    @Test func testCommunitySightingsTwoColumnGridRoundsOuterCorners() {
        let topRight = ProfilePublishedScanGridStyle.cornerRadii(
            index: 1,
            itemCount: 6,
            columnCount: 2
        )
        let bottomRight = ProfilePublishedScanGridStyle.cornerRadii(
            index: 5,
            itemCount: 6,
            columnCount: 2
        )

        #expect(topRight.topTrailing == ProfilePublishedScanGridStyle.cornerRadius)
        #expect(topRight.bottomTrailing == 0)
        #expect(bottomRight.topTrailing == 0)
        #expect(bottomRight.bottomTrailing == ProfilePublishedScanGridStyle.cornerRadius)
    }

    @Test func testSpeciesDictionaryCatalogResponseDecodesItemsAndCursor() throws {
        let data = Data("""
        {
            "schema_version": 1,
            "data": [
                {
                    "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                    "scientific_name": "Danaus plexippus",
                    "common_name": "Monarch Butterfly",
                    "content_quality": "complete",
                    "taxonomy": {
                        "kingdom": "Animalia",
                        "phylum": "Arthropoda",
                        "class": "Insecta",
                        "order": "Lepidoptera",
                        "family": "Nymphalidae",
                        "genus": "Danaus"
                    },
                    "iucn_red_list_status": "least concern",
                    "hazard_type": "none",
                    "group_tags": ["animal", "insect"],
                    "reference_image_url": "https://example.com/monarch.jpg"
                }
            ],
            "next_cursor": {
                "scientific_name": "Danaus plexippus",
                "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                "created_at": "2026-06-01T12:00:00Z"
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryCatalogResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.first?.commonName == "Monarch Butterfly")
        #expect(response.data.first?.taxonomy?.className == "Insecta")
        #expect(response.data.first?.referenceImageUrl == "https://example.com/monarch.jpg")
        #expect(response.nextCursor?.scientificName == "Danaus plexippus")
        #expect(response.nextCursor?.createdAt == "2026-06-01T12:00:00Z")
        #expect(response.data.first?.dictionaryRoute.entryPoint == .exploreDictionaryCatalog)
    }

    @Test func testSpeciesDictionaryOverviewResponseDecodesCategoriesAndRegions() throws {
        let data = Data("""
        {
            "schema_version": 1,
            "data": {
                "featured_species": {
                    "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                    "scientific_name": "Danaus plexippus",
                    "common_name": "Monarch Butterfly",
                    "overview": "The monarch butterfly is a milkweed butterfly known for long-distance migration.",
                    "reference_image_url": "https://example.com/featured.jpg"
                },
                "categories": [
                    {
                        "id": "all",
                        "title": "All",
                        "subtitle": "Browse every species in the dictionary",
                        "count": 42,
                        "reference_image_url": "https://example.com/all.jpg",
                        "region": null
                    },
                    {
                        "id": "your_region",
                        "title": "Your Region",
                        "subtitle": "Species associated with United States",
                        "count": 8,
                        "reference_image_url": "https://example.com/local.jpg",
                        "region": "United States",
                        "region_code": "US"
                    },
                    {
                        "id": "recently_added",
                        "title": "Recently added",
                        "subtitle": "Newest entries added to the database",
                        "count": 42,
                        "reference_image_url": "https://example.com/recent.jpg",
                        "region": null
                    }
                ],
                "groups": [
                    {
                        "id": "birds",
                        "title": "Birds",
                        "count": 12,
                        "reference_image_url": "https://example.com/bird.jpg"
                    }
                ],
                "regions": [
                    {
                        "id": "region:united%20states",
                        "title": "United States",
                        "count": 8,
                        "reference_image_url": "https://example.com/local.jpg",
                        "code": "US"
                    }
                ]
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryOverviewResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.featuredSpecies?.commonName == "Monarch Butterfly")
        #expect(response.data.featuredSpecies?.dictionaryRoute.speciesId == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
        #expect(response.data.featuredSpecies?.dictionaryRoute.entryPoint == .exploreDictionaryCatalog)
        #expect(response.data.categories.first?.id == .all)
        #expect(response.data.categories[1].id == .yourRegion)
        #expect(response.data.categories[1].region == "United States")
        #expect(response.data.categories[1].regionCode == "US")
        #expect(response.data.categories.last?.id == .recentlyAdded)
        #expect(response.data.groups.first?.title == "Birds")
        #expect(response.data.regions.first?.title == "United States")
        #expect(response.data.regions.first?.code == "US")
    }

    @Test func testSpeciesDictionaryRegionFlagNormalizesValidCountryCodes() {
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "US") == "🇺🇸")
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "ca") == "🇨🇦")
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "  mx\n") == "🇲🇽")
    }

    @Test func testSpeciesDictionaryRegionFlagRejectsMissingOrInvalidCountryCodes() {
        #expect(SpeciesDictionaryRegionFlag.emoji(for: nil) == nil)
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "") == nil)
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "USA") == nil)
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "ZZ") == nil)
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "1A") == nil)
    }

    @Test func testGetSpeciesDictionaryCatalogConstructsPayloadAndParsesResponse() async throws {
        let testData = Data("""
        {
            "schema_version": 1,
            "data": [],
            "next_cursor": {
                "scientific_name": "Danaus plexippus",
                "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        mockTransport.register(path: "/species-dictionary") { request in
            #expect(request.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let cursor = try #require(payload["cursor"] as? [String: Any])

            #expect(payload["mode"] as? String == "catalog")
            #expect(payload["category"] as? String == "group")
            #expect(payload["group"] as? String == "birds")
            #expect(payload["query"] as? String == "Danaus")
            #expect(payload["limit"] as? Int == 25)
            #expect(cursor["scientific_name"] as? String == "Danaus plexippus")
            #expect(cursor["species_id"] as? String == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
            #expect(cursor["created_at"] as? String == "2026-06-01T12:00:00Z")
            return (mockResponse, testData)
        }

        let response = try await networkClient.getSpeciesDictionaryCatalog(
            category: .group,
            group: " birds ",
            query: " Danaus ",
            limit: 25,
            cursor: SpeciesDictionaryCatalogCursor(
                scientificName: "Danaus plexippus",
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                createdAt: "2026-06-01T12:00:00Z"
            )
        )

        #expect(response.nextCursor?.speciesId == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
    }

    @Test func testGetSpeciesDictionaryOverviewConstructsPayloadAndParsesResponse() async throws {
        let testData = Data("""
        {
            "schema_version": 1,
            "data": {
                "categories": [],
                "regions": []
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        mockTransport.register(path: "/species-dictionary") { request in
            #expect(request.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

            #expect(payload["mode"] as? String == "overview")
            #expect(payload["user_region"] as? String == "US")
            #expect((payload["cache_buster"] as? String)?.isEmpty == false)
            return (mockResponse, testData)
        }

        let response = try await networkClient.getSpeciesDictionaryOverview(
            userRegion: " US "
        )

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.categories.isEmpty)
    }

    @Test func testSpeciesDictionaryTreeResponseDecodesGraphPayload() throws {
        let data = Data("""
        {
            "schema_version": 1,
            "data": {
                "nodes": [
                    {
                        "id": "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus",
                        "rank": "genus",
                        "title": "Danaus",
                        "subtitle": "Genus",
                        "parent_id": "taxonomy:family:animalia/arthropoda/insecta/lepidoptera/nymphalidae",
                        "species_count": 2,
                        "child_count": 2,
                        "lineage": {
                            "kingdom": "Animalia",
                            "phylum": "Arthropoda",
                            "class": "Insecta",
                            "order": "Lepidoptera",
                            "family": "Nymphalidae",
                            "genus": "Danaus"
                        },
                        "representative_species": {
                            "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                            "scientific_name": "Danaus plexippus",
                            "common_name": "Monarch Butterfly",
                            "content_quality": "complete",
                            "taxonomy": {
                                "kingdom": "Animalia",
                                "phylum": "Arthropoda",
                                "class": "Insecta",
                                "order": "Lepidoptera",
                                "family": "Nymphalidae",
                                "genus": "Danaus"
                            },
                            "iucn_red_list_status": "least concern",
                            "hazard_type": "none",
                            "group_tags": ["animal", "insect"],
                            "reference_image_url": "https://example.com/monarch.jpg"
                        },
                        "species": null
                    }
                ],
                "edges": [
                    {
                        "from": "taxonomy:family:animalia/arthropoda/insecta/lepidoptera/nymphalidae",
                        "to": "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus"
                    }
                ]
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryTreeResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.nodes.first?.rank == .genus)
        #expect(response.data.nodes.first?.lineage?.className == "Insecta")
        #expect(response.data.nodes.first?.representativeSpecies?.dictionaryRoute.scientificName == "Danaus plexippus")
        #expect(response.data.edges.first?.id.contains("->") == true)
    }

    @Test func testGetSpeciesDictionaryTreeConstructsPayloadAndParsesResponse() async throws {
        let testData = Data("""
        {
            "schema_version": 1,
            "data": {
                "nodes": [],
                "edges": []
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        mockTransport.register(path: "/species-dictionary") { request in
            #expect(request.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

            #expect(payload["mode"] as? String == "tree")
            #expect(payload["scope"] as? String == "all_species")
            #expect(payload["limit"] == nil)
            #expect(payload["query"] == nil)
            return (mockResponse, testData)
        }

        let response = try await networkClient.getSpeciesDictionaryTree()

        #expect(response.data.nodes.isEmpty)
        #expect(response.data.edges.isEmpty)
    }

    @Test func testGetSpeciesDictionaryTreeSendsMyScansScope() async throws {
        let testData = Data("""
        {
            "schema_version": 1,
            "data": {
                "nodes": [],
                "edges": []
            }
        }
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        mockTransport.register(path: "/species-dictionary") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

            #expect(payload["mode"] as? String == "tree")
            #expect(payload["scope"] as? String == "my_scans")
            return (mockResponse, testData)
        }

        let response = try await networkClient.getSpeciesDictionaryTree(scope: .myScans)

        #expect(response.data.nodes.isEmpty)
        #expect(response.data.edges.isEmpty)
    }

    @Test func testTaxonomyTreeGraphSearchVisibilityLayoutAndRouting() throws {
        let graph = TaxonomyTreeGraphBuilder.build(from: Self.taxonomyTreePayload())
        let kingdomID = "taxonomy:kingdom:animalia"
        let phylumID = "taxonomy:phylum:animalia/arthropoda"
        let classID = "taxonomy:class:animalia/arthropoda/insecta"
        let orderID = "taxonomy:order:animalia/arthropoda/insecta/lepidoptera"
        let familyID = "taxonomy:family:animalia/arthropoda/insecta/lepidoptera/nymphalidae"
        let danausID = "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus"
        let monarchID = "species:1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let queenID = "species:2cf79982-e5ee-4e3d-8d65-274527e6ae02"
        let danausNode = try #require(graph.node(id: danausID))
        let monarchNode = try #require(graph.node(id: monarchID))

        #expect(danausNode.speciesCount == 2)
        #expect(monarchNode.dictionaryRoute?.scientificName == "Danaus plexippus")
        #expect(graph.searchResults(for: "monarch").first?.id == monarchID)
        #expect(graph.rootNodeIDs == [kingdomID])

        let allNodeIDs = Set(graph.nodes.map(\.id))
        let distantIDs = graph.visibleNodeIDs(focusedNodeID: nil, selectedNodeID: nil, scale: 0.6)
        #expect(distantIDs == allNodeIDs)

        let overviewIDs = graph.visibleNodeIDs(focusedNodeID: nil, selectedNodeID: nil, scale: 1.1)
        #expect(overviewIDs.contains(phylumID))
        #expect(overviewIDs.contains(classID))
        #expect(overviewIDs == distantIDs)

        let closeOverviewIDs = graph.visibleNodeIDs(focusedNodeID: nil, selectedNodeID: nil, scale: 2.1)
        #expect(closeOverviewIDs.contains(classID))
        #expect(closeOverviewIDs.contains(orderID))
        #expect(closeOverviewIDs == distantIDs)

        let maximumOverviewIDs = graph.visibleNodeIDs(focusedNodeID: nil, selectedNodeID: nil, scale: 4)
        #expect(maximumOverviewIDs.contains(monarchID))
        #expect(maximumOverviewIDs.contains(queenID))

        let selectedClassIDs = graph.visibleNodeIDs(focusedNodeID: nil, selectedNodeID: classID, scale: 1.1)
        #expect(selectedClassIDs.contains(orderID))
        #expect(selectedClassIDs.contains(familyID))
        #expect(selectedClassIDs == allNodeIDs)

        let distantFocusedClassIDs = graph.visibleNodeIDs(
            focusedNodeID: classID,
            selectedNodeID: classID,
            scale: 0.64
        )
        #expect(distantFocusedClassIDs.contains(familyID))
        #expect(distantFocusedClassIDs.contains(danausID))
        #expect(distantFocusedClassIDs.contains(monarchID))

        let closeFocusedClassIDs = graph.visibleNodeIDs(
            focusedNodeID: classID,
            selectedNodeID: classID,
            scale: 4
        )
        #expect(distantFocusedClassIDs == closeFocusedClassIDs)

        let maximumKingdomIDs = graph.visibleNodeIDs(
            focusedNodeID: kingdomID,
            selectedNodeID: kingdomID,
            scale: 4
        )
        #expect(maximumKingdomIDs == Set(graph.nodes.map(\.id)))

        #expect(graph.visibleNodeIDs(focusedNodeID: danausID, selectedNodeID: nil, scale: 0.6).count == graph.nodes.count)

        let layout = TaxonomyConstellationLayout.make(
            graph: graph,
            visibleNodeIDs: graph.visibleNodeIDs(focusedNodeID: nil, selectedNodeID: monarchID, scale: 1.2),
            focusedNodeID: danausID,
            minimumSize: CGSize(width: 320, height: 480)
        )
        let genusPosition = try #require(layout.positions[danausID])
        let speciesPosition = try #require(layout.positions[monarchID])
        let siblingSpeciesPosition = try #require(layout.positions[queenID])

        #expect(abs(genusPosition.x - layout.size.width / 2) < 0.001)
        #expect(abs(genusPosition.y - layout.size.height / 2) < 0.001)
        #expect(abs(speciesPosition.x - genusPosition.x) > 1 || abs(speciesPosition.y - genusPosition.y) > 1)
        #expect(hypot(
            speciesPosition.x - siblingSpeciesPosition.x,
            speciesPosition.y - siblingSpeciesPosition.y
        ) * 4 >= 150)
        #expect(layout.size.width >= 320)
        #expect(layout.size.height >= 480)
    }

    @Test func testTaxonomyConstellationKeepsFocusedDescendantsVisibleWhileZoomingOut() throws {
        let graph = TaxonomyTreeGraphBuilder.build(from: Self.taxonomyTreePayload())
        let kingdomID = "taxonomy:kingdom:animalia"
        let monarchID = "species:1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let distantNodeIDs = graph.visibleNodeIDs(
            focusedNodeID: kingdomID,
            selectedNodeID: kingdomID,
            scale: 0.64
        )
        let closeNodeIDs = graph.visibleNodeIDs(
            focusedNodeID: kingdomID,
            selectedNodeID: kingdomID,
            scale: 4
        )
        var layoutNodeIDs: Set<String> = [kingdomID]
        layoutNodeIDs.formUnion(graph.descendantIDs(of: kingdomID))
        let layout = TaxonomyConstellationLayout.make(
            graph: graph,
            visibleNodeIDs: layoutNodeIDs,
            focusedNodeID: kingdomID,
            minimumSize: CGSize(width: 390, height: 760)
        )
        let kingdomPosition = try #require(layout.positions[kingdomID])

        #expect(distantNodeIDs == closeNodeIDs)
        #expect(distantNodeIDs.contains(monarchID))
        #expect(layout.positions[monarchID] != nil)
        #expect(kingdomPosition == CGPoint(
            x: layout.size.width / 2,
            y: layout.size.height / 2
        ))
    }

    @Test func testTaxonomyTreeZoomPreservesAnchorContentPoint() {
        let viewModel = TaxonomyTreeCanvasViewModel()
        viewModel.scale = 1
        viewModel.baseScale = 1
        viewModel.offset = CGSize(width: -120, height: 80)

        let anchor = CGPoint(x: 180, y: 260)
        let before = CGPoint(
            x: (anchor.x - viewModel.offset.width) / viewModel.scale,
            y: (anchor.y - viewModel.offset.height) / viewModel.scale
        )

        viewModel.zoom(by: 1.5, anchoredAt: anchor)

        let after = CGPoint(
            x: (anchor.x - viewModel.offset.width) / viewModel.scale,
            y: (anchor.y - viewModel.offset.height) / viewModel.scale
        )
        #expect(abs(before.x - after.x) < 0.001)
        #expect(abs(before.y - after.y) < 0.001)
        #expect(viewModel.scale == 1.5)
    }

    @Test func testTaxonomyTreePinchKeepsAnchorBetweenGestureUpdates() {
        let viewModel = TaxonomyTreeCanvasViewModel()
        viewModel.scale = 1
        viewModel.baseScale = 1
        viewModel.offset = CGSize(width: -80, height: 40)
        let anchor = CGPoint(x: 160, y: 240)
        let anchoredContentPoint = CGPoint(
            x: (anchor.x - viewModel.offset.width) / viewModel.scale,
            y: (anchor.y - viewModel.offset.height) / viewModel.scale
        )

        viewModel.updateMagnification(1.5, anchoredAt: anchor)
        viewModel.updateMagnification(2, anchoredAt: anchor)

        let screenPosition = CGPoint(
            x: anchoredContentPoint.x * viewModel.scale + viewModel.offset.width,
            y: anchoredContentPoint.y * viewModel.scale + viewModel.offset.height
        )
        #expect(abs(screenPosition.x - anchor.x) < 0.001)
        #expect(abs(screenPosition.y - anchor.y) < 0.001)
        #expect(abs(viewModel.scale - 2) < 0.001)
    }

    @Test func testTaxonomyTreeZoomPercentageUsesInitialViewAsOneHundredPercent() {
        let viewModel = TaxonomyTreeCanvasViewModel()

        #expect(viewModel.zoomPercentage == 100)

        viewModel.setScale(2.2)

        #expect(viewModel.zoomPercentage == 200)
    }

    @Test func testTaxonomyTreePinchCanReverseAndBeginASecondGesture() {
        let viewModel = TaxonomyTreeCanvasViewModel()
        let anchor = CGPoint(x: 160, y: 240)

        viewModel.updateMagnification(1.8, anchoredAt: anchor)
        viewModel.updateMagnification(1.2, anchoredAt: anchor)

        #expect(abs(viewModel.scale - 1.32) < 0.001)

        viewModel.endMagnification()
        viewModel.updateMagnification(1.25, anchoredAt: anchor)

        #expect(abs(viewModel.scale - 1.65) < 0.001)
        #expect(viewModel.zoomPercentage == 150)
    }

    @Test func testTaxonomyTreeRelayoutCentersFocusedNode() {
        let viewModel = TaxonomyTreeCanvasViewModel()
        viewModel.scale = 2
        viewModel.baseScale = 2
        viewModel.focusedNodeID = "focused"
        let nextPosition = CGPoint(x: 360, y: 280)
        let viewportSize = CGSize(width: 390, height: 760)

        viewModel.reconcileLayoutChange(
            to: ["focused": nextPosition],
            viewportSize: viewportSize
        )

        let nextScreenPosition = CGPoint(
            x: nextPosition.x * viewModel.scale + viewModel.offset.width,
            y: nextPosition.y * viewModel.scale + viewModel.offset.height
        )
        #expect(abs(viewportSize.width / 2 - nextScreenPosition.x) < 0.001)
        #expect(abs(viewportSize.height / 2 - nextScreenPosition.y) < 0.001)
    }

    @Test func testTaxonomyTreeNodeFocusZoomsIntoBranch() {
        let viewModel = TaxonomyTreeCanvasViewModel()

        viewModel.focus(on: "focused", viewportSize: CGSize(width: 390, height: 760))

        #expect(viewModel.focusedNodeID == "focused")
        #expect(viewModel.selectedNodeID == "focused")
        #expect(viewModel.scale == 1.35)
        #expect(viewModel.baseScale == 1.35)
    }

    @Test func testTaxonomyTreeSupportsOverviewZoomOut() {
        let viewModel = TaxonomyTreeCanvasViewModel()

        viewModel.setScale(0.1)

        #expect(viewModel.scale == 0.64)

        viewModel.setScale(10)

        #expect(viewModel.scale == 4)
    }

    @Test func testTaxonomyTreeCanFitLargeFocusedBranchOnScreen() {
        let viewModel = TaxonomyTreeCanvasViewModel()
        let viewportSize = CGSize(width: 390, height: 760)
        let contentSize = CGSize(width: 4_500, height: 4_500)
        let expectedMinimum = viewModel.minimumScale(
            for: viewportSize,
            contentSize: contentSize
        )

        viewModel.zoom(
            by: 0.01,
            viewportSize: viewportSize,
            contentSize: contentSize
        )

        #expect(expectedMinimum < 0.64)
        #expect(expectedMinimum >= 0.08)
        #expect(abs(viewModel.scale - expectedMinimum) < 0.001)
    }

    @Test func testTaxonomyTreeGestureStateReusesCachedScene() {
        let viewModel = TaxonomyTreeCanvasViewModel()
        let viewportSize = CGSize(width: 390, height: 760)
        let initialScene = viewModel.constellationScene(in: viewportSize)

        viewModel.scale = 2.4
        viewModel.baseScale = 2.4
        viewModel.offset = CGSize(width: -180, height: 90)
        viewModel.dragOffset = CGSize(width: 24, height: -12)

        let gestureScene = viewModel.constellationScene(in: viewportSize)
        let resizedScene = viewModel.constellationScene(
            in: CGSize(width: 430, height: 760)
        )

        #expect(gestureScene.revision == initialScene.revision)
        #expect(resizedScene.revision != initialScene.revision)
    }

    @Test func testTaxonomyTreeCachedReloadKeepsActiveScene() async throws {
        let graph = TaxonomyTreeGraphBuilder.build(from: Self.taxonomyTreePayload())
        var loadCount = 0
        let viewModel = TaxonomyTreeCanvasViewModel { _ in
            loadCount += 1
            return graph
        }
        let viewportSize = CGSize(width: 390, height: 760)

        await viewModel.loadTree()
        let loadedScene = viewModel.constellationScene(in: viewportSize)
        viewModel.scale = 2.4
        viewModel.offset = CGSize(width: -180, height: 90)
        let gestureScene = viewModel.constellationScene(in: viewportSize)
        await viewModel.loadTree()
        let cachedScene = viewModel.constellationScene(in: viewportSize)

        #expect(loadCount == 1)
        #expect(viewModel.graph == graph)
        #expect(gestureScene.revision == loadedScene.revision)
        #expect(gestureScene.visibleNodeIDs == loadedScene.visibleNodeIDs)
        #expect(gestureScene.visibleNodeIDs == Set(graph.nodes.map(\.id)))
        #expect(cachedScene.revision == loadedScene.revision)
    }

    @Test func testTaxonomyConstellationSceneSpatiallyCullsNodesAndEdges() throws {
        let graph = TaxonomyTreeGraphBuilder.build(from: Self.taxonomyTreePayload())
        let visibleNodeIDs = Set(graph.nodes.map(\.id))
        let layout = TaxonomyConstellationLayout.make(
            graph: graph,
            visibleNodeIDs: visibleNodeIDs,
            focusedNodeID: nil,
            minimumSize: CGSize(width: 390, height: 760)
        )
        let monarchID = "species:1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let monarchPosition = try #require(layout.positions[monarchID])
        let scene = TaxonomyConstellationScene(
            revision: 1,
            graph: graph,
            layoutNodeIDs: visibleNodeIDs,
            layout: layout
        )

        let nearbyNodes = scene.nodes(in: CGRect(
            x: monarchPosition.x - 1,
            y: monarchPosition.y - 1,
            width: 2,
            height: 2
        ))
        let distantNodes = scene.nodes(in: CGRect(
            x: layout.size.width + 1_000,
            y: layout.size.height + 1_000,
            width: 100,
            height: 100
        ))
        let nearbyEdges = scene.edges(
            in: CGRect(
                x: monarchPosition.x - 1,
                y: monarchPosition.y - 1,
                width: 2,
                height: 2
            ),
            visibleNodeIDs: visibleNodeIDs
        )
        let distantEdges = scene.edges(
            in: CGRect(
                x: layout.size.width + 1_000,
                y: layout.size.height + 1_000,
                width: 100,
                height: 100
            ),
            visibleNodeIDs: visibleNodeIDs
        )

        #expect(nearbyNodes.map(\.id).contains(monarchID))
        #expect(nearbyNodes.count < graph.nodes.count)
        #expect(distantNodes.isEmpty)
        #expect(nearbyEdges.contains { $0.edge.to == monarchID })
        #expect(nearbyEdges.count < graph.edges.count)
        #expect(distantEdges.isEmpty)
    }

    @Test func testTaxonomyConstellationSceneRejectsEdgeBoundingBoxFalsePositives() {
        let parent = TaxonomyTreeNode(
            id: "parent",
            title: "Parent",
            subtitle: nil,
            rank: .kingdom,
            parentID: nil,
            speciesCount: 1,
            childCount: 1,
            lineage: nil,
            representativeSpecies: nil,
            species: nil
        )
        let child = TaxonomyTreeNode(
            id: "child",
            title: "Child",
            subtitle: nil,
            rank: .species,
            parentID: parent.id,
            speciesCount: 1,
            childCount: 0,
            lineage: nil,
            representativeSpecies: nil,
            species: nil
        )
        let graph = TaxonomyTreeGraph(
            nodes: [parent, child],
            edges: [TaxonomyTreeEdge(from: parent.id, to: child.id)]
        )
        let layout = TaxonomyConstellationLayout(
            positions: [
                parent.id: CGPoint(x: 0, y: 0),
                child.id: CGPoint(x: 1_000, y: 1_000)
            ],
            size: CGSize(width: 1_000, height: 1_000)
        )
        let visibleNodeIDs: Set<String> = [parent.id, child.id]
        let scene = TaxonomyConstellationScene(
            revision: 1,
            graph: graph,
            layoutNodeIDs: visibleNodeIDs,
            layout: layout
        )

        let crossingEdges = scene.edges(
            in: CGRect(x: 490, y: 490, width: 20, height: 20),
            visibleNodeIDs: visibleNodeIDs
        )
        let boundingBoxOnlyEdges = scene.edges(
            in: CGRect(x: 0, y: 900, width: 20, height: 20),
            visibleNodeIDs: visibleNodeIDs
        )

        #expect(crossingEdges.count == 1)
        #expect(boundingBoxOnlyEdges.isEmpty)
    }

    @Test func testTaxonomyTreeDefaultsToAllSpeciesAndResetsOnScopeChange() {
        let viewModel = TaxonomyTreeCanvasViewModel()
        viewModel.selectedNodeID = "selected"
        viewModel.focusedNodeID = "focused"
        viewModel.offset = CGSize(width: 24, height: -12)
        viewModel.dragOffset = CGSize(width: 4, height: 8)
        viewModel.scale = 3.4
        viewModel.baseScale = 3.4

        #expect(viewModel.selectedTreeScope == .allSpecies)

        viewModel.selectTreeScope(.myScans)

        #expect(viewModel.selectedTreeScope == .myScans)
        #expect(viewModel.selectedNodeID == nil)
        #expect(viewModel.focusedNodeID == nil)
        #expect(viewModel.offset == .zero)
        #expect(viewModel.dragOffset == .zero)
        #expect(viewModel.scale == 1.1)
        #expect(viewModel.baseScale == 1.1)
        #expect(viewModel.isLoading)
    }

    @Test func testTaxonomyTreeCanCenterTopNodeAtInitialViewport() {
        let viewModel = TaxonomyTreeCanvasViewModel()
        viewModel.scale = 1.1
        let rootID = "taxonomy:kingdom:animalia"
        let rootPosition = CGPoint(x: 420, y: 100)
        let viewportSize = CGSize(width: 390, height: 760)

        viewModel.centerTop(
            nodeID: rootID,
            positions: [rootID: rootPosition],
            viewportSize: viewportSize
        )

        let screenX = rootPosition.x * viewModel.scale + viewModel.offset.width
        let screenY = rootPosition.y * viewModel.scale + viewModel.offset.height
        #expect(abs(screenX - viewportSize.width / 2) < 0.001)
        #expect(abs(screenY - 180) < 0.001)
    }

    private static func taxonomyTreePayload() -> SpeciesDictionaryTreePayload {
        let taxonomy = SpeciesDictionaryTaxonomy(
            kingdom: "Animalia",
            phylum: "Arthropoda",
            className: "Insecta",
            order: "Lepidoptera",
            family: "Nymphalidae",
            genus: "Danaus"
        )
        let monarch = SpeciesDictionaryTreeSpecies(
            id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            contentQuality: .complete,
            taxonomy: taxonomy,
            iucnRedListStatus: "least concern",
            hazardType: "none",
            groupTags: ["animal", "insect"],
            referenceImageUrl: "https://example.com/monarch.jpg"
        )
        let queen = SpeciesDictionaryTreeSpecies(
            id: "2cf79982-e5ee-4e3d-8d65-274527e6ae02",
            scientificName: "Danaus gilippus",
            commonName: "Queen Butterfly",
            contentQuality: .complete,
            taxonomy: taxonomy,
            iucnRedListStatus: nil,
            hazardType: nil,
            groupTags: ["animal", "insect"],
            referenceImageUrl: nil
        )
        let lineageIDs = [
            "taxonomy:kingdom:animalia",
            "taxonomy:phylum:animalia/arthropoda",
            "taxonomy:class:animalia/arthropoda/insecta",
            "taxonomy:order:animalia/arthropoda/insecta/lepidoptera",
            "taxonomy:family:animalia/arthropoda/insecta/lepidoptera/nymphalidae",
            "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus"
        ]
        let ranks: [SpeciesDictionaryTreeRank] = [.kingdom, .phylum, .className, .order, .family, .genus]
        let titles = ["Animalia", "Arthropoda", "Insecta", "Lepidoptera", "Nymphalidae", "Danaus"]
        let nodes = zip(lineageIDs.indices, lineageIDs).map { pair in
            let index = pair.0
            let id = pair.1
            return SpeciesDictionaryTreeNodePayload(
                id: id,
                rank: ranks[index],
                title: titles[index],
                subtitle: ranks[index].title,
                parentId: index == 0 ? nil : lineageIDs[index - 1],
                speciesCount: 2,
                childCount: index == lineageIDs.count - 1 ? 2 : 1,
                lineage: taxonomy,
                representativeSpecies: monarch,
                species: nil
            )
        } + [
            SpeciesDictionaryTreeNodePayload(
                id: "species:1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                rank: .species,
                title: "Monarch Butterfly",
                subtitle: "Danaus plexippus",
                parentId: lineageIDs.last,
                speciesCount: 1,
                childCount: 0,
                lineage: taxonomy,
                representativeSpecies: monarch,
                species: monarch
            ),
            SpeciesDictionaryTreeNodePayload(
                id: "species:2cf79982-e5ee-4e3d-8d65-274527e6ae02",
                rank: .species,
                title: "Queen Butterfly",
                subtitle: "Danaus gilippus",
                parentId: lineageIDs.last,
                speciesCount: 1,
                childCount: 0,
                lineage: taxonomy,
                representativeSpecies: queen,
                species: queen
            )
        ]
        let lineageEdges = zip(lineageIDs.dropLast(), lineageIDs.dropFirst()).map {
            SpeciesDictionaryTreeEdgePayload(from: $0, to: $1)
        }
        let speciesEdges = [
            SpeciesDictionaryTreeEdgePayload(from: lineageIDs.last!, to: "species:1cf79982-e5ee-4e3d-8d65-274527e6ae01"),
            SpeciesDictionaryTreeEdgePayload(from: lineageIDs.last!, to: "species:2cf79982-e5ee-4e3d-8d65-274527e6ae02")
        ]

        return SpeciesDictionaryTreePayload(nodes: nodes, edges: lineageEdges + speciesEdges)
    }
}

private func makeCommunitySightingsResponse(
    postIds: [String],
    nextCursor: ExploreSpeciesPostCursor?
) throws -> ExploreSpeciesPostsResponse {
    let posts: [[String: Any]] = postIds.map { postId in
        [
            "post_id": postId,
            "scan_id": "scan-\(postId)",
            "hero_image_url": "https://example.com/\(postId).webp",
            "shared_at": "2026-07-14T12:00:00.000Z",
            "author_user_id": "author-123",
            "author_name": "Sightings Author",
            "author_avatar_url": NSNull(),
            "species_common_name": "Field Test",
            "species_scientific_name": "Testus floridus",
            "public_location_label": NSNull(),
            "location_sharing": "obscured",
            "time_of_day": NSNull(),
            "current_month": NSNull(),
            "weather_condition": NSNull(),
            "weather_temperature_f": NSNull(),
            "like_count": 0,
            "comment_count": 0,
            "viewer_has_liked": false,
            "is_owned_by_viewer": false,
            "ranking_value": NSNull()
        ]
    }
    let nextCursorPayload: Any = if let nextCursor {
        [
            "image_quality_score": nextCursor.imageQualityScore.map { $0 as Any } ?? NSNull(),
            "shared_at": nextCursor.sharedAt,
            "post_id": nextCursor.postId
        ] as [String: Any]
    } else {
        NSNull()
    }
    let data = try JSONSerialization.data(withJSONObject: [
        "data": posts,
        "next_cursor": nextCursorPayload
    ])
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(ExploreSpeciesPostsResponse.self, from: data)
}
