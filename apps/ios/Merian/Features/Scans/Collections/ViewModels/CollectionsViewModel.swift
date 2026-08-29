import Combine
import Foundation
import Observation

@MainActor
@Observable
final class CollectionsViewModel {
    private(set) var membership = CollectionMembershipSnapshot.empty
    private(set) var smartCollections: [SmartCollectionSnapshot] = []
    private(set) var featuredCollection: SmartCollectionSnapshot?
    private(set) var nonBiologicalCount = 0

    @ObservationIgnored let events: AnyPublisher<AppEvent, Never>
    @ObservationIgnored let mutationService: CollectionMutationService
    @ObservationIgnored private let dependencies: CollectionsDependencies

    init(dependencies: CollectionsDependencies? = nil) {
        let resolvedDependencies = dependencies ?? .live
        self.dependencies = resolvedDependencies
        events = resolvedDependencies.events
        mutationService = CollectionMutationService(
            dependencies: resolvedDependencies
        )
    }

    func refresh(
        scans: [LocalScanRecord],
        collections: [ScanCollection],
        hiddenSmartCollectionIDs: Set<String>,
        referenceDate: Date
    ) {
        membership = CollectionMembershipSnapshot(scans: scans)
        nonBiologicalCount = scans.lazy.filter { !$0.isBiological }.count
        smartCollections = SmartCollectionSuggester.suggestions(
            from: scans,
            existingCollections: collections,
            hiddenCollectionIDs: hiddenSmartCollectionIDs,
            sharedPostIDProvider: dependencies.sharedPostID,
            referenceDate: referenceDate
        )
        featuredCollection = SmartCollectionSuggester.featuredSnapshot(
            from: scans,
            hiddenCollectionIDs: hiddenSmartCollectionIDs,
            referenceDate: referenceDate
        )
    }

    func presentation(
        searchQuery: String,
        isSearchFocused: Bool,
        collections: [ScanCollection],
        hasPrivateMapPoints: Bool
    ) -> CollectionsCatalogPresentation {
        CollectionsCatalogPresentation(
            searchQuery: searchQuery,
            isSearchFocused: isSearchFocused,
            collections: collections,
            membership: membership,
            smartCollections: smartCollections,
            featuredCollection: featuredCollection,
            hasPrivateMapPoints: hasPrivateMapPoints
        )
    }

    func refreshIdentity(
        scans: [LocalScanRecord],
        collections: [ScanCollection],
        hiddenSmartCollectionIDs: Set<String>
    ) -> CollectionsCatalogRefreshIdentity {
        CollectionsCatalogRefreshIdentity(
            scans: scans,
            collections: collections,
            hiddenSmartCollectionIDs: hiddenSmartCollectionIDs
        )
    }
}
