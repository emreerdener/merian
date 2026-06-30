import SwiftData
import SwiftUI

struct CollectionsView: View {
    let searchQuery: String
    let isSearchFocused: Bool
    let collections: [ScanCollection]
    let collectionSortOption: CollectionSortOption
    @Binding var filters: CollectionLibraryFilters
    let hiddenSmartCollectionIDs: Set<String>
    let onHideSmartCollection: (SmartCollectionSnapshot) -> Void
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
    @State private var featuredReferenceDate = Date()

    private let featuredRefreshTimer = Timer.publish(every: 3_600, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                let isSearching = !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
                let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
                let showUserCreatedCollections = shouldShowCollectionType(.userCreated)
                let showSmartSuggestionCollections = shouldShowCollectionType(.smartSuggestions)
                let showBuiltInCollections = shouldShowCollectionType(.builtIn)

                let userCollections = showUserCreatedCollections
                    ? sortedUserCollections(collections.filter {
                        !$0.isDeleted &&
                            $0.name != "Favorites" &&
                            (!isSearching || $0.name.localizedCaseInsensitiveContains(query))
                    })
                    : []
                let favoritesCollection = collections.first { $0.name == "Favorites" && !$0.isDeleted }
                let favoritesSummary = favoritesCollection.map { collectionSnapshot.summary(for: $0.id) } ?? .empty

                let showFavorites = showBuiltInCollections && (!isSearching || "favorites".contains(query))
                let showFavoritesRow = showFavorites && favoritesCollection != nil
                let showNonBio = showBuiltInCollections &&
                    (!isSearching || "non-biological".contains(query) || "non biological".contains(query))
                let featuredCollection = showSmartSuggestionCollections
                    ? SmartCollectionSuggester.featuredSnapshot(
                        from: allScans,
                        hiddenCollectionIDs: hiddenSmartCollectionIDs,
                        referenceDate: featuredReferenceDate
                    )
                    : nil
                let visibleFeaturedCollection = featuredCollection.flatMap { snapshot in
                    !isSearching || snapshot.title.localizedCaseInsensitiveContains(query) ? snapshot : nil
                }
                let visibleSmartCollections = showSmartSuggestionCollections
                    ? smartCollections.filter {
                        !isSearching || $0.title.localizedCaseInsensitiveContains(query)
                    }
                    : []
                let smartRowCollections = visibleSmartCollections.filter(\.isPinnedRow)
                let smartCardCollections = visibleSmartCollections.filter { !$0.isPinnedRow }
                let hasCardCollections = !userCollections.isEmpty || !smartCardCollections.isEmpty
                let hasTopCollectionCards = visibleFeaturedCollection != nil || hasCardCollections
                let hasRowCollections = showFavoritesRow || showNonBio || !smartRowCollections.isEmpty
                let totalFound = userCollections.count
                    + visibleSmartCollections.count
                    + (visibleFeaturedCollection == nil ? 0 : 1)
                    + (showFavoritesRow ? 1 : 0)
                    + (showNonBio ? 1 : 0)

                if shouldShowHeader(isSearching: isSearching) {
                    HStack {
                        Text(headerTitle(isSearching: isSearching))
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

                if shouldShowEmptyFilteredState(
                    isSearching: isSearching,
                    visibleFeaturedCollection: visibleFeaturedCollection,
                    userCollections: userCollections,
                    visibleSmartCollections: visibleSmartCollections,
                    showFavorites: showFavoritesRow,
                    showNonBio: showNonBio
                ) {
                    EmptyStateView(
                        iconName: isSearching ? "magnifyingglass" : "line.3.horizontal.decrease",
                        title: "No collections found",
                        message: emptyStateMessage(isSearching: isSearching)
                    ) {
                        if filters.hasActiveFilters {
                            Button {
                                HapticManager.shared.triggerMediumPulse()
                                filters.clear()
                            } label: {
                                Text("Clear filters")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                    }
                } else {
                    if let visibleFeaturedCollection {
                        NavigationLink {
                            SmartCollectionDetailView(
                                snapshot: visibleFeaturedCollection,
                                onHideSmartCollection: onHideSmartCollection
                            )
                        } label: {
                            FeaturedCollectionCard(snapshot: visibleFeaturedCollection)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }

                    if hasCardCollections {
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
                }

                if hasRowCollections {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 16),
                            count: 3
                        ),
                        spacing: 16
                    ) {
                        if showFavorites, let favoritesCollection {
                            DefaultCollectionCard(
                                title: "Favorites",
                                assetName: "heart",
                                count: favoritesSummary.count
                            ) {
                                CollectionDetailView(collection: favoritesCollection)
                            }
                        }

                        ForEach(smartRowCollections) { smartCollection in
                            DefaultCollectionCard(
                                title: smartCollection.title,
                                assetName: smartCollection.defaultCollectionAssetName,
                                count: smartCollection.count
                            ) {
                                SmartCollectionDetailView(
                                    snapshot: smartCollection,
                                    onHideSmartCollection: onHideSmartCollection
                                )
                            }
                        }

                        if showNonBio {
                            DefaultCollectionCard(
                                title: "Non-biological",
                                assetName: "cube",
                                count: nonBioCount
                            ) {
                                NonBiologicalScansView()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, hasTopCollectionCards ? 0 : 16)
                }

                if !isSearching &&
                    !filters.hasActiveFilters &&
                    visibleFeaturedCollection == nil &&
                    userCollections.isEmpty &&
                    visibleSmartCollections.isEmpty {
                    EmptyStateView(
                        imageName: "fireflies",
                        title: "Collections",
                        message: "Create your first collection to start organizing your scans."
                    )
                }
            }
            .padding(.top, isSearchHeaderVisible ? 0 : 16)
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
        .onReceive(featuredRefreshTimer) { date in
            featuredReferenceDate = date
        }
        .onReceive(AppEventPublisher.shared.publisher) { event in
            if case .exploreShareStateChanged = event {
                refreshCollectionSnapshot()
            }
        }
    }

    private var isSearchHeaderVisible: Bool {
        isSearchFocused ||
            filters.hasActiveFilters ||
            !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func shouldShowCollectionType(_ type: CollectionTypeFilter) -> Bool {
        filters.typeFilters.isEmpty || filters.typeFilters.contains(type)
    }

    private func shouldShowHeader(isSearching: Bool) -> Bool {
        isSearching || isSearchFocused || filters.hasActiveFilters
    }

    private func headerTitle(isSearching: Bool) -> String {
        if isSearching {
            return "Search results"
        }

        if filters.hasActiveFilters {
            return "Filtered collections"
        }

        return "Search collections"
    }

    private func shouldShowEmptyFilteredState(
        isSearching: Bool,
        visibleFeaturedCollection: SmartCollectionSnapshot?,
        userCollections: [ScanCollection],
        visibleSmartCollections: [SmartCollectionSnapshot],
        showFavorites: Bool,
        showNonBio: Bool
    ) -> Bool {
        (isSearching || filters.hasActiveFilters) &&
            visibleFeaturedCollection == nil &&
            userCollections.isEmpty &&
            visibleSmartCollections.isEmpty &&
            !showFavorites &&
            !showNonBio
    }

    private func emptyStateMessage(isSearching: Bool) -> String {
        if isSearching {
            return "No collections match \"\(searchQuery)\"."
        }

        return "No collections match the current filters."
    }

    private func sortedUserCollections(_ collections: [ScanCollection]) -> [ScanCollection] {
        switch collectionSortOption {
        case .newest:
            return collections.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return collections.sorted { $0.createdAt < $1.createdAt }
        case .aToZ:
            return collections.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .zToA:
            return collections.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedDescending
            }
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

    var defaultCollectionAssetName: String {
        switch definition.rule {
        case .needsReview:
            return "review"
        default:
            return iconName
        }
    }
}
