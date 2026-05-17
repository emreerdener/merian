import SwiftData
import SwiftUI

struct CollectionsView: View {
    let searchQuery: String
    let isSearchFocused: Bool
    let collections: [ScanCollection]
    @Binding var showNewCollectionAlert: Bool
    @Binding var newlyCreatedCollection: ScanCollection?

    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allScans: [LocalScanRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var nonBioCount: Int = 0
    @State private var collectionSnapshot = CollectionMembershipSnapshot.empty
    @State private var collectionToEdit: ScanCollection?
    @State private var showRenameAlert = false
    @State private var showDeleteConfirmation = false
    @State private var newCollectionName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                let isSearching = !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
                let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()

                let userCollections = collections.filter {
                    !$0.isDeleted && $0.name != "Favorites" && (!isSearching || $0.name.localizedCaseInsensitiveContains(query))
                }
                let favoritesCollection = collections.first { $0.name == "Favorites" && !$0.isDeleted }
                let favoritesSummary = favoritesCollection.map { collectionSnapshot.summary(for: $0.id) } ?? .empty

                let showFavorites = !isSearching || "favorites".contains(query)
                let showNonBio = !isSearching || "non-biological".contains(query) || "non biological".contains(query)
                let totalFound = userCollections.count + (showFavorites ? 1 : 0) + (showNonBio ? 1 : 0)

                if isSearching || isSearchFocused {
                    HStack {
                        Text(isSearching ? "Search results" : "Search collections")
                            .font(.title3)
                            .fontWeight(.bold)

                        Spacer()

                        Text("\(totalFound) found")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 0)
                }

                VStack(spacing: 16) {
                    if showFavorites, let favoritesCollection {
                        DefaultCollectionLink(
                            title: "Favorites",
                            iconName: "heart",
                            count: favoritesSummary.count
                        ) {
                            CollectionDetailView(collection: favoritesCollection)
                        }
                    }

                    if showNonBio {
                        DefaultCollectionLink(
                            title: "Non-biological",
                            iconName: "cube",
                            count: nonBioCount
                        ) {
                            NonBiologicalScansView()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                if isSearching && userCollections.isEmpty && !showFavorites && !showNonBio {
                    EmptyStateView(
                        iconName: "magnifyingglass",
                        title: "No results found",
                        message: "No collections match \"\(searchQuery)\"."
                    )
                } else if !isSearching && userCollections.isEmpty {
                    EmptyStateView(
                        imageName: "fireflies",
                        title: "Collections",
                        message: "Create your first collection to start organizing your scans."
                    ) {
                        Button {
                            showNewCollectionAlert = true
                        } label: {
                            Text("New collection")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                } else {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(userCollections) { collection in
                            NavigationLink {
                                CollectionDetailView(collection: collection)
                            } label: {
                                CollectionCard(
                                    collection: collection,
                                    summary: collectionSnapshot.summary(for: collection.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    collectionToEdit = collection
                                    newCollectionName = collection.name
                                    showRenameAlert = true
                                } label: {
                                    Label("Rename collection", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    collectionToEdit = collection
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete collection", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 16)
        }
        .collectionRenameAlert(
            isPresented: $showRenameAlert,
            newCollectionName: $newCollectionName,
            collection: collectionToEdit,
            modelContext: modelContext
        )
        .collectionDeleteAlert(
            isPresented: $showDeleteConfirmation,
            collection: collectionToEdit,
            modelContext: modelContext
        )
        .navigationDestination(item: $newlyCreatedCollection) { collection in
            CollectionDetailView(collection: collection)
        }
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.collections)
        .task {
            refreshCollectionSnapshot()
            refreshNonBioCount()
        }
        .task(id: allScans.count) {
            refreshCollectionSnapshot()
            refreshNonBioCount()
        }
        .onReceive(ScanLibraryEvents.libraryDidUpdatePublisher()) { _ in
            refreshCollectionSnapshot()
            refreshNonBioCount()
        }
    }

    private func refreshCollectionSnapshot() {
        collectionSnapshot = CollectionMembershipSnapshot(scans: allScans)
    }

    private func refreshNonBioCount() {
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.isBiological == false })
        if let count = try? modelContext.fetchCount(descriptor) {
            nonBioCount = count
        }
    }
}
