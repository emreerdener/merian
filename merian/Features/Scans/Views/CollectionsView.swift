import SwiftData
import SwiftUI

struct CollectionsView: View {
    let searchQuery: String
    let isSearchFocused: Bool
    let collections: [ScanCollection]
    @Binding var isInsightSheetOpen: Bool
    @Binding var showNewCollectionAlert: Bool
    @Binding var newlyCreatedCollection: ScanCollection?
    
    @Environment(\.modelContext) private var modelContext
    @State private var nonBioCount: Int = 0
    @State private var collectionToEdit: ScanCollection?
    @State private var showRenameAlert = false
    @State private var showDeleteConfirmation = false
    @State private var newCollectionName = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                let isSearching = !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
                let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
                
                let userCollections = collections.filter { !$0.isDeleted && $0.name != "Favorites" && (!isSearching || $0.name.localizedCaseInsensitiveContains(query)) }
                
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
                    .padding(.bottom, 0) // Adjusted since the parent VStack has spacing: 16
                }
                
                // MARK: - Promoted Links (Favorites & Non-biological)
                VStack(spacing: 16) {
                if showFavorites, let favorites = collections.first(where: { $0.name == "Favorites" && !$0.isDeleted }) {
                    DefaultCollectionLink(
                        title: "Favorites",
                        iconName: "heart",
                        count: favorites.scans?.count ?? 0
                    ) {
                        CollectionDetailView(collection: favorites, isInsightSheetOpen: $isInsightSheetOpen)
                    }
                }
                
                if showNonBio {
                    DefaultCollectionLink(
                        title: "Non-biological",
                        iconName: "cube",
                        count: nonBioCount
                    ) {
                        NonBiologicalScansView(isInsightSheetOpen: $isInsightSheetOpen)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // MARK: - User Custom Collections Grid
            if isSearching && userCollections.isEmpty && !showFavorites && !showNonBio {
                EmptyStateView(
                    iconName: "magnifyingglass",
                    title: "No results found",
                    message: "No collections match \"\(searchQuery)\"."
                )
            } else if !isSearching && userCollections.isEmpty {
                EmptyStateView(
                    iconName: "folder",
                    title: "No collections",
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
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(userCollections) { collection in
                        NavigationLink {
                            CollectionDetailView(collection: collection, isInsightSheetOpen: $isInsightSheetOpen)
                        } label: {
                            CollectionCard(collection: collection)
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
            .padding(.bottom, 16) // Added a global bottom pad for scroll bounding.
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
            CollectionDetailView(collection: collection, isInsightSheetOpen: $isInsightSheetOpen)
        }
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.collections)
        .task {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.isBiological == false })
            if let count = try? modelContext.fetchCount(descriptor) {
                nonBioCount = count
            }
        }
    }
}
