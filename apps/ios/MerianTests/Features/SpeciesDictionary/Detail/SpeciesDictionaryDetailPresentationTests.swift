import XCTest

@testable import Merian

@MainActor
final class SpeciesDictionaryDetailPresentationTests: XCTestCase {
    func testContentQualityUsesServerValueAndLegacyFallback() {
        let serverClassified = SpeciesDictionaryEntry(
            id: "species-server",
            scientificName: "Testus serveris",
            commonName: "Server Test",
            contentQuality: .sparse,
            alternativeCommonNames: [],
            taxonomy: nil,
            hazardType: nil,
            iucnRedListStatus: nil,
            wikipediaUrl: nil,
            wikipediaOverview: nil,
            habitatDescription: nil,
            gbifTaxonKey: nil,
            groupTags: [],
            referenceImages: [],
            similarSpecies: []
        )
        let legacy = SpeciesDictionaryEntry(
            id: "species-legacy",
            scientificName: "Testus legacy",
            commonName: "Legacy Test",
            contentQuality: nil,
            alternativeCommonNames: [],
            taxonomy: nil,
            hazardType: nil,
            iucnRedListStatus: nil,
            wikipediaUrl: nil,
            wikipediaOverview: nil,
            habitatDescription: nil,
            gbifTaxonKey: nil,
            groupTags: [],
            referenceImages: [],
            similarSpecies: []
        )

        XCTAssertEqual(serverClassified.effectiveContentQuality, .sparse)
        XCTAssertEqual(legacy.effectiveContentQuality, .needsEnrichment)
    }

    func testSimilarSpeciesAdapterPreservesRelationMetadata() throws {
        let data = Data("""
        [{
            "species_id": "species-minor",
            "scientific_name": " Testus minor ",
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
        }]
        """.utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let similarSpecies = try decoder.decode(
            [SpeciesDictionarySimilarSpecies].self,
            from: data
        )
        let entry = SpeciesDictionaryEntry(
            id: "species-primary",
            scientificName: "Testus floridus",
            commonName: "Field Test",
            contentQuality: .complete,
            alternativeCommonNames: [],
            taxonomy: nil,
            hazardType: nil,
            iucnRedListStatus: nil,
            wikipediaUrl: nil,
            wikipediaOverview: nil,
            habitatDescription: nil,
            gbifTaxonKey: nil,
            groupTags: [],
            referenceImages: [],
            similarSpecies: similarSpecies
        )

        let adapted = try XCTUnwrap(entry.similarSpeciesData?.entries.first)
        XCTAssertEqual(adapted.speciesId, "species-minor")
        XCTAssertEqual(adapted.scientificName, "Testus minor")
        XCTAssertEqual(adapted.similarityReason, "Similar five-petaled flowers.")
        XCTAssertEqual(adapted.visualTraits, ["five petals", "serrated leaves"])
        XCTAssertEqual(adapted.similarityConfidence, 0.78)
    }

    func testAlternativeCommonNamesSanitizeAndDeduplicateNames() {
        let names = AlternativeCommonNamesLine.displayNames(
            from: [
                "Field Test",
                " Meadow Test, Prairie Test ",
                "meadow test",
                "",
                "Garden Test"
            ],
            excluding: "Field Test"
        )

        XCTAssertEqual(names, [
            "Meadow Test",
            "Prairie Test",
            "Garden Test"
        ])
    }

    func testAlternativeCommonNamesTreatDashVariantsAsDuplicates() {
        let names = AlternativeCommonNamesLine.displayNames(
            from: [
                "Desert-rose",
                "Desert–Rose",
                "Sabi Star",
                "Sabi-star"
            ],
            excluding: "Desert Rose"
        )

        XCTAssertEqual(names, ["Sabi Star"])
    }

    func testGalleryMapsSelectionAndAttribution() throws {
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

        let presentation = try XCTUnwrap(
            SpeciesDictionaryImageGalleryBuilder.presentation(
                for: images,
                selectedImageID: images[1].id
            )
        )

        XCTAssertEqual(presentation.items.map(\.id), [
            "species-reference-https://example.com/first.jpg",
            "species-reference-https://example.com/second.jpg"
        ])
        XCTAssertEqual(
            presentation.items.map(\.referenceAttributionLabel),
            ["First Photographer · CC BY-SA · Wikipedia", "GBIF"]
        )
        XCTAssertEqual(presentation.initialSelectedIndex, 1)
        XCTAssertEqual(presentation.items.map(\.source), [
            .referenceURL("https://example.com/first.jpg"),
            .referenceURL("https://example.com/second.jpg")
        ])
    }

    func testGallerySkipsDeniedMediaAndPromotesNextImage() throws {
        let denied = SpeciesDictionaryReferenceImage(
            url:
                "https://inaturalist-open-data.s3.amazonaws.com/photos/605615444/original.jpg",
            source: .gbif,
            license: nil,
            attribution: nil,
            width: nil,
            height: nil
        )
        let safe = SpeciesDictionaryReferenceImage(
            url:
                "https://live.staticflickr.com/65535/55027456166_642323e641_b.jpg",
            source: .gbif,
            license: nil,
            attribution: nil,
            width: nil,
            height: nil
        )

        let presentation = try XCTUnwrap(
            SpeciesDictionaryImageGalleryBuilder.presentation(
                for: [denied, safe],
                selectedImageID: safe.id
            )
        )

        XCTAssertEqual(
            presentation.items.map(\.source),
            [.referenceURL(safe.url)]
        )
        XCTAssertEqual(presentation.initialSelectedIndex, 0)
        XCTAssertNil(SpeciesDictionaryImageGalleryBuilder.presentation(
            for: [denied],
            selectedImageID: denied.id
        ))
    }

    func testShareContentUsesCanonicalPublicURL() throws {
        let url = try XCTUnwrap(SpeciesDictionaryShareContent.url(
            speciesId: " 1CF79982-E5EE-4E3D-8D65-274527E6AE01 ",
            commonName: "Mwanza flat-headed rock agama",
            scientificName: "Agama mwanzae"
        ))

        XCTAssertEqual(
            url.absoluteString,
            "https://naturebook.earth/species/1cf79982-e5ee-4e3d-8d65-274527e6ae01/mwanza-flat-headed-rock-agama"
        )
        XCTAssertNil(SpeciesDictionaryShareContent.url(
            speciesId: "not-a-uuid",
            commonName: "Field Test",
            scientificName: "Testus floridus"
        ))
        XCTAssertEqual(
            SpeciesDictionaryShareContent.slug(
                commonName: "Café-à-lait!",
                scientificName: "Testus floridus"
            ),
            "cafe-a-lait"
        )
        XCTAssertEqual(
            SpeciesDictionaryShareContent.slug(
                commonName: "",
                scientificName: "Agama mwanzae"
            ),
            "agama-mwanzae"
        )
        XCTAssertEqual(
            SpeciesDictionaryShareContent.slug(
                commonName: "東京",
                scientificName: "Agama mwanzae"
            ),
            "agama-mwanzae"
        )
        XCTAssertEqual(
            SpeciesDictionaryShareContent.slug(
                commonName: "東京",
                scientificName: ""
            ),
            "species"
        )
        XCTAssertLessThanOrEqual(
            SpeciesDictionaryShareContent.slug(
                commonName: String(repeating: "a ", count: 100),
                scientificName: ""
            ).count,
            80
        )
        XCTAssertEqual(
            SpeciesDictionaryShareContent.message(commonName: "Field Test"),
            "Learn about Field Test on Naturebook."
        )
    }

    func testFieldChatPolicyRequiresCanonicalLoadedSpeciesUUID() {
        let canonicalID = "019fb71a-94de-7998-a4ce-f163b531d3e0"
        XCTAssertEqual(
            SpeciesDictionaryChatPresentationPolicy.canonicalSpeciesID(
                " 019FB71A-94DE-7998-A4CE-F163B531D3E0 "
            ),
            canonicalID
        )
        XCTAssertNil(
            SpeciesDictionaryChatPresentationPolicy.canonicalSpeciesID(
                "species-external-key"
            )
        )
        XCTAssertNil(
            SpeciesDictionaryChatPresentationPolicy.canonicalSpeciesID(nil)
        )
        XCTAssertEqual(
            SpeciesDictionaryChatPresentationPolicy.destination(
                isProActive: false
            ),
            .paywall
        )
        XCTAssertEqual(
            SpeciesDictionaryChatPresentationPolicy.destination(
                isProActive: true
            ),
            .fieldChat
        )
        XCTAssertTrue(
            SpeciesDictionaryChatPresentationPolicy
                .canCommitAsyncPresentation(
                    requestedSpeciesID: canonicalID,
                    currentSpeciesID: canonicalID.uppercased(),
                    hasActivePresentation: false,
                    isCancelled: false
                )
        )
        XCTAssertFalse(
            SpeciesDictionaryChatPresentationPolicy
                .canCommitAsyncPresentation(
                    requestedSpeciesID: canonicalID,
                    currentSpeciesID: canonicalID,
                    hasActivePresentation: true,
                    isCancelled: false
                )
        )
        XCTAssertFalse(
            SpeciesDictionaryChatPresentationPolicy
                .canCommitAsyncPresentation(
                    requestedSpeciesID: canonicalID,
                    currentSpeciesID: canonicalID,
                    hasActivePresentation: false,
                    isCancelled: true
                )
        )
    }

    func testHeroScrollPolicyUsesClearanceHysteresis() {
        XCTAssertEqual(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: 45,
            isCurrentlyHidden: true
        ), true)
        XCTAssertEqual(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: 44,
            isCurrentlyHidden: true
        ), false)
        XCTAssertEqual(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: 47,
            isCurrentlyHidden: false
        ), false)
        XCTAssertEqual(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: 48,
            isCurrentlyHidden: false
        ), true)
        XCTAssertNil(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: .infinity,
            isCurrentlyHidden: true
        ))
        XCTAssertNil(DictionaryHeroEdgePolicy.shouldHideEffect(
            heroMaxY: .nan,
            isCurrentlyHidden: true
        ))
    }

    func testCommunitySightingsGridRoundsOuterCorners() {
        let topRight = PublishedScanGridStyle.cornerRadii(
            index: 1,
            itemCount: 6,
            columnCount: 2
        )
        let bottomRight = PublishedScanGridStyle.cornerRadii(
            index: 5,
            itemCount: 6,
            columnCount: 2
        )

        XCTAssertEqual(
            topRight.topTrailing,
            PublishedScanGridStyle.cornerRadius
        )
        XCTAssertEqual(topRight.bottomTrailing, 0)
        XCTAssertEqual(bottomRight.topTrailing, 0)
        XCTAssertEqual(
            bottomRight.bottomTrailing,
            PublishedScanGridStyle.cornerRadius
        )
    }
}
