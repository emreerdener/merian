import SwiftData
import SwiftUI

struct CollectionsView: View {
    let searchQuery: String
    let isSearchFocused: Bool
    let collections: [ScanCollection]
    let hiddenSmartCollectionIDs: Set<String>
    let onHideSmartCollection: (SmartCollectionSnapshot) -> Void
    @Binding var newlyCreatedCollection: ScanCollection?
    let scans: [LocalScanRecord]

    @Environment(\.modelContext) private var modelContext
    @Environment(PrivateScanMapStore.self) private var privateScanMapStore

    @State private var viewModel: CollectionsViewModel
    @State private var collectionToEdit: ScanCollection?
    @State private var showRenameAlert = false
    @State private var showDeleteConfirmation = false
    @State private var newCollectionName = ""
    @State private var featuredReferenceDate = Date()

    private let dependencies: CollectionsDependencies?
    private let featuredRefreshTimer = Timer.publish(
        every: 3_600,
        on: .main,
        in: .common
    ).autoconnect()

    init(
        searchQuery: String,
        isSearchFocused: Bool,
        collections: [ScanCollection],
        hiddenSmartCollectionIDs: Set<String>,
        onHideSmartCollection: @escaping (SmartCollectionSnapshot) -> Void,
        newlyCreatedCollection: Binding<ScanCollection?>,
        scans: [LocalScanRecord] = [],
        dependencies: CollectionsDependencies? = nil
    ) {
        self.searchQuery = searchQuery
        self.isSearchFocused = isSearchFocused
        self.collections = collections
        self.hiddenSmartCollectionIDs = hiddenSmartCollectionIDs
        self.onHideSmartCollection = onHideSmartCollection
        _newlyCreatedCollection = newlyCreatedCollection
        self.scans = scans
        self.dependencies = dependencies
        _viewModel = State(
            initialValue: CollectionsViewModel(dependencies: dependencies)
        )
    }

    var body: some View {
        let presentation = viewModel.presentation(
            searchQuery: searchQuery,
            isSearchFocused: isSearchFocused,
            collections: collections,
            hasPrivateMapPoints: !privateMapSnapshot.points.isEmpty
        )

        CollectionsCatalogContent(
            presentation: presentation,
            scans: scans,
            privateMapSnapshot: privateMapSnapshot,
            nonBiologicalCount: viewModel.nonBiologicalCount,
            searchQuery: searchQuery,
            onHideSmartCollection: onHideSmartCollection,
            dependencies: dependencies,
            collectionToEdit: $collectionToEdit,
            showRenameAlert: $showRenameAlert,
            showDeleteConfirmation: $showDeleteConfirmation,
            newCollectionName: $newCollectionName
        )
        .collectionRenameAlert(
            isPresented: $showRenameAlert,
            newCollectionName: $newCollectionName,
            collection: collectionToEdit,
            modelContext: modelContext,
            mutationService: viewModel.mutationService
        )
        .collectionDeleteAlert(
            isPresented: $showDeleteConfirmation,
            collection: collectionToEdit,
            modelContext: modelContext,
            mutationService: viewModel.mutationService
        )
        .navigationDestination(item: $newlyCreatedCollection) { collection in
            CollectionDetailView(
                collection: collection,
                scans: scans,
                dependencies: dependencies
            )
        }
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.collections)
        .task(id: refreshIdentity) {
            refresh()
        }
        .task {
            await privateScanMapStore.refresh()
        }
        .onReceive(viewModel.events) { event in
            switch event {
            case .scanLibraryChanged,
                 .exploreShareStateChanged:
                refresh()
            default:
                break
            }
        }
        .onReceive(featuredRefreshTimer) { date in
            featuredReferenceDate = date
            refresh()
        }
    }

    private var privateMapSnapshot: PrivateScanMapPreviewSnapshot {
        privateScanMapStore.snapshot.previewSnapshot
    }

    private var refreshIdentity: CollectionsCatalogRefreshIdentity {
        viewModel.refreshIdentity(
            scans: scans,
            collections: collections,
            hiddenSmartCollectionIDs: hiddenSmartCollectionIDs
        )
    }

    private func refresh() {
        viewModel.refresh(
            scans: scans,
            collections: collections,
            hiddenSmartCollectionIDs: hiddenSmartCollectionIDs,
            referenceDate: featuredReferenceDate
        )
    }
}
