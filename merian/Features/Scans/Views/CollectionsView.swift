import SwiftUI
import SwiftData

struct CollectionsView: View {
    let collections: [ScanCollection]
    @Binding var isInsightSheetOpen: Bool
    
    @Environment(\.modelContext) private var modelContext
    @State private var nonBioCount: Int = 0
    @State private var collectionToEdit: ScanCollection?
    @State private var showRenameAlert = false
    @State private var showDeleteConfirmation = false
    @State private var newCollectionName = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                let userCollections = collections.filter { $0.name != "Favorites" }
                
                // MARK: - Promoted Links (Favorites & Non-biological)
                VStack(spacing: 16) {
                if let favorites = collections.first(where: { $0.name == "Favorites" }) {
                    DefaultCollectionLink(
                        title: "Favorites",
                        iconName: "heart",
                        count: favorites.scans?.count ?? 0
                    ) {
                        CollectionDetailView(collection: favorites, isInsightSheetOpen: $isInsightSheetOpen)
                    }
                }
                
                DefaultCollectionLink(
                    title: "Non-biological",
                    iconName: "cube",
                    count: nonBioCount
                ) {
                    NonBiologicalScansView(isInsightSheetOpen: $isInsightSheetOpen)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // MARK: - User Custom Collections Grid
            if userCollections.isEmpty {
                EmptyStateView(
                    iconName: "folder",
                    title: "No collections",
                    message: "Create your first collection to start organizing your scans."
                )
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
        .containerRelativeFrame(.horizontal)
        .id(ScansTab.collections)
        .task {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.isBiological == false || $0.commonName == "Unknown Subject" })
            if let count = try? modelContext.fetchCount(descriptor) {
                nonBioCount = count
            }
        }
    }
}
