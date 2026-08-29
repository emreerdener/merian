import Foundation

struct CollectionsCatalogPresentation {
    let headerTitle: String?
    let membership: CollectionMembershipSnapshot
    let userCollections: [ScanCollection]
    let favoritesCollection: ScanCollection?
    let favoritesSummary: CollectionSummaryItem
    let featuredCollection: SmartCollectionSnapshot?
    let smartRowCollections: [SmartCollectionSnapshot]
    let smartCardCollections: [SmartCollectionSnapshot]
    let showFavoritesRow: Bool
    let showNonBiologicalRow: Bool
    let showPrivateMap: Bool
    let showsFilteredEmptyState: Bool
    let showsPrimaryEmptyState: Bool
    let hasTopCollectionCards: Bool
    let hasRowCollections: Bool
    let totalFound: Int

    init(
        searchQuery: String,
        isSearchFocused: Bool,
        collections: [ScanCollection],
        membership: CollectionMembershipSnapshot,
        smartCollections: [SmartCollectionSnapshot],
        featuredCollection: SmartCollectionSnapshot?,
        hasPrivateMapPoints: Bool
    ) {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespaces)
        let query = trimmedQuery.lowercased()
        let isSearching = !trimmedQuery.isEmpty
        let visibleUserCollections = collections
            .filter {
                !$0.isPendingDeletion &&
                    $0.name != "Favorites" &&
                    (!isSearching ||
                        $0.name.localizedCaseInsensitiveContains(query))
            }
            .sorted { $0.createdAt > $1.createdAt }
        let favorites = collections.first {
            $0.name == "Favorites" && !$0.isPendingDeletion
        }
        let showFavorites = !isSearching || "favorites".contains(query)
        let showFavoritesRow = showFavorites && favorites != nil
        let showNonBiologicalRow = !isSearching ||
            "non-biological".contains(query) ||
            "non biological".contains(query)
        let showPrivateMap = hasPrivateMapPoints &&
            (!isSearching || PrivateScanMapCollectionSearch.matches(query))
        let visibleFeatured = featuredCollection.flatMap { snapshot in
            !isSearching || snapshot.title.localizedCaseInsensitiveContains(query)
                ? snapshot
                : nil
        }
        let visibleSmartCollections = smartCollections.filter {
            !isSearching || $0.title.localizedCaseInsensitiveContains(query)
        }
        let smartRows = visibleSmartCollections.filter(\.isPinnedRow)
        let smartCards = visibleSmartCollections.filter { !$0.isPinnedRow }
        let hasCardCollections = !visibleUserCollections.isEmpty ||
            !smartCards.isEmpty
        let hasTopCollectionCards = showPrivateMap ||
            visibleFeatured != nil ||
            hasCardCollections
        let hasRowCollections = showFavoritesRow ||
            showNonBiologicalRow ||
            !smartRows.isEmpty
        let totalFound = visibleUserCollections.count +
            visibleSmartCollections.count +
            (showPrivateMap ? 1 : 0) +
            (visibleFeatured == nil ? 0 : 1) +
            (showFavoritesRow ? 1 : 0) +
            (showNonBiologicalRow ? 1 : 0)

        self.membership = membership
        headerTitle = isSearching
            ? "Search results"
            : (isSearchFocused ? "Search collections" : nil)
        userCollections = visibleUserCollections
        favoritesCollection = favorites
        favoritesSummary = favorites.map {
            membership.summary(for: $0.id)
        } ?? .empty
        self.featuredCollection = visibleFeatured
        smartRowCollections = smartRows
        smartCardCollections = smartCards
        self.showFavoritesRow = showFavoritesRow
        self.showNonBiologicalRow = showNonBiologicalRow
        self.showPrivateMap = showPrivateMap
        showsFilteredEmptyState = isSearching &&
            !showPrivateMap &&
            visibleFeatured == nil &&
            visibleUserCollections.isEmpty &&
            visibleSmartCollections.isEmpty &&
            !showFavoritesRow &&
            !showNonBiologicalRow
        showsPrimaryEmptyState = !isSearching &&
            !hasPrivateMapPoints &&
            visibleFeatured == nil &&
            visibleUserCollections.isEmpty &&
            visibleSmartCollections.isEmpty
        self.hasTopCollectionCards = hasTopCollectionCards
        self.hasRowCollections = hasRowCollections
        self.totalFound = totalFound
    }
}
