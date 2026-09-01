import Foundation
import Testing

@testable import Merian

@Suite("Species Dictionary Catalog Presentation")
struct SpeciesDictionaryCatalogPresentationTests {
    @Test func regionFlagNormalizesValidCountryCodes() {
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "US") == "🇺🇸")
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "ca") == "🇨🇦")
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "  mx\n") == "🇲🇽")
    }

    @Test func regionFlagRejectsMissingOrInvalidCountryCodes() {
        #expect(SpeciesDictionaryRegionFlag.emoji(for: nil) == nil)
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "") == nil)
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "USA") == nil)
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "ZZ") == nil)
        #expect(SpeciesDictionaryRegionFlag.emoji(for: "1A") == nil)
    }

    @Test func overviewFiltersEmptyAndZeroCountRegions() throws {
        let overview = try Self.overview()

        let visibleRegions = SpeciesDictionaryOverviewPresentation
            .visibleRegions(in: overview)

        #expect(visibleRegions.map(\.id) == ["country:US"])
    }

    @Test func bottomCategoriesUseStableRecentlyAddedThenAllOrder() throws {
        let overview = try Self.overview()

        let categories = SpeciesDictionaryOverviewPresentation
            .bottomCategories(in: overview)

        #expect(categories.map(\.id) == [.recentlyAdded, .all])
    }

    @Test func regionRoutePrefersCodeAndFallsBackToRegionBrowser() throws {
        let overview = try Self.overview()
        let local = try #require(
            SpeciesDictionaryOverviewPresentation.category(
                .yourRegion,
                in: overview
            )
        )

        #expect(
            SpeciesDictionaryOverviewPresentation.route(for: local)
                == .catalog(
                    title: "Your region",
                    category: .region,
                    region: "US"
                )
        )

        let missingRegion = SpeciesDictionaryCategorySummary(
            id: .yourRegion,
            title: "Your Region",
            subtitle: nil,
            count: 0,
            referenceImageUrl: nil,
            region: "   ",
            regionCode: nil
        )
        #expect(
            SpeciesDictionaryOverviewPresentation.route(for: missingRegion)
                == .regions
        )
    }

    @Test func categoryRoutesRetainCanonicalTitlesAndSemantics() throws {
        let overview = try Self.overview()
        let all = try #require(
            SpeciesDictionaryOverviewPresentation.category(.all, in: overview)
        )
        let recent = try #require(
            SpeciesDictionaryOverviewPresentation.category(
                .recentlyAdded,
                in: overview
            )
        )

        #expect(
            SpeciesDictionaryOverviewPresentation.route(for: all)
                == .catalog(title: "All", category: .all, region: nil)
        )
        #expect(
            SpeciesDictionaryOverviewPresentation.route(for: recent)
                == .catalog(
                    title: "Recently added",
                    category: .recentlyAdded,
                    region: nil
                )
        )
    }

    @Test func groupRowsReserveSpaceForAnOddFinalCard() throws {
        let groups = try Self.overview().groups

        #expect(
            Array(
                SpeciesDictionaryOverviewPresentation.groupRowIndices(
                    for: groups
                )
            ) == [0, 1]
        )
    }

    private static func overview() throws -> SpeciesDictionaryOverview {
        let data = Data(
            """
            {
                "schema_version": 1,
                "data": {
                    "categories": [
                        {
                            "id": "all",
                            "title": "All",
                            "subtitle": null,
                            "count": 42,
                            "reference_image_url": null,
                            "region": null,
                            "region_code": null
                        },
                        {
                            "id": "your_region",
                            "title": "Your Region",
                            "subtitle": null,
                            "count": 8,
                            "reference_image_url": null,
                            "region": "United States",
                            "region_code": "US"
                        },
                        {
                            "id": "recently_added",
                            "title": "Recently added",
                            "subtitle": null,
                            "count": 4,
                            "reference_image_url": null,
                            "region": null,
                            "region_code": null
                        }
                    ],
                    "groups": [
                        {
                            "id": "birds",
                            "title": "Birds",
                            "count": 12,
                            "reference_image_url": null
                        },
                        {
                            "id": "plants",
                            "title": "Plants",
                            "count": 14,
                            "reference_image_url": null
                        },
                        {
                            "id": "fungi",
                            "title": "Fungi",
                            "count": 8,
                            "reference_image_url": null
                        }
                    ],
                    "regions": [
                        {
                            "id": "country:US",
                            "title": "United States",
                            "count": 8,
                            "reference_image_url": null,
                            "code": "US"
                        },
                        {
                            "id": "country:CA",
                            "title": "Canada",
                            "count": 0,
                            "reference_image_url": null,
                            "code": "CA"
                        },
                        {
                            "id": "country:blank",
                            "title": "   ",
                            "count": 3,
                            "reference_image_url": null,
                            "code": null
                        }
                    ]
                }
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(
            SpeciesDictionaryOverviewResponse.self,
            from: data
        ).data
    }
}
