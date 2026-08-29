import SwiftUI

struct CollectionsCatalogContent: View {
    let presentation: CollectionsCatalogPresentation
    let scans: [LocalScanRecord]
    let privateMapSnapshot: PrivateScanMapPreviewSnapshot
    let nonBiologicalCount: Int
    let searchQuery: String
    let onHideSmartCollection: (SmartCollectionSnapshot) -> Void
    let dependencies: CollectionsDependencies?

    @Binding var collectionToEdit: ScanCollection?
    @Binding var showRenameAlert: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var newCollectionName: String

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let headerTitle = presentation.headerTitle {
                    catalogHeader(title: headerTitle)
                }

                if presentation.showsFilteredEmptyState {
                    EmptyStateView(
                        iconName: "magnifyingglass",
                        title: "No collections found",
                        message: "No collections match \"\(searchQuery)\"."
                    )
                } else {
                    topCards
                    collectionGrid
                }

                if presentation.showsPrimaryEmptyState {
                    EmptyStateView(
                        imageName: "fireflies",
                        title: "Collections",
                        message: "Create your first collection to start organizing your scans."
                    )
                }

                if presentation.hasRowCollections {
                    defaultCollectionGrid
                }
            }
            .padding(.top, presentation.headerTitle == nil ? 16 : 0)
            .padding(.bottom, 16)
        }
    }

    private func catalogHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.title3)
                .fontWeight(.bold)

            Spacer()

            Text("\(presentation.totalFound) found")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var topCards: some View {
        if presentation.showPrivateMap {
            NavigationLink(value: ScansNavigationRoute.privateScanMap) {
                PrivateScanMapCollectionCard(snapshot: privateMapSnapshot)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }

        if let featuredCollection = presentation.featuredCollection {
            NavigationLink {
                SmartCollectionDetailView(
                    snapshot: featuredCollection,
                    onHideSmartCollection: onHideSmartCollection,
                    scans: scans,
                    dependencies: dependencies
                )
            } label: {
                FeaturedCollectionCard(snapshot: featuredCollection)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var collectionGrid: some View {
        if !presentation.userCollections.isEmpty ||
            !presentation.smartCardCollections.isEmpty {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 16
            ) {
                ForEach(presentation.smartCardCollections) { collection in
                    NavigationLink {
                        SmartCollectionDetailView(
                            snapshot: collection,
                            onHideSmartCollection: onHideSmartCollection,
                            scans: scans,
                            dependencies: dependencies
                        )
                    } label: {
                        SmartCollectionCard(snapshot: collection)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(presentation.userCollections) { collection in
                    NavigationLink {
                        CollectionDetailView(
                            collection: collection,
                            scans: scans,
                            dependencies: dependencies
                        )
                    } label: {
                        CollectionCard(
                            collection: collection,
                            summary: presentation.membership.summary(
                                for: collection.id
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            collectionToEdit = collection
                            newCollectionName = collection.name
                            showRenameAlert = true
                        } label: {
                            Label(
                                "Rename collection",
                                systemImage: "pencil"
                            )
                        }

                        Button(role: .destructive) {
                            collectionToEdit = collection
                            showDeleteConfirmation = true
                        } label: {
                            Label(
                                "Delete collection",
                                systemImage: "trash"
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var defaultCollectionGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 16),
                count: 3
            ),
            spacing: 16
        ) {
            if presentation.showFavoritesRow,
               let favorites = presentation.favoritesCollection {
                DefaultCollectionCard(
                    title: "Favorites",
                    assetName: "heart",
                    count: presentation.favoritesSummary.count
                ) {
                    CollectionDetailView(
                        collection: favorites,
                        scans: scans,
                        dependencies: dependencies
                    )
                }
            }

            ForEach(presentation.smartRowCollections) { collection in
                DefaultCollectionCard(
                    title: collection.title,
                    assetName: collection.defaultCollectionAssetName,
                    count: collection.count
                ) {
                    SmartCollectionDetailView(
                        snapshot: collection,
                        onHideSmartCollection: onHideSmartCollection,
                        scans: scans,
                        dependencies: dependencies
                    )
                }
            }

            if presentation.showNonBiologicalRow {
                DefaultCollectionCard(
                    title: "Non-biological",
                    assetName: "cube",
                    count: nonBiologicalCount
                ) {
                    NonBiologicalScansView()
                }
                .accessibilityIdentifier("NonBiologicalCollectionCard")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, presentation.hasTopCollectionCards ? 0 : 16)
    }

}
