import SwiftData
import SwiftUI

struct CollectionsView: View {
    let searchQuery: String
    let isSearchFocused: Bool
    let collections: [ScanCollection]
    let hiddenSmartCollectionIDs: Set<String>
    let onHideSmartCollection: (SmartCollectionSnapshot) -> Void
    @Binding var showNewCollectionAlert: Bool
    @Binding var newlyCreatedCollection: ScanCollection?

    @Query(sort: \LocalScanRecord.timestamp, order: .reverse) private var allScans: [LocalScanRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var nonBioCount: Int = 0
    @State private var collectionSnapshot = CollectionMembershipSnapshot.empty
    @State private var smartCollections: [SmartCollectionSnapshot] = []
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
                let visibleSmartCollections = smartCollections.filter {
                    !isSearching || $0.title.localizedCaseInsensitiveContains(query)
                }
                let smartRowCollections = visibleSmartCollections.filter(\.isPinnedRow)
                let smartCardCollections = visibleSmartCollections.filter { !$0.isPinnedRow }
                let hasCardCollections = !userCollections.isEmpty || !smartCardCollections.isEmpty
                let hasRowCollections = (showFavorites && favoritesCollection != nil) || showNonBio || !smartRowCollections.isEmpty
                let totalFound = userCollections.count + visibleSmartCollections.count + (showFavorites ? 1 : 0) + (showNonBio ? 1 : 0)

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

                if isSearching && userCollections.isEmpty && visibleSmartCollections.isEmpty && !showFavorites && !showNonBio {
                    EmptyStateView(
                        iconName: "magnifyingglass",
                        title: "No results found",
                        message: "No collections match \"\(searchQuery)\"."
                    )
                } else if hasCardCollections {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(smartCardCollections) { smartCollection in
                            NavigationLink {
                                SmartCollectionDetailView(
                                    snapshot: smartCollection,
                                    onHideSmartCollection: onHideSmartCollection
                                )
                            } label: {
                                SmartCollectionCard(snapshot: smartCollection)
                            }
                            .buttonStyle(.plain)
                        }

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

                if hasRowCollections {
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

                        ForEach(smartRowCollections) { smartCollection in
                            DefaultCollectionLink(
                                title: smartCollection.title,
                                iconName: smartCollection.iconName,
                                count: smartCollection.count
                            ) {
                                SmartCollectionDetailView(
                                    snapshot: smartCollection,
                                    onHideSmartCollection: onHideSmartCollection
                                )
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
                    .padding(.top, hasCardCollections ? 0 : 16)
                }

                if !isSearching && userCollections.isEmpty && visibleSmartCollections.isEmpty {
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
        .task(id: scanSmartCollectionSignature) {
            refreshCollectionSnapshot()
            refreshNonBioCount()
        }
        .task(id: collectionsSignature) {
            refreshCollectionSnapshot()
        }
        .task(id: hiddenSmartCollectionSignature) {
            refreshCollectionSnapshot()
        }
        .onReceive(ScanLibraryEvents.libraryDidUpdatePublisher()) { _ in
            refreshCollectionSnapshot()
            refreshNonBioCount()
        }
    }

    private var collectionsSignature: String {
        collections
            .filter { !$0.isDeleted }
            .map { "\($0.id):\($0.name)" }
            .sorted()
            .joined(separator: "|")
    }

    private var hiddenSmartCollectionSignature: String {
        hiddenSmartCollectionIDs.sorted().joined(separator: "|")
    }

    private var scanSmartCollectionSignature: String {
        allScans
            .map { scan in
                [
                    scan.id,
                    String(scan.timestamp.timeIntervalSince1970),
                    scan.isBiological ? "1" : "0",
                    scan.locationName ?? "",
                    scan.taxonomyKingdom ?? "",
                    scan.taxonomyClass ?? "",
                    scan.isInvasive ? "1" : "0",
                    scan.hazardType,
                    String(scan.confidenceScore ?? -1),
                    String(scan.candidatesData?.count ?? 0),
                    scan.userReviewState.rawValue
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    private func refreshCollectionSnapshot() {
        collectionSnapshot = CollectionMembershipSnapshot(scans: allScans)
        smartCollections = SmartCollectionSuggester.suggestions(
            from: allScans,
            existingCollections: collections,
            hiddenCollectionIDs: hiddenSmartCollectionIDs
        )
    }

    private func refreshNonBioCount() {
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.isBiological == false })
        if let count = try? modelContext.fetchCount(descriptor) {
            nonBioCount = count
        }
    }
}

private extension SmartCollectionSnapshot {
    var isPinnedRow: Bool {
        definition.rule == .needsReview
    }
}
