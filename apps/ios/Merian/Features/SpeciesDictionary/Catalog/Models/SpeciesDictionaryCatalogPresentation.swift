import Foundation

extension SpeciesDictionaryCatalogItem {
    var taxonomyData: TaxonomyData? {
        SpeciesDictionaryTaxonomyPresentation.data(from: taxonomy)
    }

    var dictionaryRoute: SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: scientificName,
            speciesId: id,
            entryPoint: .exploreDictionaryCatalog
        )
    }
}

extension SpeciesDictionaryFeaturedSpecies {
    var dictionaryRoute: SpeciesDictionaryRoute {
        SpeciesDictionaryRoute(
            scientificName: scientificName,
            speciesId: id,
            entryPoint: .exploreDictionaryCatalog
        )
    }
}

enum SpeciesDictionaryRegionFlag {
    static func emoji(for countryCode: String?) -> String? {
        guard let normalizedCode = countryCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
            Locale.Region.isoRegions.contains(Locale.Region(normalizedCode))
        else {
            return nil
        }

        let asciiScalars = Array(normalizedCode.unicodeScalars)
        guard asciiScalars.count == 2,
              asciiScalars.allSatisfy({ (65...90).contains($0.value) })
        else {
            return nil
        }

        let regionalIndicatorScalars = asciiScalars.compactMap { scalar in
            UnicodeScalar(127_397 + scalar.value)
        }
        guard regionalIndicatorScalars.count == 2 else { return nil }

        return regionalIndicatorScalars.map(String.init).joined()
    }
}

enum SpeciesDictionaryOverviewPresentation {
    static func category(
        _ id: SpeciesDictionaryOverviewCategoryID,
        in overview: SpeciesDictionaryOverview
    ) -> SpeciesDictionaryCategorySummary? {
        overview.categories.first { $0.id == id }
    }

    static func bottomCategories(
        in overview: SpeciesDictionaryOverview
    ) -> [SpeciesDictionaryCategorySummary] {
        [.recentlyAdded, .all].compactMap { category($0, in: overview) }
    }

    static func shouldShowRegionMapCard(
        for category: SpeciesDictionaryCategorySummary
    ) -> Bool {
        category.region?.trimmedNonEmptyValue != nil
    }

    static func visibleRegions(
        in overview: SpeciesDictionaryOverview
    ) -> [SpeciesDictionaryRegionSummary] {
        overview.regions.filter { region in
            region.count >= 1 && region.title.trimmedNonEmptyValue != nil
        }
    }

    static func route(
        for category: SpeciesDictionaryCategorySummary
    ) -> SpeciesDictionaryCategoryRoute {
        switch category.id {
        case .all:
            return .catalog(title: "All", category: .all, region: nil)
        case .yourRegion:
            guard let region = (category.regionCode ?? category.region)?
                .trimmedNonEmptyValue
            else {
                return .regions
            }
            return .catalog(
                title: "Your region",
                category: .region,
                region: region
            )
        case .taxonomy:
            // Compatibility for an older overview payload. The dedicated Tree
            // destination is retired, so this degrades to the complete catalog.
            return .catalog(title: "All", category: .all, region: nil)
        case .recentlyAdded:
            return .catalog(
                title: "Recently added",
                category: .recentlyAdded,
                region: nil
            )
        }
    }

    static func groupRowIndices(
        for groups: [SpeciesDictionaryGroupSummary]
    ) -> Range<Int> {
        0..<((groups.count + 1) / 2)
    }
}
