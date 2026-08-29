import XCTest

@testable import Merian

@MainActor
final class CollectionsViewModelTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testCatalogRefreshBuildsMembershipSmartAndFeaturedState() {
        let favorites = ScanCollection(
            id: "favorites",
            name: "Favorites"
        )
        let wetlands = ScanCollection(
            id: "wetlands",
            name: "Wetlands",
            createdAt: referenceDate
        )
        let shared = makeRecord(
            id: "shared",
            timestamp: referenceDate
        )
        let second = makeRecord(
            id: "second",
            timestamp: referenceDate.addingTimeInterval(-1)
        )
        let third = makeRecord(
            id: "third",
            timestamp: referenceDate.addingTimeInterval(-2)
        )
        let nonBiological = makeRecord(
            id: "non-biological",
            timestamp: referenceDate.addingTimeInterval(-3),
            isBiological: false
        )
        shared.collections = [wetlands, favorites]

        let viewModel = CollectionsViewModel(
            dependencies: CollectionsDependencies(
                sharedPostID: { scanID in
                    scanID == shared.id ? "post-shared" : nil
                }
            )
        )
        viewModel.refresh(
            scans: [shared, second, third, nonBiological],
            collections: [favorites, wetlands],
            hiddenSmartCollectionIDs: [],
            referenceDate: referenceDate
        )

        XCTAssertEqual(viewModel.nonBiologicalCount, 1)
        XCTAssertEqual(viewModel.membership.summary(for: wetlands.id).count, 1)
        XCTAssertEqual(
            viewModel.membership.summary(for: favorites.id).count,
            1
        )
        XCTAssertEqual(viewModel.featuredCollection?.count, 3)
        XCTAssertTrue(
            viewModel.smartCollections.map(\.title).contains("Recent finds")
        )
        XCTAssertTrue(
            viewModel.smartCollections.map(\.title).contains("Explore posts")
        )

        let presentation = viewModel.presentation(
            searchQuery: "",
            isSearchFocused: false,
            collections: [favorites, wetlands],
            hasPrivateMapPoints: true
        )
        XCTAssertNil(presentation.headerTitle)
        XCTAssertTrue(presentation.showPrivateMap)
        XCTAssertTrue(presentation.showFavoritesRow)
        XCTAssertTrue(presentation.showNonBiologicalRow)
        XCTAssertEqual(presentation.userCollections.map(\.id), [wetlands.id])
        XCTAssertFalse(presentation.showsPrimaryEmptyState)
    }

    func testCatalogSearchDerivesIndependentHeaderAndEmptyStates() {
        let favorites = ScanCollection(
            id: "favorites",
            name: "Favorites"
        )
        let viewModel = CollectionsViewModel(
            dependencies: CollectionsDependencies()
        )
        viewModel.refresh(
            scans: [],
            collections: [favorites],
            hiddenSmartCollectionIDs: [],
            referenceDate: referenceDate
        )

        let focused = viewModel.presentation(
            searchQuery: "",
            isSearchFocused: true,
            collections: [favorites],
            hasPrivateMapPoints: true
        )
        XCTAssertEqual(focused.headerTitle, "Search collections")

        let favoritesResult = viewModel.presentation(
            searchQuery: "favorites",
            isSearchFocused: true,
            collections: [favorites],
            hasPrivateMapPoints: true
        )
        XCTAssertEqual(favoritesResult.headerTitle, "Search results")
        XCTAssertTrue(favoritesResult.showFavoritesRow)
        XCTAssertFalse(favoritesResult.showPrivateMap)
        XCTAssertFalse(favoritesResult.showNonBiologicalRow)
        XCTAssertEqual(favoritesResult.totalFound, 1)
        XCTAssertFalse(favoritesResult.showsFilteredEmptyState)

        let privateMapResult = viewModel.presentation(
            searchQuery: "private",
            isSearchFocused: true,
            collections: [favorites],
            hasPrivateMapPoints: true
        )
        XCTAssertTrue(privateMapResult.showPrivateMap)
        XCTAssertEqual(privateMapResult.totalFound, 1)

        let emptyResult = viewModel.presentation(
            searchQuery: "does not exist",
            isSearchFocused: true,
            collections: [favorites],
            hasPrivateMapPoints: true
        )
        XCTAssertEqual(emptyResult.totalFound, 0)
        XCTAssertTrue(emptyResult.showsFilteredEmptyState)
    }

    func testDetailSelectionAndRefreshIdentityShareMembershipProjection() {
        let collection = ScanCollection(
            id: "collection",
            name: "Wetlands"
        )
        let newest = makeRecord(
            id: "newest",
            timestamp: referenceDate
        )
        let oldest = makeRecord(
            id: "oldest",
            timestamp: referenceDate.addingTimeInterval(-10)
        )
        newest.collections = [collection]
        let scans = [newest, oldest]

        let detail = CollectionDetailViewModel(
            dependencies: CollectionsDependencies()
        )
        detail.refresh(scans: scans, collectionID: collection.id)
        XCTAssertEqual(detail.memberScans.map(\.id), [newest.id])
        let detailIdentityBefore = detail.refreshIdentity(
            scans: scans,
            collectionID: collection.id
        )
        XCTAssertEqual(detailIdentityBefore, [collection.id, newest.id])

        let selection = SelectMultipleScansViewModel(
            dependencies: CollectionsDependencies()
        )
        selection.refresh(scans: scans)
        let selectionIdentityBefore = selection.refreshIdentity(
            scans: scans,
            collectionID: collection.id
        )
        XCTAssertEqual(selectionIdentityBefore, detailIdentityBefore)
        XCTAssertTrue(
            selection.contains(
                scanID: newest.id,
                collectionID: collection.id
            )
        )
        XCTAssertFalse(
            selection.contains(
                scanID: oldest.id,
                collectionID: collection.id
            )
        )

        let catalog = CollectionsViewModel(
            dependencies: CollectionsDependencies()
        )
        let before = catalog.refreshIdentity(
            scans: scans,
            collections: [collection],
            hiddenSmartCollectionIDs: []
        )
        oldest.collections = [collection]
        let after = catalog.refreshIdentity(
            scans: scans,
            collections: [collection],
            hiddenSmartCollectionIDs: []
        )
        let detailIdentityAfter = detail.refreshIdentity(
            scans: scans,
            collectionID: collection.id
        )
        let selectionIdentityAfter = selection.refreshIdentity(
            scans: scans,
            collectionID: collection.id
        )
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(
            detailIdentityAfter,
            [collection.id, newest.id, oldest.id]
        )
        XCTAssertEqual(selectionIdentityAfter, detailIdentityAfter)
    }

    func testCatalogAndSmartDetailIdentityTrackInPlaceReviewDataChanges() {
        let scan = makeRecord(
            id: "review",
            timestamp: referenceDate
        )
        scan.candidatesData = Data([0, 1, 2])
        let scans = [scan]
        let catalog = CollectionsViewModel(
            dependencies: CollectionsDependencies()
        )
        let snapshot = SmartCollectionSnapshot(
            definition: SmartCollectionDefinition(
                id: "needs review",
                title: "Needs review",
                iconName: "checkmark.seal",
                rule: .needsReview,
                rank: 0
            ),
            scans: scans,
            coverScan: scan
        )
        let detail = SmartCollectionDetailViewModel(
            snapshot: snapshot,
            dependencies: CollectionsDependencies()
        )

        let catalogBefore = catalog.refreshIdentity(
            scans: scans,
            collections: [],
            hiddenSmartCollectionIDs: []
        )
        let detailBefore = detail.refreshIdentity(scans: scans)

        scan.candidatesData = Data([2, 1, 0])

        let catalogAfter = catalog.refreshIdentity(
            scans: scans,
            collections: [],
            hiddenSmartCollectionIDs: []
        )
        let detailAfter = detail.refreshIdentity(scans: scans)
        XCTAssertNotEqual(catalogBefore, catalogAfter)
        XCTAssertNotEqual(detailBefore, detailAfter)
    }

    func testSmartDetailUsesInjectedShareStateAndHideFeedback() {
        let shared = makeRecord(
            id: "shared",
            timestamp: referenceDate
        )
        let privateRecord = makeRecord(
            id: "private",
            timestamp: referenceDate.addingTimeInterval(-1)
        )
        let snapshot = SmartCollectionSnapshot(
            definition: SmartCollectionDefinition(
                id: "explore posts",
                title: "Explore posts",
                iconName: "globe.americas",
                rule: .shared,
                rank: 2
            ),
            scans: [shared, privateRecord],
            coverScan: shared
        )
        let feedback = CollectionEffectsRecorder()
        let viewModel = SmartCollectionDetailViewModel(
            snapshot: snapshot,
            dependencies: CollectionsDependencies(
                sharedPostID: { scanID in
                    scanID == shared.id ? "post-shared" : nil
                },
                triggerLightFeedback: {
                    feedback.values.append("light")
                }
            )
        )

        viewModel.refresh(
            snapshot: snapshot,
            scans: [shared, privateRecord],
            referenceDate: referenceDate
        )
        XCTAssertEqual(viewModel.liveSnapshot.scans.map(\.id), [shared.id])

        var hiddenID: String?
        XCTAssertTrue(
            viewModel.hide(snapshot: snapshot) {
                hiddenID = $0.id
            }
        )
        XCTAssertEqual(hiddenID, snapshot.id)
        XCTAssertEqual(feedback.values, ["light"])
    }

    private func makeRecord(
        id: String,
        timestamp: Date,
        isBiological: Bool = true
    ) -> LocalScanRecord {
        LocalScanRecord(
            id: id,
            speciesId: "species-\(id)",
            scientificName: "Species \(id)",
            commonName: "Species \(id)",
            timestamp: timestamp,
            hazardType: "none",
            isBiological: isBiological,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild",
            confidenceScore: 0.995,
            inferenceTier: "pro"
        )
    }
}
