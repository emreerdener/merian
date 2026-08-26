import Foundation

enum ExploreMapFilterPolicy {
    static func visiblePosts(
        from posts: [ExploreMapPost],
        selectedSpeciesCategories: Set<ExploreMapSpeciesCategory>,
        selectedMediaTypes: Set<ExploreMediaKind>,
        appliedSpeciesCategories: Set<ExploreMapSpeciesCategory>,
        appliedMediaTypes: Set<ExploreMediaKind>
    ) -> [ExploreMapPost] {
        if appliedSpeciesCategories == selectedSpeciesCategories,
           appliedMediaTypes == selectedMediaTypes {
            return posts
        }

        guard appliedSpeciesCategories.isEmpty, appliedMediaTypes.isEmpty else { return [] }
        return posts.filter { post in
            let matchesSpecies = selectedSpeciesCategories.isEmpty
                || selectedSpeciesCategories.contains(speciesCategory(for: post))
            let matchesMedia = selectedMediaTypes.isEmpty
                || !selectedMediaTypes.isDisjoint(with: mediaTypes(for: post))
            return matchesSpecies && matchesMedia
        }
    }

    static func visibleCategoryCounts(
        from categoryCounts: [ExploreMapCategoryCount],
        selectedCategories: Set<ExploreMapSpeciesCategory>
    ) -> [ExploreMapCategoryCount] {
        let availableCategories = Set(categoryCounts.map(\.category))
        let defaultCounts = ExploreMapSpeciesCategory.defaultFilters
            .filter { !availableCategories.contains($0) }
            .map { ExploreMapCategoryCount(category: $0, count: 0) }
        let selectedCounts = selectedCategories
            .subtracting(availableCategories)
            .subtracting(ExploreMapSpeciesCategory.defaultFilters)
            .map { ExploreMapCategoryCount(category: $0, count: 0) }

        return (categoryCounts + defaultCounts + selectedCounts)
            .filter {
                $0.count >= 1
                    || ExploreMapSpeciesCategory.defaultFilters.contains($0.category)
                    || selectedCategories.contains($0.category)
            }
            .sorted { lhs, rhs in
                if lhs.category.sortPriority != rhs.category.sortPriority {
                    return lhs.category.sortPriority < rhs.category.sortPriority
                }
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.category.title < rhs.category.title
            }
    }

    static func visibleMediaTypeCounts(
        from mediaTypeCounts: [ExploreMapMediaTypeCount]
    ) -> [ExploreMapMediaTypeCount] {
        let countsByType = Dictionary(
            uniqueKeysWithValues: mediaTypeCounts.map { ($0.mediaType, $0.count) }
        )
        return ExploreMediaKind.allCases.map { mediaType in
            ExploreMapMediaTypeCount(
                mediaType: mediaType,
                count: countsByType[mediaType] ?? 0
            )
        }
    }

    private static func speciesCategory(
        for post: ExploreMapPost
    ) -> ExploreMapSpeciesCategory {
        let kingdom = normalized(post.taxonomyKingdom)
        let className = normalized(post.taxonomyClass)

        if kingdom == "plantae" {
            return .plants
        }

        if kingdom == "fungi" {
            return .fungi
        }

        switch className {
        case "aves":
            return .birds
        case "mammalia":
            return .mammals
        case "reptilia", "squamata":
            return .reptiles
        case "amphibia":
            return .amphibians
        case "actinopterygii", "chondrichthyes", "sarcopterygii":
            return .fish
        case "insecta", "entognatha":
            return .insects
        case "arachnida":
            return .arachnids
        default:
            return .other
        }
    }

    private static func mediaTypes(for post: ExploreMapPost) -> Set<ExploreMediaKind> {
        Set(post.resolvedMediaItems.map(\.kind))
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
